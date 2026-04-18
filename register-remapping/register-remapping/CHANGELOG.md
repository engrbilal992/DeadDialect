# RISC-V Register Remapping — Changelog

## Phase 3 Milestone 2 — Register Rewriter + QEMU Hook

### April 2026

#### Initial Release
- `isa_register_rewrite.py` — rewrites 5-bit rd/rs1/rs2 register fields in ELF .text
- `register_mapping.h` — QEMU translate.c hook, mtime-reload, no initialized flag
- `/etc/isa/register_keyring` — 640 permissions, sudo tee fallback
- `build.sh` — portable QEMU build with register patch only
- `audit.sh` — 11 live checks + static code verification
- `demo.sh` — boot A/B proof, malware blocked

#### Design Decisions
- Frozen registers: x0(zero), x1(ra), x2(sp), x10-x17(a0-a7) — 11 frozen, 21 shuffleable
- Entropy: 21! ≈ 2^65 — genuine brute-force resistance
- POC limitation: -march=rv64g required (RVC compressed instructions disabled)
- No initialized flag — mtime=0 guarantees first load (Curtis fix applied)
- secrets.token_bytes(32) for 256-bit entropy random seeds
- sudo tee fallback for 640 root-owned keyring files
