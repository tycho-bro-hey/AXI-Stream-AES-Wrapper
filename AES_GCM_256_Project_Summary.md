# AES-GCM-256 AXI-Stream Wrapper — Project Summary & Integration Guide

## Part 1: Development Stages

### Stage 1 — Key and IV Configuration Registers (`gcm_axi_config`)

Built the AXI-Stream configuration module that manages the 256-bit encryption
key and 96-bit IV. Both load from hardcoded defaults on reset and can be
overwritten at runtime by pushing bytes to their respective 8-bit AXI-Stream
ports. The IV auto-increments its lower 64 bits after each encryption.
Validates `tlast` alignment and gates commits on core idle. 31 tests passed.

### Stage 2 — TX Byte Serializer (`gcm_tx_serializer`)

Built the output serializer that converts the encrypt path's three output
phases (96-bit IV, 128-bit ciphertext blocks, 128-bit tag) into a single
byte-serial AXI-Stream output. Implements the two-phase header handshake
protocol (header with payload length, then byte transfer with backpressure
and `tlast`). 49 tests passed.

### Stage 3 — Encrypt Wrapper (`gcm_axi_encrypt`)

Integrated Stages 1 and 2 with the validated `aes_gcm_256` core via a
sequencing FSM. The FSM accepts 128-bit plaintext blocks, drives the core's
start/pt_valid/finalize protocol with fixed-delay timing, captures ciphertext
and tag outputs, and feeds them to the TX serializer. Verified end-to-end
against NIST test vectors (McGrew-Viega TC13–TC15). 24 tests passed.

### Stage 4 — RX Byte-Order Shim (`gcm_rx_shim`)

Built a purely combinational module that sits between the Vivado
`axis_dwidth_converter` output and the encrypt wrapper's block input. Reverses
AXI-Stream little-endian byte order to GCM big-endian (MSB-first) and converts
the width converter's `tkeep[15:0]` bitmask into a 5-bit byte count. 25 tests
passed.

### Stage 5 — Encrypt Top-Level Integration (`gcm_axi_top`)

Wired the complete encrypt pipeline: 8-bit RX payload → Vivado width converter
(8→128 bit) → byte-order shim → encrypt wrapper → 8-bit TX payload. This is
the production-facing encrypt module. Verified byte-in to byte-out against
NIST vectors including partial final blocks. 34 tests passed.

### Stage 6 — RX Byte Parser (`gcm_rx_parser`)

Built the incoming packet parser for the decrypt path. Separates the encrypted
byte stream into its three fields: IV (bytes 0–11), ciphertext (bytes 12
through len−17), and tag (final 16 bytes). Routes ciphertext bytes to the
width converter while accumulating IV and tag into registers. Handles
backpressure from the width converter and zero-ciphertext (GMAC) packets.
33 tests passed.

### Stage 7 — Decrypt Wrapper (`gcm_axi_decrypt`)

Integrated the RX parser, width converter, byte-order shim, crypto core
(decrypt mode), and a new plaintext serializer (`gcm_pt_serializer`) with a
sequencing FSM. The FSM starts the core after the parser extracts the IV,
feeds ciphertext blocks in real-time as they arrive, then compares the core's
computed tag against the parser-extracted tag after completion. Verified with
NIST vectors for authentication pass, authentication fail (corrupted tag),
and zero-ciphertext. 23 tests passed.

### Roundtrip Test

Wired `gcm_axi_top` TX output directly to `gcm_axi_decrypt` RX input with
no glue logic. Fed plaintext bytes into encrypt, verified that decrypt
recovered identical plaintext with authentication passing. Tested 1-byte,
16-byte, 33-byte (non-aligned), and 64-byte payloads plus back-to-back
packets with IV auto-increment. 30 tests passed.

### CAVP Wrapper Test

Ran 13 NIST CAVP vectors through the full encrypt pipeline (`gcm_axi_top`)
at the byte level. Verified every TX output byte (IV, ciphertext, tag)
against published expected values. Covered PTlen = 0, 13, 16, 32, and 64
bytes. 53 tests passed.

### MTU Roundtrip Test

Full Ethernet MTU roundtrip at 1500 bytes (93 full blocks + 12-byte partial).
Also tested 256 bytes (16 blocks) and 1488 bytes (93 exact blocks, no partial).
All three sizes roundtripped with byte-perfect plaintext recovery and
authentication passing. 15 tests passed.

### Synthesis

Synthesized `gcm_axi_top` (encrypt path) targeting XC7A100T at 100 MHz.
Timing met with +1.746 ns slack. Utilization: 2,896 LUTs (4.57%), 3,893 FFs
(3.07%). Critical path through AES key schedule S-box.

---

## Part 2: Module Descriptions

