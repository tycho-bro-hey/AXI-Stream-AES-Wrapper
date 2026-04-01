**Key Management**

The key should never be hardcoded in the bitstream or stored in plaintext on the FPGA board. For Xilinx 7-series, the three viable storage options in order of security are:

**eFUSE** — one-time programmable fuses on the FPGA die. The key is physically embedded in silicon and cannot be read back via JTAG once readback protection is set. Survives power loss permanently. Downside: you cannot change the key — ever. If the key is compromised, the device must be physically replaced. Appropriate when the device has a fixed lifetime and key rotation is handled by replacing hardware.

**BBRAM** — battery-backed RAM on the FPGA. The key persists as long as a coin cell battery is connected. Can be reprogrammed. If the battery is removed or dies, the key is erased and the device becomes inoperable until re-provisioned. This provides tamper-evidence: physical intrusion that disconnects the battery wipes the key. Appropriate for field-deployed devices where key rotation may be needed.

**Neither option stores the key in flash** where it could be extracted by reading the SPI chip off-board. For your reactor monitoring system, BBRAM is likely the better fit — it allows key rotation during maintenance windows and provides tamper-evidence.

The current AXI-Stream key port is the right architecture for all of these. A small boot controller (MicroBlaze soft processor, or a dedicated FSM that reads from BBRAM on startup) loads the key through the port after reset. The wrapper should be modified for production so that **encryption is blocked until a key is explicitly loaded** — change the default key to all-zeros and add a `keyLoaded` gate that prevents the FSM from accepting packets until a non-zero key has been committed.

**IV Management**

NIST SP 800-38D §8.2 is unambiguous: **an IV must never be reused with the same key.** IV reuse under the same key completely breaks GCM's authentication and leaks plaintext via crib-dragging. This is the single most catastrophic failure mode in GCM.

The standard defines two construction methods:

**Deterministic construction (§8.2.1)** — what our wrapper implements. The IV is split into a fixed field (device identity) and an invocation field (counter). The counter increments after each packet. This is safe as long as the fixed field is unique per device and the counter never wraps to a previously-used value under the same key.

For production, the recommended IV partition is:

```
96-bit IV:
[95:64]  32-bit fixed field — unique device identifier
[63:0]   64-bit invocation counter — auto-incremented per packet
```

The 64-bit counter supports 2^64 packets per key. At 1500 bytes per packet at line rate (100 Mbps), this is over 2 million years before exhaustion. The counter is not a practical concern.

The fixed field **must be unique** across every device sharing the same key. If two encryptors use the same key and the same fixed field, their counters will overlap and produce IV reuse. For your system, since the sending and receiving FPGAs have separate roles (one encrypts, one decrypts), only the encrypting device generates IVs. If you later deploy multiple encrypting devices sharing one key, each must have a distinct fixed field.

**What must not happen at power cycle:** if the device loses power and restarts, the counter resets to zero. If the same key is still active, every IV from the previous session will be reused. There are three standard mitigations:

1. **Persist the counter** — write the current counter value to non-volatile storage periodically. On boot, load it and add a safety margin (e.g., skip ahead by 1000). This is the simplest approach but requires flash writes.
2. **New key per session** — if the key changes every time the device powers up (via a key exchange protocol), the counter can safely restart at zero because the key is different.
3. **Random IV construction (§8.2.2)** — use a cryptographic random number generator to produce each IV. This eliminates the counter persistence problem but requires a good entropy source on the FPGA, which Artix-7 does not have natively. Not recommended for this platform.

For your reactor monitoring system, the most practical approach is **BBRAM key storage + counter persistence in SPI flash with a skip-ahead margin**. On boot: read the key from BBRAM, read the last-saved counter from flash, add 10,000 to the counter (covering any packets sent between the last save and the power loss), and resume. Periodically (every N packets), save the current counter to flash.

**What the wrapper needs for production (changes from current implementation):**

1. Change `DEFAULT_KEY` to all-zeros and add a `keyLoaded` flag that blocks packet processing until a valid key is loaded
2. Set the upper 32 bits of the default IV to a device-specific identifier (loaded at boot, not hardcoded)
3. Add an interface to load an initial counter value on boot (could reuse the existing IV AXI-Stream port — load the full 96-bit seed including the persisted counter)
4. None of these changes affect the wrapper's RTL architecture — they're all seed values and policy logic around the existing AXI-Stream ports

---
---

## Integrating Ethernet

**Encrypt device — `gcm_axi_top`**

Ethernet RX (ingress, cleartext) → wrapper → Ethernet TX (egress, encrypted)

- Coworker's RX stack strips Ethernet/IP/UDP headers, delivers raw UDP payload bytes
- Connect `rx_hdr_valid`, `rx_payload_len` (plaintext byte count), and `rx_hdr_ready` for the header handshake
- Connect `rx_payload_tdata` (8-bit), `rx_payload_tvalid`, `rx_payload_tready`, `rx_payload_tlast` for byte transfer
- Wrapper outputs on `tx_hdr_valid` with `tx_payload_len = 12 + N + 16` — coworker's TX stack uses this to build the outgoing UDP/IP/Ethernet headers
- Connect `tx_payload_tdata` (8-bit), `tx_payload_tvalid`, `tx_payload_tready`, `tx_payload_tlast` for byte transfer
- Coworker's TX stack treats the entire TX payload as opaque — does not parse IV/CT/tag fields
- TX signal names map directly: `tx_hdr_valid` → `fmc0_tx_udp_hdr_valid`, `tx_payload_tdata` → `fmc0_tx_udp_payload_axis_tdata`, etc.

**Decrypt device — `gcm_axi_decrypt`**

Ethernet RX (ingress, encrypted) → wrapper → Ethernet TX (egress, plaintext)

- Coworker's RX stack delivers the entire UDP payload as-is — does not strip or parse IV/CT/tag
- Connect `rx_hdr_valid`, `rx_payload_len` (total encrypted length: 12 + N + 16), and `rx_hdr_ready`
- Connect `rx_payload_tdata/tvalid/tready/tlast` — same protocol as encrypt
- Wrapper outputs only the plaintext bytes on `tx_payload_tdata` with `tx_payload_len = rx_payload_len - 28`
- `authOk` and `authFail` are valid for one cycle on `decDone` — coworker should gate or buffer plaintext output until `authOk` confirms authenticity

**Both devices — handshake protocol**

- Two-phase: header handshake first (`hdr_valid`/`hdr_ready`), then byte transfer (`tvalid`/`tready`/`tlast`)
- One byte transfers per clock edge where both `tvalid` and `tready` are high
- Backpressure: if `tready` drops, the master holds `tdata` and `tvalid` steady until `tready` returns
- `tlast` asserted with the final byte

**Both devices — key loading**

- Push 32 bytes MSB-first on `key_axis_tdata` with `key_axis_tvalid`, assert `key_axis_tlast` on byte 31
- Same key must be loaded into both encrypt and decrypt devices
- Default key on reset is all-zeros — load a real key before sending packets

**Encrypt device — IV**

- Default IV seed is all-zeros on reset — optionally load a 12-byte seed via `iv_axis_*`
- IV auto-increments after each packet — no per-packet coordination needed
- IV is prepended to each encrypted packet automatically

**Decrypt device — IV**

- No IV port — the wrapper extracts the IV from the first 12 bytes of each incoming packet
- Zero IV management required from the Ethernet stack

**Clock and reset**

- Single clock domain: `clk` at 100 MHz
- Active-high synchronous reset: `rst`, hold for at least 5 cycles at startup