# AES-GCM-256 AXI-Stream wrapper — module list

## Crypto core (shared, validated)

| File | Module |
|------|--------|
| `aes_gcm_256.v` | GCM controller |
| `aes256.v` | AES-256 block cipher |
| `aesKeySchedule.v` | Key expansion |
| `aesRound_comb.v` | AES round |
| `subByte.v` | S-box |
| `mixColumn.v` | MixColumns |
| `gfMult.v` | GF(2^8) multiply |
| `ghash.v` | GHASH accumulator |
| `gf128_mult.v` | GF(2^128) multiplier |
| `gfInverse_canright.v` | GF(2^8) inverse |

## Custom wrapper modules (shared)

| File | Module | Used by |
|------|--------|---------|
| `aes_gcm_core_adapter.v` | Wraps core with AXI-Stream, encrypt/decrypt | Both |
| `key_loader.v` | 8-bit AXI-Stream → 256-bit key register | Both |
| `tx_header_bridge.v` | AXI-Stream → coworker's TX protocol | Both |

## Custom wrapper modules (encrypt only)

| File | Module |
|------|--------|
| `iv_loader.v` | 8-bit AXI-Stream → 96-bit IV register, auto-increment |
| `tx_stream_composer.v` | Sequences IV + CT + tag into byte stream |

## Custom wrapper modules (decrypt only)

| File | Module |
|------|--------|
| `rx_stream_parser.v` | Parses IV + CT + tag from incoming byte stream |

## Vivado IP cores

| Component name | Type | Used by |
|----------------|------|---------|
| `axis_upsizer` | AXI4-Stream Data Width Converter (1B → 16B) | Both |
| `axis_downsizer` | AXI4-Stream Data Width Converter (16B → 1B) | Both |
| `axis_pt_fifo` | AXI4-Stream Data FIFO (8-bit, 2048 deep) | Decrypt only |

## Top-level modules

| File | Pipeline |
|------|----------|
| `aes_gcm_256_axis_top.v` | Encrypt |
| `aes_gcm_256_axis_decrypt_top.v` | Decrypt |

## Testbenches

| File | Covers |
|------|--------|
| `tb_aes_gcm_core_adapter.v` | Stage 1: adapter encrypt (20/20) |
| `tb_aes_gcm_core_adapter_decrypt.v` | Stage D2: adapter decrypt + regression (11/11) |
| `tb_tx_stream_composer.v` | Stage 2: composer (370/370) |
| `tb_tx_header_bridge.v` | Stage 3: bridge (82/82) |
| `tb_key_iv_loaders.v` | Stage 4: key + IV loaders (17/17) |
| `tb_rx_stream_parser.v` | Stage D1: parser (111/111) |
| `tb_aes_gcm_256_axis_top.v` | Stage 6: encrypt system (157/157) |
| `tb_aes_gcm_256_axis_decrypt_top.v` | Stage D3: decrypt system (91/91) |