### Wrapper Modules (New — Built in This Project)

| Module | Description |
|--------|-------------|
| `gcm_axi_top` | Encrypt top-level. Wires width converter, shim, and encrypt wrapper into a single module with 8-bit RX/TX interfaces. |
| `gcm_axi_encrypt` | Encrypt sequencing FSM. Accepts 128-bit blocks from the shim, drives the core protocol (start → feed blocks → capture CT/tag), pushes results to the TX serializer. |
| `gcm_axi_decrypt` | Decrypt top-level and sequencing FSM. Contains the RX parser, width converter, shim, core (decrypt mode), PT serializer, and post-decryption tag comparison. |
| `gcm_axi_config` | Key (256-bit) and IV (96-bit) configuration registers. 8-bit AXI-Stream loading ports. Hardcoded defaults on reset. IV auto-increments after each encrypt operation. Commits new values only when the core is idle. |
| `gcm_tx_serializer` | Serializes IV (12B) + ciphertext blocks (128-bit) + tag (16B) into 8-bit AXI-Stream output with header handshake and backpressure support. |
| `gcm_pt_serializer` | Serializes 128-bit plaintext blocks from the decrypt core into 8-bit AXI-Stream output with header handshake. Simpler than TX serializer (no IV prefix or tag suffix). |
| `gcm_rx_parser` | Parses incoming encrypted byte stream into IV (12B register), ciphertext (routed to width converter as 8-bit stream), and tag (16B register). Handles zero-CT packets. |
| `gcm_rx_shim` | Combinational byte-order reversal (16 lanes) and `tkeep[15:0]` to `byteCount[4:0]` conversion. Sits between width converter output and the FSM's block input. |

### Crypto Core Modules (Pre-existing — Validated with 254 NIST Tests)

| Module | Description |
|--------|-------------|
| `aes_gcm_256` | Top-level GCM controller. 16-state FSM implementing NIST SP 800-38D Algorithms 4 (encrypt) and 5 (decrypt). Orchestrates H computation, GCTR, GHASH, and tag generation. |
| `aes256` | AES-256 block cipher. 14-round iterative architecture. Rising-edge detection on `in_valid` starts computation; `out_valid` signals completion. |
| `aesKeySchedule` | AES-256 key expansion. Generates all 15 round keys from the 256-bit master key. |
| `aesRound_comb` | Single AES round (combinational). SubBytes, ShiftRows, MixColumns, AddRoundKey. |
| `subByte` | AES S-box byte substitution using Canright inverse. |
| `gfInverse_canright` | GF(2^8) multiplicative inverse via Canright's compact composite-field method. |
| `mixColumn` | AES MixColumns column transformation. |
| `gfMult` | GF(2^8) multiplication used by MixColumns. |
| `ghash` | GHASH iterative accumulator. Computes Y_i = (Y_{i−1} ⊕ X_i) × H for each 128-bit block. |
| `gf128_mult` | GF(2^128) bit-serial multiplier. 128 clock cycles per multiplication. Reduction polynomial x^128 + x^7 + x^2 + x + 1. |

### Vivado IP

| Module | Description |
|--------|-------------|
| `axis_dwidth_converter_0` | Xilinx AXI-Stream Data Width Converter. Configured as 1-byte slave → 16-byte master with `tkeep` and `tlast` enabled. Accumulates 8-bit input bytes into 128-bit output words. Generates `tkeep` bitmask for partial final blocks. Separate instance in each path. |

---

## Part 3: Coworker Integration Guide

### Overview

The crypto wrapper operates at the UDP payload level. The Ethernet stack passes
raw UDP payload bytes to the wrapper and receives processed bytes back. All
Ethernet, IP, and UDP headers are handled by the Ethernet stack — the wrapper
never sees them.

Two independent modules are provided:

- **`gcm_axi_top`** — Encrypt path (cleartext in → ciphertext out)
- **`gcm_axi_decrypt`** — Decrypt path (ciphertext in → plaintext out)

Both use the same clock (`clk`) and active-high synchronous reset (`rst`).

### Encrypt Path — `gcm_axi_top`

#### Port List

