# AES-GCM-256 AXI-Stream wrapper — open items

## RTL / wrapper items

| # | Item | Risk | Status | Notes |
|---|------|------|--------|-------|
| 1 | IV fixed/counter field partition | Critical | Open | Current: full 96-bit counter from seed. Production: 32-bit device ID + 64-bit counter recommended. No RTL change needed — only the seed value changes. |
| 2 | IV counter persistence across power cycles | Critical | Open | Counter resets to seed on power-up. Either store counter in non-volatile memory or rotate key on every boot. |
| 3 | Replay protection / sequence numbering | High | Open | IV counter could double as sequence number. Receiver needs sliding window check (RFC 6479). Interacts with AAD decision. |
| 4 | AAD contents | Medium-high | Open | AAD path exists but is unused. Recommended: device ID + sequence number. Requires wrapper FSM changes to feed AAD blocks before data. |
| 5 | Key lifetime / invocation count limit | Medium-high | Open | No counter enforcement. At 1000 pkt/s with 32-bit counter: exhaustion in ~50 days. Need counter + key rotation signal. |
| 6 | Key zeroization | Medium-high | Open | No dedicated zeroization command. FIPS 140-3 §7.9 requires it. Need signal to scrub key_reg, h_reg, and all key-derived state. |
| 7 | Watchdog / error recovery | Medium | Open | No timeout on core FSM. Stuck operation hangs silently. Need watchdog timer in wrapper with configurable max latency. |
| 8 | Side-channel protections (AES core) | Medium | Open | No DPA/CPA countermeasures on S-box. Document threat model and risk-accept or add masking. |
| 9 | RX interface confirmation with coworker | Medium | Open | Using proposed mirror of TX protocol. Coworker has not confirmed. Share spec and adapt if needed. |
| 10 | Encrypt top-level: adapter tag comparison in decrypt mode | Low | Resolved | Adapter does its own tag comparison at core-done time since tag arrives after start. Documented, tested, correct. |

## Resolved items (for reference)

| Item | Resolution |
|------|------------|
| IV transmission | Prepend 12B IV to payload in cleartext (TLS 1.3 / IPsec approach) |
| IV per-packet increment | Auto-increment lower 64 bits after each encryption |
| IV loading | AXI-Stream port with localparam default |
| Key provisioning (development) | AXI-Stream port with localparam default |
| Packet format | IV(12B) + CT(NB) + Tag(16B), tx_payload_len = N + 28 |
| Plaintext hold-off (decrypt) | FIFO + release gate, NIST SP 800-38D §7 compliant |
| Byte order (Vivado IP ↔ core) | Byte-swap + tkeep-reverse at both boundaries |

## System / program-level items

| # | Item | Risk | Notes |
|---|------|------|-------|
| 11 | NRC regulatory classification (10 CFR 73.54) | High | Determines documentation and QA requirements. Program-level decision. |
| 12 | FIPS 140-2/3 determination | High | If required: 12-24 month validation, constrains design (self-tests, approved RNG). |
| 13 | Failure mode policy (fail-closed vs fail-open) | High | Single point of failure in safety data path. Requires safety engineering input. |
| 14 | Production key provisioning | Medium | Default key must be removed or zeroed for deployment. Key source TBD (eFUSE, BBRAM, secure boot). |
