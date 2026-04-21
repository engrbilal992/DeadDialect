# RISC-V ISA Integration — Changelog

## [2026-04-21] Phase 3 Milestone 3 — Integration

### Added
- `isa_integrate.py` — unified rewriter applying register + syscall layers simultaneously
- `register_mapping.h` — QEMU register hook with fingerprint verification
- `syscall_mapping.h` — QEMU syscall hook with mtime-reload
- `isa_remap_ldso.h` — musl ld.so patch for dynamic binary support
- `riscv_demo/simple.S` — assembly test binary (register + syscall layers)
- `riscv_demo/complex.S` — assembly test binary (multi-syscall + arithmetic)
- `build.sh` — portable build: downloads QEMU, applies both patches
- `audit.sh` — combined audit: register + syscall independent + together
- `demo.sh` — end-to-end security demonstration

### Security
- Register layer: 21 shuffleable regs, 21! ≈ 2^65 entropy, fingerprint blocking
- Syscall layer: 436 syscalls, 436! ≈ 2^3000+ entropy, mtime-reload
- Combined: attacker must defeat both layers independently
- ld.so patch: dynamic binaries covered at load time (musl Alpine RISC-V)

### Entropy
- Register: 21! ≈ 2^65
- Syscall:  436! ≈ 2^3000+
- Combined: 21! × 436! ≈ 2^3065+

### Audit
- 6/6 security scenarios pass
- Both simple and complex binaries verified
