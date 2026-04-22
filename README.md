# DeadDialect

> *Every boot speaks a different language. Yesterday's binary is today's dead code.*

A session-unique RISC-V ISA remapping system. Every time the system boots, it generates a fresh cryptographic permutation of the instruction set. Binaries compiled for one session are cryptographically rejected in the next. Malware that survives a reboot cannot execute — it speaks a dead dialect.

---

## The Idea

Standard ISAs are fixed contracts. Every program, every library, every piece of malware agrees on what `0x13` means, what syscall 64 does, which register is the stack pointer. DeadDialect breaks that contract every session.

```
Boot A:  addi = 0x13,  write = syscall 64,   t0 = x5
Boot B:  addi = 0x33,  write = syscall 178,  t0 = x19
Boot C:  addi = 0x67,  write = syscall 291,  t0 = x23
```

A binary compiled for Boot A is nonsense on Boot B. It either executes the wrong instructions, calls the wrong kernel functions, or fails the cryptographic fingerprint check — whichever comes first.

---

## Architecture

```
256-bit session seed  (os.urandom)
         │
         ├─── opcode permutation   →  /etc/isa/map              12!  ≈ 2²⁹
         ├─── register permutation →  /etc/isa/register_keyring 21!  ≈ 2⁶⁵
         └─── syscall permutation  →  /etc/isa/syscall_keyring  436! ≈ 2³⁰⁰⁰⁺
                                                                 ─────────────
                                               Combined entropy: 2³⁰⁹⁴⁺
```

Three independent layers. An attacker who breaks one still faces the other two.

```
┌──────────────────────────────────────────────────────────────┐
│                     Binary (.text)                           │
│        rewritten at compile time by isa_integrate.py         │
│        fingerprint NOPs embedded at .text+0                  │
└─────────────────────────┬────────────────────────────────────┘
                          │
                          ▼
┌──────────────────────────────────────────────────────────────┐
│                  Patched QEMU 8.2.0                          │
│                                                              │
│  translate.c  ←  register_mapping.h                         │
│  ├── verify 24-bit SHA-256 fingerprint                       │
│  │   mismatch → SIGILL before first instruction              │
│  └── remap 21 shuffleable registers                         │
│                                                              │
│  syscall.c    ←  syscall_mapping.h                          │
│  └── translate permuted syscall number → standard           │
│                                                              │
│  [Phase 1/2]  ←  isa_mapping.h                              │
│  └── remap 12 primary opcodes                               │
└──────────────────────────┬───────────────────────────────────┘
                           │
                           ▼
              Alpine Linux RISC-V (boots normally)
              OS is unaware of the remapping
```

---

## Fingerprint Protocol

Every compiled binary carries a 24-bit cryptographic fingerprint embedded as two harmless `addi x0,x0,N` NOPs at the start of `.text`. These are true RISC-V NOPs — they write to the zero register and have no architectural effect — but they encode the session proof.

```
QEMU sees fingerprint NOPs + matching keyring  →  RUN
QEMU sees fingerprint NOPs + wrong keyring     →  SIGILL
QEMU sees no fingerprint  + active keyring     →  SIGILL  ← standard binary blocked
QEMU sees fingerprint NOPs + empty keyring     →  SIGILL  ← remapped binary blocked
```

The fingerprint is derived from `SHA-256(seed)`. No collisions found in the first 100,000 seeds tested.

---

## Repository Structure

```
DeadDialect/
├── opcode-remapping/       Phase 1 — 12 opcode shuffle
├── trigger-remapping/      Phase 2 — live trigger, no reboot needed
│   └── alpine/             Alpine Linux demo
├── syscall-remapping/      Phase 3 M1 — 436 syscall shuffle
├── register-remapping/     Phase 3 M2 — 21 register shuffle + fingerprint
└── integration/            Phase 3 M3 — all layers simultaneously
    ├── isa_integrate.py    unified rewriter
    ├── register_mapping.h
    ├── syscall_mapping.h
    ├── isa_remap_ldso.h    musl ld.so patch (dynamic binaries)
    ├── trigger/
    │   └── trigger_demo.sh one trigger rotates both layers atomically
    ├── alpine/
    │   ├── boot_alpine.sh  boot Alpine under patched QEMU
    │   ├── alpine_demo.sh  full ISA demo inside Alpine
    │   ├── full_alpine_test.sh
    │   └── setup_alpine.sh fresh machine setup
    ├── build.sh            downloads + patches QEMU 8.2.0
    ├── demo.sh
    └── audit.sh            51/51 checks
```