```verilog
module gcm_axi_top (
    input wire         clk,               // System clock (100 MHz)
    input wire         rst,               // Active-high synchronous reset

    // Key loading (32 bytes, MSB-first) — load once at startup
    input wire [7:0]   key_axis_tdata,
    input wire         key_axis_tvalid,
    output wire        key_axis_tready,
    input wire         key_axis_tlast,

    // IV seed loading (12 bytes, MSB-first) — optional, defaults to zero
    input wire [7:0]   iv_axis_tdata,
    input wire         iv_axis_tvalid,
    output wire        iv_axis_tready,
    input wire         iv_axis_tlast,

    // RX: Ethernet stack (master) → crypto wrapper (slave)
    input wire         rx_hdr_valid,      // Payload length is valid
    input wire [15:0]  rx_payload_len,    // Plaintext byte count (1–1500)
    output wire        rx_hdr_ready,      // Wrapper accepted header

    input wire [7:0]   rx_payload_tdata,  // Plaintext byte
    input wire         rx_payload_tvalid, // Byte is valid
    output wire        rx_payload_tready, // Wrapper can accept
    input wire         rx_payload_tlast,  // Last plaintext byte

    // TX: crypto wrapper (master) → Ethernet stack (slave)
    output wire        tx_hdr_valid,      // Payload length is valid
    output wire [15:0] tx_payload_len,    // = 12 + rx_payload_len + 16
    input wire         tx_hdr_ready,      // Ethernet stack accepted header

    output wire [7:0]  tx_payload_tdata,  // Encrypted byte
    output wire        tx_payload_tvalid, // Byte is valid
    input wire         tx_payload_tready, // Ethernet stack can accept
    output wire        tx_payload_tlast,  // Last byte of encrypted payload

    // Status
    output wire        keyError,          // Sticky: key loading tlast error
    output wire        ivError,           // Sticky: IV loading tlast error
    output wire        encBusy,           // High while encrypting
    output wire        encDone            // Pulses 1 cycle when complete
);
```

#### RX Protocol (Ethernet Stack → Wrapper)

The Ethernet stack is the master; the wrapper is the slave.

**Step 1 — Header handshake:**
1. Assert `rx_hdr_valid` with `rx_payload_len` set to the plaintext byte count.
2. Wait for `rx_hdr_ready` to go high.
3. On the clock edge where both are high, the handshake completes.
4. Deassert `rx_hdr_valid`.

**Step 2 — Payload bytes:**
1. Place each plaintext byte on `rx_payload_tdata` and assert `rx_payload_tvalid`.
2. Hold the byte steady until `rx_payload_tready` is high (backpressure).
3. One byte transfers per clock edge where both `tvalid` and `tready` are high.
4. Assert `rx_payload_tlast` with the final byte.

#### TX Protocol (Wrapper → Ethernet Stack)

The wrapper is the master; the Ethernet stack is the slave. Same two-phase
protocol as RX but with master/slave roles reversed.

**Step 1 — Header handshake:**
1. Wrapper asserts `tx_hdr_valid` with `tx_payload_len = 12 + N + 16` (where N = plaintext length).
2. Ethernet stack acknowledges with `tx_hdr_ready`.

**Step 2 — Payload bytes:**
1. Wrapper outputs bytes on `tx_payload_tdata` with `tx_payload_tvalid`.
2. If `tx_payload_tready` drops, the wrapper holds the current byte.
3. `tx_payload_tlast` is asserted on the final byte.

#### TX Payload Format

```
Byte 0           Byte 11  Byte 12          Byte 12+N-1  Byte 12+N     Byte 12+N+15
+-----------------+------------------------+-------------------------------+
|  IV (12 bytes)  |  Ciphertext (N bytes)  |  GCM Tag (16 bytes)           |
|  (cleartext)    |  (encrypted data)      |  (authentication tag)         |
+-----------------+------------------------+-------------------------------+
                   tx_payload_len = 12 + N + 16
```

The wrapper prepends the IV and appends the tag automatically. The Ethernet
stack treats the entire TX payload as opaque data — it does not need to
parse or understand the IV/CT/tag structure.

#### Timing

At 100 MHz, encryption latency per packet is approximately:

| Payload size | Blocks | Cycles | Time |
|-------------|--------|--------|------|
| 16 bytes | 1 | ~320 | 3.2 µs |
| 256 bytes | 16 | ~2,600 | 26 µs |
| 1500 bytes (MTU) | 94 | ~14,400 | 144 µs |

Plus byte serialization time: 12 + N + 16 clock cycles for TX output.

---

### Decrypt Path — `gcm_axi_decrypt`

#### Port List

