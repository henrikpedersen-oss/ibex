# Ibex-local changes to the riscv-isa-sim mseccfg tests

These tests are vendored from riscv-isa-sim and are driven by the `epmp-tests`
config in `dv/uvm/core_ibex/directed_tests/directed_testlist.yaml`. They carry
local changes so that they run against Ibex's memory map rather than Spike's.
Anything here needs re-applying if the vendored copy is refreshed.

Note the generator's `gengen` tool (`gengen_tool/`) is **not** present in this
checkout, so `gengen_src/outputs/*.c` cannot be regenerated from the skeletons
here. Any change must therefore be made at all three levels so that they stay
consistent for whoever does have the tool:

1. `gengen_src/*.cc_skel` — the source of truth
2. `gengen_src/*.h` — what `gen_pmp_test.cc` compiles (produced from the skeletons by `gengen`)
3. `gengen_src/outputs/*.c` — the 744 generated tests the build actually uses

## 1. Linker VMA offset (`mseccfg_test.ld`)

The Ibex testbench maps ELF VMA to simulation address with a fixed `+0x7FF00000`
offset, so the `MEMORY` origins are chosen to land where the C sources expect:
`TEST_MEM` at `0x300000` -> `0x80200000` (`TEST_MEM_START`), `U_MEM` at
`0x340000` -> `0x80240000` (`TEST_MEM_END`).

## 2. `pmpaddr7` for the signature address

`csrw pmpaddr7, (0x8ffffff8 >> 2)` with `R|W|NAPOT` in all three skeletons.
Ibex's testbench handshake writes to `SIGNATURE_ADDR 0x8ffffff8`
(`syscalls.c:14`), which is outside every region the upstream tests set up. With
`mseccfg.MMWP=1` that write would be denied and the test could not report its
result.

## 3. `pmp0` sized to M_MEM, not 8 MiB  (2026-09-22)

`csrw pmpaddr0, ((0x80000000 >> 2) | 0x1ffff)` — was `| 0xfffff` upstream.

Only reachable under `#if M_MODE_RWX`, which is set for 32 of the 192
`test_pmp_ok_1` tests and none of the `test_pmp_csr_1` / `test_pmp_ok_share_1`
ones.

The skeleton comment states the intent: *"Set pmp0cfg for M mode (M_MEM)"*. But
`0xfffff` is 20 trailing ones, so the NAPOT region is `2^(20+3)` = **8 MiB**,
covering `0x80000000`–`0x80800000`. M_MEM is `LENGTH = 1M` in
`mseccfg_test.ld`, so that region also swallowed `TEST_MEM` (`0x80200000`) and
`U_MEM` (`0x80240000`) — the very regions under test. Because `pmp0` is the
lowest-numbered entry it won the priority match every time, so the `pmp2` entry
being tested was never consulted, and with `L=0` it left M-mode unrestricted.

`0x1ffff` is 17 trailing ones -> `2^(17+3)` = 1 MiB = `0x80000000`–`0x80100000`,
matching M_MEM exactly. That still covers all M-mode code, data, `__global_pointer$`
(`0x80040000`), `_end` (`0x80080000`) and the 128 KiB stack above it, while
leaving `TEST_MEM` and `U_MEM` to the entries that are supposed to govern them.

### Why it showed up as 21 regression failures

`gen_pmp_test.cc` keys two independent decisions off the *same* expression:

```cpp
if (mml) { set_m_mode_rwx(0); }
else     { set_m_mode_rwx(cur_files_count % 3 == 0 ? 1 : 0); }
...
} else {                                  // pmp_match == 0
    if (cur_files_count % 3 == 0) {
        set_create_pmp_cfg(1);
        set_pmp_addr_offset(0x100);       // create an address mismatch
    }
    if (u_mode == 1 || mmwp) { rw_err = 1; x_err = 1; }   // assumes nothing matches
```

So exactly when it creates the address mismatch it also installs the oversized
`pmp0`, which matches anyway and defeats the mismatch — then asserts the access
must fail. `mml=1` forces `m_mode_rwx` to 0, which is why the `mml1` half of the
matrix never failed.

Before the change, of the 32 `M_MODE_RWX=1` tests: all 21 that expected a fault
failed, and the 11 that expected none passed *vacuously* (nothing could fault).
After it, all 32 pass, and `test_pmp_ok_1_u0_rw00_x0_l0_match0_mmwp1_mml0` now
takes real `trap_load_access_fault` / `trap_store_access_fault` and a
`trap_instruction_access_fault` at `epc 0x80200000`, where it previously took
none.

This is a stimulus bug in the upstream generator, not an Ibex RTL defect: the
cosim reported zero DUT/Spike mismatches on every one of these failures both
before and after — Spike and the RTL always agreed, and it was the test's own
self-check that failed. Worth reporting upstream.

### Not fixed by this

The 5 failing `test_pmp_csr_1_*_mml1_*` tests are unrelated — `gen_pmp_test.cc`
sets `m_mode_rwx(0)` unconditionally for that family, so `pmp0` is `PMP_OFF` and
this change is compiled out for all 528 of them.