---

## Quick Start

**Requirements:** Ubuntu 22.04, `clang`, `lld`, `python3`, `wget`, `ninja-build`, `libglib2.0-dev`, `libpixman-1-dev`, `libslirp-dev`

```bash
git clone https://github.com/engrbilal992/DeadDialect.git
cd DeadDialect/integration

# Build patched QEMU 8.2.0 (~10 min first run)
bash build.sh

# Security demo
bash demo.sh

# One trigger rotates both layers simultaneously
bash trigger/trigger_demo.sh

# Boot Alpine Linux under patched QEMU
cd alpine
bash setup_alpine.sh   # first time only — downloads kernel + rootfs
bash boot_alpine.sh    # boots to ~ # prompt in ~30 seconds

# Alpine ISA demos
bash alpine_demo.sh
bash full_alpine_test.sh
```

---

## Demo Results

### 6-scenario security proof

```
T1: Standard binary,   empty keyrings    →  runs   ✓
T2: Integrated binary, correct keyrings  →  runs   ✓
T3: Standard binary,   active keyrings   →  SIGILL ✗
T4: Integrated binary, empty keyrings    →  SIGILL ✗
T5: Wrong-seed binary                    →  SIGILL ✗
T6: Correct seed binary                  →  runs   ✓
```

### Trigger demo

```
Session A  binary runs                        SUCCESS ✓
Session A  malware runs                       EXECUTED (expected — same session)
           ── trigger fires ──
Session B  old binary                         BLOCKED ✓
Session B  malware                            BLOCKED ✓
Session B  new binary compiled for B          SUCCESS ✓
```

### Stress tests

```
100,000 seeds — zero collisions
Seed 999999999                →  BLOCKED under different session ✓
Seed 2²⁵⁶-1 (max 256-bit)    →  BLOCKED under different session ✓
Keyring corrupted mid-run     →  BLOCKED on corrupted keyring   ✓
```

---

## Audit Results

| Milestone | Checks | Status |
|---|---|---|
| Trigger remapping | 37/37 | ✓ |
| Syscall remapping | 40/40 | ✓ |
| Register remapping | 43/43 | ✓ |
| Integration | 51/51 | ✓ |

---

## Security Properties

### What it stops
- **Malware persistence** — any binary from a previous session is dead on next boot
- **Pre-compiled exploits** — shellcode for a fixed ISA fails immediately
- **Replay attacks** — binaries from one session cannot execute in another
- **Standard QEMU execution** — remapped binaries require the patched executor

### Why the entropy matters

```
Guessing register permutation:  1 in 21!  ≈ 1 in 51 quintillion
Guessing syscall permutation:   1 in 436! ≈ 1 in 10^(1000+)
Guessing both simultaneously:   not a viable attack
```

### POC scope
- `-march=rv64g` required (RVC compressed instructions not yet handled)
- Static binaries only for test programs (dynamic support via `isa_remap_ldso.h`)
- Attacks completing within a single session are not addressed

---

## How Each Layer Works

### Register (`register_mapping.h`)
21 of 32 RISC-V registers shuffled. ABI registers frozen. QEMU hook uses `OPCODE_FIELDS` table — only actual register fields remapped, immediates never touched (Curtis's fix).

| Frozen | Shuffleable |
|---|---|
| x0 x1 x2 x10-x17 | x3-x9, x18-x31 (21 regs) |

### Syscall (`syscall_mapping.h`)
436 Linux RISC-V syscalls permuted. One line in `do_syscall()`. mtime-reload — keyring updates without QEMU restart.

### Opcode (`isa_mapping.h`)
12 primary opcodes shuffled. Decode hook in `translate.c` restores standard opcode before decoder.

### ld.so (`isa_remap_ldso.h`)
musl dynamic linker patch — remaps `.text` of every loaded ELF at load time. Cannot be bypassed via `LD_PRELOAD`. Requires Alpine musl rebuild.

---

## Future Directions

- ARM support (same concept, different fixed ISA contract)
- Kernel `.text` remapping pre-boot
- Hardware FPGA implementation
- Hacker News / academic publication
- GitHub Sponsors

---

## Author

**Curtis Cole** — April 2026
**Muhammad Bilal** — April 2026

*"I knew my idea was real but I'm pretty sure everyone just thought I was crazy."* — Curtis Cole
