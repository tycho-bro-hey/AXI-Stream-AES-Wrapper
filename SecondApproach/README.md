# AES-GCM-256 AXI-Stream Wrapper

Bump-in-the-wire Ethernet encryption device for the Arty A7-100T (development) and Nexys Video (deployment). Wraps a validated AES-GCM-256 core with AXI-Stream interfaces for integration with a UDP/Ethernet stack.

## What it does

- **Encrypt**: receives plaintext UDP payload bytes, outputs IV + ciphertext + GCM tag
- **Decrypt**: receives IV + ciphertext + tag, verifies authentication, outputs plaintext (or discards on auth failure)

Packet format: `IV (12B) | Ciphertext (NB) | Tag (16B)`

## Verification

The AES-GCM-256 core passes all 254 NIST CAVP test vectors. The AXI-Stream wrapper passes 859 checks across 8 testbenches covering both pipelines end-to-end against NIST McGrew-Viega vectors.

## Quick start

1. Create a Vivado project targeting `xc7a100tcsg324-1`
2. Add all source files (see `MODULE_LIST.md`)
3. Generate three Vivado IP cores from the IP Catalog:
   - `axis_upsizer` — AXI4-Stream Data Width Converter (1B → 16B)
   - `axis_downsizer` — AXI4-Stream Data Width Converter (16B → 1B)
   - `axis_pt_fifo` — AXI4-Stream Data FIFO (8-bit, 2048 deep, BRAM)
4. Run Open Elaborated Design to verify connectivity
5. Add a testbench and simulate

See `VIVADO_PROJECT_SETUP.md` for detailed IP configuration steps.

## Key files

| File | Purpose |
|------|---------|
| `aes_gcm_256_axis_top.v` | Encrypt top-level |
| `aes_gcm_256_axis_decrypt_top.v` | Decrypt top-level |
| `MODULE_LIST.md` | Complete file list for both pipelines |
| `OPEN_ITEMS.md` | Security and compliance items to resolve before deployment |

## Status

Development complete. Open items remain for production hardening — see `OPEN_ITEMS.md`.