```verilog
module gcm_axi_decrypt (
    input wire         clk,               // System clock (100 MHz)
    input wire         rst,               // Active-high synchronous reset

    // Key loading (32 bytes, MSB-first) — must match encrypt key
    input wire [7:0]   key_axis_tdata,
    input wire         key_axis_tvalid,
    output wire        key_axis_tready,
    input wire         key_axis_tlast,

    // RX: Ethernet stack (master) → crypto wrapper (slave)
    input wire         rx_hdr_valid,      // Payload length is valid
    input wire [15:0]  rx_payload_len,    // Total encrypted payload (IV+CT+Tag)
    output wire        rx_hdr_ready,      // Wrapper accepted header

    input wire [7:0]   rx_payload_tdata,  // Encrypted byte
    input wire         rx_payload_tvalid, // Byte is valid
    output wire        rx_payload_tready, // Wrapper can accept
    input wire         rx_payload_tlast,  // Last encrypted byte

    // TX: crypto wrapper (master) → Ethernet stack (slave)
    output wire        tx_hdr_valid,      // Payload length is valid
    output wire [15:0] tx_payload_len,    // = rx_payload_len - 28
    input wire         tx_hdr_ready,      // Downstream accepted header

    output wire [7:0]  tx_payload_tdata,  // Plaintext byte
    output wire        tx_payload_tvalid, // Byte is valid
    input wire         tx_payload_tready, // Downstream can accept
    output wire        tx_payload_tlast,  // Last plaintext byte

    // Status
    output wire        keyError,          // Sticky: key loading tlast error
    output wire        decBusy,           // High while decrypting
    output wire        decDone,           // Pulses 1 cycle when complete
    output wire        authOk,            // Tags match (valid on decDone)
    output wire        authFail           // Tags mismatch (valid on decDone)
);
```

#### RX Protocol (Ethernet Stack → Wrapper)

Same two-phase protocol as encrypt RX. The difference is what the bytes
contain:

- `rx_payload_len` = total encrypted payload size (12 + N + 16)
- The byte stream contains: IV (12B) + ciphertext (NB) + tag (16B)
- The Ethernet stack does NOT need to parse or strip these fields — just pass the entire UDP payload through

#### TX Protocol (Wrapper → Downstream)

Same two-phase protocol. The wrapper outputs only the decrypted plaintext:

- `tx_payload_len` = plaintext byte count = `rx_payload_len - 28`
- No IV or tag in the output — just raw plaintext bytes

#### Authentication

After decryption completes, `decDone` pulses for one clock cycle. On that
same cycle:

- `authOk = 1` — tags match, plaintext is authentic
- `authFail = 1` — tags do not match, plaintext should be discarded

The wrapper outputs plaintext bytes during decryption (before authentication
completes). This is inherent to GCM — the plaintext must be computed to
verify the tag. The Ethernet stack should buffer or gate the plaintext
output based on `authOk` before forwarding to the application.

#### No IV Port

The decrypt path has no IV AXI-Stream input. The IV is extracted from the
first 12 bytes of the incoming encrypted packet. The Ethernet stack does
not need to handle IV management for the decrypt side.

---

### Key Loading

Both encrypt and decrypt modules accept a 256-bit (32-byte) key via their
`key_axis_*` AXI-Stream ports. The same key must be loaded into both paths.

- Bytes arrive MSB-first (byte 0 = key bits [255:248])
- Assert `tlast` on byte 31 (the last byte)
- The key takes effect on the next encrypt/decrypt operation
- On power-up, both default to an all-zero key
- The key persists until explicitly replaced

For simultaneous loading, tie both `key_axis_tdata/tvalid/tlast` inputs to
the same source and AND the two `tready` outputs.

### Clock and Reset

- Single clock domain: `clk` at 100 MHz, positive-edge triggered
- Active-high synchronous reset: `rst`
- Assert `rst` for at least 5 clock cycles at startup

### Signal Naming Convention

Encrypt TX output signals map to the coworker's existing naming:

| Wrapper port | Connects to |
|-------------|-------------|
| `tx_hdr_valid` | `fmc0_tx_udp_hdr_valid` |
| `tx_payload_len` | `fmc0_tx_udp_length` |
| `tx_hdr_ready` | `fmc0_tx_udp_hdr_ready` |
| `tx_payload_tdata` | `fmc0_tx_udp_payload_axis_tdata` |
| `tx_payload_tvalid` | `fmc0_tx_udp_payload_axis_tvalid` |
| `tx_payload_tready` | `fmc0_tx_udp_payload_axis_tready` |
| `tx_payload_tlast` | `fmc0_tx_udp_payload_axis_tlast` |

---

### Verification Status

| Test | Result |
|------|--------|
| NIST CAVP vectors (13 vectors, byte-exact) | 53/53 |
| Encrypt integration (byte-in to byte-out) | 34/34 |
| Decrypt integration (auth pass, fail, zero-CT) | 23/23 |
| Roundtrip: decrypt(encrypt(PT)) == PT | 30/30 |
| MTU roundtrip (1500-byte full Ethernet MTU) | 15/15 |
| All unit tests | 146/146 |
| **Total** | **317/317** |

### Synthesis (XC7A100T, encrypt path only)

| Resource | Used | Available | Utilization |
|----------|------|-----------|-------------|
| LUT | 2,896 | 63,400 | 4.57% |
| FF | 3,893 | 126,800 | 3.07% |
| Timing (WNS) | +1.746 ns | — | Met at 100 MHz |
