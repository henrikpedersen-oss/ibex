# Testplan

## Testpoints

### Stage V1 Testpoints

#### `rdv_random_instructions`

Tests:
- `riscv_arithmetic_basic_test`
- `riscv_machine_mode_rand_test`
- `riscv_rand_instr_test`
- `riscv_rv32im_instr_test`
- `riscv_user_mode_rand_test`


Random instruction streams checked against Spike

Random instruction streams in M and U mode, arithmetic-only through full RV32IMC,
compared instruction by instruction against Spike (cosim).

- riscv_arithmetic_basic_test: Arithmetic instruction test, no load/store/branch
  instructions
- riscv_machine_mode_rand_test: Machine mode random instruction test
- riscv_rand_instr_test: Random instruction stress test
- riscv_rv32im_instr_test: Random instruction test without compressed instructions
- riscv_user_mode_rand_test: User mode random instruction tes

#### `directed_flow_smoke`

Test: `empty`

Directed-test flow smoke test

The directed-test flow itself: an empty test boots, signals completion and passes the
testbench's end-of-test checks. If this fails, no other directed result means
anything.

- empty: Empty directed test

#### `riscv_tests_isa`

Tests:
- `add`
- `addi`
- `and`
- `andi`
- `auipc`
- `beq`
- `bge`
- `bgeu`
- `blt`
- `bltu`
- `bne`
- `breakpoint`
- `csr`
- `div`
- `divu`
- `fence_i`
- `illegal`
- `jal`
- `jalr`
- `lb`
- `lbu`
- `lh`
- `lh-misaligned`
- `lhu`
- `lui`
- `lw`
- `lw-misaligned`
- `ma_addr`
- `ma_fetch`
- `mcsr`
- `mul`
- `mulh`
- `mulhsu`
- `mulhu`
- `or`
- `ori`
- `rem`
- `remu`
- `rvc`
- `sb`
- `sbreak`
- `scall`
- `sh`
- `sh-misaligned`
- `shamt`
- `simple`
- `sll`
- `slli`
- `slt`
- `slti`
- `sltiu`
- `sltu`
- `sra`
- `srai`
- `srl`
- `srli`
- `sub`
- `sw`
- `sw-misaligned`
- `xor`
- `xori`
- `zicntr`


riscv-tests ISA suites

riscv-tests ISA suites rv32ui, rv32um and rv32mi: each instruction and M-mode
behaviour self-checks and passes.

Generated tests from directed_testlist.yaml; each name encodes its scenario (add ...
zicntr).

#### `riscv_arch_tests`

Tests:
- `Fencei`
- `add-01`
- `addi-01`
- `and-01`
- `andi-01`
- `andn-01`
- `auipc-01`
- `bclr-01`
- `bclri-01`
- `beq-01`
- `bext-01`
- `bexti-01`
- `bge-01`
- `bgeu-01`
- `binv-01`
- `binvi-01`
- `blt-01`
- `bltu-01`
- `bne-01`
- `bset-01`
- `bseti-01`
- `cadd-01`
- `caddi-01`
- `caddi16sp-01`
- `caddi4spn-01`
- `cand-01`
- `candi-01`
- `cbeqz-01`
- `cbnez-01`
- `cebreak-01`
- `cj-01`
- `cjal-01`
- `cjalr-01`
- `cjr-01`
- `cli-01`
- `clmul-01`
- `clmulh-01`
- `clmulr-01`
- `clui-01`
- `clw-01`
- `clwsp-01`
- `clz-01`
- `cmv-01`
- `cnop-01`
- `cor-01`
- `cpop-01`
- `cslli-01`
- `csrai-01`
- `csrli-01`
- `csub-01`
- `csw-01`
- `cswsp-01`
- `ctz-01`
- `cxor-01`
- `div-01`
- `divu-01`
- `fence-01`
- `jal-01`
- `jalr-01`
- `lb-align-01`
- `lbu-align-01`
- `lh-align-01`
- `lhu-align-01`
- `lui-01`
- `lw-align-01`
- `max-01`
- `maxu-01`
- `min-01`
- `minu-01`
- `misalign1-jalr-01`
- `mul-01`
- `mulh-01`
- `mulhsu-01`
- `mulhu-01`
- `or-01`
- `orcb_32-01`
- `ori-01`
- `orn-01`
- `rem-01`
- `remu-01`
- `rev8_32-01`
- `rol-01`
- `ror-01`
- `rori-01`
- `sb-align-01`
- `sext-b-01`
- `sext-h-01`
- `sh-align-01`
- `sh1add-01`
- `sh2add-01`
- `sh3add-01`
- `sll-01`
- `slli-01`
- `slt-01`
- `slti-01`
- `sltiu-01`
- `sltu-01`
- `sra-01`
- `srai-01`
- `srl-01`
- `srli-01`
- `sub-01`
- `sw-align-01`
- `xnor-01`
- `xor-01`
- `xori-01`
- `zext-h_32-01`


RISC-V architectural test suite

RISC-V architectural test suite (I, M, C, B): each test's signature matches the
reference.

Generated tests from directed_testlist.yaml; each name encodes its scenario (Fencei
... zext-h_32-01).

### Stage V2 Testpoints

#### `rdv_control_flow`

Tests:
- `riscv_fetch_en_chk_test`
- `riscv_jump_stress_test`
- `riscv_loop_test`
- `riscv_rand_jump_test`


Random jumps, branches and loops

Random jumps, jump stress and loops: branch/jump targets, the prefetch buffer and
instruction-side flushes; fetch_enable_i toggled while loads and stores are in flight
(riscv_fetch_en_chk_test).

- riscv_fetch_en_chk_test: Load/store-heavy random program while fetch_enable_i is
  toggled by a second, more frequent generator (core_ibex_fetch_en_chk_test) on top
  of the default one. Targets uarch_cg.pipe_cross: fetch disabled while a load or
  store is waiting in writeback.
- riscv_jump_stress_test: Stress back to back jump instruction
- riscv_loop_test: Loop test
- riscv_rand_jump_test: Jump among large number of sub-programs, stress testing iTLB
  operations.

#### `rdv_exceptions`

Tests:
- `riscv_ebreak_test`
- `riscv_hint_instr_test`
- `riscv_illegal_instr_test`
- `riscv_invalid_csr_test`


Illegal instructions, hints, ebreak and invalid CSRs

Illegal instructions, hints, ebreak and invalid CSR accesses trap (or retire) exactly
as the reference model does, and the handler resumes correctly.

- riscv_ebreak_test: Random instruction test with ebreak instruction enabled. Debug
  mode is not enabled for this test, processor should raise ebreak exception.
- riscv_hint_instr_test: HINT instruction test, verify the processor can detect HINT
  instruction treat it as NOP. No illegal instruction exception is expected
- riscv_illegal_instr_test: Illegal instruction test, verify the processor can detect
  illegal instruction and handle corresponding exception properly. An exception
  handling routine is designed to resume execution after illegal instruction
  exception.
- riscv_invalid_csr_test: Boot core into random priv mode and generate csr accesses
  to invalid CSRs (at a higher priv mode)

#### `rdv_debug`

Tests:
- `riscv_debug_basic_test`
- `riscv_debug_branch_jump_test`
- `riscv_debug_csr_entry_test`
- `riscv_debug_ebreak_test`
- `riscv_debug_ebreakmu_test`
- `riscv_debug_in_irq_test`
- `riscv_debug_instr_test`
- `riscv_debug_on_stall_test`
- `riscv_debug_single_step_test`
- `riscv_debug_stress_test`
- `riscv_debug_triggers_test`
- `riscv_debug_wfi_test`
- `riscv_dret_test`
- `riscv_irq_in_debug_mode_test`


Debug mode entry, exit and interaction with interrupts

Debug mode: entry by request, trigger, ebreak and single step; dret; debug CSRs;
debug and interrupts in both orders; debug during WFI and branches.

- riscv_debug_basic_test: Randomly assert debug_req_i, random instruction sequence in
  debug_rom section
- riscv_debug_branch_jump_test: Randomly assert debug_req_i, insert branch
  instructions and subprograms into debug_rom to make core jump around within the
  debug_rom
- riscv_debug_csr_entry_test: Inject debug stimulus during writes to xSTATUS and xIE
- riscv_debug_ebreak_test: A directed ebreak sequence will be inserted into the debug
  rom, upon encountering it, ibex should jump back to the beginning of debug mode.
  The sequence is designed to avoid an infinite loop.
- riscv_debug_ebreakmu_test: dcsr.ebreakm will be set at the beginning of the test
  upon the first entry into the debug rom. From then on, every ebreak instruction
  should cause debug mode to be entered.
- riscv_debug_in_irq_test: Send debug stimulus while core is in an interrupt handler
- riscv_debug_instr_test: At a high level, this test checks that Ibex can correctly
  respond after receiving debug stimulus while every supported instruction is in its
  decoding stage. e.g. If the test detects a LUI instruction in the decoding stage, a
  debug request is generated and sent into Ibex. We never send a debug request if we
  see a LUI instruction again, as we don't want to send in debug requests for every
  instruction that is executed.
- riscv_debug_on_stall_test: Random program with load/store hazard streams, data-
  independent timing toggles and illegal instructions under
  core_ibex_stall_events_test: debug requests raised while an instruction is held in
  ID (stalled or waiting to trap), and fetch_enable_i dropped for a few cycles there.
  Targets the debug_req = 1 bins of uarch_cg.exception_stall_instr_cross without LSU
  errors, debug_entry_if_instr_cross and pipe_cross (IF idle while ID is stalled).
- riscv_debug_single_step_test: Randomly assert debug_req_i, and set dcsr.step to
  make ibex execute one insn then re-enter debug mode The riscv-dv plusarg
  +enable_debug_single_step adds a short sequence of assembly
  (riscv_debug_rom_gen::gen_single_step_logic) that single-steps for a randomized
  number of sequential instructions. It stops setting dcsr.step after the counter
  reaches 0, and then starts the process again the next time an external debug
  stimulus is encountered.
- riscv_debug_stress_test: Randomly assert debug_req_i more often, debug_rom is
  empty, with only a dret instruction
- riscv_debug_triggers_test: Test stimulus includes directed routine which set the
  breakpoint addr forwards a few instructions. This test has no pass/fail criteria,
  but instead is used to gather appropriate coverage. //
  rtl_test:core_ibex_single_debug_pulse_test // In combination with the test-program,
  this HALTREQ triggers code that then // enables the DCSR.ebreakm/u functionality.
  From then on, EBREAK instructions trigger the // DUT to run some debug-mode code to
  setup the next breakpoint address.
- riscv_debug_wfi_test: Assert debug_req while core is in WFI sleep state, should
  jump to debug mode
- riscv_dret_test: Dret instructions will be inserted into generated code, ibex
  should treat these like illegal instructions.
- riscv_irq_in_debug_mode_test: Send interrupts while the core is executing in debug
  mode, should ignore everything

#### `rdv_interrupts`

Tests:
- `riscv_assorted_traps_interrupts_debug_test`
- `riscv_interrupt_csr_test`
- `riscv_interrupt_instr_test`
- `riscv_interrupt_wfi_test`
- `riscv_multiple_interrupt_test`
- `riscv_nested_interrupt_test`
- `riscv_nmi_at_exc_test`
- `riscv_single_interrupt_test`


Interrupt handling

Single, multiple and nested interrupts, interrupts during WFI and CSR access, traps
mixed with interrupts and debug, and NMIs taken ahead of an excepting instruction in
ID (riscv_nmi_at_exc_test).

- riscv_assorted_traps_interrupts_debug_test: Send assorted, intermixed stimulus to
  test trap-handling and recovery
- riscv_interrupt_csr_test: Inject interrupts during dummy writes to xSTATUS and xIE
- riscv_interrupt_instr_test: At a high level, this test checks that Ibex can
  correctly respond after receiving interrupt stimulus while every supported
  instruction is in its decoding stage. e.g. If the test detects a LUI instruction in
  the decoding stage, an interrupt is generated and sent into Ibex. We never send an
  interrupt if we see a LUI instruction again, as we don't want to send interrupts
  for every instruction that is executed.
- riscv_interrupt_wfi_test: Inject interrupts after a encountering wfi instructions.
- riscv_multiple_interrupt_test, riscv_single_interrupt_test: Random instruction test
  with complete interrupt handling
- riscv_nested_interrupt_test: Assert interrupt, and then assert another interrupt
  during the first irq_handler routine
- riscv_nmi_at_exc_test: NMIs raised while an excepting instruction (ECALL, EBREAK as
  an exception, an illegal instruction) is in ID, so the NMI is taken ahead of it,
  plus maskable interrupts at random. Targets the nmi = 1 bins of
  uarch_cg.interrupt_taken_instr_cross with an excepting last category. No debug
  section: EBREAK must raise a breakpoint exception, not enter debug mode.

#### `rdv_csrs_and_privilege`

Tests:
- `riscv_csr_test`
- `riscv_umode_tw_test`


CSR behaviour and U-mode WFI timeout

CSR read/write behaviour against the CSR description, and U-mode WFI timeout
(mstatus.TW).

- riscv_csr_test: Test all CSR instructions on all implemented CSR registers
- riscv_umode_tw_test: Set mstatus.tw and enable generation of WFI instructions. Boot
  into U-mode, upon encountering WFI instruction, core should trap to M-mode due to
  illegal instruction exception.

#### `rdv_memory`

Tests:
- `riscv_mem_error_test`
- `riscv_mem_error_traps_test`
- `riscv_mmu_stress_test`
- `riscv_unaligned_load_store_test`


Unaligned accesses, bus errors and memory stress

Unaligned loads and stores, bus errors on data and instruction fetch, and memory
stress; bus errors with interrupts and debug requests on top, some raised the moment
a data-side error is decided so that they are pending when it arrives
(riscv_mem_error_traps_test).

- riscv_mem_error_test: Normal random instruction test, but randomly insert
  instruction fetch or memory load/store errors
- riscv_mem_error_traps_test: riscv_mem_error_test with interrupts and debug requests
  on top (the irq/debug generators of riscv_assorted_traps_interrupts_debug_test).
  Targets the irq_pending/debug_req bins of uarch_cg.exception_stall_instr_cross:
  memory and PMP errors, stalls and instruction categories crossed with a pending
  interrupt or debug request.
- riscv_mmu_stress_test: Test with different patterns of load/store instructions,
  stress test MMU operations.
- riscv_unaligned_load_store_test: Unaligned load/store test, ibex should handle it
  correctly without raising any exception

#### `rdv_reset`

Test: `riscv_reset_test`

Reset during execution

Reset in the middle of execution returns the core to its reset state.

- riscv_reset_test: Randomly reset the core once in the middle of program execution

#### `rdv_pmp_epmp`

Tests:
- `riscv_epmp_mml_execute_only_test`
- `riscv_epmp_mml_read_only_test`
- `riscv_epmp_mml_test`
- `riscv_epmp_mmwp_test`
- `riscv_epmp_rlb_test`
- `riscv_pmp_basic_test`
- `riscv_pmp_disable_all_regions_test`
- `riscv_pmp_full_random_test`
- `riscv_pmp_out_of_bounds_test`
- `riscv_pmp_region_exec_test`
- `riscv_pmp_traps_test`


Random PMP and ePMP configurations

PMP and ePMP (mseccfg MML/MMWP/RLB): region matching, permissions, locked regions,
out-of-bounds and fully random configurations.

- riscv_epmp_mml_execute_only_test: An enhanced PMP machine mode lockdown test - all
  PMP regions are set to execute only. Exception is expected on any store or load.
  Randomize mstatus.mprv.
- riscv_epmp_mml_read_only_test: An enhanced PMP machine mode lockdown test - all PMP
  regions are set to shared read only. Exception is expected right after enabling
  MML. Randomize mstatus.mprv.
- riscv_epmp_mml_test: An enhanced PMP machine mode lockdown test - initialization
  and main regions are set to execute only in both M and U modes. All other regions
  are set to read/write only. Exceptions when reading/writing code or executing data.
  Randomize mstatus.mprv.
- riscv_epmp_mmwp_test: An enhanced PMP machine mode whitelist policy - all PMP
  regions will be configured to default setting, enabling all forms of accesses,
  expect that an exception when machine mode access memory not in PMP. Randomize
  mstatus.mprv.
- riscv_epmp_rlb_test: An enhanced PMP rule lock bypass - all PMP regions are locked
  and enable all forms of accesses, expect that no exception will be thrown even when
  trying to change locked entries. Randomize mstatus.mprv.
- riscv_pmp_basic_test: Basic PMP test - all PMP regions will be configured to
  default setting, enabling all forms of accesses, expect that no exception will be
  thrown. Randomize mstatus.mprv.
- riscv_pmp_disable_all_regions_test: Disable all permissions from PMP regions,
  randomize the boot mode, and randomize mstatus.mprv. Expect that all appropriate
  faults are taken, and that the core finishes executing successfully.
- riscv_pmp_full_random_test: Completely randomize the boot mode, mstatus.mprv, and
  all PMP configuration, and allow PMP regions to overlap.  A large number of
  iterations will be required since this introduces a huge state space of
  configurations.  Some configurations result in very slow execution as every
  instruction ends up generating a fault. As this is still a useful test a short
  timeout with pass on timeout is enabled.
- riscv_pmp_out_of_bounds_test: Default PMP settings - enable all regions with full
  permissions. Randomize mstatus.mprv and the boot mode. Insert streams of memory
  instructions that access addresses out of PMP boundaries.
- riscv_pmp_region_exec_test: A more specialised pmp_full_random_test that attempts
  to make regions executable whilst MML is set.
- riscv_pmp_traps_test: riscv_pmp_full_random_test with interrupts on top
  (core_ibex_irq_traps_test: stimulus only, no per-interrupt checks). Targets the
  PMP-error bins of uarch_cg.exception_stall_instr_cross crossed with a pending
  interrupt. No debug requests: Ibex exempts the debug module range from PMP in debug
  mode and Spike does not, so random PMP configurations break every debug entry.

#### `rdv_bitmanip`

Tests:
- `riscv_bitmanip_balanced_test`
- `riscv_bitmanip_full_test`
- `riscv_bitmanip_otearlgrey_test`


Bit-manipulation instructions

Bit-manipulation instructions for each supported configuration.

- riscv_bitmanip_balanced_test: Random instruction test with supported B extension
  instructions in balanced configuration
- riscv_bitmanip_full_test: Random instruction test with supported B extension
  instructions in full configuration
- riscv_bitmanip_otearlgrey_test: Random instruction test with supported B extension
  instructions in OTEarlGrey configuration

#### `epmp_generated`

Tests:
- `test_pmp_csr_1_lock00_rlb0_mmwp0_mml0_pmp_01`
- `test_pmp_csr_1_lock00_rlb0_mmwp0_mml0_pmp_02`
- `test_pmp_csr_1_lock00_rlb0_mmwp0_mml0_pmp_03`
- `test_pmp_csr_1_lock00_rlb0_mmwp0_mml0_pmp_04`
- `test_pmp_csr_1_lock00_rlb0_mmwp0_mml0_pmp_05`
- `test_pmp_csr_1_lock00_rlb0_mmwp0_mml0_pmp_06`
- `test_pmp_csr_1_lock00_rlb0_mmwp0_mml0_pmp_07`
- `test_pmp_csr_1_lock00_rlb0_mmwp0_mml0_pmp_11`
- `test_pmp_csr_1_lock00_rlb0_mmwp0_mml0_pmp_12`
- `test_pmp_csr_1_lock00_rlb0_mmwp0_mml0_pmp_13`
- `test_pmp_csr_1_lock00_rlb0_mmwp0_mml0_pmp_14`
- `test_pmp_csr_1_lock00_rlb0_mmwp0_mml0_pmp_15`
- `test_pmp_csr_1_lock00_rlb0_mmwp0_mml0_pmp_16`
- `test_pmp_csr_1_lock00_rlb0_mmwp0_mml0_pmp_17`
- `test_pmp_csr_1_lock00_rlb0_mmwp0_mml0_sec_00`
- `test_pmp_csr_1_lock00_rlb0_mmwp0_mml0_sec_01`
- `test_pmp_csr_1_lock00_rlb0_mmwp0_mml0_sec_02`
- `test_pmp_csr_1_lock00_rlb0_mmwp0_mml0_sec_03`
- `test_pmp_csr_1_lock00_rlb0_mmwp0_mml0_sec_04`
- `test_pmp_csr_1_lock00_rlb0_mmwp0_mml0_sec_05`
- `test_pmp_csr_1_lock00_rlb0_mmwp0_mml0_sec_06`
- `test_pmp_csr_1_lock00_rlb0_mmwp0_mml0_sec_07`
- `test_pmp_csr_1_lock00_rlb0_mmwp0_mml1_pmp_01`
- `test_pmp_csr_1_lock00_rlb0_mmwp0_mml1_pmp_02`
- `test_pmp_csr_1_lock00_rlb0_mmwp0_mml1_pmp_03`
- `test_pmp_csr_1_lock00_rlb0_mmwp0_mml1_pmp_04`
- `test_pmp_csr_1_lock00_rlb0_mmwp0_mml1_pmp_05`
- `test_pmp_csr_1_lock00_rlb0_mmwp0_mml1_pmp_06`
- `test_pmp_csr_1_lock00_rlb0_mmwp0_mml1_pmp_07`
- `test_pmp_csr_1_lock00_rlb0_mmwp0_mml1_pmp_11`
- `test_pmp_csr_1_lock00_rlb0_mmwp0_mml1_pmp_12`
- `test_pmp_csr_1_lock00_rlb0_mmwp0_mml1_pmp_13`
- `test_pmp_csr_1_lock00_rlb0_mmwp0_mml1_pmp_14`
- `test_pmp_csr_1_lock00_rlb0_mmwp0_mml1_pmp_15`
- `test_pmp_csr_1_lock00_rlb0_mmwp0_mml1_pmp_16`
- `test_pmp_csr_1_lock00_rlb0_mmwp0_mml1_pmp_17`
- `test_pmp_csr_1_lock00_rlb0_mmwp0_mml1_sec_00`
- `test_pmp_csr_1_lock00_rlb0_mmwp0_mml1_sec_01`
- `test_pmp_csr_1_lock00_rlb0_mmwp0_mml1_sec_02`
- `test_pmp_csr_1_lock00_rlb0_mmwp0_mml1_sec_03`
- `test_pmp_csr_1_lock00_rlb0_mmwp0_mml1_sec_04`
- `test_pmp_csr_1_lock00_rlb0_mmwp0_mml1_sec_05`
- `test_pmp_csr_1_lock00_rlb0_mmwp0_mml1_sec_06`
- `test_pmp_csr_1_lock00_rlb0_mmwp0_mml1_sec_07`
- `test_pmp_csr_1_lock00_rlb0_mmwp1_mml0_pmp_01`
- `test_pmp_csr_1_lock00_rlb0_mmwp1_mml0_pmp_02`
- `test_pmp_csr_1_lock00_rlb0_mmwp1_mml0_pmp_03`
- `test_pmp_csr_1_lock00_rlb0_mmwp1_mml0_pmp_04`
- `test_pmp_csr_1_lock00_rlb0_mmwp1_mml0_pmp_05`
- `test_pmp_csr_1_lock00_rlb0_mmwp1_mml0_pmp_06`
- `test_pmp_csr_1_lock00_rlb0_mmwp1_mml0_pmp_07`
- `test_pmp_csr_1_lock00_rlb0_mmwp1_mml0_pmp_11`
- `test_pmp_csr_1_lock00_rlb0_mmwp1_mml0_pmp_12`
- `test_pmp_csr_1_lock00_rlb0_mmwp1_mml0_pmp_13`
- `test_pmp_csr_1_lock00_rlb0_mmwp1_mml0_pmp_14`
- `test_pmp_csr_1_lock00_rlb0_mmwp1_mml0_pmp_15`
- `test_pmp_csr_1_lock00_rlb0_mmwp1_mml0_pmp_16`
- `test_pmp_csr_1_lock00_rlb0_mmwp1_mml0_pmp_17`
- `test_pmp_csr_1_lock00_rlb0_mmwp1_mml0_sec_00`
- `test_pmp_csr_1_lock00_rlb0_mmwp1_mml0_sec_01`
- `test_pmp_csr_1_lock00_rlb0_mmwp1_mml0_sec_02`
- `test_pmp_csr_1_lock00_rlb0_mmwp1_mml0_sec_03`
- `test_pmp_csr_1_lock00_rlb0_mmwp1_mml0_sec_04`
- `test_pmp_csr_1_lock00_rlb0_mmwp1_mml0_sec_05`
- `test_pmp_csr_1_lock00_rlb0_mmwp1_mml0_sec_06`
- `test_pmp_csr_1_lock00_rlb0_mmwp1_mml0_sec_07`
- `test_pmp_csr_1_lock00_rlb0_mmwp1_mml1_pmp_01`
- `test_pmp_csr_1_lock00_rlb0_mmwp1_mml1_pmp_02`
- `test_pmp_csr_1_lock00_rlb0_mmwp1_mml1_pmp_03`
- `test_pmp_csr_1_lock00_rlb0_mmwp1_mml1_pmp_04`
- `test_pmp_csr_1_lock00_rlb0_mmwp1_mml1_pmp_05`
- `test_pmp_csr_1_lock00_rlb0_mmwp1_mml1_pmp_06`
- `test_pmp_csr_1_lock00_rlb0_mmwp1_mml1_pmp_07`
- `test_pmp_csr_1_lock00_rlb0_mmwp1_mml1_pmp_11`
- `test_pmp_csr_1_lock00_rlb0_mmwp1_mml1_pmp_12`
- `test_pmp_csr_1_lock00_rlb0_mmwp1_mml1_pmp_13`
- `test_pmp_csr_1_lock00_rlb0_mmwp1_mml1_pmp_14`
- `test_pmp_csr_1_lock00_rlb0_mmwp1_mml1_pmp_15`
- `test_pmp_csr_1_lock00_rlb0_mmwp1_mml1_pmp_16`
- `test_pmp_csr_1_lock00_rlb0_mmwp1_mml1_pmp_17`
- `test_pmp_csr_1_lock00_rlb0_mmwp1_mml1_sec_00`
- `test_pmp_csr_1_lock00_rlb0_mmwp1_mml1_sec_01`
- `test_pmp_csr_1_lock00_rlb0_mmwp1_mml1_sec_02`
- `test_pmp_csr_1_lock00_rlb0_mmwp1_mml1_sec_03`
- `test_pmp_csr_1_lock00_rlb0_mmwp1_mml1_sec_04`
- `test_pmp_csr_1_lock00_rlb0_mmwp1_mml1_sec_05`
- `test_pmp_csr_1_lock00_rlb0_mmwp1_mml1_sec_06`
- `test_pmp_csr_1_lock00_rlb0_mmwp1_mml1_sec_07`
- `test_pmp_csr_1_lock00_rlb1_mmwp0_mml0_pmp_01`
- `test_pmp_csr_1_lock00_rlb1_mmwp0_mml0_pmp_02`
- `test_pmp_csr_1_lock00_rlb1_mmwp0_mml0_pmp_03`
- `test_pmp_csr_1_lock00_rlb1_mmwp0_mml0_pmp_04`
- `test_pmp_csr_1_lock00_rlb1_mmwp0_mml0_pmp_05`
- `test_pmp_csr_1_lock00_rlb1_mmwp0_mml0_pmp_06`
- `test_pmp_csr_1_lock00_rlb1_mmwp0_mml0_pmp_07`
- `test_pmp_csr_1_lock00_rlb1_mmwp0_mml0_pmp_11`
- `test_pmp_csr_1_lock00_rlb1_mmwp0_mml0_pmp_12`
- `test_pmp_csr_1_lock00_rlb1_mmwp0_mml0_pmp_13`
- `test_pmp_csr_1_lock00_rlb1_mmwp0_mml0_pmp_14`
- `test_pmp_csr_1_lock00_rlb1_mmwp0_mml0_pmp_15`
- `test_pmp_csr_1_lock00_rlb1_mmwp0_mml0_pmp_16`
- `test_pmp_csr_1_lock00_rlb1_mmwp0_mml0_pmp_17`
- `test_pmp_csr_1_lock00_rlb1_mmwp0_mml0_sec_00`
- `test_pmp_csr_1_lock00_rlb1_mmwp0_mml0_sec_01`
- `test_pmp_csr_1_lock00_rlb1_mmwp0_mml0_sec_02`
- `test_pmp_csr_1_lock00_rlb1_mmwp0_mml0_sec_03`
- `test_pmp_csr_1_lock00_rlb1_mmwp0_mml0_sec_04`
- `test_pmp_csr_1_lock00_rlb1_mmwp0_mml0_sec_05`
- `test_pmp_csr_1_lock00_rlb1_mmwp0_mml0_sec_06`
- `test_pmp_csr_1_lock00_rlb1_mmwp0_mml0_sec_07`
- `test_pmp_csr_1_lock00_rlb1_mmwp0_mml1_pmp_01`
- `test_pmp_csr_1_lock00_rlb1_mmwp0_mml1_pmp_02`
- `test_pmp_csr_1_lock00_rlb1_mmwp0_mml1_pmp_03`
- `test_pmp_csr_1_lock00_rlb1_mmwp0_mml1_pmp_04`
- `test_pmp_csr_1_lock00_rlb1_mmwp0_mml1_pmp_05`
- `test_pmp_csr_1_lock00_rlb1_mmwp0_mml1_pmp_06`
- `test_pmp_csr_1_lock00_rlb1_mmwp0_mml1_pmp_07`
- `test_pmp_csr_1_lock00_rlb1_mmwp0_mml1_pmp_11`
- `test_pmp_csr_1_lock00_rlb1_mmwp0_mml1_pmp_12`
- `test_pmp_csr_1_lock00_rlb1_mmwp0_mml1_pmp_13`
- `test_pmp_csr_1_lock00_rlb1_mmwp0_mml1_pmp_14`
- `test_pmp_csr_1_lock00_rlb1_mmwp0_mml1_pmp_15`
- `test_pmp_csr_1_lock00_rlb1_mmwp0_mml1_pmp_16`
- `test_pmp_csr_1_lock00_rlb1_mmwp0_mml1_pmp_17`
- `test_pmp_csr_1_lock00_rlb1_mmwp0_mml1_sec_00`
- `test_pmp_csr_1_lock00_rlb1_mmwp0_mml1_sec_01`
- `test_pmp_csr_1_lock00_rlb1_mmwp0_mml1_sec_02`
- `test_pmp_csr_1_lock00_rlb1_mmwp0_mml1_sec_03`
- `test_pmp_csr_1_lock00_rlb1_mmwp0_mml1_sec_04`
- `test_pmp_csr_1_lock00_rlb1_mmwp0_mml1_sec_05`
- `test_pmp_csr_1_lock00_rlb1_mmwp0_mml1_sec_06`
- `test_pmp_csr_1_lock00_rlb1_mmwp0_mml1_sec_07`
- `test_pmp_csr_1_lock00_rlb1_mmwp1_mml0_pmp_01`
- `test_pmp_csr_1_lock00_rlb1_mmwp1_mml0_pmp_02`
- `test_pmp_csr_1_lock00_rlb1_mmwp1_mml0_pmp_03`
- `test_pmp_csr_1_lock00_rlb1_mmwp1_mml0_pmp_04`
- `test_pmp_csr_1_lock00_rlb1_mmwp1_mml0_pmp_05`
- `test_pmp_csr_1_lock00_rlb1_mmwp1_mml0_pmp_06`
- `test_pmp_csr_1_lock00_rlb1_mmwp1_mml0_pmp_07`
- `test_pmp_csr_1_lock00_rlb1_mmwp1_mml0_pmp_11`
- `test_pmp_csr_1_lock00_rlb1_mmwp1_mml0_pmp_12`
- `test_pmp_csr_1_lock00_rlb1_mmwp1_mml0_pmp_13`
- `test_pmp_csr_1_lock00_rlb1_mmwp1_mml0_pmp_14`
- `test_pmp_csr_1_lock00_rlb1_mmwp1_mml0_pmp_15`
- `test_pmp_csr_1_lock00_rlb1_mmwp1_mml0_pmp_16`
- `test_pmp_csr_1_lock00_rlb1_mmwp1_mml0_pmp_17`
- `test_pmp_csr_1_lock00_rlb1_mmwp1_mml0_sec_00`
- `test_pmp_csr_1_lock00_rlb1_mmwp1_mml0_sec_01`
- `test_pmp_csr_1_lock00_rlb1_mmwp1_mml0_sec_02`
- `test_pmp_csr_1_lock00_rlb1_mmwp1_mml0_sec_03`
- `test_pmp_csr_1_lock00_rlb1_mmwp1_mml0_sec_04`
- `test_pmp_csr_1_lock00_rlb1_mmwp1_mml0_sec_05`
- `test_pmp_csr_1_lock00_rlb1_mmwp1_mml0_sec_06`
- `test_pmp_csr_1_lock00_rlb1_mmwp1_mml0_sec_07`
- `test_pmp_csr_1_lock00_rlb1_mmwp1_mml1_pmp_01`
- `test_pmp_csr_1_lock00_rlb1_mmwp1_mml1_pmp_02`
- `test_pmp_csr_1_lock00_rlb1_mmwp1_mml1_pmp_03`
- `test_pmp_csr_1_lock00_rlb1_mmwp1_mml1_pmp_04`
- `test_pmp_csr_1_lock00_rlb1_mmwp1_mml1_pmp_05`
- `test_pmp_csr_1_lock00_rlb1_mmwp1_mml1_pmp_06`
- `test_pmp_csr_1_lock00_rlb1_mmwp1_mml1_pmp_07`
- `test_pmp_csr_1_lock00_rlb1_mmwp1_mml1_pmp_11`
- `test_pmp_csr_1_lock00_rlb1_mmwp1_mml1_pmp_12`
- `test_pmp_csr_1_lock00_rlb1_mmwp1_mml1_pmp_13`
- `test_pmp_csr_1_lock00_rlb1_mmwp1_mml1_pmp_14`
- `test_pmp_csr_1_lock00_rlb1_mmwp1_mml1_pmp_15`
- `test_pmp_csr_1_lock00_rlb1_mmwp1_mml1_pmp_16`
- `test_pmp_csr_1_lock00_rlb1_mmwp1_mml1_pmp_17`
- `test_pmp_csr_1_lock00_rlb1_mmwp1_mml1_sec_00`
- `test_pmp_csr_1_lock00_rlb1_mmwp1_mml1_sec_01`
- `test_pmp_csr_1_lock00_rlb1_mmwp1_mml1_sec_02`
- `test_pmp_csr_1_lock00_rlb1_mmwp1_mml1_sec_03`
- `test_pmp_csr_1_lock00_rlb1_mmwp1_mml1_sec_04`
- `test_pmp_csr_1_lock00_rlb1_mmwp1_mml1_sec_05`
- `test_pmp_csr_1_lock00_rlb1_mmwp1_mml1_sec_06`
- `test_pmp_csr_1_lock00_rlb1_mmwp1_mml1_sec_07`
- `test_pmp_csr_1_lock01_rlb0_mmwp0_mml0_pmp_01`
- `test_pmp_csr_1_lock01_rlb0_mmwp0_mml0_pmp_02`
- `test_pmp_csr_1_lock01_rlb0_mmwp0_mml0_pmp_03`
- `test_pmp_csr_1_lock01_rlb0_mmwp0_mml0_pmp_04`
- `test_pmp_csr_1_lock01_rlb0_mmwp0_mml0_pmp_05`
- `test_pmp_csr_1_lock01_rlb0_mmwp0_mml0_pmp_06`
- `test_pmp_csr_1_lock01_rlb0_mmwp0_mml0_pmp_07`
- `test_pmp_csr_1_lock01_rlb0_mmwp0_mml0_pmp_11`
- `test_pmp_csr_1_lock01_rlb0_mmwp0_mml0_pmp_12`
- `test_pmp_csr_1_lock01_rlb0_mmwp0_mml0_pmp_13`
- `test_pmp_csr_1_lock01_rlb0_mmwp0_mml0_pmp_14`
- `test_pmp_csr_1_lock01_rlb0_mmwp0_mml0_pmp_15`
- `test_pmp_csr_1_lock01_rlb0_mmwp0_mml0_pmp_16`
- `test_pmp_csr_1_lock01_rlb0_mmwp0_mml0_pmp_17`
- `test_pmp_csr_1_lock01_rlb0_mmwp0_mml0_sec_00`
- `test_pmp_csr_1_lock01_rlb0_mmwp0_mml0_sec_01`
- `test_pmp_csr_1_lock01_rlb0_mmwp0_mml0_sec_02`
- `test_pmp_csr_1_lock01_rlb0_mmwp0_mml0_sec_03`
- `test_pmp_csr_1_lock01_rlb0_mmwp0_mml0_sec_04`
- `test_pmp_csr_1_lock01_rlb0_mmwp0_mml0_sec_05`
- `test_pmp_csr_1_lock01_rlb0_mmwp0_mml0_sec_06`
- `test_pmp_csr_1_lock01_rlb0_mmwp0_mml0_sec_07`
- `test_pmp_csr_1_lock01_rlb0_mmwp0_mml1_pmp_01`
- `test_pmp_csr_1_lock01_rlb0_mmwp0_mml1_pmp_02`
- `test_pmp_csr_1_lock01_rlb0_mmwp0_mml1_pmp_03`
- `test_pmp_csr_1_lock01_rlb0_mmwp0_mml1_pmp_04`
- `test_pmp_csr_1_lock01_rlb0_mmwp0_mml1_pmp_05`
- `test_pmp_csr_1_lock01_rlb0_mmwp0_mml1_pmp_06`
- `test_pmp_csr_1_lock01_rlb0_mmwp0_mml1_pmp_07`
- `test_pmp_csr_1_lock01_rlb0_mmwp0_mml1_pmp_11`
- `test_pmp_csr_1_lock01_rlb0_mmwp0_mml1_pmp_12`
- `test_pmp_csr_1_lock01_rlb0_mmwp0_mml1_pmp_13`
- `test_pmp_csr_1_lock01_rlb0_mmwp0_mml1_pmp_14`
- `test_pmp_csr_1_lock01_rlb0_mmwp0_mml1_pmp_15`
- `test_pmp_csr_1_lock01_rlb0_mmwp0_mml1_pmp_16`
- `test_pmp_csr_1_lock01_rlb0_mmwp0_mml1_pmp_17`
- `test_pmp_csr_1_lock01_rlb0_mmwp0_mml1_sec_00`
- `test_pmp_csr_1_lock01_rlb0_mmwp0_mml1_sec_01`
- `test_pmp_csr_1_lock01_rlb0_mmwp0_mml1_sec_02`
- `test_pmp_csr_1_lock01_rlb0_mmwp0_mml1_sec_03`
- `test_pmp_csr_1_lock01_rlb0_mmwp0_mml1_sec_04`
- `test_pmp_csr_1_lock01_rlb0_mmwp0_mml1_sec_05`
- `test_pmp_csr_1_lock01_rlb0_mmwp0_mml1_sec_06`
- `test_pmp_csr_1_lock01_rlb0_mmwp0_mml1_sec_07`
- `test_pmp_csr_1_lock01_rlb0_mmwp1_mml0_pmp_01`
- `test_pmp_csr_1_lock01_rlb0_mmwp1_mml0_pmp_02`
- `test_pmp_csr_1_lock01_rlb0_mmwp1_mml0_pmp_03`
- `test_pmp_csr_1_lock01_rlb0_mmwp1_mml0_pmp_04`
- `test_pmp_csr_1_lock01_rlb0_mmwp1_mml0_pmp_05`
- `test_pmp_csr_1_lock01_rlb0_mmwp1_mml0_pmp_06`
- `test_pmp_csr_1_lock01_rlb0_mmwp1_mml0_pmp_07`
- `test_pmp_csr_1_lock01_rlb0_mmwp1_mml0_pmp_11`
- `test_pmp_csr_1_lock01_rlb0_mmwp1_mml0_pmp_12`
- `test_pmp_csr_1_lock01_rlb0_mmwp1_mml0_pmp_13`
- `test_pmp_csr_1_lock01_rlb0_mmwp1_mml0_pmp_14`
- `test_pmp_csr_1_lock01_rlb0_mmwp1_mml0_pmp_15`
- `test_pmp_csr_1_lock01_rlb0_mmwp1_mml0_pmp_16`
- `test_pmp_csr_1_lock01_rlb0_mmwp1_mml0_pmp_17`
- `test_pmp_csr_1_lock01_rlb0_mmwp1_mml0_sec_00`
- `test_pmp_csr_1_lock01_rlb0_mmwp1_mml0_sec_01`
- `test_pmp_csr_1_lock01_rlb0_mmwp1_mml0_sec_02`
- `test_pmp_csr_1_lock01_rlb0_mmwp1_mml0_sec_03`
- `test_pmp_csr_1_lock01_rlb0_mmwp1_mml0_sec_04`
- `test_pmp_csr_1_lock01_rlb0_mmwp1_mml0_sec_05`
- `test_pmp_csr_1_lock01_rlb0_mmwp1_mml0_sec_06`
- `test_pmp_csr_1_lock01_rlb0_mmwp1_mml0_sec_07`
- `test_pmp_csr_1_lock01_rlb0_mmwp1_mml1_pmp_01`
- `test_pmp_csr_1_lock01_rlb0_mmwp1_mml1_pmp_02`
- `test_pmp_csr_1_lock01_rlb0_mmwp1_mml1_pmp_03`
- `test_pmp_csr_1_lock01_rlb0_mmwp1_mml1_pmp_04`
- `test_pmp_csr_1_lock01_rlb0_mmwp1_mml1_pmp_05`
- `test_pmp_csr_1_lock01_rlb0_mmwp1_mml1_pmp_06`
- `test_pmp_csr_1_lock01_rlb0_mmwp1_mml1_pmp_07`
- `test_pmp_csr_1_lock01_rlb0_mmwp1_mml1_pmp_11`
- `test_pmp_csr_1_lock01_rlb0_mmwp1_mml1_pmp_12`
- `test_pmp_csr_1_lock01_rlb0_mmwp1_mml1_pmp_13`
- `test_pmp_csr_1_lock01_rlb0_mmwp1_mml1_pmp_14`
- `test_pmp_csr_1_lock01_rlb0_mmwp1_mml1_pmp_15`
- `test_pmp_csr_1_lock01_rlb0_mmwp1_mml1_pmp_16`
- `test_pmp_csr_1_lock01_rlb0_mmwp1_mml1_pmp_17`
- `test_pmp_csr_1_lock01_rlb0_mmwp1_mml1_sec_00`
- `test_pmp_csr_1_lock01_rlb0_mmwp1_mml1_sec_01`
- `test_pmp_csr_1_lock01_rlb0_mmwp1_mml1_sec_02`
- `test_pmp_csr_1_lock01_rlb0_mmwp1_mml1_sec_03`
- `test_pmp_csr_1_lock01_rlb0_mmwp1_mml1_sec_04`
- `test_pmp_csr_1_lock01_rlb0_mmwp1_mml1_sec_05`
- `test_pmp_csr_1_lock01_rlb0_mmwp1_mml1_sec_06`
- `test_pmp_csr_1_lock01_rlb0_mmwp1_mml1_sec_07`
- `test_pmp_csr_1_lock01_rlb1_mmwp0_mml0_pmp_01`
- `test_pmp_csr_1_lock01_rlb1_mmwp0_mml0_pmp_02`
- `test_pmp_csr_1_lock01_rlb1_mmwp0_mml0_pmp_03`
- `test_pmp_csr_1_lock01_rlb1_mmwp0_mml0_pmp_04`
- `test_pmp_csr_1_lock01_rlb1_mmwp0_mml0_pmp_05`
- `test_pmp_csr_1_lock01_rlb1_mmwp0_mml0_pmp_06`
- `test_pmp_csr_1_lock01_rlb1_mmwp0_mml0_pmp_07`
- `test_pmp_csr_1_lock01_rlb1_mmwp0_mml0_pmp_11`
- `test_pmp_csr_1_lock01_rlb1_mmwp0_mml0_pmp_12`
- `test_pmp_csr_1_lock01_rlb1_mmwp0_mml0_pmp_13`
- `test_pmp_csr_1_lock01_rlb1_mmwp0_mml0_pmp_14`
- `test_pmp_csr_1_lock01_rlb1_mmwp0_mml0_pmp_15`
- `test_pmp_csr_1_lock01_rlb1_mmwp0_mml0_pmp_16`
- `test_pmp_csr_1_lock01_rlb1_mmwp0_mml0_pmp_17`
- `test_pmp_csr_1_lock01_rlb1_mmwp0_mml0_sec_00`
- `test_pmp_csr_1_lock01_rlb1_mmwp0_mml0_sec_01`
- `test_pmp_csr_1_lock01_rlb1_mmwp0_mml0_sec_02`
- `test_pmp_csr_1_lock01_rlb1_mmwp0_mml0_sec_03`
- `test_pmp_csr_1_lock01_rlb1_mmwp0_mml0_sec_04`
- `test_pmp_csr_1_lock01_rlb1_mmwp0_mml0_sec_05`
- `test_pmp_csr_1_lock01_rlb1_mmwp0_mml0_sec_06`
- `test_pmp_csr_1_lock01_rlb1_mmwp0_mml0_sec_07`
- `test_pmp_csr_1_lock01_rlb1_mmwp0_mml1_pmp_01`
- `test_pmp_csr_1_lock01_rlb1_mmwp0_mml1_pmp_02`
- `test_pmp_csr_1_lock01_rlb1_mmwp0_mml1_pmp_03`
- `test_pmp_csr_1_lock01_rlb1_mmwp0_mml1_pmp_04`
- `test_pmp_csr_1_lock01_rlb1_mmwp0_mml1_pmp_05`
- `test_pmp_csr_1_lock01_rlb1_mmwp0_mml1_pmp_06`
- `test_pmp_csr_1_lock01_rlb1_mmwp0_mml1_pmp_07`
- `test_pmp_csr_1_lock01_rlb1_mmwp0_mml1_pmp_11`
- `test_pmp_csr_1_lock01_rlb1_mmwp0_mml1_pmp_12`
- `test_pmp_csr_1_lock01_rlb1_mmwp0_mml1_pmp_13`
- `test_pmp_csr_1_lock01_rlb1_mmwp0_mml1_pmp_14`
- `test_pmp_csr_1_lock01_rlb1_mmwp0_mml1_pmp_15`
- `test_pmp_csr_1_lock01_rlb1_mmwp0_mml1_pmp_16`
- `test_pmp_csr_1_lock01_rlb1_mmwp0_mml1_pmp_17`
- `test_pmp_csr_1_lock01_rlb1_mmwp0_mml1_sec_00`
- `test_pmp_csr_1_lock01_rlb1_mmwp0_mml1_sec_01`
- `test_pmp_csr_1_lock01_rlb1_mmwp0_mml1_sec_02`
- `test_pmp_csr_1_lock01_rlb1_mmwp0_mml1_sec_03`
- `test_pmp_csr_1_lock01_rlb1_mmwp0_mml1_sec_04`
- `test_pmp_csr_1_lock01_rlb1_mmwp0_mml1_sec_05`
- `test_pmp_csr_1_lock01_rlb1_mmwp0_mml1_sec_06`
- `test_pmp_csr_1_lock01_rlb1_mmwp0_mml1_sec_07`
- `test_pmp_csr_1_lock01_rlb1_mmwp1_mml0_pmp_01`
- `test_pmp_csr_1_lock01_rlb1_mmwp1_mml0_pmp_02`
- `test_pmp_csr_1_lock01_rlb1_mmwp1_mml0_pmp_03`
- `test_pmp_csr_1_lock01_rlb1_mmwp1_mml0_pmp_04`
- `test_pmp_csr_1_lock01_rlb1_mmwp1_mml0_pmp_05`
- `test_pmp_csr_1_lock01_rlb1_mmwp1_mml0_pmp_06`
- `test_pmp_csr_1_lock01_rlb1_mmwp1_mml0_pmp_07`
- `test_pmp_csr_1_lock01_rlb1_mmwp1_mml0_pmp_11`
- `test_pmp_csr_1_lock01_rlb1_mmwp1_mml0_pmp_12`
- `test_pmp_csr_1_lock01_rlb1_mmwp1_mml0_pmp_13`
- `test_pmp_csr_1_lock01_rlb1_mmwp1_mml0_pmp_14`
- `test_pmp_csr_1_lock01_rlb1_mmwp1_mml0_pmp_15`
- `test_pmp_csr_1_lock01_rlb1_mmwp1_mml0_pmp_16`
- `test_pmp_csr_1_lock01_rlb1_mmwp1_mml0_pmp_17`
- `test_pmp_csr_1_lock01_rlb1_mmwp1_mml0_sec_00`
- `test_pmp_csr_1_lock01_rlb1_mmwp1_mml0_sec_01`
- `test_pmp_csr_1_lock01_rlb1_mmwp1_mml0_sec_02`
- `test_pmp_csr_1_lock01_rlb1_mmwp1_mml0_sec_03`
- `test_pmp_csr_1_lock01_rlb1_mmwp1_mml0_sec_04`
- `test_pmp_csr_1_lock01_rlb1_mmwp1_mml0_sec_05`
- `test_pmp_csr_1_lock01_rlb1_mmwp1_mml0_sec_06`
- `test_pmp_csr_1_lock01_rlb1_mmwp1_mml0_sec_07`
- `test_pmp_csr_1_lock01_rlb1_mmwp1_mml1_pmp_01`
- `test_pmp_csr_1_lock01_rlb1_mmwp1_mml1_pmp_02`
- `test_pmp_csr_1_lock01_rlb1_mmwp1_mml1_pmp_03`
- `test_pmp_csr_1_lock01_rlb1_mmwp1_mml1_pmp_04`
- `test_pmp_csr_1_lock01_rlb1_mmwp1_mml1_pmp_05`
- `test_pmp_csr_1_lock01_rlb1_mmwp1_mml1_pmp_06`
- `test_pmp_csr_1_lock01_rlb1_mmwp1_mml1_pmp_07`
- `test_pmp_csr_1_lock01_rlb1_mmwp1_mml1_pmp_11`
- `test_pmp_csr_1_lock01_rlb1_mmwp1_mml1_pmp_12`
- `test_pmp_csr_1_lock01_rlb1_mmwp1_mml1_pmp_13`
- `test_pmp_csr_1_lock01_rlb1_mmwp1_mml1_pmp_14`
- `test_pmp_csr_1_lock01_rlb1_mmwp1_mml1_pmp_15`
- `test_pmp_csr_1_lock01_rlb1_mmwp1_mml1_pmp_16`
- `test_pmp_csr_1_lock01_rlb1_mmwp1_mml1_pmp_17`
- `test_pmp_csr_1_lock01_rlb1_mmwp1_mml1_sec_00`
- `test_pmp_csr_1_lock01_rlb1_mmwp1_mml1_sec_01`
- `test_pmp_csr_1_lock01_rlb1_mmwp1_mml1_sec_02`
- `test_pmp_csr_1_lock01_rlb1_mmwp1_mml1_sec_03`
- `test_pmp_csr_1_lock01_rlb1_mmwp1_mml1_sec_04`
- `test_pmp_csr_1_lock01_rlb1_mmwp1_mml1_sec_05`
- `test_pmp_csr_1_lock01_rlb1_mmwp1_mml1_sec_06`
- `test_pmp_csr_1_lock01_rlb1_mmwp1_mml1_sec_07`
- `test_pmp_csr_1_lock10_rlb0_mmwp0_mml0_pmp_01`
- `test_pmp_csr_1_lock10_rlb0_mmwp0_mml0_pmp_02`
- `test_pmp_csr_1_lock10_rlb0_mmwp0_mml0_pmp_03`
- `test_pmp_csr_1_lock10_rlb0_mmwp0_mml0_pmp_04`
- `test_pmp_csr_1_lock10_rlb0_mmwp0_mml0_pmp_05`
- `test_pmp_csr_1_lock10_rlb0_mmwp0_mml0_pmp_06`
- `test_pmp_csr_1_lock10_rlb0_mmwp0_mml0_pmp_07`
- `test_pmp_csr_1_lock10_rlb0_mmwp0_mml0_pmp_11`
- `test_pmp_csr_1_lock10_rlb0_mmwp0_mml0_pmp_12`
- `test_pmp_csr_1_lock10_rlb0_mmwp0_mml0_pmp_13`
- `test_pmp_csr_1_lock10_rlb0_mmwp0_mml0_pmp_14`
- `test_pmp_csr_1_lock10_rlb0_mmwp0_mml0_pmp_15`
- `test_pmp_csr_1_lock10_rlb0_mmwp0_mml0_pmp_16`
- `test_pmp_csr_1_lock10_rlb0_mmwp0_mml0_pmp_17`
- `test_pmp_csr_1_lock10_rlb0_mmwp0_mml0_sec_00`
- `test_pmp_csr_1_lock10_rlb0_mmwp0_mml0_sec_01`
- `test_pmp_csr_1_lock10_rlb0_mmwp0_mml0_sec_02`
- `test_pmp_csr_1_lock10_rlb0_mmwp0_mml0_sec_03`
- `test_pmp_csr_1_lock10_rlb0_mmwp0_mml0_sec_04`
- `test_pmp_csr_1_lock10_rlb0_mmwp0_mml0_sec_05`
- `test_pmp_csr_1_lock10_rlb0_mmwp0_mml0_sec_06`
- `test_pmp_csr_1_lock10_rlb0_mmwp0_mml0_sec_07`
- `test_pmp_csr_1_lock10_rlb0_mmwp0_mml1_pmp_01`
- `test_pmp_csr_1_lock10_rlb0_mmwp0_mml1_pmp_02`
- `test_pmp_csr_1_lock10_rlb0_mmwp0_mml1_pmp_03`
- `test_pmp_csr_1_lock10_rlb0_mmwp0_mml1_pmp_04`
- `test_pmp_csr_1_lock10_rlb0_mmwp0_mml1_pmp_05`
- `test_pmp_csr_1_lock10_rlb0_mmwp0_mml1_pmp_06`
- `test_pmp_csr_1_lock10_rlb0_mmwp0_mml1_pmp_07`
- `test_pmp_csr_1_lock10_rlb0_mmwp0_mml1_pmp_11`
- `test_pmp_csr_1_lock10_rlb0_mmwp0_mml1_pmp_12`
- `test_pmp_csr_1_lock10_rlb0_mmwp0_mml1_pmp_13`
- `test_pmp_csr_1_lock10_rlb0_mmwp0_mml1_pmp_14`
- `test_pmp_csr_1_lock10_rlb0_mmwp0_mml1_pmp_15`
- `test_pmp_csr_1_lock10_rlb0_mmwp0_mml1_pmp_16`
- `test_pmp_csr_1_lock10_rlb0_mmwp0_mml1_pmp_17`
- `test_pmp_csr_1_lock10_rlb0_mmwp0_mml1_sec_00`
- `test_pmp_csr_1_lock10_rlb0_mmwp0_mml1_sec_01`
- `test_pmp_csr_1_lock10_rlb0_mmwp0_mml1_sec_02`
- `test_pmp_csr_1_lock10_rlb0_mmwp0_mml1_sec_03`
- `test_pmp_csr_1_lock10_rlb0_mmwp0_mml1_sec_04`
- `test_pmp_csr_1_lock10_rlb0_mmwp0_mml1_sec_05`
- `test_pmp_csr_1_lock10_rlb0_mmwp0_mml1_sec_06`
- `test_pmp_csr_1_lock10_rlb0_mmwp0_mml1_sec_07`
- `test_pmp_csr_1_lock10_rlb0_mmwp1_mml0_pmp_01`
- `test_pmp_csr_1_lock10_rlb0_mmwp1_mml0_pmp_02`
- `test_pmp_csr_1_lock10_rlb0_mmwp1_mml0_pmp_03`
- `test_pmp_csr_1_lock10_rlb0_mmwp1_mml0_pmp_04`
- `test_pmp_csr_1_lock10_rlb0_mmwp1_mml0_pmp_05`
- `test_pmp_csr_1_lock10_rlb0_mmwp1_mml0_pmp_06`
- `test_pmp_csr_1_lock10_rlb0_mmwp1_mml0_pmp_07`
- `test_pmp_csr_1_lock10_rlb0_mmwp1_mml0_pmp_11`
- `test_pmp_csr_1_lock10_rlb0_mmwp1_mml0_pmp_12`
- `test_pmp_csr_1_lock10_rlb0_mmwp1_mml0_pmp_13`
- `test_pmp_csr_1_lock10_rlb0_mmwp1_mml0_pmp_14`
- `test_pmp_csr_1_lock10_rlb0_mmwp1_mml0_pmp_15`
- `test_pmp_csr_1_lock10_rlb0_mmwp1_mml0_pmp_16`
- `test_pmp_csr_1_lock10_rlb0_mmwp1_mml0_pmp_17`
- `test_pmp_csr_1_lock10_rlb0_mmwp1_mml0_sec_00`
- `test_pmp_csr_1_lock10_rlb0_mmwp1_mml0_sec_01`
- `test_pmp_csr_1_lock10_rlb0_mmwp1_mml0_sec_02`
- `test_pmp_csr_1_lock10_rlb0_mmwp1_mml0_sec_03`
- `test_pmp_csr_1_lock10_rlb0_mmwp1_mml0_sec_04`
- `test_pmp_csr_1_lock10_rlb0_mmwp1_mml0_sec_05`
- `test_pmp_csr_1_lock10_rlb0_mmwp1_mml0_sec_06`
- `test_pmp_csr_1_lock10_rlb0_mmwp1_mml0_sec_07`
- `test_pmp_csr_1_lock10_rlb0_mmwp1_mml1_pmp_01`
- `test_pmp_csr_1_lock10_rlb0_mmwp1_mml1_pmp_02`
- `test_pmp_csr_1_lock10_rlb0_mmwp1_mml1_pmp_03`
- `test_pmp_csr_1_lock10_rlb0_mmwp1_mml1_pmp_04`
- `test_pmp_csr_1_lock10_rlb0_mmwp1_mml1_pmp_05`
- `test_pmp_csr_1_lock10_rlb0_mmwp1_mml1_pmp_06`
- `test_pmp_csr_1_lock10_rlb0_mmwp1_mml1_pmp_07`
- `test_pmp_csr_1_lock10_rlb0_mmwp1_mml1_pmp_11`
- `test_pmp_csr_1_lock10_rlb0_mmwp1_mml1_pmp_12`
- `test_pmp_csr_1_lock10_rlb0_mmwp1_mml1_pmp_13`
- `test_pmp_csr_1_lock10_rlb0_mmwp1_mml1_pmp_14`
- `test_pmp_csr_1_lock10_rlb0_mmwp1_mml1_pmp_15`
- `test_pmp_csr_1_lock10_rlb0_mmwp1_mml1_pmp_16`
- `test_pmp_csr_1_lock10_rlb0_mmwp1_mml1_pmp_17`
- `test_pmp_csr_1_lock10_rlb0_mmwp1_mml1_sec_00`
- `test_pmp_csr_1_lock10_rlb0_mmwp1_mml1_sec_01`
- `test_pmp_csr_1_lock10_rlb0_mmwp1_mml1_sec_02`
- `test_pmp_csr_1_lock10_rlb0_mmwp1_mml1_sec_03`
- `test_pmp_csr_1_lock10_rlb0_mmwp1_mml1_sec_04`
- `test_pmp_csr_1_lock10_rlb0_mmwp1_mml1_sec_05`
- `test_pmp_csr_1_lock10_rlb0_mmwp1_mml1_sec_06`
- `test_pmp_csr_1_lock10_rlb0_mmwp1_mml1_sec_07`
- `test_pmp_csr_1_lock10_rlb1_mmwp0_mml0_pmp_01`
- `test_pmp_csr_1_lock10_rlb1_mmwp0_mml0_pmp_02`
- `test_pmp_csr_1_lock10_rlb1_mmwp0_mml0_pmp_03`
- `test_pmp_csr_1_lock10_rlb1_mmwp0_mml0_pmp_04`
- `test_pmp_csr_1_lock10_rlb1_mmwp0_mml0_pmp_05`
- `test_pmp_csr_1_lock10_rlb1_mmwp0_mml0_pmp_06`
- `test_pmp_csr_1_lock10_rlb1_mmwp0_mml0_pmp_07`
- `test_pmp_csr_1_lock10_rlb1_mmwp0_mml0_pmp_11`
- `test_pmp_csr_1_lock10_rlb1_mmwp0_mml0_pmp_12`
- `test_pmp_csr_1_lock10_rlb1_mmwp0_mml0_pmp_13`
- `test_pmp_csr_1_lock10_rlb1_mmwp0_mml0_pmp_14`
- `test_pmp_csr_1_lock10_rlb1_mmwp0_mml0_pmp_15`
- `test_pmp_csr_1_lock10_rlb1_mmwp0_mml0_pmp_16`
- `test_pmp_csr_1_lock10_rlb1_mmwp0_mml0_pmp_17`
- `test_pmp_csr_1_lock10_rlb1_mmwp0_mml0_sec_00`
- `test_pmp_csr_1_lock10_rlb1_mmwp0_mml0_sec_01`
- `test_pmp_csr_1_lock10_rlb1_mmwp0_mml0_sec_02`
- `test_pmp_csr_1_lock10_rlb1_mmwp0_mml0_sec_03`
- `test_pmp_csr_1_lock10_rlb1_mmwp0_mml0_sec_04`
- `test_pmp_csr_1_lock10_rlb1_mmwp0_mml0_sec_05`
- `test_pmp_csr_1_lock10_rlb1_mmwp0_mml0_sec_06`
- `test_pmp_csr_1_lock10_rlb1_mmwp0_mml0_sec_07`
- `test_pmp_csr_1_lock10_rlb1_mmwp0_mml1_pmp_01`
- `test_pmp_csr_1_lock10_rlb1_mmwp0_mml1_pmp_02`
- `test_pmp_csr_1_lock10_rlb1_mmwp0_mml1_pmp_03`
- `test_pmp_csr_1_lock10_rlb1_mmwp0_mml1_pmp_04`
- `test_pmp_csr_1_lock10_rlb1_mmwp0_mml1_pmp_05`
- `test_pmp_csr_1_lock10_rlb1_mmwp0_mml1_pmp_06`
- `test_pmp_csr_1_lock10_rlb1_mmwp0_mml1_pmp_07`
- `test_pmp_csr_1_lock10_rlb1_mmwp0_mml1_pmp_11`
- `test_pmp_csr_1_lock10_rlb1_mmwp0_mml1_pmp_12`
- `test_pmp_csr_1_lock10_rlb1_mmwp0_mml1_pmp_13`
- `test_pmp_csr_1_lock10_rlb1_mmwp0_mml1_pmp_14`
- `test_pmp_csr_1_lock10_rlb1_mmwp0_mml1_pmp_15`
- `test_pmp_csr_1_lock10_rlb1_mmwp0_mml1_pmp_16`
- `test_pmp_csr_1_lock10_rlb1_mmwp0_mml1_pmp_17`
- `test_pmp_csr_1_lock10_rlb1_mmwp0_mml1_sec_00`
- `test_pmp_csr_1_lock10_rlb1_mmwp0_mml1_sec_01`
- `test_pmp_csr_1_lock10_rlb1_mmwp0_mml1_sec_02`
- `test_pmp_csr_1_lock10_rlb1_mmwp0_mml1_sec_03`
- `test_pmp_csr_1_lock10_rlb1_mmwp0_mml1_sec_04`
- `test_pmp_csr_1_lock10_rlb1_mmwp0_mml1_sec_05`
- `test_pmp_csr_1_lock10_rlb1_mmwp0_mml1_sec_06`
- `test_pmp_csr_1_lock10_rlb1_mmwp0_mml1_sec_07`
- `test_pmp_csr_1_lock10_rlb1_mmwp1_mml0_pmp_01`
- `test_pmp_csr_1_lock10_rlb1_mmwp1_mml0_pmp_02`
- `test_pmp_csr_1_lock10_rlb1_mmwp1_mml0_pmp_03`
- `test_pmp_csr_1_lock10_rlb1_mmwp1_mml0_pmp_04`
- `test_pmp_csr_1_lock10_rlb1_mmwp1_mml0_pmp_05`
- `test_pmp_csr_1_lock10_rlb1_mmwp1_mml0_pmp_06`
- `test_pmp_csr_1_lock10_rlb1_mmwp1_mml0_pmp_07`
- `test_pmp_csr_1_lock10_rlb1_mmwp1_mml0_pmp_11`
- `test_pmp_csr_1_lock10_rlb1_mmwp1_mml0_pmp_12`
- `test_pmp_csr_1_lock10_rlb1_mmwp1_mml0_pmp_13`
- `test_pmp_csr_1_lock10_rlb1_mmwp1_mml0_pmp_14`
- `test_pmp_csr_1_lock10_rlb1_mmwp1_mml0_pmp_15`
- `test_pmp_csr_1_lock10_rlb1_mmwp1_mml0_pmp_16`
- `test_pmp_csr_1_lock10_rlb1_mmwp1_mml0_pmp_17`
- `test_pmp_csr_1_lock10_rlb1_mmwp1_mml0_sec_00`
- `test_pmp_csr_1_lock10_rlb1_mmwp1_mml0_sec_01`
- `test_pmp_csr_1_lock10_rlb1_mmwp1_mml0_sec_02`
- `test_pmp_csr_1_lock10_rlb1_mmwp1_mml0_sec_03`
- `test_pmp_csr_1_lock10_rlb1_mmwp1_mml0_sec_04`
- `test_pmp_csr_1_lock10_rlb1_mmwp1_mml0_sec_05`
- `test_pmp_csr_1_lock10_rlb1_mmwp1_mml0_sec_06`
- `test_pmp_csr_1_lock10_rlb1_mmwp1_mml0_sec_07`
- `test_pmp_csr_1_lock10_rlb1_mmwp1_mml1_pmp_01`
- `test_pmp_csr_1_lock10_rlb1_mmwp1_mml1_pmp_02`
- `test_pmp_csr_1_lock10_rlb1_mmwp1_mml1_pmp_03`
- `test_pmp_csr_1_lock10_rlb1_mmwp1_mml1_pmp_04`
- `test_pmp_csr_1_lock10_rlb1_mmwp1_mml1_pmp_05`
- `test_pmp_csr_1_lock10_rlb1_mmwp1_mml1_pmp_06`
- `test_pmp_csr_1_lock10_rlb1_mmwp1_mml1_pmp_07`
- `test_pmp_csr_1_lock10_rlb1_mmwp1_mml1_pmp_11`
- `test_pmp_csr_1_lock10_rlb1_mmwp1_mml1_pmp_12`
- `test_pmp_csr_1_lock10_rlb1_mmwp1_mml1_pmp_13`
- `test_pmp_csr_1_lock10_rlb1_mmwp1_mml1_pmp_14`
- `test_pmp_csr_1_lock10_rlb1_mmwp1_mml1_pmp_15`
- `test_pmp_csr_1_lock10_rlb1_mmwp1_mml1_pmp_16`
- `test_pmp_csr_1_lock10_rlb1_mmwp1_mml1_pmp_17`
- `test_pmp_csr_1_lock10_rlb1_mmwp1_mml1_sec_00`
- `test_pmp_csr_1_lock10_rlb1_mmwp1_mml1_sec_01`
- `test_pmp_csr_1_lock10_rlb1_mmwp1_mml1_sec_02`
- `test_pmp_csr_1_lock10_rlb1_mmwp1_mml1_sec_03`
- `test_pmp_csr_1_lock10_rlb1_mmwp1_mml1_sec_04`
- `test_pmp_csr_1_lock10_rlb1_mmwp1_mml1_sec_05`
- `test_pmp_csr_1_lock10_rlb1_mmwp1_mml1_sec_06`
- `test_pmp_csr_1_lock10_rlb1_mmwp1_mml1_sec_07`
- `test_pmp_ok_1_u0_rw00_x0_l0_match0_mmwp0_mml0`
- `test_pmp_ok_1_u0_rw00_x0_l0_match0_mmwp0_mml1`
- `test_pmp_ok_1_u0_rw00_x0_l0_match0_mmwp1_mml0`
- `test_pmp_ok_1_u0_rw00_x0_l0_match0_mmwp1_mml1`
- `test_pmp_ok_1_u0_rw00_x0_l0_match1_mmwp0_mml0`
- `test_pmp_ok_1_u0_rw00_x0_l0_match1_mmwp0_mml1`
- `test_pmp_ok_1_u0_rw00_x0_l0_match1_mmwp1_mml0`
- `test_pmp_ok_1_u0_rw00_x0_l0_match1_mmwp1_mml1`
- `test_pmp_ok_1_u0_rw00_x0_l1_match0_mmwp0_mml0`
- `test_pmp_ok_1_u0_rw00_x0_l1_match0_mmwp0_mml1`
- `test_pmp_ok_1_u0_rw00_x0_l1_match0_mmwp1_mml0`
- `test_pmp_ok_1_u0_rw00_x0_l1_match0_mmwp1_mml1`
- `test_pmp_ok_1_u0_rw00_x0_l1_match1_mmwp0_mml0`
- `test_pmp_ok_1_u0_rw00_x0_l1_match1_mmwp0_mml1`
- `test_pmp_ok_1_u0_rw00_x0_l1_match1_mmwp1_mml0`
- `test_pmp_ok_1_u0_rw00_x0_l1_match1_mmwp1_mml1`
- `test_pmp_ok_1_u0_rw00_x1_l0_match0_mmwp0_mml0`
- `test_pmp_ok_1_u0_rw00_x1_l0_match0_mmwp0_mml1`
- `test_pmp_ok_1_u0_rw00_x1_l0_match0_mmwp1_mml0`
- `test_pmp_ok_1_u0_rw00_x1_l0_match0_mmwp1_mml1`
- `test_pmp_ok_1_u0_rw00_x1_l0_match1_mmwp0_mml0`
- `test_pmp_ok_1_u0_rw00_x1_l0_match1_mmwp0_mml1`
- `test_pmp_ok_1_u0_rw00_x1_l0_match1_mmwp1_mml0`
- `test_pmp_ok_1_u0_rw00_x1_l0_match1_mmwp1_mml1`
- `test_pmp_ok_1_u0_rw00_x1_l1_match0_mmwp0_mml0`
- `test_pmp_ok_1_u0_rw00_x1_l1_match0_mmwp0_mml1`
- `test_pmp_ok_1_u0_rw00_x1_l1_match0_mmwp1_mml0`
- `test_pmp_ok_1_u0_rw00_x1_l1_match0_mmwp1_mml1`
- `test_pmp_ok_1_u0_rw00_x1_l1_match1_mmwp0_mml0`
- `test_pmp_ok_1_u0_rw00_x1_l1_match1_mmwp0_mml1`
- `test_pmp_ok_1_u0_rw00_x1_l1_match1_mmwp1_mml0`
- `test_pmp_ok_1_u0_rw00_x1_l1_match1_mmwp1_mml1`
- `test_pmp_ok_1_u0_rw10_x0_l0_match0_mmwp0_mml0`
- `test_pmp_ok_1_u0_rw10_x0_l0_match0_mmwp0_mml1`
- `test_pmp_ok_1_u0_rw10_x0_l0_match0_mmwp1_mml0`
- `test_pmp_ok_1_u0_rw10_x0_l0_match0_mmwp1_mml1`
- `test_pmp_ok_1_u0_rw10_x0_l0_match1_mmwp0_mml0`
- `test_pmp_ok_1_u0_rw10_x0_l0_match1_mmwp0_mml1`
- `test_pmp_ok_1_u0_rw10_x0_l0_match1_mmwp1_mml0`
- `test_pmp_ok_1_u0_rw10_x0_l0_match1_mmwp1_mml1`
- `test_pmp_ok_1_u0_rw10_x0_l1_match0_mmwp0_mml0`
- `test_pmp_ok_1_u0_rw10_x0_l1_match0_mmwp0_mml1`
- `test_pmp_ok_1_u0_rw10_x0_l1_match0_mmwp1_mml0`
- `test_pmp_ok_1_u0_rw10_x0_l1_match0_mmwp1_mml1`
- `test_pmp_ok_1_u0_rw10_x0_l1_match1_mmwp0_mml0`
- `test_pmp_ok_1_u0_rw10_x0_l1_match1_mmwp0_mml1`
- `test_pmp_ok_1_u0_rw10_x0_l1_match1_mmwp1_mml0`
- `test_pmp_ok_1_u0_rw10_x0_l1_match1_mmwp1_mml1`
- `test_pmp_ok_1_u0_rw10_x1_l0_match0_mmwp0_mml0`
- `test_pmp_ok_1_u0_rw10_x1_l0_match0_mmwp0_mml1`
- `test_pmp_ok_1_u0_rw10_x1_l0_match0_mmwp1_mml0`
- `test_pmp_ok_1_u0_rw10_x1_l0_match0_mmwp1_mml1`
- `test_pmp_ok_1_u0_rw10_x1_l0_match1_mmwp0_mml0`
- `test_pmp_ok_1_u0_rw10_x1_l0_match1_mmwp0_mml1`
- `test_pmp_ok_1_u0_rw10_x1_l0_match1_mmwp1_mml0`
- `test_pmp_ok_1_u0_rw10_x1_l0_match1_mmwp1_mml1`
- `test_pmp_ok_1_u0_rw10_x1_l1_match0_mmwp0_mml0`
- `test_pmp_ok_1_u0_rw10_x1_l1_match0_mmwp0_mml1`
- `test_pmp_ok_1_u0_rw10_x1_l1_match0_mmwp1_mml0`
- `test_pmp_ok_1_u0_rw10_x1_l1_match0_mmwp1_mml1`
- `test_pmp_ok_1_u0_rw10_x1_l1_match1_mmwp0_mml0`
- `test_pmp_ok_1_u0_rw10_x1_l1_match1_mmwp0_mml1`
- `test_pmp_ok_1_u0_rw10_x1_l1_match1_mmwp1_mml0`
- `test_pmp_ok_1_u0_rw10_x1_l1_match1_mmwp1_mml1`
- `test_pmp_ok_1_u0_rw11_x0_l0_match0_mmwp0_mml0`
- `test_pmp_ok_1_u0_rw11_x0_l0_match0_mmwp0_mml1`
- `test_pmp_ok_1_u0_rw11_x0_l0_match0_mmwp1_mml0`
- `test_pmp_ok_1_u0_rw11_x0_l0_match0_mmwp1_mml1`
- `test_pmp_ok_1_u0_rw11_x0_l0_match1_mmwp0_mml0`
- `test_pmp_ok_1_u0_rw11_x0_l0_match1_mmwp0_mml1`
- `test_pmp_ok_1_u0_rw11_x0_l0_match1_mmwp1_mml0`
- `test_pmp_ok_1_u0_rw11_x0_l0_match1_mmwp1_mml1`
- `test_pmp_ok_1_u0_rw11_x0_l1_match0_mmwp0_mml0`
- `test_pmp_ok_1_u0_rw11_x0_l1_match0_mmwp0_mml1`
- `test_pmp_ok_1_u0_rw11_x0_l1_match0_mmwp1_mml0`
- `test_pmp_ok_1_u0_rw11_x0_l1_match0_mmwp1_mml1`
- `test_pmp_ok_1_u0_rw11_x0_l1_match1_mmwp0_mml0`
- `test_pmp_ok_1_u0_rw11_x0_l1_match1_mmwp0_mml1`
- `test_pmp_ok_1_u0_rw11_x0_l1_match1_mmwp1_mml0`
- `test_pmp_ok_1_u0_rw11_x0_l1_match1_mmwp1_mml1`
- `test_pmp_ok_1_u0_rw11_x1_l0_match0_mmwp0_mml0`
- `test_pmp_ok_1_u0_rw11_x1_l0_match0_mmwp0_mml1`
- `test_pmp_ok_1_u0_rw11_x1_l0_match0_mmwp1_mml0`
- `test_pmp_ok_1_u0_rw11_x1_l0_match0_mmwp1_mml1`
- `test_pmp_ok_1_u0_rw11_x1_l0_match1_mmwp0_mml0`
- `test_pmp_ok_1_u0_rw11_x1_l0_match1_mmwp0_mml1`
- `test_pmp_ok_1_u0_rw11_x1_l0_match1_mmwp1_mml0`
- `test_pmp_ok_1_u0_rw11_x1_l0_match1_mmwp1_mml1`
- `test_pmp_ok_1_u0_rw11_x1_l1_match0_mmwp0_mml0`
- `test_pmp_ok_1_u0_rw11_x1_l1_match0_mmwp0_mml1`
- `test_pmp_ok_1_u0_rw11_x1_l1_match0_mmwp1_mml0`
- `test_pmp_ok_1_u0_rw11_x1_l1_match0_mmwp1_mml1`
- `test_pmp_ok_1_u0_rw11_x1_l1_match1_mmwp0_mml0`
- `test_pmp_ok_1_u0_rw11_x1_l1_match1_mmwp0_mml1`
- `test_pmp_ok_1_u0_rw11_x1_l1_match1_mmwp1_mml0`
- `test_pmp_ok_1_u0_rw11_x1_l1_match1_mmwp1_mml1`
- `test_pmp_ok_1_u1_rw00_x0_l0_match0_mmwp0_mml0`
- `test_pmp_ok_1_u1_rw00_x0_l0_match0_mmwp0_mml1`
- `test_pmp_ok_1_u1_rw00_x0_l0_match0_mmwp1_mml0`
- `test_pmp_ok_1_u1_rw00_x0_l0_match0_mmwp1_mml1`
- `test_pmp_ok_1_u1_rw00_x0_l0_match1_mmwp0_mml0`
- `test_pmp_ok_1_u1_rw00_x0_l0_match1_mmwp0_mml1`
- `test_pmp_ok_1_u1_rw00_x0_l0_match1_mmwp1_mml0`
- `test_pmp_ok_1_u1_rw00_x0_l0_match1_mmwp1_mml1`
- `test_pmp_ok_1_u1_rw00_x0_l1_match0_mmwp0_mml0`
- `test_pmp_ok_1_u1_rw00_x0_l1_match0_mmwp0_mml1`
- `test_pmp_ok_1_u1_rw00_x0_l1_match0_mmwp1_mml0`
- `test_pmp_ok_1_u1_rw00_x0_l1_match0_mmwp1_mml1`
- `test_pmp_ok_1_u1_rw00_x0_l1_match1_mmwp0_mml0`
- `test_pmp_ok_1_u1_rw00_x0_l1_match1_mmwp0_mml1`
- `test_pmp_ok_1_u1_rw00_x0_l1_match1_mmwp1_mml0`
- `test_pmp_ok_1_u1_rw00_x0_l1_match1_mmwp1_mml1`
- `test_pmp_ok_1_u1_rw00_x1_l0_match0_mmwp0_mml0`
- `test_pmp_ok_1_u1_rw00_x1_l0_match0_mmwp0_mml1`
- `test_pmp_ok_1_u1_rw00_x1_l0_match0_mmwp1_mml0`
- `test_pmp_ok_1_u1_rw00_x1_l0_match0_mmwp1_mml1`
- `test_pmp_ok_1_u1_rw00_x1_l0_match1_mmwp0_mml0`
- `test_pmp_ok_1_u1_rw00_x1_l0_match1_mmwp0_mml1`
- `test_pmp_ok_1_u1_rw00_x1_l0_match1_mmwp1_mml0`
- `test_pmp_ok_1_u1_rw00_x1_l0_match1_mmwp1_mml1`
- `test_pmp_ok_1_u1_rw00_x1_l1_match0_mmwp0_mml0`
- `test_pmp_ok_1_u1_rw00_x1_l1_match0_mmwp0_mml1`
- `test_pmp_ok_1_u1_rw00_x1_l1_match0_mmwp1_mml0`
- `test_pmp_ok_1_u1_rw00_x1_l1_match0_mmwp1_mml1`
- `test_pmp_ok_1_u1_rw00_x1_l1_match1_mmwp0_mml0`
- `test_pmp_ok_1_u1_rw00_x1_l1_match1_mmwp0_mml1`
- `test_pmp_ok_1_u1_rw00_x1_l1_match1_mmwp1_mml0`
- `test_pmp_ok_1_u1_rw00_x1_l1_match1_mmwp1_mml1`
- `test_pmp_ok_1_u1_rw10_x0_l0_match0_mmwp0_mml0`
- `test_pmp_ok_1_u1_rw10_x0_l0_match0_mmwp0_mml1`
- `test_pmp_ok_1_u1_rw10_x0_l0_match0_mmwp1_mml0`
- `test_pmp_ok_1_u1_rw10_x0_l0_match0_mmwp1_mml1`
- `test_pmp_ok_1_u1_rw10_x0_l0_match1_mmwp0_mml0`
- `test_pmp_ok_1_u1_rw10_x0_l0_match1_mmwp0_mml1`
- `test_pmp_ok_1_u1_rw10_x0_l0_match1_mmwp1_mml0`
- `test_pmp_ok_1_u1_rw10_x0_l0_match1_mmwp1_mml1`
- `test_pmp_ok_1_u1_rw10_x0_l1_match0_mmwp0_mml0`
- `test_pmp_ok_1_u1_rw10_x0_l1_match0_mmwp0_mml1`
- `test_pmp_ok_1_u1_rw10_x0_l1_match0_mmwp1_mml0`
- `test_pmp_ok_1_u1_rw10_x0_l1_match0_mmwp1_mml1`
- `test_pmp_ok_1_u1_rw10_x0_l1_match1_mmwp0_mml0`
- `test_pmp_ok_1_u1_rw10_x0_l1_match1_mmwp0_mml1`
- `test_pmp_ok_1_u1_rw10_x0_l1_match1_mmwp1_mml0`
- `test_pmp_ok_1_u1_rw10_x0_l1_match1_mmwp1_mml1`
- `test_pmp_ok_1_u1_rw10_x1_l0_match0_mmwp0_mml0`
- `test_pmp_ok_1_u1_rw10_x1_l0_match0_mmwp0_mml1`
- `test_pmp_ok_1_u1_rw10_x1_l0_match0_mmwp1_mml0`
- `test_pmp_ok_1_u1_rw10_x1_l0_match0_mmwp1_mml1`
- `test_pmp_ok_1_u1_rw10_x1_l0_match1_mmwp0_mml0`
- `test_pmp_ok_1_u1_rw10_x1_l0_match1_mmwp0_mml1`
- `test_pmp_ok_1_u1_rw10_x1_l0_match1_mmwp1_mml0`
- `test_pmp_ok_1_u1_rw10_x1_l0_match1_mmwp1_mml1`
- `test_pmp_ok_1_u1_rw10_x1_l1_match0_mmwp0_mml0`
- `test_pmp_ok_1_u1_rw10_x1_l1_match0_mmwp0_mml1`
- `test_pmp_ok_1_u1_rw10_x1_l1_match0_mmwp1_mml0`
- `test_pmp_ok_1_u1_rw10_x1_l1_match0_mmwp1_mml1`
- `test_pmp_ok_1_u1_rw10_x1_l1_match1_mmwp0_mml0`
- `test_pmp_ok_1_u1_rw10_x1_l1_match1_mmwp0_mml1`
- `test_pmp_ok_1_u1_rw10_x1_l1_match1_mmwp1_mml0`
- `test_pmp_ok_1_u1_rw10_x1_l1_match1_mmwp1_mml1`
- `test_pmp_ok_1_u1_rw11_x0_l0_match0_mmwp0_mml0`
- `test_pmp_ok_1_u1_rw11_x0_l0_match0_mmwp0_mml1`
- `test_pmp_ok_1_u1_rw11_x0_l0_match0_mmwp1_mml0`
- `test_pmp_ok_1_u1_rw11_x0_l0_match0_mmwp1_mml1`
- `test_pmp_ok_1_u1_rw11_x0_l0_match1_mmwp0_mml0`
- `test_pmp_ok_1_u1_rw11_x0_l0_match1_mmwp0_mml1`
- `test_pmp_ok_1_u1_rw11_x0_l0_match1_mmwp1_mml0`
- `test_pmp_ok_1_u1_rw11_x0_l0_match1_mmwp1_mml1`
- `test_pmp_ok_1_u1_rw11_x0_l1_match0_mmwp0_mml0`
- `test_pmp_ok_1_u1_rw11_x0_l1_match0_mmwp0_mml1`
- `test_pmp_ok_1_u1_rw11_x0_l1_match0_mmwp1_mml0`
- `test_pmp_ok_1_u1_rw11_x0_l1_match0_mmwp1_mml1`
- `test_pmp_ok_1_u1_rw11_x0_l1_match1_mmwp0_mml0`
- `test_pmp_ok_1_u1_rw11_x0_l1_match1_mmwp0_mml1`
- `test_pmp_ok_1_u1_rw11_x0_l1_match1_mmwp1_mml0`
- `test_pmp_ok_1_u1_rw11_x0_l1_match1_mmwp1_mml1`
- `test_pmp_ok_1_u1_rw11_x1_l0_match0_mmwp0_mml0`
- `test_pmp_ok_1_u1_rw11_x1_l0_match0_mmwp0_mml1`
- `test_pmp_ok_1_u1_rw11_x1_l0_match0_mmwp1_mml0`
- `test_pmp_ok_1_u1_rw11_x1_l0_match0_mmwp1_mml1`
- `test_pmp_ok_1_u1_rw11_x1_l0_match1_mmwp0_mml0`
- `test_pmp_ok_1_u1_rw11_x1_l0_match1_mmwp0_mml1`
- `test_pmp_ok_1_u1_rw11_x1_l0_match1_mmwp1_mml0`
- `test_pmp_ok_1_u1_rw11_x1_l0_match1_mmwp1_mml1`
- `test_pmp_ok_1_u1_rw11_x1_l1_match0_mmwp0_mml0`
- `test_pmp_ok_1_u1_rw11_x1_l1_match0_mmwp0_mml1`
- `test_pmp_ok_1_u1_rw11_x1_l1_match0_mmwp1_mml0`
- `test_pmp_ok_1_u1_rw11_x1_l1_match0_mmwp1_mml1`
- `test_pmp_ok_1_u1_rw11_x1_l1_match1_mmwp0_mml0`
- `test_pmp_ok_1_u1_rw11_x1_l1_match1_mmwp0_mml1`
- `test_pmp_ok_1_u1_rw11_x1_l1_match1_mmwp1_mml0`
- `test_pmp_ok_1_u1_rw11_x1_l1_match1_mmwp1_mml1`
- `test_pmp_ok_share_1_r0_x0_cfgl0_typex0_umode0`
- `test_pmp_ok_share_1_r0_x0_cfgl0_typex0_umode1`
- `test_pmp_ok_share_1_r0_x0_cfgl0_typex1_umode0`
- `test_pmp_ok_share_1_r0_x0_cfgl0_typex1_umode1`
- `test_pmp_ok_share_1_r0_x0_cfgl1_typex0_umode0`
- `test_pmp_ok_share_1_r0_x0_cfgl1_typex0_umode1`
- `test_pmp_ok_share_1_r0_x0_cfgl1_typex1_umode0`
- `test_pmp_ok_share_1_r0_x0_cfgl1_typex1_umode1`
- `test_pmp_ok_share_1_r0_x1_cfgl0_typex0_umode0`
- `test_pmp_ok_share_1_r0_x1_cfgl0_typex0_umode1`
- `test_pmp_ok_share_1_r0_x1_cfgl0_typex1_umode0`
- `test_pmp_ok_share_1_r0_x1_cfgl0_typex1_umode1`
- `test_pmp_ok_share_1_r0_x1_cfgl1_typex0_umode0`
- `test_pmp_ok_share_1_r0_x1_cfgl1_typex0_umode1`
- `test_pmp_ok_share_1_r0_x1_cfgl1_typex1_umode0`
- `test_pmp_ok_share_1_r0_x1_cfgl1_typex1_umode1`
- `test_pmp_ok_share_1_r1_x0_cfgl0_typex0_umode1`
- `test_pmp_ok_share_1_r1_x0_cfgl0_typex1_umode1`
- `test_pmp_ok_share_1_r1_x0_cfgl1_typex0_umode1`
- `test_pmp_ok_share_1_r1_x0_cfgl1_typex1_umode1`
- `test_pmp_ok_share_1_r1_x1_cfgl0_typex0_umode1`
- `test_pmp_ok_share_1_r1_x1_cfgl0_typex1_umode1`
- `test_pmp_ok_share_1_r1_x1_cfgl1_typex0_umode1`
- `test_pmp_ok_share_1_r1_x1_cfgl1_typex1_umode1`


Generated ePMP CSR and access tests

Generated ePMP tests (riscv-isa-sim mseccfg gengen): every combination of lock, RLB,
MMWP, MML, mode and permission, for CSR behaviour and for access checks.

Generated tests from directed_testlist.yaml; each name encodes its scenario
(test_pmp_csr_1_lock00_rlb0_mmwp0_mml0_pmp_01 ...
test_pmp_ok_share_1_r1_x1_cfgl1_typex1_umode1).

#### `pmp_directed`

Tests:
- `access_pmp_overlap`
- `cov_expr_fetch_wrap`
- `cov_expr_pmp_tor`
- `cov_fcov_pmp_mml_locked_wr`
- `pmp_fault_hazard`
- `pmp_mseccfg_test_rlb0_l0_0_u0`
- `pmp_mseccfg_test_rlb0_l0_0_u1`
- `pmp_mseccfg_test_rlb0_l0_1_next_l1_r1_u0`
- `pmp_mseccfg_test_rlb0_l0_1_next_l1_r1_u1`
- `pmp_mseccfg_test_rlb0_l0_1_next_l1_r1_w1_u0`
- `pmp_mseccfg_test_rlb0_l0_1_next_l1_r1_w1_u1`
- `pmp_mseccfg_test_rlb0_l0_1_next_l1_r1_w1_x1_u0`
- `pmp_mseccfg_test_rlb0_l0_1_next_l1_r1_w1_x1_u1`
- `pmp_mseccfg_test_rlb0_l0_1_next_l1_r1_x1_u0`
- `pmp_mseccfg_test_rlb0_l0_1_next_l1_r1_x1_u1`
- `pmp_mseccfg_test_rlb0_l0_1_next_l1_u0`
- `pmp_mseccfg_test_rlb0_l0_1_next_l1_u1`
- `pmp_mseccfg_test_rlb0_l0_1_next_l1_w1_u0`
- `pmp_mseccfg_test_rlb0_l0_1_next_l1_w1_u1`
- `pmp_mseccfg_test_rlb0_l0_1_next_l1_w1_x1_u0`
- `pmp_mseccfg_test_rlb0_l0_1_next_l1_w1_x1_u1`
- `pmp_mseccfg_test_rlb0_l0_1_next_l1_x1_u0`
- `pmp_mseccfg_test_rlb0_l0_1_next_l1_x1_u1`
- `pmp_mseccfg_test_rlb1_l0_0_u0`
- `pmp_mseccfg_test_rlb1_l0_0_u1`
- `pmp_mseccfg_test_rlb1_l0_1_u0`
- `pmp_mseccfg_test_rlb1_l0_1_u1`
- `pmp_mseccfg_test_rlb1_l1_0_u0`
- `pmp_mseccfg_test_rlb1_l1_0_u1`
- `pmp_mseccfg_test_rlb1_l1_1_u0`
- `pmp_mseccfg_test_rlb1_l1_1_u1`


Directed PMP: overlap, mseccfg lock, TOR edges and faults behind accesses

PMP directed tests: overlapping regions (priority of the lowest-numbered match), and
mseccfg RLB and lock interaction -- which pmpcfg writes are accepted after locking;
PMP-fault, bus-error and completing load/stores followed by each instruction
category, with the icache and data-independent timing off and on, a masked pending
interrupt, dcsr.ebreakm, and debug requests, NMIs and fetch-enable drops raised at
the fault (pmp_fault_hazard, core_ibex_stall_events_test), including a non-executable
word that decodes as a load, so the faulting fetch also stalls ID as a memory
instruction. TOR entries whose top is not above their bottom match nothing, for all
16 entries, and a fetch at the start of a locked TOR entry faults with mtval at that
address; an instruction access fault at pc 0 and an exception taken with the mtvec
base at 0 (cov_expr_pmp_tor). A 32-bit instruction at 0xFFFFFFFE whose second half
wraps to address 0 executes, and with address 0 denied faults with mepc 0xFFFFFFFE
and mtval 0 (cov_expr_fetch_wrap). With mseccfg.MML = 1 and RLB = 0, writes of every
executable MML configuration to locked entries are ignored
(cov_fcov_pmp_mml_locked_wr).

- access_pmp_overlap: PMP access basic test
- cov_expr_fetch_wrap: A 32-bit instruction at 0xFFFFFFFE whose second half wraps to
  address 0: it executes when nothing denies address 0, and with a locked no-X TOR
  entry [0, 4) its fetch faults with mcause 1, mepc 0xFFFFFFFE, mtval 0 (pc + 2).
  Targets ibex_controller.sv csr_mtval_o with instr_fetch_err_plus2_i. Cosim off
  (Spike forms pc + 2 in 64 bits); self-checking, TEST_FAIL code in gp.
- cov_expr_pmp_tor: PMP TOR entries whose top is not above their bottom match nothing
  (Privileged ISA, PMP): for every entry 0..15, an M-mode fetch and load at exactly
  the entry's start succeed while the entry is locked with no permissions
  (mseccfg.RLB = 1 so entries can be rewritten); a fetch at the start of a locked TOR
  entry [X, X+16) succeeds with X and faults (mcause 1, mtval X) without. Also an
  instruction access fault at pc 0 (mtval 0) and an exception taken with the mtvec
  base at 0 (handler copied to address 0). Targets ibex_pmp.sv region_match_all
  (TOR), ibex_controller.sv csr_mtval_o for fetch faults and ibex_if_stage.sv exc_pc
  (EXC_PC_EXC). Spike cosim on. TEST_FAIL code in gp (test header).
- cov_fcov_pmp_mml_locked_wr: mseccfg.MML = 1, RLB = 0: PMP entries 4-7 locked as
  MML_L, MML_RM, MML_WRM and MML_RM_RU (A = OFF), region 0 a locked M-mode RX rule
  over the program. Seven writes of pmpcfg1, one per executable MML configuration
  (XU, XRU, XWRU, XM_XU, XM, XRM, XRM_XU in every byte), are all ignored: pmpcfg1
  reads back unchanged after each (Privileged Spec 3.7.1 lock, Smepmp). Fills every
  rlb = 0 bin of pmp_region_cg.pmp_wr_exec_region from a locked source, which the
  riscv_epmp_* random tests reach only on some seeds. Spike cosim on. TEST_PASS /
  TEST_FAIL with the failing check's code in TESTNUM (gp): 1-4 setup, 10-16 a write
  took effect, 0x100|code unexpected trap.
- pmp_fault_hazard: Load/store accesses each followed by one instruction category
  (ALU/Mul/Div with and without a load hazard, branch, jalr through the loaded
  address, jal, load, store, CSR, fence, fence.i, ecall, ebreak, mret, wfi,
  compressed/uncompressed/CSR/privilege illegal, fetch error of a nop and of a load
  word, the latter FetchError with a Mem stall), in three passes: PMP fault (locked
  no-permission entry), bus error (d-side error window) and a completing access after
  which the instruction executes. Sweeps with icache off/on, data-independent timing,
  a masked pending timer interrupt and dcsr.ebreakm. The rtl_test raises debug
  requests at PMP faults, bus errors, ID stalls and after trap flushes, NMIs after
  trap flushes, fetch-enable drops, and the timer interrupt at the first wfi. Targets
  uarch_cg.exception_stall_instr_cross, stall_cross, pipe_cross,
  pipe_flush_instr_cross, debug_entry_if_instr_cross, interrupt_taken_instr_cross and
  irq_wfi_cross. Self-checking (fail codes in the test header), Spike cosim on.
- pmp_mseccfg_test_rlb0_l0_0_u0, pmp_mseccfg_test_rlb0_l0_0_u1,
  pmp_mseccfg_test_rlb0_l0_1_next_l1_r1_u0, pmp_mseccfg_test_rlb0_l0_1_next_l1_r1_u1,
  pmp_mseccfg_test_rlb0_l0_1_next_l1_r1_w1_u0,
  pmp_mseccfg_test_rlb0_l0_1_next_l1_r1_w1_u1,
  pmp_mseccfg_test_rlb0_l0_1_next_l1_r1_w1_x1_u0,
  pmp_mseccfg_test_rlb0_l0_1_next_l1_r1_w1_x1_u1,
  pmp_mseccfg_test_rlb0_l0_1_next_l1_r1_x1_u0,
  pmp_mseccfg_test_rlb0_l0_1_next_l1_r1_x1_u1, pmp_mseccfg_test_rlb0_l0_1_next_l1_u0,
  pmp_mseccfg_test_rlb0_l0_1_next_l1_u1, pmp_mseccfg_test_rlb0_l0_1_next_l1_w1_u0,
  pmp_mseccfg_test_rlb0_l0_1_next_l1_w1_u1,
  pmp_mseccfg_test_rlb0_l0_1_next_l1_w1_x1_u0,
  pmp_mseccfg_test_rlb0_l0_1_next_l1_w1_x1_u1,
  pmp_mseccfg_test_rlb0_l0_1_next_l1_x1_u0, pmp_mseccfg_test_rlb0_l0_1_next_l1_x1_u1,
  pmp_mseccfg_test_rlb1_l0_0_u0, pmp_mseccfg_test_rlb1_l0_0_u1,
  pmp_mseccfg_test_rlb1_l0_1_u0, pmp_mseccfg_test_rlb1_l0_1_u1,
  pmp_mseccfg_test_rlb1_l1_0_u0, pmp_mseccfg_test_rlb1_l1_0_u1,
  pmp_mseccfg_test_rlb1_l1_1_u0, pmp_mseccfg_test_rlb1_l1_1_u1: mseccfg test

#### `counters_and_user_mode`

Tests:
- `cov_expr_counter_inhibit`
- `csr_access_sweep`
- `mcounteren_lock_test`
- `mcounteren_test`
- `u_mode_exec_test`


Counter enable and inhibit, and U-mode execution

mcounteren gating of U-mode counter access, its lock behaviour, and U-mode execution;
every CSR read and written from M-mode and from U-mode, illegal accesses trapping
(csr_access_sweep). minstret and mhpmcounter10 (compressed instructions retired)
count exactly, stay frozen while their mcountinhibit bits are set and count again
once cleared (cov_expr_counter_inhibit, self-checking: this Spike does not inhibit
minstret).

- cov_expr_counter_inhibit: minstret and mhpmcounter10 (compressed instructions
  retired) count exactly (N + 1 / the compressed ones), stay frozen while
  mcountinhibit bits 2 and 10 are set and instructions (8 compressed, 8 not) retire,
  then count again. Targets ibex_cs_registers.sv mhpmcounter[2] and
  gen_compressed_instr_cnt (instr_ret*_spec_i & ~mcountinhibit). Cosim off: this
  Spike does not inhibit minstret (see counter_high_half_write). TEST_FAIL code in
  gp.
- csr_access_sweep: Reads and writes every CSR counted by uarch_cg's cp_csr_read_only
  / cp_csr_write, from M-mode (write back the value read) and from U-mode (with
  mcounteren 0 and all-ones). Illegal accesses are skipped by the trap handler. Fills
  csr_read_only_priv_cross, csr_write_priv_cross and cp_csr_write. MSHWM/MSHWMB are
  swept from U-mode only (Ibex and Spike both trap); their M-mode accesses are left
  to CHERIoT tests.
- mcounteren_lock_test: Tests that mcounteren retains its value after
  mcounteren_writable_i is de-asserted mid-simulation (write-lock).
- mcounteren_test: Tests the mcounteren CSR: reset value, hardwired-zero bit 1
  (time), and U-mode counter access gating.
- u_mode_exec_test: PMP U mode exec test

#### `cheriot_isa_directed`

Tests:
- `cheriot_andperm`
- `cheriot_asr_counter_csr`
- `cheriot_auipcc_auicgp_repr`
- `cheriot_branch_self_loop`
- `cheriot_c_shift_imm`
- `cheriot_cap_addr`
- `cheriot_cap_base`
- `cheriot_cap_high`
- `cheriot_cap_len`
- `cheriot_cap_perms`
- `cheriot_cap_readback`
- `cheriot_cap_type`
- `cheriot_ccleartag`
- `cheriot_cinc_addr`
- `cheriot_cincaddrimm`
- `cheriot_cjal_link_wrap`
- `cheriot_cjalr_faults`
- `cheriot_cjalr_sentry`
- `cheriot_clsc_top_edge`
- `cheriot_cseal_cunseal`
- `cheriot_csetaddr`
- `cheriot_csethigh`
- `cheriot_cspecialrw_c0`
- `cheriot_csub`
- `cheriot_debug_mode`
- `cheriot_fetch_bounds`
- `cheriot_intcap_arith`
- `cheriot_irq_cheri`
- `cheriot_mem_err`
- `cheriot_mscratchc_seal`
- `cheriot_mtvec_mepc_access`
- `cheriot_null_cap`
- `cheriot_pcc`
- `cheriot_perm_lc_sc`
- `cheriot_reg_index`
- `cheriot_repr_window_sweep`
- `cheriot_scr_faults`
- `cheriot_scr_legalize`
- `cheriot_seal_fail`
- `cheriot_setbounds`
- `cheriot_setboundsexact`
- `cheriot_setboundsimm`
- `cheriot_setboundsrndn`
- `cheriot_zero_len_perm`
- `cov_fcov2_cheri_isa`


Directed CHERIoT instruction tests

CHERIoT instructions and capability state, self-checking: capability fields (base,
length, type, permissions, address, high word), CIncAddr/CSetAddr/CSetBounds variants
and rounding, sealing and unsealing, sentries on CJALR, CJALR fault causes, priority
and sentry/register-pair rules, PCC, PCC bounds at instruction fetch (sequential,
straddling 32-bit, branch/jump/CJALR/MRET targets), the null capability, capability
readback, CLC/CSC through an authority without MC (tag stripped on load, tagged store
traps, untagged store succeeds), SCRs, and ASR-gated counters; every failing arm of
CSeal/CUnseal and the tag-clearing of modified sealed capabilities; CSR, CSpecialRW
and MRET faults without PCC.SR; the legacy mtvec/mepc CSRs being illegal in CHERIoT
mode. CSetHigh: the CGetHigh/CSetHigh round trip (cheriot_cap_high) and, in
cheriot_csethigh, tagged, untagged, sealed and bounded sources, inexact and exact
bounds, cursors that move the decoded bounds, all six permission formats, the
reserved bit and sealed otypes, with the tag always cleared. AUIPCC and AUICGP on
both sides of each representable-window edge (cheriot_auipcc_auicgp_repr); CSetAddr,
CIncAddr and CIncAddrImm at every byte within 10 of both window edges for E = 0, 3
and 10 (cheriot_repr_window_sweep). CSpecialRW read-only (cs1 = c0), write-only (cd =
c0), read-write and no-op forms on all four SCRs (cheriot_cspecialrw_c0). Zero-length
and zero-permission capabilities through every instruction class that uses an
authority (cheriot_zero_len_perm). MTCC/MEPCC legalisation of misaligned and sealed
values (cheriot_scr_legalize); CLC bounds against a top of 2^32
(cheriot_clsc_top_edge); the faulting register's index in mtval for c0 and csp-cs1,
and R-type operand indices over x0/x5/x15 (cheriot_reg_index). c.srli/c.srai with a
non-zero shift on a capability register: shifted address, tag cleared
(cheriot_c_shift_imm). CJAL at 2^32 - 2, whose link wraps to 0
(cheriot_cjal_link_wrap, cosim off: CHERIoT-Sail cannot represent the link): the link
is untagged or keeps exactly the PCC's bounds. AUICGP, CIncAddrImm and CIncAddr on an
untagged sealed E = 0 capability whose base decodes above its address (0xFFFFFF00 for
address 0x10), and CGetBase of the memory root at address 0xFFFFFFFF, against
CHERIoT-Sail (cov_fcov2_cheri_isa).

- cheriot_andperm: CAndPerm (funct7=0x0D) narrows a capability's permission field
  without clearing the tag (unsealed capabilities: narrowing permissions is always
  safe/monotone). Applies mask=0xFF to MTCC (perms=0x1EB), clearing EX (bit 8) while
  preserving GL (bit 0). Tests: (1) tag still 1 after CAndPerm; (2) EX now clear; (3)
  GL still set.
- cheriot_asr_counter_csr: Counter CSRs must be readable while PCC lacks the access-
  system-registers permission. ext_check_CSR() in the CHERIoT Sail model admits reads
  of mcycle/minstret/mcycleh/minstreth and the unprivileged cycle/time/instret
  shadows without ASR, and requires ASR only for writes. ibex_decoder.sv's safe-list
  originally covered just 0xC00-0xC9F and omitted the four 0xB machine-mode counters,
  so "csrr rd, mcycle" from a compartment without ASR raised
  PermitAccessSystemRegistersViolation -- CHERIoT RTOS times every test with that
  instruction and hung in an endless violation loop. CAndPerm is monotone and the
  crt's exit path needs ASR, so the read is done inside a CJALR excursion whose
  backward sentry restores the ASR-bearing PCC on return. Tests: (1) the derived
  capability has SR clear; (2) it retains EX, so the excursion is genuinely
  executable; (3) mcycle advances rather than trapping while ASR is absent; (4) the
  excursion ran to completion; (5) ASR is restored afterwards.
- cheriot_auipcc_auicgp_repr: AUIPCC and AUICGP (imm20 << 11) at the edges of the
  representable window [base, base + 2^(9+E)) (CHERIoT-Sail AUIPCC/AUICGP,
  setCapAddr/incCapAddr). AUIPCC runs in five code blocks, each from its own
  CSetBoundsExact PCC (E = 3, and E = 0), so that pc -/+ 2048 lands on the window
  base, 2 below it, 2 below the top and one past the top: tag kept inside, cleared
  outside, address always pc + offset; plus the full PCC, and a block stored at
  0x80FFF7FC whose AUIPCC lands 2 below the base of an E = 24 PCC [0x80000000,
  0x81000000) (tag kept) and below an E = 12 PCC (tag cleared). AUICGP from a bounded
  c3 with the cursor at d = -2, -1 and 0 from the edges, an E = 0 c3, a sealed c3
  (tag cleared, otype kept), an untagged c3 and the full c3. Hits the new
  AUIPCC/AUICGP bins of cheri_representability_cg (rep_op_outside_cross,
  rep_op_edge_cross, cp_rep_auipcc_edge) and cheriot_cauipcc_cross /
  cheriot_cauicgp_cross. Returns 0, else a code from the test header, 250 (trap), 251
  (liveness).
- cheriot_branch_self_loop: A taken branch (c.beqz) or CJAL (c.jal) to itself at the
  base of a PCC of length 2, 3 or 4: cp_cheri_branch_bound 0x022, 0x032, 0x0a2,
  0x122, 0x132 and cp_cheri_cjal_bound 0x022, 0x032, 0x0c2, 0x122, 0x132, in bench
  memory, at 0 and just under 2^32 (+far_code_windows=1). The trap handler writes
  each loop, enters it by mret with MIE = 1, and the interrupt
  core_ibex_cheriot_irq_test raises ends it. The handler checks mcause, mtval = 0,
  mstatus, MEPCC = the loop PCC with the loop address and, for CJAL, the link (tag,
  pc + 2, otype 5). CHERIoT-Sail oracle on. Returns 0, else a code from the test
  header plus 256 x the loop index.
- cheriot_c_shift_imm: c.srli and c.srai with a non-zero shift in CHERIoT mode: on a
  capability register (an MTCC copy) the result is the shifted address with the tag
  cleared; c.srai of a negative integer shifts arithmetically. Returns 0 on success,
  else the failing check (1-6).
- cheriot_cap_addr: CGetAddr (funct7=0x7F, rs2=0x0F -- note: not 0x05) on the three
  reset root capabilities. At reset all three have base=0, so CGetAddr must return 0
  for each. Tests: (1) MTCC addr=0; (2) MTDC addr=0; (3) MScratchC addr=0.
- cheriot_cap_base: CHERIoT capability base address test. Verifies that MTCC, MTDC,
  and MScratchC all have base address = 0 at reset using CGetBase (funct7=0x7F,
  rs2=2, .word 0xFE25055B) -- an instruction not exercised by earlier tests. All
  three root capabilities cover the full 4 GB address space (base=0, length=2^32).
  Tests: (1) MTCC base=0; (2) MTDC base=0; (3) MScratchC base=0.
- cheriot_cap_high: CGetHigh/CSetHigh (funct7=0x7f rs2=0x17 / funct7=0x16) round-trip
  a capability's packed non-address metadata through the CHERIoT memory
  representation. Tests: (1) tag is always cleared by CSetHigh (it can never mint a
  valid capability); (2)-(5) perm/base/len/otype round-trip correctly; (6) address is
  taken from cs1's cursor, not the "high" word.
- cheriot_cap_len: CGetLen (funct7=0x7F, rs2=3) on the three reset root capabilities.
  MTCC/MTDC/MScratchC all cover the full 4GB address space at reset (base=0,
  top=2^32), which overflows a 32-bit register; cheriot_cap_length saturates to
  0xFFFFFFFF when top33[32]=1. Tests: (1) MTCC length= 0xFFFFFFFF; (2) MTDC
  length=0xFFFFFFFF; (3) MScratchC length=0xFFFFFFFF.
- cheriot_cap_perms: CHERIoT capability permission checks inspired by cheri-c-
  tests/clang_purecap_init.c (CTSRD/Cambridge). Verifies that code capabilities have
  execute permission and data capabilities do not, using cgetperm on the reset values
  of MTCC (execution root, perms=0x1EB) and MTDC (memory data root, perms=0x07F).
  Tests: (1) MTCC tag=1; (2) MTCC permit_execute (bit 8) is set; (3) MTDC tag=1; (4)
  MTDC permit_execute (bit 8) is clear; (5) MTDC permit_load (bit 5) is set; (6) MTDC
  permit_store (bit 2) is set.
- cheriot_cap_readback: Field-by-field CSC/CLC round-trip check: stores a capability
  (MTDC, then MTCC) to memory and reloads it, verifying tag/perm/base/len/ addr/type
  are all preserved exactly, and that an integer store to the same slot clears the
  tag on reload (revocation); round trips of CSetBoundsExact caps at E = 1..14 (tag,
  length, base) and of an otype-14 sealed data cap (codes 20-79).
- cheriot_cap_type: CGetType (funct7=0x7F, rs2=1) on the three reset root
  capabilities. All three are unsealed at reset, so CGetType must return 0
  (OTYPE_UNSEALED) for each. Tests: (1) MTCC type=0; (2) MTDC type=0; (3) MScratchC
  type=0.
- cheriot_ccleartag: CClearTag (funct7=0x7F, rs2=0x0B) clears the tag and nothing
  else (CHERIoT-Sail clearTag). On a copy of MTCC, whose cursor is trap_entry
  (installed by crt_cheriot.S): (1) tag=1 before; (7) address before is non-zero
  (precondition); (2) tag=0 after; (3) address after equals the address before;
  (4)-(6) no interrupt. Results in t0/s0 so ca0 keeps the capability. Returns 0 on
  success, else 1-7.
- cheriot_cinc_addr: CIncAddr (funct7=0x11) adds an integer offset to a capability's
  cursor; the tag stays 1 as long as the new cursor is within [base, top). Applies +4
  to MTCC (full 4GB range). Tests: (1) cursor now 4; (2) base unchanged (0); (3) tag
  still 1 (in-bounds).
- cheriot_cincaddrimm: CIncAddrImm (funct3=001), the immediate-operand sibling of
  CIncAddr. Tests: (1) CGetAddr after +4 immediate increment; (2) base unchanged; (3)
  tag preserved (in-bounds increment on MTCC).
- cheriot_cjal_link_wrap: A c.jal (CJAL cra) at 2^32 - 2 under PCC [2^32 - 2, 2^32),
  whose link address wraps to 0: cp_cheri_cjal_bound 0x0c1 (2 bytes back, the
  target's fetch faults with mcause 28, mtval 0x401, MEPCC.address = target,
  untagged) and 0x0a2 (to itself, ended by an interrupt as in
  cheriot_branch_self_loop, with the minstret liveness count). CHERIoT-Sail asserts
  that a CJAL link is always representable, so the cosim is off and the test checks
  the obligation itself: the link address is 0 and the link is untagged, or tagged
  with exactly the PCC's bounds and a backward-sentry otype (4 with MIE = 0, 5 with
  MIE = 1). cra holds a recognisable tagged capability before each CJAL, so an
  unwritten link fails. Returns 0, else a code from the test header.
- cheriot_cjalr_faults: CJALR exception causes and priority (REQ_CFI_01/03,
  REQ_PER_03, REQ_SEL_06/08), expected values from CHERIoT-Sail CJALR. Untagged cs1
  gives capcause 0x02 against cs1, before seal and EX (also via c.jr); data-sealed
  (otype 9, 15) and executable non-sentry (6, 7) cs1 give 0x03, before EX; tagged
  unsealed cs1 without EX gives 0x11 (also via c.jalr). Sentry/register-pair rules:
  backward sentry for a call or tail call, forward sentry otype 2 with cd = ct1,
  forward sentry or unsealed cap as a return (cd = c0, cs1 = cra), and a sealed cs1
  with imm != 0 all give 0x03. mtval[9:5] = cs1, MEPCC at the CJALR and tagged, cd
  not written. Controls: otype 1 sentry with cd = ct1 or c0 and an unsealed cap with
  imm 4 jump. REQ_PER_03: an MTCC written without EX reads back untagged (restored at
  once; trapping through it would livelock), and MRET through an EX-less MEPCC faults
  at the fetch with 0x02 against PCC (mtval 0x402). Returns 0 on success, else a
  section-coded failure.
- cheriot_cjalr_sentry: CJALR compartment call/return through a real interrupt-
  toggling sentry (OTYPE_SENTRY_IE_FWD), not just the implicit unsealed-jump path
  exercised by crt boot code elsewhere. Tests: (1) mstatus.MIE set on entry; (2)
  CJALR mints a real tagged backward sentry in ra; (3) mstatus.MIE restored to its
  pre-call value on return via that sentry; (4) the callee actually executed.
- cheriot_clsc_top_edge: CLC bounds checks against a top of 2^32 (REQ_BND_01/02,
  CHERIoT-Sail LoadCapImm inCapBounds): authorities [0xFFFFFFFE, 2^32) and
  [0xFFFFFFF0, 2^32) from CSetBoundsExact; CLC at -1, -3, -5 (below the base, 3/5/7
  bytes under the top) and +9 (addr + 8 = 2^32 + 1) each raise a bounds violation
  (mtval 0x161 / 0x1C1) with MEPCC at the CLC and cd not written. Returns 0, else
  1-6, 10-44, 250 (trap), 251 (liveness).
- cheriot_cseal_cunseal: CSeal/CUnseal (funct7=0x0b/0x0c) round-trip an executable
  capability (MTCC) through a sentry seal using MScratchC (ROOT_CAP_TS, the dedicated
  sealing root with SE/US permission) as the sealing authority. Tests: (1)-(2) CSeal
  succeeds (tag=1, otype=1= OTYPE_SENTRY_II_FWD); (3) original cs1 untouched; (4)-(5)
  CUnseal succeeds (tag=1, otype=0); (6) permissions preserved round-trip; (10-24)
  CUnseal with an untagged, sealed, local data authority gives an untagged, unsealed,
  non-global result for an integer, untagged sealed local/global and tagged unsealed
  cs1; (25-52) CUnseal of an unsealed cs1 with a tagged sealed authority (US 0 or 1),
  an untagged sealed one with US = 1, and an untagged sealed global one: cd untagged,
  unsealed, GL = cs1.GL & cs2.GL; (53-54) CSeal of MTCC with an untagged sealing
  authority whose address is its base gives an untagged result; (55-58) CUnseal of a
  tagged unsealed global cs1 with a tagged sealed authority without US and GL: cd
  untagged, unsealed, GL 0; (59-61) CSeal of MTCC with an untagged SE authority at
  address 13 inside its bounds, and with a tagged non-SE authority whose address 4 is
  above its top: cd untagged.
- cheriot_csetaddr: CSetAddr (funct7=0x10) sets a capability's cursor to an absolute
  address from an integer register (vs CIncAddr's relative offset). Per CHERIoT-Sail
  setCapAddr the tag is cleared iff cs1 is sealed or the new address is
  unrepresentable (window [base, base + 2^(9+E))); MTCC is full-range, so it is kept
  here. On one MTCC copy, no re-derivation: (1) CSetAddr(0x1000) gives cursor 0x1000;
  (2) base still 0; (3) tag still 1; (4) a second CSetAddr(0) gives cursor 0; (5)-(7)
  no interrupt. Results in t0 so ca0 keeps the capability. Returns 0 on success, else
  1-7.
- cheriot_csethigh: CSetHigh (CHERIoT-Sail cheri_insts.sail CSetHigh: cd =
  capBitsToCapability(false, rs2 @ cs1.address)) from a tagged root, an inexact (len
  1001 -> 1002, E = 1) and an exact bounded source, untagged sources (CClearTag and a
  plain integer), a sealed source and the cra sentry: the result is always untagged,
  takes its address from cs1 and every other field from rs2, never traps, and
  CGetHigh returns rs2 bit for bit. The same high word decodes to different bounds at
  different cs1 cursors (inside, 64 KiB away, 2 below the base). Sixteen fixed rs2
  patterns (the last seven add (cotype, cperms) pairs no other source produces,
  cotype 2 and 7 with cperms 0x39 and cotype 6 with 0x22 for cheriot_csethigh_cross0)
  cover all six permission formats, the reserved bit, sealed otypes, E = 24 and T <
  B, with Sail-decoded perms/otype/base/top/len. CSEQX tells two results apart by the
  reserved bit alone. Returns 0, else 1-247, 250 (trap), 251 (liveness).
- cheriot_cspecialrw_c0: CSpecialRW forms on MTCC, MTDC, MScratchC and MEPCC
  (CHERIoT-Sail CSpecialRW: cs1 = c0 only reads). For each SCR: write-only (cd = c0)
  writes and leaves c0 null; read-only (cs1 = c0) returns the value bit for bit
  (CSEQX) and a second read-only returns it again, so the first did not write NULL;
  read-write returns the old value and installs the new; a nonzero cs1 index holding
  NULL does write NULL; cd = cs1 = c0 changes nothing. Legal values are used for
  MTCC/MEPCC so legalisation must not alter them. Returns 0, else 10-60, 250 (trap),
  251 (liveness).
- cheriot_csub: CSub (funct7=0x14) computes an integer cursor difference between two
  capability registers (cs1.cursor - cs2.cursor), the canonical CHERIoT pointer-
  difference idiom. Tests: (1) CSub(MTCC, MTCC)=0; (2) CSub(MTCC+16, MTCC)=16 after
  CIncAddr.
- cheriot_debug_mode: Debug mode with cheriot_enable_i asserted: haltreq entry (DEPCC
  = PCC at dpc), the debug-mode capability-check bypass (untagged/out-of-bounds/no-
  SD/sealed authority, clc through an untagged pointer) and the same accesses
  faulting after dret, DScratchC0/1 preserving capabilities, ebreak with
  dcsr.ebreakm, single step (including a stepped ebreak, cause ebreak, and a stepped
  faulting fetch that re-enters at the trap handler), dret with an untagged / out-of-
  bounds / sealed / non-executable DEPCC faulting on the first fetch, debug SCRs
  illegal outside debug mode, then random debug requests over CHERI work
  (core_ibex_cheriot_debug_test). Self-checking, cosim off (CHERIoT-Sail has no debug
  mode). Returns 0 on success; codes in the test header.
- cheriot_fetch_bounds: PCC bounds at instruction fetch (REQ_BND_03/07,
  REQ_BRA_05/08, REQ_CFI_05). Enters small exact CSetBoundsExact execute regions and
  expects each fetch outside [base, top) to trap with mcause 28, mtval 0x401 (Bounds
  Violation against PCC), MEPCC.address = the faulting fetch PC and MEPCC.tag = 0,
  with the out-of-bounds instruction not executed: sequential fetch reaching Top; a
  32-bit instruction whose second half-word is past Top (both alignments, mepc = the
  instruction, not +2); a 16-bit instruction ending exactly at Top executes (both
  alignments); a taken BEQ past Top and a CJAL below Base retire and fault at the
  target; CJALR to a capability whose address is its Top, and CJALR with imm -4 to
  below Base, retire and fault at the target; MRET to a tagged MEPCC whose address is
  its Top. Section 11 runs one taken branch per reachable cp_cheri_branch_bound value
  (gen_branch_bounds.py): targets below, at, inside, 1..7 bytes under, at and above
  the top of exact small regions, and against PCC [0x81000000, 2^32) and [0,
  0x81000000) with code copied there; in-bounds targets must run, the others fault at
  the target. Section 12 (needs +far_code_windows=1) copies code to 0 and to 2^32 -
  32 and runs the same checks for taken branches and CJALs to targets 2..6 bytes
  under a top of 2^32, at a base of 0, 1..7 bytes under an odd top over a base of 0
  and at 0 / 2^32 - 2..6 under the root PCC (CJAL also at the base of [0x81000000,
  2^32), below it, at, above and 2..6 under the top of [0, 0x81000000), under section
  11's PCCs of length 2..7 and 7 bytes under the top of a length-9 one,
  cp_cheri_cjal_bound 0x070), checking the CJAL link; and AUIPCC from PCCs at both
  ends whose result wraps past 2^32 or 0, checking the address and the cleared tag.
  Section 13 is section 10's MRET with an untagged MEPCC: the fetch at Top violates
  the tag and the bounds, and must report the tag (mtval 0x402). Returns 0 on
  success, else a section-coded failure.
- cheriot_intcap_arith: Any integer ALU op writing a register clears its capability
  tag -- the core CHERI guarantee that a capability cannot be forged by integer
  arithmetic. Exercises addi/add/sub/andi/ori/xori/slli/mul, checking cgettag=0 after
  each. Tests: (1) li/addi; (2) add; (3) sub; (4) andi; (5) ori; (6) xori; (7) slli;
  (8) mul.
- cheriot_irq_cheri: Timer/external/software interrupts taken while cheriot_enable_i
  is asserted, during CSC/CLC bursts, misaligned accesses, interrupt-disabling and
  -enabling sentry calls and register-only CHERI work. CHERIoT handler (MTCC,
  MScratchC trap stack, csc/clc frame, mret through MEPCC) checks mtval = 0, mstatus
  MIE/MPIE/MPP, MEPCC tag/otype/perms/address and mcause; the program checks
  capability state survives every interrupt, MIE across sentries (REQ_INT_07) and
  that >= 12 interrupts arrived. The UVM side (core_ibex_cheriot_irq_test) checks the
  riscv-dv handshake. CHERIoT-Sail oracle on. Returns 0 on success; codes in the test
  header.
- cheriot_mem_err: Bus errors and memory integrity errors with cheriot_enable_i
  asserted, injected by address so each lands on a chosen access: both halves of
  misaligned lw/sw/sh, both beats of CLC and CSC, bad integrity on a word load and on
  each beat of a CLC (internal NMI, mcause 0xFFFFFFE0), and instruction-fetch bus and
  integrity errors. Also a misaligned lw with both halves faulting, a CHERI op and a
  branch after a faulting load (flushed), and word-load integrity NMIs arriving among
  CHERI ops (exactly the ops before MEPCC executed). Checks mcause, mtval, MEPCC and
  that a faulted load leaves its destination unchanged; the UVM side
  (core_ibex_cheriot_mem_err_test) requires a bus alert per integrity error and no
  other alert. Self-checking, cosim off (CHERIoT-Sail has no bus errors and no NMI).
  Returns 0 on success; codes in the test header (89 = open question, see there).
- cheriot_mscratchc_seal: MScratchC (SCR 30) resets to CPERMS_TS, the seal root
  capability, not a general-purpose scratch register. Checks expand_perms(CPERMS_TS)
  via cgetperm: GL(0)=1, US(9)=1, SE(10)=1, U0(11)=1, all else clear (in particular
  EX(8)=0 -- not executable). Tests: (1) tag=1; (2) permit_seal set; (3)
  permit_unseal set; (4) permit_execute clear; (5) global set.
- cheriot_mtvec_mepc_access: Legacy mtvec/mepc CSRs in CHERIoT mode (REQ_SCR_07), per
  the CHERIoT ISA document: csrr, csrw, csrrw, csrrs, csrrc, csrrwi, csrrsi, csrrci
  and csrrsi-with-0 on mtvec (0x305) and on mepc (0x341) each raise an illegal
  instruction (mcause 2) at that pc, leave rd and MTCC unchanged, and a write never
  redirects the trap vector. Boots in RISC-V mode, the bench raises cheriot_enable_i
  on the write to 0x80200000; cosim off (see the comment above). Returns 0 on
  success, else 1-8 or 10*probe + 1..5, 190-193.
- cheriot_null_cap: CHERIoT capability property checks adapted from cheri-c-
  tests/clang_purecap_null.c (CTSRD/Cambridge). Uses raw .word-encoded CHERIoT
  instructions (cgettag, cspecialr) compiled via the standard rv32imc toolchain.
  Checks: (1) an integer-zero register has capability tag = 0; (2) MTCC has tag = 1;
  (3) MTDC has tag = 1.
- cheriot_pcc: Program Counter Capability (PCC) properties via AUIPCC (opcode=0x17,
  decoded as CAUIPCC under cheriot_enable_i). Tests: (1) PCC tag=1; (2) PCC has
  execute permission (EX, bit 8); (3) PCC has global permission (GL, bit 0).
- cheriot_perm_lc_sc: CLC and CSC through an authority without MC
  (Permit_Load_Store_Capability, CHERIoT's single load/store-capability permission;
  perms 0x25 GL SD LD). CLC of a global and a local capability returns each with tag
  0 and every other field intact (address, perms, CSetEqualExact to CClearTag of the
  original), with no exception. CSC of an untagged value succeeds and writes it
  untagged. CSC of a tagged capability traps: mcause 28, mtval 0x175 (capcause 0x15
  against c11), MEPCC at the CSC, target slot still holds its old tagged value.
  Controls through the MTDC authority (0x7F) keep the tag. Returns 0 on success, else
  1-34.
- cheriot_reg_index: Register indices (REQ_EXC_01/03/05, CHERIoT-Sail
  handle_cheri_reg_exception): a Tag Violation through c0 (lw and CJALR) and through
  csp, cgp, ctp, ct0-ct2, cs0 and cs1 holding an integer gives mcause 28, mtval =
  index << 5 | 0x02, MEPCC at the instruction and rd not written. Then ADD over all
  27 (rd, rs1, rs2) drawn from x0, t0 and a5, results checked (rd = x0 discards; x0
  read back as 0 afterwards). Returns 0, else 10-104, 110-164, 250 (trap), 251
  (liveness).
- cheriot_repr_window_sweep: CSetAddr, CIncAddr and CIncAddrImm at every byte within
  10 of both edges of the representable window [base, base + 2^(9+E)) (CHERIoT-Sail
  CSetAddr/CIncAddr/ CIncAddrImmediate, setCapAddr/incCapAddr, capBoundsEqual), for
  unsealed E = 0, E = 3 and E = 10 capabilities whose bases are not aligned to the
  window size: the address is always the requested one, the tag is kept iff the
  address is inside the window. CIncAddr and CIncAddrImm start from a cursor 16 bytes
  inside the edge (for E = 0, past the bounds but inside the window). Hits
  cp_rep_hi_dist, rep_lo_edge_cross, rep_hi_edge_cross and the
  CSetAddr/CIncAddr/CIncAddrImm upper-edge bins of rep_op_edge_cross. Returns 0, else
  a code from the test header (n*1000 + edge*500 + op*100 + (d+10)*2 + {0 tag, 1
  address}; n*1000 + 900-904), 250 (trap), 251 (liveness).
- cheriot_scr_faults: System-register access without PCC.SR (REQ_PER_06, REQ_SCR_01,
  REQ_EXC_04), expected values from CHERIoT-Sail. Runs from a PCC derived with
  CAndPerm(MTCC, 0xF7F) and recovers through a test-local MTCC. Reads of mcycle,
  minstret, mcycleh, minstreth (and csrrsi/csrrci with uimm 0) are permitted; csrr
  mstatus, csrw mscratch, csrw mcycle, csrrs with rs1 != x0 and MRET give capcause
  0x18 against PCC (mtval 0x418), with no side effect; CSpecialRW on
  MTCC/MTDC/MScratchC/MEPCC gives 0x18 with mtval[10:5] = 0x20 + scr (0x798, 0x7B8,
  0x7D8, 0x7F8) and writes neither cd nor the SCR. SCRs 1, 24 and 27, an undefined
  CSR and a write to mhartid are illegal instructions (mcause 2) ahead of the SR
  check. Returns 0 on success, else 1-87.
- cheriot_scr_legalize: MTCC/MEPCC legalisation on CSpecialW (REQ_SCR_02/03, CHERIoT-
  Sail CSpecialRW): MTCC written with address[1:0] = 1, 2, 3 and MEPCC with
  address[0] = 1 read back untagged with those bits cleared; a sealed (otype 1)
  executable value reads back untagged with its otype kept; an aligned unsealed value
  stays tagged (control). Operands checked tagged first; MTCC restored immediately
  after each probe. Returns 0, else 10-90, 250 (trap), 251 (liveness).
- cheriot_seal_fail: Sealing failure arms and sealed-capability immutability
  (REQ_SEL_01-04), expected values from CHERIoT-Sail. CSeal gives tag 0, no trap, for
  an untagged, sealed or SE-less cs2, cs2.address = cs2.top, a sealed cs1, and an
  otype outside 1-7 (executable cs1) or 9-15 (data cs1), including values whose low
  bits are legal; controls at otypes 1, 7, 9, 15 and the last in-bounds address.
  CUnseal gives tag 0 for an untagged, sealed or US-less cs2, an unsealed cs1, and an
  otype below base or at top; cs2.address is not compared; GL = cs1.GL & cs2.GL.
  CIncAddr, CIncAddrImm, CSetAddr, CSetBounds(Exact/Imm/RoundDown), AUICGP and
  CAndPerm on a sealed cap clear the tag (CAndPerm keeps it for mask 0xFFF or only GL
  cleared), each with an unsealed control. lw, sw, CLC and CSC through a data-sealed
  cap and a sentry trap with capcause 0x03 against the authority, nothing written.
  Returns 0 on success, else 1-136.
- cheriot_setbounds: CSetBounds (funct7=0x08) narrows a capability's bounds to
  [cursor, cursor+len). Tests: (1) CGetLen=256 after CSetBounds(MTDC,256); (2)
  CGetBase=0; (3) tag=1 (sub-region contained in original bounds); (4) CGetAddr
  (cursor) unchanged; (8-20) a tagged cs1 with its cursor above top (E = 2 at top+4,
  E = 24 at 0x91000000) gives an untagged result for requests 1, 7 and 0, with Sail
  base/length; (21-24) the same with the E = 2 cursor at top and a request of 3;
  (25-27) the E = 24 cursor above top with a request of 7; (28-31) a sealed tagged E
  = 1 source with its cursor inside and a request of 0 gives an untagged result (Sail
  clearTagIfSealed), base = cursor, length 0; (32-34) the E = 24 cursor above top
  with a request of 1; (35-42) a length-2 E = 0 source with its cursor above top and
  requests 3 and 7 (longer than cs1): untagged, base = cursor, length = request
  (cheriot_csetbounds_cross1).
- cheriot_setboundsexact: CSetBoundsExact (funct7=0x09) clears the tag instead of
  rounding up when the requested bounds aren't exactly representable. Tests: (1)-(2)
  len=256 (exact) succeeds with tag=1, CGetLen=256; (3) len=300 (not exactly
  representable) clears the tag.
- cheriot_setboundsimm: CSetBoundsImm (funct3=010), the immediate-operand sibling of
  CSetBounds. Tests: (1) CGetLen=256 after CSetBoundsImm(MTDC,256); (2) CGetBase=0;
  (3) tag=1; (4) CGetAddr (cursor) unchanged.
- cheriot_setboundsrndn: CSetBoundsRoundDown (funct7=0x0a) rounds the requested
  length DOWN (result subset of request) instead of UP like plain CSetBounds (result
  superset of request). Tests: (1) length <= requested; (2) base unchanged; (3)
  tag=1; (4) round-down length strictly less than plain CSetBounds's round-up length
  for the same non-power-of-two request, proving the two take genuinely different
  datapaths.
- cheriot_zero_len_perm: Zero-length capabilities (CSetBounds(c, 0), including at the
  end of an object, where inCapBounds(c, top, 0) holds) and zero-permission
  capabilities (CAndPerm(c, 0)), per CHERIoT-Sail. Field reads;
  CSetBounds/Exact/Imm/RoundDown with length 0 keep the tag, length 1 and an address
  above top clear it; CIncAddr/CSetAddr follow the 512-byte E = 0 window; lw, lb, sw,
  sb, CLC, CSC through a zero-length authority give capcause 0x01, through a zero-
  permission one 0x12/0x13, and through one with both the permission fault wins;
  untagged gives 0x02; nothing is written. CJALR to a zero-length executable
  capability retires and the fetch faults (mtval 0x401, MEPCC tag 0); CJALR to a
  permission-less one gives 0x11. Zero-length and permission-less sealing authorities
  make CSeal/CUnseal clear the tag, while a zero-length capability can be sealed and
  unsealed. Returns 0, else 1-110, 250 (trap), 251 (liveness).
- cov_fcov2_cheri_isa: AUICGP 0, CIncAddrImm 0 / -1 and CIncAddr x0 / 0xFFFFFFFF on
  an untagged sealed E = 0 capability (CSetHigh of the null capability at 0x10, high
  word 0x00422100) whose base decodes to 0xFFFFFF00, above its address; CGetBase of
  the memory root at address 0xFFFFFFFF. Results from CHERIoT-Sail: tag 0, address
  +increment, high word unchanged, no trap; base 0, tagged. Targets cheriot_uarch_cg
  cheriot_cauicgp_cross, cheriot_cincaddrimm_cross, cheriot_cincaddr_cross (untagged,
  case1, sealed, E = 0) and cheriot_cget_field_cross (tagged, address 0xFFFFFFFF,
  CFIELD_BASE). CHERIoT-Sail cosim on. Returns 0, else a code from the test header,
  250 (trap), 251 (liveness).

#### `cheriot_random_operands`

Tests:
- `cheriot_rand_ldst`
- `cheriot_rand_operands`
- `cheriot_rand_operands_far`


CHERIoT instructions over random operands, checked by the cosim

CHERIoT instructions over randomly built operands, checked instruction by instruction
by the CHERIoT-Sail cosim (rd value and tag; capability metadata through a CGetHigh
of every capability result): a per-seed LFSR builds capabilities from MTDC, MTCC and
MScratchC in every operand class the cheriot_uarch_cg crosses name -- root, E = 24, E
= 1..14, E = 0 and zero-length bounds, cursor below/at the base, inside, near, at and
above the top, all permission encodings, every otype, untagged and raw-encoded -- and
runs the CSetBounds family, CIncAddr/CIncAddrImm/CSetAddr, AUICGP and AUIPCC (every
imm20 class, from E = 0/2/5/24 PCCs), CGet*, CSetHigh, CSEQX, CTestSubset, CSeal,
CUnseal, CRRL, CRAM, CSC, CLC, CJALR (every rd and immediate class, target against
the bounds, sentries, MIE), CJAL from bounded PCCs, and CSpecialRW on every SCR form
with and without PCC.SR. Instructions that fault resume through a CHERIoT trap
handler; the program checks liveness, its trap causes and model-independent
invariants (CSetHigh round trip, monotonic CSetBounds, CAndPerm only removes
permissions, CUnseal unseals). Fills the per-instruction operand crosses while
riscv_cheriot_rand_instr_test is disabled (cheriot_rand_operands). The same program
built for loads and stores only (cheriot_rand_ldst) issues every load/store width and
CLC/CSC at -10..10 bytes from the base or the top of an authority that is valid,
untagged or sealed, with the needed permission dropped or kept -- below-base cursors
through an E = 24 authority, the only exponent whose representable range includes
them -- for the bounds edges and the fault priority of every access
(cheri_access_bounds_cg).

- cheriot_rand_ldst: cheriot_rand_operands built with -DONLY_LDST: every operation is
  one load or store (LB, LBU, LH, LHU, LW, CLC, SB, SH, SW, CSC), naturally aligned,
  through an MTDC-derived authority whose base or top is placed -10..10 bytes from
  the access, with the needed permission (LD or SD) dropped or kept and the authority
  valid, untagged or sealed. Below-base cursors use an E = 24 authority, the only
  exponent whose representable range includes them. Fills cheri_access_bounds_cg
  (base/top edge crosses and the fault-priority cross). Faults resume through the
  CHERIoT handler; CHERIoT-Sail cosim checks every load result. Returns 0, else a
  code from the test header (2/3 unexpected trap, 10 liveness, 14 no access
  completed, 15 no access faulted).
- cheriot_rand_operands: Random CHERIoT operands for the per-instruction crosses of
  cheriot_uarch_cg: an LFSR (seeded per UVM seed) builds capabilities from
  MTDC/MTCC/MScratchC of every class the crosses name -- root, E = 24, E = 1..14, E =
  0 and zero-length bounds; base near 0, near 2^32 or anywhere; cursor below/at the
  base, inside, top-1..7, at/above the top; all permission encodings; every otype;
  untagged and raw-encoded -- and runs CSetBounds (all req_len classes),
  CSetBoundsExact/RoundDown/Imm, CIncAddr/CIncAddrImm/CSetAddr, AUICGP and AUIPCC
  (all imm20 classes, from E = 0/2/5/24 PCCs), the CGet* family, CSetHigh,
  CSEQX/CTestSubset (explicit tag x otype), CSeal/CUnseal (sealer otype 0-15/>=16 x
  position), CRRL/CRAM (rs1 bit-size 0-32), CSC/CLC, CJALR (rd c0/cra/ct1/ca5 x five
  imm classes, target vs bounds, sentries, MIE), CJAL from bounded PCCs, and a
  CSpecialRW sweep of SCR 28-31 and undefined SCRs x cs1/cd classes with and without
  PCC.SR. Before the loop, deterministic sweeps: CSetBounds requests 0-9 over fixed
  sources (setbounds_det); CRRL/CRAM/ CSetBoundsRoundDown on a tagged rs1 of every
  bit-size, and CSetBounds[Imm] on untagged raw E = 24 sources (bits_det); CJALR over
  cs1 tag x EX x cp_cheri_cjalr_bound value x imm class, generated from a model of
  CHERIoT-Sail (cjalr_det, gen_cjalr_det.py): every attempt checks its mtval, and
  tagged+EX jumps whose target is in bounds land in a zone the test writes at
  0x80FFFF80, where the number of instructions run before the fetch leaves PCC's
  bounds is checked; CJALR over cs1 tag x otype x rd x imm x MIE (cjalr_ot_det); and
  the address group on base-0, top-of-memory, wrapped-base, untagged sealed E = 4 and
  raw wrapped-base E = 0 capabilities (addr_det). CSEQX/CTestSubset operands include
  E = 0 capabilities with chosen T/B mantissas; CSeal sealers cover every SE x tag
  combination. Faulting instructions resume through a CHERIoT handler; CHERIoT-Sail
  cosim checks every result. Returns 0, else a code from the test header (2
  unexpected trap, 3 wrong cause or a fall-through ebreak, 4 CJALR fell through,
  10/11 liveness, 12/13 no CJALR faulted/landed, 16-18 cjalr_det landing count /
  return-or-trap / mtval, 19-27 ISA invariants).
- cheriot_rand_operands_far: cheriot_rand_operands built with -DFAR_WINDOWS and run
  with +far_code_windows=1 (CHERIoT-Sail maps [0, 0x1000) and [0x80000000, 2^32); the
  bench and Spike answer every address): the same program plus the cjalr_det cases
  whose tagged + EX target is fetched in bounds within 7 bytes of 0 or of 2^32 -- the
  63 cheriot_cjalr_cross1 bins the default build cannot reach (cp_cheri_cjalr_bound
  0x0a0/0x0c0/0x0e0 bin1-5, 0x0a2 bin1/2/5, 0x0c2/0x0e2 bin1/2/4/5, 0x102/0x182
  bin1-5, 0x122/0x132/0x142/0x152/0x162 bin1/2/4/5, 0x172 bin1/2/5, 0x130/0x150 bin2,
  0x170 bin2/4) and 24 more the random loop also hits. They land in two zones the
  test writes at [0, 0x80) and [0xFFFFFF80, 2^32) (c.addi in every halfword; the top
  zone ends in a c.beqz at 2^32 - 2 back to a cjalr at 0xFFFFFF78, so no fetch or
  link crosses 2^32), where the number of instructions run before the fetch leaves
  PCC's bounds and the return-or-fetch-fault outcome are checked against the CHERIoT-
  Sail model in gen_cjalr_det.py. Same failure codes as cheriot_rand_operands;
  liveness (11) counts CJD_NTRY + CJD_NTRY_FAR attempts.

#### `cheriot_stack_high_water_mark`

Test: `cheriot_mshwm`

CHERIoT stack high water mark CSRs

Stack high water mark CSRs mshwm/mshwmb (CHERIoT ISA section 'Stack high water mark',
CHERIoT-Sail): reset value, rounding of every write form to 16 bytes, the update on
every store kind whose start address is in [mshwmb, mshwm) and on no other access
(loads, stores outside the window, an empty window, faulting stores, a misaligned
store starting below mshwmb), the update from a PCC without SR, and SR-gated CSR
access (capcause 0x18). The pin-Off half (CSRs absent, illegal instruction) is in
cheriot_illegal_rv_mode.

- cheriot_mshwm: Stack high water mark CSRs mshwm (0xBC1) / mshwmb (0xBC2), CHERIoT
  ISA section "Stack high water mark" and CHERIoT-Sail (legalize_mshwm,
  ext_check_phys_mem_write, ext_check_CSR): reset value 0; every write form
  (csrw/csrrs/csrrc/csrrwi/csrrsi/csrrci) rounds bits [3:0] down to 0; a store whose
  start address is in [mshwmb, mshwm) sets mshwm to it rounded down to 16 -- sb, sh,
  sw, c.sw, CSC (tagged and untagged), c.csc -- and nothing else does: loads, CLC,
  stores below mshwmb or at/above mshwm, an empty window, a store that takes a CHERI
  bounds fault, a misaligned store starting below mshwmb; the update also happens
  from a PCC without SR. Without PCC.SR, csrr/csrw/csrrs of the CSRs raise capcause
  0x18 against PCC (mtval 0x418) and change nothing; every store kind (sb/sh/csc)
  below and at/above the window, faulting stores below and at mshwm, and csrw mshwm /
  csrr mshwmb without SR (checks run in the order 35, 64-68, 70-79, 36-44, 50-63,
  80-89, so the store-kind and faulting-store checks do not depend on check 37).
  Returns 0, else 1-89, 250 (trap), 251 (liveness).

#### `cheriot_illegal_instructions`

Tests:
- `cheriot_cdbg_ctrl_illegal`
- `cheriot_cgetoffset_illegal`
- `cheriot_illegal_branch_dit`
- `cheriot_illegal_rv_mode`
- `cheriot_illegal_sweep`
- `cheriot_illegal_sweep_sail_only`


Illegal instructions in CHERIoT and RISC-V mode

Illegal instructions with the expected cause, mtval and MEPCC: in CHERIoT mode a
sweep of every reserved encoding class on which CHERIoT-Sail and the RTL agree
(mcause 2, mtval 0), a second sweep of the encodings Sail rejects and the RTL
executes (Zcb, draft bit-manipulation, CSRs absent from the Sail platform; GAP-CS-3,
expected to fail until each disagreement is resolved), one unwaived test per encoding
the specification makes illegal and the RTL accepted (CGetOffset:
cheriot_cgetoffset_illegal; every CSR instruction form on cdbg_ctrl:
cheriot_cdbg_ctrl_illegal), and with the pin Off every CHERIoT-only encoding (opcodes
0x5B and 0x7B, CLC/CSC, the CHERIoT CSRs, compressed capability loads/stores) with
mtval = the instruction bits, against Spike. Random illegal instructions with the pin
Off are rdv_exceptions.

- cheriot_cdbg_ctrl_illegal: Every CSR instruction form on cdbg_ctrl (0xBC4) must
  raise an illegal instruction in CHERIoT mode (REQ_ISA_11 names the CSR; CHERIoT-
  Sail and the CHERIoT ISA have none). An RTL finding, not a known gap, so no waiver:
  fails until the RTL drops the CSR. Same mechanism as cheriot_illegal_sweep; codes
  2000 + 4 * slot + kind (kind 0 = executed instead of trapping), 1999 = liveness.
- cheriot_cgetoffset_illegal: CGetOffset (0x5B, funct7 0x7F, rs2 6) must raise an
  illegal instruction in CHERIoT mode: the CHERIoT ISA says the instruction is not
  present. An RTL finding, not a known gap, so no waiver: fails until the RTL drops
  it. Same mechanism as cheriot_illegal_sweep; code 2000 = executed instead of
  trapping, 1999 = liveness.
- cheriot_illegal_branch_dit: Branches and CJAL naming x16-x31 in CHERIoT mode must
  be illegal instructions (mcause 2, mtval 0, MEPCC at the instruction), with
  cpuctrlsts.data_ind_timing off and then on. The directed check of the unconfirmed
  RTL issue in tech-notes/rtl_todo.md: illegal_reg_16 does not clear branch_in_dec_o,
  so with data-independent timing an illegal branch may stall in ID, which the
  assertion IllegalInsnStallMustBeMemStall fails. The CHERIoT-Sail cosim checks both
  passes, cpuctrlsts included (GAP-CS-3); pass 2 also relies on the RTL assertions.
  Codes 2000/3000 + 4 * slot + kind (pass 1/2), 1999/2999 liveness, 2998
  data_ind_timing not set.
- cheriot_illegal_rv_mode: cheriot_enable_i held Off: every CHERIoT-only encoding is
  an illegal instruction with mtval = the instruction bits and mepc at it, checked
  against Spike -- one of each 0x5B instruction (CGet*, CRRL, CRAM, CMove, CClearTag,
  CSpecialRW, CSetBounds variants, CSeal, CUnseal, CAndPerm, CSetAddr, CIncAddr(Imm),
  CSub, CSetHigh, CTestSubset, CSEQX), AUICGP, CLC/CSC (ld/sd), csrr/csrw of mshwm,
  mshwmb and cdbg_ctrl, and c.clc/c.csc/ c.clcsp/c.cscsp
  (c.flw/c.fsw/c.flwsp/c.fswsp, no F). Returns 0, else 100 + 4 * slot + kind in the
  CORE_STATUS word, 99 (liveness).
- cheriot_illegal_sweep: Table-driven sweep of 163 encodings that CHERIoT-Sail and
  the RTL both reject in CHERIoT mode: unused 0x5B sub-opcodes, funct7 and funct3,
  undefined SCRs, reserved LOAD/STORE/JALR/BRANCH/MISC-MEM/SYSTEM forms, opcodes with
  no instruction in this configuration, reserved OP/OP-IMM forms, every instruction
  class naming x16-x31, CSRs that do not exist in CHERIoT mode and writes to read-
  only CSRs, and reserved 16-bit encodings including Zcmp and c.clcsp c0, and reads
  and writes of uccsr, sccsr and mccsr (legacy CHERI-RISC-V CSRs CHERIoT drops). Each
  must trap with mcause 2, mtval 0 and MEPCC at the encoding; the sweep records every
  misbehaving slot and carries on. Returns 0, else 1000 + 4 * slot + kind (first
  failure; count in mscratch), 999 (liveness).
- cheriot_illegal_sweep_sail_only: The encodings CHERIoT-Sail rejects but the RTL
  executes in CHERIoT mode, written to the model (the GAP-CS-3 items): the eleven Zcb
  instructions, the draft bit-manipulation instructions of RV32BOTEarlGrey outside
  Zba/Zbb/Zbc/Zbs/Zbkb/Zbkx, and CSRs the RTL implements and the Sail platform does
  not (mconfigptr, mcounteren, menvcfg[h], HPM, tdata1-3, m/s/mscontext, cpuctrlsts,
  secureseed). Same mechanism as cheriot_illegal_sweep. Fails on the current RTL by
  design: each failure code (2000 + 4 * slot + kind) identifies a disagreement for
  triage; 1999 = liveness.

#### `cheriot_rtos_patterns`

Tests:
- `cheriot_rtos_clc_csc`
- `cheriot_rtos_cmove`
- `cheriot_rtos_crrl`
- `cheriot_rtos_gettop`
- `cheriot_rtos_isequal`
- `cheriot_rtos_subset`


CHERIoT RTOS-pattern capability tests

CHERIoT instructions exercised the way the CHERIoT RTOS uses them, with expected
values from the CHERIoT Sail model: capabilities survive CSC/CLC exactly and an
integer store untags only its own granule; CMove copies every field and never sets a
tag; CRRL/CRAM across the exponent boundaries and saturation, and the allocator's
CSetBoundsExact recipe built on them; CGetTop saturates at 2^32 and decodes
independently of cursor and tag; CSetEqualExact detects a difference in any single
field; CTestSubset uses the Sail operand order and compares bounds, permissions and
tag.

- cheriot_rtos_clc_csc: Capabilities survive a trip through memory. MTCC and a
  bounded, permission-reduced object capability each come back from CSC/CLC tagged
  and CSetEqualExact to the original (base and length also checked). An SW to one
  slot clears its tag, the reloaded value carries the stored integer, and the other
  slot stays tagged. Returns 0 on success, else 1-12.
- cheriot_rtos_cmove: CMove copies every field. From a non-root source (bounded to
  [0x80001230,+64), cursor +8, perms reduced) the copy keeps tag, perms, base, length
  and address and is CSetEqualExact to the source; an untagged source gives an
  untagged copy; a copy of MTCC keeps perms 0x1EB. Returns 0 on success, else 1-12.
- cheriot_rtos_crrl: CRRL and CRAM against the Sail model for lengths 16, 511, 512,
  513, 1023 (exponent bump), 0x12345, 0x400000 (largest unsaturated exponent),
  0x800001 (exponent saturates to 24), 0xFFFFFFFF (CRRL wraps to 0) and 0. CRAM is
  all ones when no alignment is needed. Then the allocator recipe: CSetBoundsExact on
  base & CRAM with length CRRL keeps the tag and gives the expected bounds, and the
  unaligned base does not. Returns 0 on success, else 1-27.
- cheriot_rtos_gettop: CGetTop returns the decoded top, saturated: 0xFFFFFFFF for
  full range (not 0), 512 and 1024 for [0,512) and [0,1024), 0x80001100 for a non-
  zero base, unchanged after a cursor move and after CClearTag, and 0x80001202 when
  length 513 is rounded up. Returns 0 on success, else 1-10.
- cheriot_rtos_isequal: CSetEqualExact compares every field. Equal: a CMove copy, the
  same register twice, and a no-op CAndPerm(0xFFF). Not equal, each differing in one
  field only: permissions, address, tag, bounds; plus MTCC against MTDC. Returns 0 on
  success, else 1-11.
- cheriot_rtos_subset: CTestSubset rd, cs1, cs2 is "cs2 subset of cs1" (Sail operand
  order). Checks the order itself, the top, base and permission comparisons, a strict
  interior subset of a bounded capability, self-subset, a tag mismatch (0) and two
  untagged operands (1). Returns 0 on success, else 1-12.

#### `cheriot_temporal_safety`

Tests:
- `cheriot_revoke_attenuation`
- `cheriot_revoke_basic`
- `cheriot_revoke_load_barrier`
- `cheriot_revoke_load_barrier_intg`
- `cheriot_revoke_load_barrier_rnd`
- `cheriot_revoke_load_barrier_rnd_both`
- `cheriot_revoke_load_barrier_rnd_intg`


CHERIoT temporal safety: store revocation and stale-pointer faults

Temporal safety at the core boundary (REQ_TMP_01): every integer store width clears
the tag of the granule it touches, CSC of an untagged value clears it, stores do not
disturb neighbouring granules, and dereferencing a scrubbed (untagged) pointer raises
a CHERI tag violation reported against the right register and PC. The CLC load
barrier returns tag 0 for a capability whose base lies in a revoked granule (bit
select, unaligned base, first/last bitmap word), never revokes outside the heap
window, exempts SE/US/U0 capabilities, and treats a bitmap bus or integrity error as
revoked (alone or both on one response) and raises alert_major_bus.
ibex_revbm_responder serves the bitmap from +revbm_* plusargs and the CHERIoT-Sail
cosim is given the same bitmap, so every revoked CLC is checked by the model.

- cheriot_revoke_attenuation: A revoked capability loaded through an authority
  without LG: tag 0 and, per CHERIoT-Sail's LoadCapImm order, GL/LG cleared (perms
  0x7C). Controls: the same attenuation on a live load, and no attenuation through a
  full authority. Returns 0 on success, else 1-7.
- cheriot_revoke_basic: Integer stores revoke, stale pointers fault. CSC MTCC then
  CLC gives tag=1 (also the TRVK not-revoked path); SW to the low word, SW to the
  high word, SH and SB each clear the granule's tag; CSC of an untagged register
  clears it too; a store to the neighbouring granule leaves this one tagged. Then a
  scrubbed pointer is reloaded (tag=0, address intact) and an LW through it must
  trap: mcause=28, mtval=0x1A2 (tag violation on c13), MEPCC at the LW. Uses a test-
  local MTCC vector as juliet_cwe131_fault does. Returns 0 on success, else the
  number of the failing check (1-18).
- cheriot_revoke_load_barrier: Revoked arm of the TRVK load barrier. A CLC of a
  capability whose base is in a revoked granule returns tag 0, address and all other
  fields intact (bit select, unaligned base, base not cursor, first and last bitmap
  words); the neighbouring live granules keep the tag; bases out of TRVK's window
  (base 0, one past, one below, each aliasing a revoked bit) are never revoked;
  SE/US/U0 capabilities are exempt but a sealed data capability is not; a bitmap
  device error revokes the whole word and raises alert_major_bus (TB assertions);
  back-to-back lookups each get their own verdict. Returns 0 on success, else 1-38.
- cheriot_revoke_load_barrier_intg: cheriot_revoke_load_barrier with the error word
  answered with a flipped ECC bit instead of trvk_revbm_err_i (TRVK's integrity-error
  revocation path, cp_trvk_intg_error). Needs MemECC (SecureIbex=1); the responder
  stops the run at time 0 otherwise. Returns 0 on success, else 1-38.
- cheriot_revoke_load_barrier_rnd: 256 CLCs over bitmap words 0x180-0x187 against a
  per-seed random bitmap (50% revoked, 10% error words), with random bitmap-port
  backpressure and latency. The cosim checks each verdict; the program checks that a
  load is either identical or identical-but-untagged, that both outcomes occurred,
  that sealing capabilities over the same bases always keep the tag, and that bases
  just past the window are never revoked. Returns 0, else 1-8.
- cheriot_revoke_load_barrier_rnd_both: cheriot_revoke_load_barrier_rnd with 30% of
  the bitmap words answered with a device error and a flipped ECC bit on the same
  response (+revbm_err_kind=both; TRVK ORs them), with the selected bit set and clear
  (trvk_revoked_source_cross). Needs MemECC. Returns 0, else 1-8.
- cheriot_revoke_load_barrier_rnd_intg: cheriot_revoke_load_barrier_rnd with 30% of
  the bitmap words answered with a flipped ECC bit (+revbm_err_kind=intg), so
  integrity errors arrive on words whose selected bit is set and clear
  (trvk_revoked_source_cross). Needs MemECC (SecureIbex=1). Returns 0, else 1-8.

#### `cheriot_enable_transition`

Test: `cheriot_enable_transition`

cheriot_enable_i 0 to 1 while running

cheriot_enable_i 0->1 while running (#827, REQ_BCK_05): RISC-V mode works with the
pin Off, the testbench raises the pin when the program writes the trigger address
(+cheriot_enable_on_write), and CHERIoT mode is then active -- auipc decodes as
CAUIPCC and returns a tagged capability, while the auipc executed before the switch
left no tag. Self-checking, cosim off: neither Spike nor CHERIoT-Sail models a pin
that changes mid-run. The formal side (formal_testplan.hjson
cheriot_enable_transition) covers invalid encodings and tag creation while Off.

- cheriot_enable_transition: cheriot_enable_i 0->1 while running (#827, REQ_BCK_05).
  Starts in RISC-V mode with the pin Off, checks arithmetic, a load/store round trip
  and that auipc returns an untagged result; writes to 0x80200000, after which the
  testbench raises the pin (+cheriot_enable_on_write); then checks auipc decodes as
  CAUIPCC and returns a tagged capability. Self-checking, cosim off: neither Spike
  nor CHERIoT-Sail models a pin that changes mid-run.

#### `cheriot_enable_on_off`

Test: `cheriot_enable_on_off`

cheriot_enable_i 1 to 0 during a capability store raises a major alert

cheriot_enable_i 0->1 and then 1->0 while running (REQ_BCK_06). The 1->0 change
breaks the pin contract of REQ_BCK_05; the core must then raise
alert_major_internal_o rather than switch the capability checks off silently. After a
CSC/CLC round trip in CHERIoT mode the testbench slows the d-side grants and lowers
the pin while a CSC waits for its first grant (LSU CTX_WAIT_GNT1 -> IDLE, otherwise
never taken), and requires the alert within 100 cycles (+cheriot_disable_on_write).
Cosim off: neither model has the pin.

- cheriot_enable_on_off: cheriot_enable_i 0->1, then 1->0 while a CSC waits for the
  grant of its first word (REQ_BCK_06). As cheriot_enable_transition up to CHERIoT
  mode, plus a CSC/CLC round trip; then a write to 0x80200010, after which the
  testbench slows the d-side grants, lowers the pin while the next CSC sits in LSU
  state CTX_WAIT_GNT1 (the LSU must hold the request until granted and complete the
  CSC), and requires alert_major_internal_o within 100 cycles
  (+cheriot_disable_on_write, core_ibex_base_test::watch_cheriot_disable_trigger).
  The 1->0 change breaks the pin contract of REQ_BCK_05 on purpose; the testbench
  turns CheriotEnableOneWaySwitch off for it. The program then continues in RISC-V
  mode without a trap. Cosim off: neither model has the pin.

#### `zcmp_push_pop_mv`

Test: `zcmp_push_pop_mv`

Zcmp push/pop/move: every rlist, stack adjustment and register pair

Every Zcmp instruction in RISC-V mode: cm.push/cm.pop/cm.popret/cm.popretz over all
rlist values (ra .. ra,s0-s11) and all spimm values, cm.mvsa01/cm.mva01s over all
sreg pairs, the reserved rlist 0-3 and mv forms (illegal instruction), and back-to-
back sequences. Checks sp, every saved/loaded slot and register, and that nothing
else changed. Self-checking, cosim off: Spike cannot pair Zcmp's multi-register
accesses (GAP-RV-6).

- zcmp_push_pop_mv: Every Zcmp instruction with cheriot_enable_i Off, self-checked
  against the Zc specification (cosim off, GAP-RV-6). cm.push for every rlist 4..15
  and every spimm 0..3 (rlist 4 and 15 with all four): sp, every saved word at its
  slot, no other register changed, nothing written outside the saved slots. cm.pop,
  cm.popretz and cm.popret for every kind x rlist and kind x spimm: sp, every listed
  register loaded, unlisted ones untouched, a0 = 0 only for popretz, return to the
  popped ra for popret/popretz, no store. Some of each behind a DIV (the cm.* waits
  in IF). cm.mvsa01 for all 56 r1s != r2s pairs and cm.mva01s for all 64 pairs, three
  of each again with the first move's source loaded just before (its load-use stall
  holds the second move). The reserved/unused encodings of quadrant 2 funct3 101
  (push/pop forms with rlist 0..3, the 011 group with [6:5] = 00/10, other [12:8])
  trap with mcause 2, mepc at the instruction and mtval = its 16 bits, and change no
  register or memory. Back-to-back push;push, pop;pop, push;popretz, mvsa01;mva01s
  and push;mva01s;pop. Targets the Zcmp FSM and helper functions of
  ibex_compressed_decoder.sv. Returns 0, else case*100+check, 2 (unexpected trap), 1
  (liveness).

#### `counter_high_half_write`

Test: `counter_high_half_write`

Writes to the upper half of the 64-bit counters

Writes to the high halves of mcycle, minstret and mhpmcounter3-12 (mcycleh,
minstreth, mhpmcounterNh): mcycleh/minstreth read back, the low half is unchanged,
both counters carry into the high half; the 32-bit event counters read 0 in their
high half. Checked against Spike.

- counter_high_half_write: Writes the upper half of every 64-bit counter: mcycleh and
  minstreth read back the written value with the lower half undisturbed, and both
  counters carry from 0xFFFFFFxx into the upper half; mhpmcounter3h-12h
  (MHPMCounterWidth = 32 in the verified configuration) read 0 after a write of all-
  ones and their lower halves are unchanged. Targets the `if (counterh_we_i)` block
  of ibex_counter.sv in mcycle_counter_i, minstret_counter_i and the ten
  mcounters_variable_i instances (REQ_ISA_10; cp_counter_upper_half_write,
  cp_counter_lower_wrap). RISC-V mode, Spike oracle; mcountinhibit is not touched
  (this Spike does not inhibit minstret). TEST_FAIL with the failing check's code in
  TESTNUM (gp): 1-10, 20+N / 40+N for mhpmcounterN, 99 liveness, 0x100|code
  unexpected trap.

#### `cheriot_fatal_err_mtcc`

Test: `cheriot_fatal_err_mtcc`

A trap through an untagged MTCC raises a sticky major alert

A trap taken with MTCC untagged sets the sticky cheriot_fatal_err:
alert_major_internal_o rises within 4 cycles of the trap and stays high; no alert
before it, no minor or bus alert (core_ibex_cheriot_fatal_err_test). The spec leaves
this trap undefined (REQ_PER_03); the alert is checked as RTL design intent.

- cheriot_fatal_err_mtcc: A trap taken while MTCC is untagged. The program checks
  MTCC reads back untagged after CSpecialRW of an untagged value (REQ_PER_03),
  announces the trap (CORE_STATUS HANDLING_EXCEPTION) and executes ecall; it can
  never report afterwards. The bench (core_ibex_cheriot_fatal_err_test) requires the
  first trap after the announcement to be the ecall with alert_major_internal_o still
  low, the alert within 4 cycles and held for 2000 (sticky cheriot_fatal_err_q,
  ibex_cs_registers.sv gen_scr: "unrecoverable, need external reset"), no earlier
  alert and no minor/bus alert, then ends the run. The spec leaves this trap
  undefined, so the alert is checked as RTL design intent. NoAlertsTriggered and the
  double-fault detector are off in that class. CHERIoT-Sail stops at this trap
  (not_implemented), hence the RISC-V boot and +disable_cosim=1. Program codes 1, 2,
  10, 11, 249-251 (test header).

#### `cheriot_enable_off`

Test: `cheriot_bck_nocheck`

Loads and stores unchecked while cheriot_enable_i is Off

cheriot_enable_i held Off on the CHERIoT-capable build (REQ_BCK_02, Off half):
integer loads and stores through base registers that carry no capability -- which in
CHERIoT mode would each be a tag violation -- complete normally, checked against
Spike; CHERI instructions and CLC are illegal instructions, showing the pin really is
Off.

- cheriot_bck_nocheck: cheriot_enable_i Off (REQ_BCK_02, Off half): on the CHERIoT-
  capable build with the pin never raised, lw/sw, lh/lhu/sh and lb/lbu/sb through
  integer base registers (la-derived, loaded from memory, lui-only, and 2 KiB past
  the target with a negative offset) complete with the right data and no trap, where
  in CHERIoT mode each would be a tag violation. cgettag and a funct3=3 load (CLC)
  are illegal instructions, showing the pin is Off. Spike cosim. Returns 0 on
  success, else 1-17 in the CORE_STATUS word.

#### `juliet_baremetal`

Tests:
- `juliet_cwe121_stack_bof`
- `juliet_cwe122_heap_bof`
- `juliet_cwe123_write_what_where`
- `juliet_cwe124_buf_underwrite`
- `juliet_cwe131_fault`
- `juliet_cwe131_repr`
- `juliet_cwe190_int_overflow`
- `juliet_cwe193_off_by_one`
- `juliet_cwe272_least_privilege`
- `juliet_cwe415_double_free`
- `juliet_cwe416_use_after_free`
- `juliet_cwe457_uninit_var`
- `juliet_cwe468_fault`
- `juliet_cwe468_repr`


Juliet CWE memory-safety cases on bare metal

Juliet CWE cases on bare metal: each memory-safety weakness is stopped by the
expected CHERI check (bounds, tag, permission, representability).

- juliet_cwe121_stack_bof: CWE-121 Stack Buffer Overflow (Juliet Test Suite,
  NIST/NSA). A 64-byte capability to a .data "stack frame" (CSetBounds of MTDC). (1)
  CGetLen=64; (2) base=&frame; (3) tag=1; (4) CIncAddr+32 keeps tag=1; (9)-(10)
  control: sw through buf+32 does not trap and is written; (5) CIncAddr+128 (cursor
  160, past top 64 but representable, E=0) KEEPS tag=1; (11) cursor = &frame+160;
  (6)-(8) no interrupt; then the overflowing sw through buf+160 (12) traps with (13)
  mcause 28, (14) mtval 0x141 (bounds violation 0x01, c10), (15) MEPCC at the sw, and
  (16) frame[160] unchanged. (17) any other trap. Test-local MTCC vectors. Returns 0
  on success, else 1-17.
- juliet_cwe122_heap_bof: CWE-122 Heap Buffer Overflow (Juliet Test Suite, NIST/NSA).
  Creates a 256-byte bounded "heap allocation" via CSetBounds(MTDC,256). Tests: (1)
  CGetLen=256; (2) tag=1; (3) CIncAddr+64→tag=1 (in-bounds); (4) fresh bounded cap,
  CIncAddr+512 → tag=0 (past top=256, heap overflow denied — CHERIoT prevents the
  out-of-bounds write).
- juliet_cwe123_write_what_where: CWE-123 Write-What-Where Condition (Juliet Test
  Suite, NIST/NSA). Per CHERIoT-Sail setCapAddr, CSetAddr clears the tag iff the new
  address is unrepresentable (window [base, base + 2^(9+E))), not iff it leaves
  [base, top). 16-byte capability at 0x80080000, E=0 (no memory access): (1) tag=1;
  (7) control: CSetAddr(base+0x100), out of bounds but representable, keeps tag=1;
  (2) the attacker's CSetAddr(0x80090000) = base+0x10000 gives tag=0; (3)
  CGetAddr=0x80090000; (4)-(6) no interrupt. Returns 0 on success, else 1-7.
- juliet_cwe124_buf_underwrite: CWE-124 Buffer Underwrite (Juliet Test Suite,
  NIST/NSA). The CHERIoT representable window starts at base ([base, base +
  2^(9+E))), so per CHERIoT-Sail incCapAddr a cursor below base is unrepresentable
  and CIncAddr clears the tag; a store at base - 4 is a bounds violation. 16-byte
  capability on a .data buffer with a guard word below it: (1) tag=1; (7) control:
  CIncAddr +4 then -4 back to base keeps tag=1; (8)-(9) control store at base
  succeeds; (4)-(6) no interrupt; (10)-(14) sw -4(ca0) traps with mcause=28,
  mtval=0x141, MEPCC at the store, guard word unchanged; (2) CIncAddr -4 from base
  gives tag=0; (3) CGetAddr = base-4; (15) unexpected trap. Returns 0 on success,
  else 1-15.
- juliet_cwe131_fault: CWE-131 buffer size miscalculation — bounds enforcement at
  dereference. Builds a 4-byte bounded capability and stores at offset 8. The store
  is denied by hardware: mcause is set, the target word is unmodified, and an in-
  bounds store through the same capability still succeeds. Overrides the weak
  handle_trap from syscalls.c (which would exit the test) with a pure assembly stub
  that skips the faulting instruction and touches no memory. Returns 0 on success;
  1=cap invalid, 2=no trap, 3=memory was modified, 4=in-bounds store trapped,
  5=interrupt state.
- juliet_cwe131_repr: CWE-131 buffer size miscalculation — representability limit of
  CIncAddr. Confirms an 8-byte capability moved 8 past its end is STILL tagged (out
  of bounds but representable — the case the original test got wrong), then that
  moving it 256 MB out does clear the tag. Also checks CIncAddr never traps. Returns
  0 on success; 1=tag wrongly cleared, 2=tag wrongly kept, 3=cursor wrong,
  4-6=interrupt state.
- juliet_cwe190_int_overflow: CWE-190 Integer Overflow or Wraparound (Juliet Test
  Suite, NIST/NSA). Shows that an overflowed array index (0x7FFFFFFF) is caught by
  CHERIoT bounds even without software range checks. Tests: (1) CGetLen=64 (bounded
  buffer); (2) safe CIncAddr+32→tag=1; (3) CIncAddr+0x7FFFFFFF on fresh bounded cap →
  tag=0 (overflowed index denied — no software bounds check required).
- juliet_cwe193_off_by_one: CWE-193 Off-by-One Error (Juliet Test Suite, NIST/NSA). A
  16-byte capability to a .data buffer followed by a guard word. (1) tag=1; (2)
  CIncAddr+16, cursor = top, KEEPS tag=1 (one-past-the-end is representable); (7)
  cursor = &area+16; (3) fresh cap, CIncAddr+15 keeps tag=1; (8)-(9) control: sb
  buf[15] does not trap and is written; (4)-(6) no interrupt; then sb buf[16] through
  the cursor-at-top cap (10) traps with (11) mcause 28, (12) mtval 0x141 (bounds
  violation 0x01, c10), (13) MEPCC at the sb, and (14) the guard word unchanged. (15)
  any other trap. Test-local MTCC vectors. Returns 0 on success, else 1-15.
- juliet_cwe272_least_privilege: CWE-272 Least Privilege Violation (Juliet Test
  Suite, NIST/NSA). MTDC resets with perms=0x07F (bits 0-6 set, including
  SD=bit2=permit-store). CAndPerm(mask=0x07B) strips the SD bit.  The resulting
  capability cannot authorise stores, enforcing least privilege.  Tag is preserved
  because CAndPerm on an unsealed capability is a monotone (safe) narrowing. Tests:
  (1) cgetperm on MTDC=0x07F (baseline); (2) SD bit 2 clear after CAndPerm(0x07B)
  (write permission removed); (3) tag=1 after CAndPerm (tag preserved — narrowing is
  safe).
- juliet_cwe415_double_free: Named after CWE-415 Double Free; a register-level check
  only. (1) CSetBounds(MTDC, 128) gives tag=1; (2) CClearTag clears it; (3) a second
  CClearTag leaves it cleared; (4) the address is unchanged; (5)-(7) no interrupt. No
  load, store or trap; nothing is freed or revoked (revocation is covered at the
  Sonata layer).
- juliet_cwe416_use_after_free: Named after CWE-416 Use After Free; a register-level
  CClearTag check only. A 64-byte capability to a .data object (MTDC, CSetAddr,
  CSetBounds): (1) tag=1; (2) CClearTag ("free") gives tag=0; (3) CGetAddr is still
  the object's (non-zero) address; (4)-(6) no interrupt. No load, store or trap;
  nothing is freed or revoked (cheriot_revoke_basic covers the fault on a revoked
  pointer). Returns 0 on success, else 1-6.
- juliet_cwe457_uninit_var: CWE-457 Use of Uninitialized Variable (Juliet Test Suite,
  NIST/NSA). The CHERIoT null capability (x0, hardwired) has tag=0 and address=0. Any
  dereference through a tag=0 pointer raises a CHERI exception. An initialized root
  (MTDC via cspecialr) has tag=1. Tests: (1) cgettag on x0=0 (null/uninit pointer has
  no valid tag); (2) cgettag on MTDC=1 (initialized root is valid); (3) cgetaddr on
  x0=0 (null address is zero, not garbage).
- juliet_cwe468_fault: CWE-468 incorrect pointer scaling — bounds enforcement at
  dereference. Builds a capability bounded to a 2-element int32 array (8 bytes) and
  stores with a wrong stride at offset 8, one element past the end. The store is
  denied: mcause is set, memory is unmodified, and an in-bounds store still succeeds.
  Same handle_trap override as juliet_cwe131_fault. Returns 0 on success; 1=cap
  invalid, 2=no trap, 3=memory was modified, 4=in-bounds store trapped, 5=interrupt
  state.
- juliet_cwe468_repr: CWE-468 incorrect pointer scaling — representability limit of
  CIncAddr. Confirms a wrong stride that steps one element past an 8-byte array
  leaves the capability tagged (out of bounds but representable), while a wildly
  wrong scale factor makes the cursor unrepresentable and clears the tag. Returns 0
  on success; 1=tag wrongly cleared, 2=tag wrongly kept, 3=cursor wrong,
  4-6=interrupt state.

#### `whitebox_uarch`

Tests:
- `wb_branch_after_stall`
- `wb_cheri_clc_csc`
- `wb_cheri_sentry_cjalr`
- `wb_cheri_trap_mret`
- `wb_counter_inhibit`
- `wb_fetch_fifo_full`
- `wb_fetch_fifo_single`
- `wb_instr_stall_loop`
- `wb_lsu_misaligned`
- `wb_prefetch_branch`


White-box microarchitecture scenarios

White-box microarchitecture scenarios: fetch FIFO full/single, prefetch on branch,
instruction stalls, CLC/CSC in the pipeline, sentry CJALR, trap/mret, misaligned LSU
accesses and counter inhibit.

- wb_branch_after_stall: White-box data-dependent branch after multi-cycle EX stall
  (ibex_controller branch_req from WB stage after MUL/DIV stall).  Branch condition
  depends on DIVU result, so the branch cannot resolve until the divide completes.
  Tests both taken and not-taken paths.  Returns 0 on success; 1=taken branch wrong,
  2=not-taken branch wrong, 3-5=interrupt state.
- wb_cheri_clc_csc: White-box CHERIoT CLC two-beat cap_rx_fsm
  (ibex_load_store_unit.sv states CRX_IDLE → CRX_WAIT_RESP1 → CRX_WAIT_RESP2).
  Stores MTCC via CSC then loads it back via CLC, verifying tag=1.  Back-to-back CLCs
  exercise consecutive cap_rx_fsm cycles.  An integer SW to the same address then a
  CLC confirms tag revocation (CHERIoT temporal safety, tag=0). Returns 0 on success;
  1=CLC tag wrong, 2=back-to-back CLC wrong, 3=revocation failed, 4-6=interrupt
  state.
- wb_cheri_sentry_cjalr: White-box CHERIoT sentry CJALR path (cheri_ex.sv CJALR +
  CSeal, otype=1). Derives a code capability from PCC via AUIPCC, moves its cursor to
  a target label, seals it with MScratchC (cursor=1 = OTYPE_SENTRY), then jumps
  through it with CJALR.  Verifies: sentry tag=1 before jump, otype=1 before jump,
  ra.cap.otype=5 (OTYPE_SENTRY_IE_BKWD, MIE=1 at jump time), ra.cap.tag=1 after jump.
  Returns 0 on success; 1-7 identify specific failing checks.
- wb_cheri_trap_mret: White-box ibex_controller ECALL trap entry and MRET wakeup path
  (same controller FSM path as WFI wakeup).  Installs a 256-byte-aligned mtvec,
  executes ECALL (mcause=11), verifies the handler fires, then MRET resumes at
  mepc+4.  Checks mcause, mepc, and MIE restoration.  The 256-byte alignment is
  required for Spike cosim agreement (Ibex WARL vs Spike MTVEC granularity). Returns
  0 on success; 1=handler not called, 2=wrong mcause, 3=wrong mepc, 4=MIE not
  restored, 5=mip non-zero.
- wb_counter_inhibit: White-box mcountinhibit.CY gate on mcycle counter
  (ibex_cs_registers.sv). Verifies three states: (1) mcycle increments normally, (2)
  mcycle is frozen while mcountinhibit bit 0 = 1, (3) mcycle resumes after inhibit is
  cleared. CSR 0x320 = mcountinhibit; bit 1 is hardwired to 0 in ibex.  Returns 0 on
  success; 1=counter not running, 2=counter not stopped, 3=counter not resumed,
  4-6=interrupt state.
- wb_fetch_fifo_full: White-box fetch-FIFO full state (ibex_fetch_fifo DEPTH=3).  A
  ~32-cycle DIVU stall allows the prefetch buffer to fill all three FIFO slots.  A
  branch afterward exercises the FIFO-flush + prefetch-redirect path.  Tests that no
  instruction is lost or corrupted when the FIFO reaches maximum occupancy. Returns 0
  on success; 1=wrong first DIVU, 2=wrong second DIVU, 3-5=interrupt state
  divergence.
- wb_fetch_fifo_single: White-box fetch-FIFO single-entry state (ibex_fetch_fifo
  fifo_valid_n=1). Two back-to-back far JALs flush the FIFO and restart the
  prefetcher, so exactly one instruction is buffered before it is decoded.  Exercises
  the FIFO in its single-occupancy state on two successive prefetch restarts. Returns
  0 on success; 1=arithmetic wrong after jumps, 2-4=interrupt state.
- wb_instr_stall_loop: White-box sustained fetch stall: four consecutive ~32-cycle
  DIVU operations keep the pipeline stalled for ~128 cycles total, holding the fetch
  FIFO near maximum occupancy across multiple fill/drain cycles.  Exercises prolonged
  FIFO-full states analogous to many cycles of instr_gnt_i=0.  Sum of four quotients
  (700/7 + 800/8 + 900/9 + 600/6 = 400) verifies no stall corruption. Returns 0 on
  success; 1=wrong sum, 2-4=interrupt state.
- wb_lsu_misaligned: White-box ibex_load_store_unit misaligned word load
  (handle_misaligned_q two-beat split access).  Stores two known 32-bit words to a
  4-byte-aligned scratch address, then performs three misaligned LWs at offsets +1,
  +2, +3. The hardware merges the two aligned beats transparently; no exception is
  raised (CHERIoT-Ibex handles misaligned LW in hardware).  Returns 0 on success;
  1-3=wrong merged value, 4-6=interrupt state (no exception expected).
- wb_prefetch_branch: White-box prefetch-branch timing: branch while an instruction
  fetch is outstanding (ibex_prefetch_buffer prefetch_branch signal during in-flight
  request).  Three consecutive unconditional and conditional branches exercise the
  branch_req path before and during outstanding prefetches.  Also verifies the not-
  taken branch path after a branch resolve.  Returns 0 on success; 1=arithmetic
  wrong, 3-5=interrupt state.

#### `debug_directed`

Tests:
- `cov_expr_cheriot_dbg`
- `cov_expr_step_irq`
- `cov_fcov_debug_tdata_read`
- `debug_dm_pmp`
- `debug_mret_umode`


Directed debug-mode tests: privilege changes, the Debug Module range, trigger CSRs and single step

Debug mode beyond the riscv-dv debug tests: ebreak in debug mode re-enters without
updating dpc/dcsr; ecall, mret to U, a U-mode CSR access and dret at U inside one
debug session (UNSPECIFIED in the Debug Spec; expected values from the RTL, see the
test header) (debug_mret_umode); fetches, loads and stores in the Debug Module range
in debug mode with the PMP allowing and denying the range, addresses outside it still
PMP-checked, and the range denied outside debug mode (debug_dm_pmp, REQ_DBG_05). The
trigger CSRs tselect, tdata1 and tdata2 read in debug mode, which riscv-dv's debug
ROM never does (cov_fcov_debug_tdata_read). A single step with the timer interrupt
pending and enabled runs exactly one instruction and re-enters debug mode (cause 4;
Ibex hardwires dcsr.stepie to 0), and the interrupt is taken after the next dret with
mepc = that dpc (cov_expr_step_irq, REQ_DBG_02). In CHERIoT mode: a trap through an
MTCC at address 0, DEPCC := NULL read back untagged, and an ecall in debug mode going
to the debug exception address with mcause and MEPCC unchanged
(cov_expr_cheriot_dbg).

- cov_expr_cheriot_dbg: CHERIoT mode (pin raised by +cheriot_enable_on_write): a
  breakpoint trap through MTCC with address 0 runs the handler copied there and
  returns; in one debug session (doorbell store, core_ibex_stall_events_test) DEPCC
  := NULL reads back untagged with address 0, and an ecall in debug mode goes to the
  debug exception address and leaves mcause and MEPCC unchanged. Targets
  ibex_if_stage.sv exc_pc (CHERIoT arm) and ibex_cs_registers.sv gen_scr (DEPCC read,
  mepc_cap save in debug mode). Cosim off (CHERIoT-Sail has no debug mode); exit code
  in a0 (test header).
- cov_expr_step_irq: A single step (dcsr.step, stepie = 0) with mstatus.MIE set and
  the timer interrupt pending: exactly one instruction runs, debug mode is re-entered
  with dcsr.cause 4, and after the next dret the timer interrupt is taken with mepc =
  that dpc (Debug Spec 0.13.2). The bench raises irq_timer_i at the program's wfi and
  debug_req_i on a doorbell store (core_ibex_stall_events_test). Targets ibex_core.sv
  RVFI captured_taken (capture in DBG_TAKEN_IF without debug_req_i). Spike cosim on;
  needs spike_cosim.cc to hide pending interrupts from Spike while it single-steps
  (Ibex dcsr.stepie = 0; this Spike has no stepie and takes the interrupt before the
  step's debug entry). Any other mismatch points at the RVFI interrupt capture.
  TEST_FAIL code in gp.
- cov_fcov_debug_tdata_read: Read-only accesses to tselect, tdata1 and tdata2 in
  debug mode (one haltreq session): tselect 0, tdata1 0x28001048 (type 2, dmode,
  action = enter debug mode, m, u, execute 0), tdata2 0, then 0x5A5AA5A4 after a
  debug-mode write, then 0 again; tdata2 0 after dret. Targets
  uarch_cg.csr_read_only_debug_cross {TDATA1, TDATA2} x debug mode, which riscv-dv's
  debug ROM never reads. Expected values from ibex_cs_registers.sv gen_trigger_regs
  (Debug Spec 0.13.2 5.2); Spike cosim on. Returns 0 on success; codes in the test
  header.
- debug_dm_pmp: REQ_DBG_05 in RISC-V mode. In one debug session (haltreq) the handler
  copies a routine into the Debug Module range [0x1A110000, 0x1A111000) and runs it
  there (fetch, load, store), first with mseccfg.MMWP = 0 (the PMP check allows the
  range), then with MMWP = 1 (the PMP check denies it and only the debug-mode
  exemption allows it). A load just above the range still faults in debug mode (debug
  exception, no CSR updated). Back in M-mode, a load from and a jump into the range
  fault (mcause 5 / 1). Spike cosim on. Targets pmp_top_cg's dm_* coverpoints.
  Returns 0 on success; codes in the test header.
- debug_mret_umode: One debug session (haltreq) that runs, in debug mode: ebreak with
  dcsr.ebreakm while data-independent timing and dummy instructions are on (re-enters
  without updating dpc/dcsr, Debug Spec 4.1); ecall; mret with MPP = U to code that
  reads mstatus at U; mret to U again and dret at U. ecall and mret in debug mode are
  UNSPECIFIED in the Debug Spec, so those expected values come from the RTL and the
  privileged spec's mret semantics (test header): an exception jumps to the debug
  exception address, updates no CSR and returns the hart to M; dret at U returns to
  dpc at dcsr.prv = M (REQ_DBG_04). RISC-V mode, cosim off (Spike does not return to
  M on a debug-mode exception). Returns 0 on success; codes in the test header.

#### `cheriot_cpuctrl_hardening`

Test: `cheriot_dummy_instr`

Dummy instructions and data-independent timing in CHERIoT mode

Data-independent timing and dummy instruction insertion with cheriot_enable_i
asserted: CHERI work gives the same results and takes no trap
(doc/03_reference/security.rst). Depends on the RTL accepting cpuctrlsts in CHERIoT
mode (GAP-CS-3).

- cheriot_dummy_instr: CHERI work (derivation, CGet*, CSC/CLC round trip, CSEQX;
  every result checked) with cheriot_enable_i asserted, once with
  cpuctrlsts.data_ind_timing set and once with dummy instruction insertion on: no
  result may change and nothing may trap (Ibex doc/03_reference/security.rst). Code
  92 (a trap in the dummy-instruction pass) is the suspected RTL finding in the test
  header: dummy instructions naming x16-x31 are illegal in CHERIoT mode. Cosim off
  (Spike: +disable_cosim; CHERIoT-Sail runs only with +enable_cheriot_seq, not with
  the pin raised mid-test). Returns 0 on success; codes in the test header.

#### `port_toggle`

Tests:
- `ibex_boot_addr`
- `ibex_mhartid`
- `ibex_mhartid_ones`


ibex_top port toggle coverage for hart_id_i and boot_addr_i

The configuration inputs hart_id_i and boot_addr_i: mhartid reads hart_id_i (0 and
all-ones) and cannot be written; mtvec holds the boot address when the core boots.
The testbench drives both ports' complement while rst_n is low, so their toggle
coverage measures the ports (boot_addr_i[7:0] waived: 256-byte aligned).

- ibex_boot_addr: mtvec reads {boot address[31:8], 8'h01} when the core boots, before
  software writes it (doc/03_reference/exception_interrupts.rst: the vector table
  base is initialised to the boot address). The reset PC is already checked by every
  test through the cosim. Also the guard for the testbench driving boot_addr_i's
  complement during reset only. Returns 0 on success; codes in the test header.
- ibex_mhartid: mhartid reads the value on hart_id_i (0 here, the testbench default)
  and a csrw to it raises an illegal-instruction exception and leaves it unchanged
  (RISC-V Privileged ISA, read-only CSRs). Returns 0 on success; codes in the test
  header.
- ibex_mhartid_ones: As ibex_mhartid with hart_id_i = 0xFFFFFFFF (+hart_id). The
  testbench drives the complement while rst_n is low, so this run toggles every
  hart_id_i bit 0->1 and the default runs toggle it 1->0. Cosim off: Spike's mhartid
  is always 0, so the test's own checks are the only ones on the value. gcc_opts
  repeats the riscv-tests config's flags (a test-level gcc_opts replaces them).
  Returns 0 on success; codes in the test header.

#### `rv32_decode_corners`

Tests:
- `cov_expr_rv_misc`
- `ibex_decode_holes`


packu/packh, reserved OP-IMM encodings and HPM counter writes

Decode corners the random tests do not reach: packu and packh results (draft 0.93
Zbp); reserved OP-IMM encodings (unary group rs2 = 15, srli/srai with shamt[5] = 1)
raise an illegal-instruction exception with mtval = the instruction and leave rd
unwritten; every mhpmcounter low half is writable and the unavailable ones read 0.
rori and bexti with shamt[5] = 1 likewise, without stalling ID as a multi-cycle ALU
operation (cov_expr_rv_misc).

- cov_expr_rv_misc: rori and bexti with shamt 33 (instr[25] = 1, reserved on RV32)
  raise an illegal instruction exception with mtval = the instruction and leave rd
  unwritten. Targets the rori/bexti legality term of ibex_decoder.sv (OP-IMM funct3
  101). Spike cosim on. TEST_FAIL code in gp.
- ibex_decode_holes: packu and packh (draft 0.93 XZbp; riscv-dv emits neither, see
  vendor patch 0007) give {rs2[31:16], rs1[31:16]} and {16'b0, rs2[7:0], rs1[7:0]};
  the OP-IMM unary group with rs2 = 15 and srli/srai with shamt[5] = 1 raise an
  illegal-instruction exception with mtval = the instruction and leave rd unwritten;
  every mhpmcounter3..31 low half is written, and mhpmcounter13..31 (unavailable with
  MHPMCounterNum = 10) read 0 after a write of all-ones. Returns 0 on success; codes
  in the test header.

#### `trap_timing_hazards`

Tests:
- `cov_fcov2_cheri_hazard`
- `cov_fcov2_rv_hazard`


Debug requests, NMIs and fetch drops timed to a data access's grant

Debug requests, NMIs and fetch-enable drops placed in an exact cycle of the
instruction behind a data access rather than at random: the bench acts on the
access's grant (+gnt_trig_lo/hi) and the program chooses the data-side response delay
per section (+mem_mode_on_write), with a masked timer interrupt pending. RISC-V mode
(cov_fcov2_rv_hazard): a debug request rising in the single ID cycle of a Mul or
Load; ebreak, ecall and a fetch error unstalling with a debug request pending;
ebreak, an illegal and a CSR-illegal instruction behind a faulting access at every
response timing, interrupt and debug combination; an NMI pending while ebreak, wfi, a
fetch error or a dcsr read waits behind a faulting access, taken right after its
flush; and IF empty and idle behind c.ebreak, c.unimp and a CSR-illegal instruction
for each writeback state. CHERIoT mode (cov_fcov2_cheri_hazard): a CHERI instruction
independent of, or reading, a load's result, behind an access that completes or gets
a bus error, at each response timing, with and without the interrupt and a debug
request. Self-checking (trap, NMI and debug-entry counts, causes, NMI mepc); the
bench fails the test if a configured trigger never fires. Spike cosim on in RISC-V
mode; cosim off in CHERIoT mode (CHERIoT-Sail has no debug mode and no bus errors).

- cov_fcov2_cheri_hazard: CHERIoT mode (pin raised by +cheriot_enable_on_write): a
  CHERI instruction (CIncAddrImm independent of the access, CIncAddr reading the
  loaded register) behind a data access, with debug_req raised from the access's
  grant (+gnt_trig), data-side responses immediate or 4..12 cycles late
  (+mem_mode_on_write), the timer interrupt pending and masked or not, and the access
  completing or getting a bus error; plus a doorbell debug request landing in a sled
  of CIncAddrImm. Targets the InstrCategoryCheri bins of uarch_cg
  exception_stall_instr_cross (None / Mem / LdHz, unstalled, irq, debug, with and
  without the bus error) and debug_entry_if_instr_cross. Self-checking (trap and
  debug-entry counts, causes), cosim off (CHERIoT-Sail has no debug mode and no bus
  errors). Exit code in a0 (test header).
- cov_fcov2_rv_hazard: RISC-V mode: debug requests, NMIs and fetch-enable drops
  placed in an exact cycle of the instruction behind a data access (grant-timed,
  +gnt_trig), with the data-side response delay chosen per section
  (+mem_mode_on_write) and a masked pending timer interrupt. Mul and Load sleds and
  accesses with debug_req rising in the next instruction's only ID cycle; ebreak,
  ecall and a fetch error unstalling with debug_req pending; ebreak into debug mode,
  an uncompressed illegal and a CSR-illegal instruction behind a faulting access at
  every response timing, irq and debug combination; an NMI pending while ebreak
  (ebreakm), wfi, a fetch error or a dcsr read waits behind a faulting access (taken
  right after its FLUSH); IF empty and idle behind c.ebreak, c.unimp and a CSR-
  illegal instruction for each WB state. Targets uarch_cg
  exception_stall_instr_cross, interrupt_taken_instr_cross and pipe_cross. Self-
  checking (trap, NMI and debug-entry counts, causes, NMI mepc; codes in the header),
  Spike cosim on.

#### `debug_module`

Tests:
- `dm_basic`
- `dm_basic_cheriot`


The real debug module driven over DMI, RISC-V and CHERIoT mode

The real RISC-V debug module (vendor/pulp_riscv_dbg dm_top with the CHERIoT patches)
behind the core's instruction and data buses, driven over its DMI port: dmstatus,
hartinfo and abstractcs reset values; halt, cross-checked against the core's debug
mode; dcsr and dpc; GPR reads and writes by abstract command, with s0 and a0, which
every command borrows, restored; the program buffer; a mailbox write; resume. RISC-V
mode (dm_basic): a 64-bit access is refused (cmderr 2) and a read of an unimplemented
CSR reports the debug-mode exception (cmderr 3). CHERIoT mode (dm_basic_cheriot):
64-bit capability register reads match the program's own stored images, DEPCC is read
through the SCR path, a 64-bit write puts an untagged capability in a4, x16 faults
(cmderr 3), and s0/a0 keep their tags (REQ_DBG_05). Needs the DM=1 testbench build,
which ties the core's debug addresses to the DM ROM and takes debug_req_i from
dm_top; skipped by all_directed without it. Self-checking, cosim off (+cosim_off=1:
no model has the debug module's ROM).

- dm_basic: Real debug module, RISC-V mode. The program fills registers and spins;
  over DMI the test activates the DM, halts the hart, reads GPRs (x8-x15, x16, x31)
  and dcsr/dpc with abstract commands, checks that a 64-bit access is refused (cmderr
  2) and that an abstract read of an unimplemented CSR reports the debug-mode
  exception (cmderr 3), runs a program buffer (addi a1; ebreak), writes x20 and the
  mailbox a2, and resumes. The program then checks the written registers and that
  s0/a0, which every abstract command borrows, were restored. Self-checking, cosim
  off. Returns 0 on success; codes in the test header.
- dm_basic_cheriot: Real debug module, CHERIoT mode (cheriot_enable_i asserted from
  reset, so the DM selects its CHERIoT debug ROM and CSpecialRW scratch handling). As
  dm_basic, plus 64-bit abstract register reads of capability registers (s0, s1, a0,
  a5: address in data0, metadata in data1, checked against the program's own csc
  images; the tag from the testbench's view of the core's store to data0) and of
  DEPCC through the SCR path, a 64-bit write of an untagged capability to a4, and an
  abstract read of x16 that must fault (no x16 in CHERIoT mode, cmderr 3). After
  resume the program checks that s0/a0 kept their tags (DScratchC0/1) and the
  capability written to a4. Self-checking, cosim off. Returns 0 on success; codes in
  the test header.

### Stage V2S Testpoints

#### `rdv_integrity_countermeasures`

Tests:
- `riscv_icache_intg_test`
- `riscv_mem_intg_error_test`
- `riscv_pc_intg_test`
- `riscv_ram_intg_test`
- `riscv_rf_addr_intg_test`
- `riscv_rf_intg_test`


Integrity-error countermeasures

Security countermeasures: integrity errors on memory responses, the PC, the register
file (data and address) and the RAMs/icache are detected and raise the right alert.

- riscv_icache_intg_test: Randomly corrupt the instruction cache once in the middle
  of program execution
- riscv_mem_intg_error_test: Normal random instruction test, but randomly insert
  memory load/store integrity errors
- riscv_pc_intg_test: Randomly corrupt the PC of the core once in the middle of
  program execution
- riscv_ram_intg_test: Randomly corrupt one of the RAM MUBI values in the middle of
  program execution
- riscv_rf_addr_intg_test: Randomly corrupt one of the register file addresses in the
  middle of program execution
- riscv_rf_intg_test: Randomly corrupt the register file read port once in the middle
  of program execution

#### `integrity_directed`

Test: `cov_expr_intg_err`

Directed bus integrity errors: internal NMI and fetch faults

Bus integrity errors injected by address (+dside_intg_err_lo/hi,
+iside_intg_err_lo/hi): a load with bad integrity raises the internal NMI (mcause
0xFFFFFFE0, mtval its address, rd unwritten); a second one raised inside the NMI
handler stays pending while nmi_mode blocks it and is taken right after the handler's
mret; the instructions after the first load each execute once. Zcmp encodings fetched
with bad integrity raise an instruction access fault and change nothing. A bus alert
per integrity error and no other alert (core_ibex_cheriot_mem_err_test). Self-
checking (cov_expr_intg_err).

- cov_expr_intg_err: A load with bad integrity raises the internal NMI (mcause
  0xFFFFFFE0, mtval its address, rd unwritten); the NMI handler loads it again, so a
  second internal NMI is pending while nmi_mode blocks it, and it is taken right
  after the handler's mret (same mepc); the instructions after the first load each
  execute once. Then four Zcmp encodings (cm.push rlist 4, cm.pop rlist 4 and 5,
  cm.mvsa01) fetched with bad integrity each raise an instruction access fault at
  their address and change nothing. Integrity errors are injected by address
  (+dside/iside_intg_err_lo/hi). Targets ibex_core.sv RVFI rvfi_ext_stage_nmi_int
  (irq_nm_int pending without a capture) and ibex_compressed_decoder.sv CmIdle
  `valid_i && id_in_ready_i` with valid_i = 0. core_ibex_cheriot_mem_err_test (mode-
  agnostic) requires a bus alert per integrity error and no other alert. Cosim off;
  TEST_FAIL code in gp.

## Covergroups

### cheri_access_bounds_cg

Data accesses within 10 bytes of capability bounds

Every CHERIoT-mode data access, sampled once in its first execute cycle from the
signals the core's bounds check uses (base32, top33, the access address and size):
plain loads and stores through a capability, and CLC/CSC, which are always 8 bytes.
Debug mode and the unchecked second half of a misaligned access are not sampled.

- cp_acc_type: 8 access types, load/store x byte/half/word/cap
- cp_acc_base_dist: access start minus base, one bin per byte from -10 to +10
- cp_acc_top_dist: access end minus top, one bin per byte from -10 to +10; using the
  end covers accesses that straddle top (a word at top-2 lands at +2)
- cp_acc_perm_ok: whether the access has the permission it needs, Load or Store
- cp_acc_auth: whether the authorising capability is untagged, sealed or valid
- cp_acc_bounds: whether the access starts below base, lies inside, or ends above top
- acc_base_edge_cross (168 bins): access type x distance from base
- acc_top_edge_cross (168 bins): access type x distance from top
- acc_fault_priority_cross (144 bins): access type x authority x permission x bounds

The priority cross covers accesses where several checks fail at once: which cause the
core reports then is where a core and its model most often disagree, and the cosim
compares the trap cause. Unreachable bins (for example a CLC/CSC address that is not
8-byte aligned) are ignored, each with its reason.

Source: fcov/core_ibex_fcov_if.sv. 9 coverpoints and crosses, sampled in the main
core only (the lockstep shadow core is excluded).

Built by default: cp_acc_type, cp_acc_base_dist, cp_acc_top_dist, cp_acc_perm_ok,
cp_acc_auth, cp_acc_bounds, acc_base_edge_cross, acc_top_edge_cross,
acc_fault_priority_cross.

### cheri_illegal_insn_cg

Illegal instructions by encoding class, CHERIoT mode and pin Off

Illegal-instruction exceptions by encoding class (CHERI opcode, LOAD, STORE,
JALR/BRANCH, MISC-MEM, SYSTEM, CSR, OP/OP-IMM, other opcodes, 16-bit, x16-x31),
separately in CHERIoT mode and with the pin Off; in CHERIoT mode mtval must be 0
(illegal_bins), as CHERIoT-Sail's handle_illegal gives with the C platform's
settings.

From the verification spec (Functional Coverage):

- cp_ill_class_cheriot, cp_ill_class_pin_off, cp_ill_mtval_cheriot: Illegal-
  instruction exceptions by encoding class (CHERI opcode, LOAD, STORE, JALR/BRANCH,
  MISC-MEM, SYSTEM, CSR, OP/OP-IMM, other opcodes, 16-bit, x16–x31; with the pin Off,
  the CHERIoT-only classes); in CHERIoT mode mtval must be 0 (illegal bin otherwise)
  [REQ_ISA_11, REQ_ISA_12, REQ_IFE_02]

Source: fcov/core_ibex_fcov_if.sv. 3 coverpoints and crosses, sampled in the main
core only (the lockstep shadow core is excluded).

Built by default: cp_ill_class_cheriot, cp_ill_class_pin_off, cp_ill_mtval_cheriot.

### cheri_interrupt_cheri_cg

Interrupts taken during CHERIoT instructions

From the verification spec (Functional Coverage):

- cp_csc_atomic_interrupt: Interrupt is pending during a CSC bus transaction; the CSC
  either completes both beats before the interrupt is taken, or is fully rolled back
  — no partial-store architectural state observed

Source: fcov/core_ibex_fcov_if.sv. 1 coverpoints and crosses, sampled in the main
core only (the lockstep shadow core is excluded).

Built by default: cp_csc_atomic_interrupt.

### cheri_mshwm_cg

Stack high water mark CSR access, legalisation and store updates

mshwm (0xBC1) and mshwmb (0xBC2), CHERIoT ISA section 'Stack high water mark' and
CHERIoT-Sail (legalize_mshwm, ext_check_phys_mem_write, ext_check_CSR).

- hwm_access_cross: CSR x read/write x PCC.SR in CHERIoT mode (without SR: capcause
  0x18)
- cp_hwm_pin_off: the CSRs read and written with cheriot_enable_i Off (illegal
  instruction)
- cp_hwm_legalise: writes with bits [3:0] zero and nonzero, per CSR
- cp_hwm_store_pos x cp_hwm_store_kind / cp_hwm_store_err / cp_hwm_store_set: each
  store kind below, inside and above the window and with an empty window; faulting
  stores; whether the core updated mshwm
- cp_hwm_split: the second half of a misaligned store, which the ISA does not count

From the verification spec (Functional Coverage):

- cp_hwm_csr, cp_hwm_csr_wr, cp_hwm_sr, hwm_store_kind_cross, hwm_store_err_cross,
  hwm_store_set_cross: mshwm/mshwmb read and write with and without PCC.SR and with
  the pin Off; aligned and rounded writes; each store kind below, inside and above
  the window and with an empty window; faulting stores; the core's update decision;
  the second half of a misaligned store [REQ_SCR_09]

Source: fcov/core_ibex_fcov_if.sv. 14 coverpoints and crosses, sampled in the main
core only (the lockstep shadow core is excluded).

Built by default: cp_hwm_csr, cp_hwm_csr_wr, cp_hwm_sr, hwm_access_cross,
cp_hwm_pin_off, cp_hwm_legalise, cp_hwm_store_pos, cp_hwm_store_kind,
cp_hwm_store_err, cp_hwm_store_set, hwm_store_kind_cross, hwm_store_err_cross,
hwm_store_set_cross, cp_hwm_split.

### cheri_representability_cg

Address changes within 10 bytes of the representable window

CSetAddr, CIncAddr, CIncAddrImm, AUIPCC and AUICGP on a tagged capability, sampled in
the execute cycle: the new address (result_data_o) against the input capability --
rf_fullcap_a (cs1, or c3 for AUICGP) or PCC (pcc_cap_i) for AUIPCC. The window edges
are the RTL's rule in ibex_cheriot_pkg::cheriot_set_address: the address is
representable in [base, base + 2^(9+E)), or anywhere when E = 24. The older
cheriot_uarch_cg crosses cheriot_cauipcc_cross and cheriot_cauicgp_cross also cross
both instructions with the below/above-window cases (cp_cheri_cd_pcc_repr_cases,
cp_cheri_cd_cs1_repr_cases).

- cp_rep_op: CSetAddr, CIncAddr, CIncAddrImm, AUIPCC or AUICGP
- cp_rep_eclass: exponent class, E = 0, 1-7, 8-14 or 24 (whole address space)
- cp_rep_lo_dist: new address minus base, one bin per byte from -10 to +10
- cp_rep_hi_dist: new address minus the window's top, one bin per byte from -10 to
  +10; not sampled at E = 24, which has no upper edge
- cp_rep_lo_edge, cp_rep_hi_edge: the tag outcome exactly at each edge, both outcomes
  binned (below/base, last/past x cleared/kept)
- cp_rep_sealed_out: the outcome for a sealed input, which must always lose its tag
- rep_lo_edge_cross (84 bins): exponent class x lower-edge distance
- rep_hi_edge_cross (63 bins): exponent class x upper-edge distance, E = 24 ignored
- rep_op_eclass_cross (20 bins): instruction x exponent class
- cp_rep_outside, rep_op_outside_cross: every instruction with its new address inside
  and outside the window -- the representability-failure case
- cp_rep_edge_hit, rep_op_edge_cross: every instruction exactly at each edge (-1, -2,
  base; -1, -2, one past the top); AUIPCC's odd distances are ignored, since its PC
  is 2-aligned, the offset a multiple of 2048 and a PCC window above 2048 bytes needs
  an 8-aligned base
- cp_rep_auipcc_edge: AUIPCC's tag outcome at the even edge distances
- cp_rep_auicgp_sealed_out: AUICGP through a sealed c3 (must clear the tag)

There are deliberately no illegal_bins. The window formula is the RTL's
implementation, while CHERIoT-Sail defines representability as the bounds decoding
the same with the new address; illegal bins built on the RTL's formula would miss
exactly a disagreement between the two. The group records which edges were reached;
whether each outcome is right is the cosim's and TestRIG's call against Sail, so a
below_kept or past_kept hit is checked there.

Source: fcov/core_ibex_fcov_if.sv. 16 coverpoints and crosses, sampled in the main
core only (the lockstep shadow core is excluded).

Built by default: cp_rep_op, cp_rep_eclass, cp_rep_lo_dist, cp_rep_hi_dist,
cp_rep_lo_edge, cp_rep_hi_edge, cp_rep_sealed_out, cp_rep_auicgp_sealed_out,
cp_rep_outside, cp_rep_edge_hit, cp_rep_auipcc_edge, rep_lo_edge_cross,
rep_hi_edge_cross, rep_op_eclass_cross, rep_op_outside_cross, rep_op_edge_cross.

### cheri_spatial_gap_cg

Accesses just outside a capability's bounds

From the verification spec (Functional Coverage):

- cp_compressed_pcc_top_cross: A fetch bounds violation on a compressed (16-bit)
  instruction (`instr_rdata_i[1:0] != 2'b11`), i.e. one whose own two bytes are not
  inside PCC bounds. It does not cover the 32-bit instruction whose second half-word
  crosses PCC.Top; that needs its own coverpoint

Source: fcov/core_ibex_fcov_if.sv. 1 coverpoints and crosses, sampled in the main
core only (the lockstep shadow core is excluded).

Built by default: cp_compressed_pcc_top_cross.

### cheri_zero_len_perm_cg

Zero-length and zero-permission capability operands

Tagged operands with length 0 (top = base) or permissions 0, by the instruction class
that uses them, and CSetBounds* with length 0 at an address inside the bounds, at the
top (the end of an object, still in bounds) and outside.

From the verification spec (Functional Coverage):

- cp_zl_cs1_use, cp_zp_cs1_use, cp_zl_cs2_seal, cp_zp_cs2_seal, cp_zl_setbounds:
  Zero-length and zero-permission operands by the instruction class that uses them
  (load, store, CLC, CSC, CJALR, CSetBounds*, address ops, CSeal, CUnseal, CGet*,
  CAndPerm) and as sealing authorities; CSetBounds* of length 0 with the address
  inside, at the top, or outside [REQ_BND_11, REQ_PER_09]

Source: fcov/core_ibex_fcov_if.sv. 5 coverpoints and crosses, sampled in the main
core only (the lockstep shadow core is excluded).

Built by default: cp_zl_cs1_use, cp_zp_cs1_use, cp_zl_cs2_seal, cp_zp_cs2_seal,
cp_zl_setbounds.

### cheriot_cfi_detail_cg

CHERIoT control-flow integrity detail

From the verification spec (Functional Coverage):

- cp_pcc_bounds_squash: `cheriot_cfi_detail_cg`

Source: fcov/core_ibex_fcov_if.sv. 1 coverpoints and crosses, sampled in the main
core only (the lockstep shadow core is excluded).

Built by default: cp_pcc_bounds_squash.

### cheriot_obi_backpressure_cg

CHERIoT memory accesses under bus back-pressure

From the verification spec (Functional Coverage):

- cp_lsu_fsm: LSU state: `IDLE`, `CTX_WAIT_GNT1`, `CTX_WAIT_GNT2`, `CTX_WAIT_RESP`,
  and the RV32-only misaligned states folded into one bin [REQ_CSC_01, REQ_INT_06]
- cp_obi_handshake: `{1'b0, data_req_o, data_gnt_i}`: quiet, grant-without-request,
  **backpressured**, accepted. Grant-without-request is an ignore_bins in CHERIoT
  configurations: `ibex_core`'s `data_gnt_i` is TRVK's `stream_fork` `ready_o`, which
  is 0 whenever `valid_i` (`data_req_o`) is 0 (`ibex_trvk.sv`, `stream_fork.sv`); in
  RV32I configurations `ibex_top` ties `trvk_gnt = data_gnt_i` and the bin is covered
  through `+dmem_gnt_when_idle_pct` [REQ_CSC_01]
- cp_is_cap: Whether the access is a capability access, distinguishing a stalled
  `CLC`/`CSC` from a stalled integer access in the same state [REQ_CSC_01]
- cheriot_obi_stall_cross: The three crossed: backpressure at each stage of a
  capability transaction — first beat issued from `IDLE`, `CTX_WAIT_GNT1`,
  `CTX_WAIT_GNT2`, `CTX_WAIT_RESP`; `resp_stalled` is CTX_WAIT_RESP with req low.
  Illegal: req low in CTX_WAIT_GNT1/GNT2, req high in CTX_WAIT_RESP, an integer
  access in any CTX state (REQ_BCK_06 hold, `ibex_core.sv` `cheriot_enable_ex`)
  [REQ_CSC_01, REQ_INT_06, REQ_BCK_06]

Not described in the verification spec: cp_lsu_ctx_abort, cp_cheriot_disable_err.

Source: fcov/core_ibex_fcov_if.sv. 6 coverpoints and crosses, sampled in the main
core only (the lockstep shadow core is excluded).

Built by default: cp_lsu_fsm, cp_lsu_ctx_abort, cp_cheriot_disable_err,
cp_obi_handshake, cp_is_cap, cheriot_obi_stall_cross.

### cheriot_uarch_cg

CHERIoT instructions, capability operands and their results

From the verification spec (Functional Coverage):

- cp_cheri_rs1_regaddr, cp_cheri_rs2_regaddr, cp_cheri_rd_regaddr: Register file
  address for each source/destination — covers x0–x15. The coverpoints are gated on
  CHERIoT mode, where x16–x31 are illegal (RV32E), so `bin16to31` is an ignore bin:
  only an instruction the decoder rejects as illegal presents those addresses
  [REQ_TAG_05]
- cp_cheri_rs2_as_inc: CIncAddr increment: −large, −small, 0, +small, +large
  [REQ_BND_04, REQ_CPR_04]
- cp_cheri_instr_set: One bin per CHERIoT instruction (CAUICGP, CAUIPCC, CINC_ADDR,
  CINC_ADDR_IMM, CSET_ADDR, CSET_BOUNDS, CSET_BOUNDS_EX, CSET_BOUNDS_IMM,
  CSET_BOUNDS_RNDN, CRRL, CRAM, CCLEAR_TAG, CMOVE_CAP, CSEAL, CUNSEAL, CAND_PERM,
  CSUB_CAP, CIS_SUBSET, CIS_EQUAL, CSET_HIGH, CGET_PERM, CGET_TYPE, CGET_BASE,
  CGET_TOP, CGET_LEN, CGET_TAG, CGET_ADDR, CGET_HIGH, CLOAD_CAP, CSTORE_CAP, CCSR_RW,
  CJAL, CJALR). Note: `CGET_HIGH`, `CSET_HIGH`, and `CAUICGP` are present in this bin
  but do not have dedicated REQ_ entries — they are covered under the general
  bounds/permissions/monotonicity requirements. [All REQ_TAG, REQ_BND, REQ_PER,
  REQ_MON, REQ_SEL]
- cp_cheri_cget_field, cp_cheri_imm20, cp_cheri_imm12, cp_cheri_rs1_bitsize:
  Immediate ranges, operand bit-width, and the CGetField selector [REQ_ISA]
- cp_cheri_pcc_tag: PCC tag (should always be 1; coverage confirms no unexpected
  clearing) [REQ_BND_03]
- cp_cheri_pcc_exp, cp_cheri_pcc_perm_ex: PCC exponent and execute permission
  [REQ_PCC]
- cp_cheri_pcc_perm_asr: PCC Permit_Access_System_Registers bit [REQ_PER_06]
- cp_cheri_cs1_tag: Source CS1 valid/invalid tag [REQ_TAG_04, REQ_TAG_07]
- cp_cheri_cs1_exp: CS1 CHERI Concentrate exponent E: 0 (small cap), 1–13 (mid), 14
  (null/max) [REQ_BND_04–06, REQ_CPR]
- cp_cheri_cs1_otype: CS1 3-bit otype field, one bin per value: 0 unsealed; with EX,
  1–5 sentries (inheriting, fwd-ID, fwd-IE, bwd-ID, bwd-IE) and 6–7 sealed non-
  sentries; without EX, 1–7 encode data otypes 9–15 [REQ_SEL_01–09]
- cp_cheri_cs1_sealed: CS1 otype ≠ 0 (sealed in any form) [REQ_SEL_01]
- cp_cheri_cs1_sealed_tagged_cross, cp_cs2_sealed_tagged_cross: Tag × sealed state of
  CS1 and of CS2, including a sealed operand that is untagged [REQ_SEL_01]
- cp_cheri_cs1_cor: CS1 bound corrections from cap_cor: top 0 / +1 with base 0, top 0
  / -1 with base -1 (the 4 reachable values) [REQ_CPR_01]
- cp_cheri_cs1_top, cp_cheri_cs1_base, cp_cheri_cs2_exp, cp_cheri_cs2_cor,
  cp_cheri_cs2_top, cp_cheri_cs2_base, cp_cheri_cs2_address: Source-operand bounds,
  cursor, exponent and correction fields [REQ_BND, REQ_CPR]
- cp_cheri_cs1_perms: CS1 permission bits — individual bins for EX, LD, ST, LC, SC,
  GL combinations [REQ_PER_01–07]
- cp_cheri_cs1_perms_load: CS1 permission bits gated on load instructions
  [REQ_PER_01, REQ_PER_04]
- cp_cheri_cs1_perms_store: CS1 permission bits gated on store instructions
  [REQ_PER_02, REQ_PER_05]
- cp_cheri_cs1_perm_ex: CS1 Permit_Execute bit isolated [REQ_PER_03]
- cp_cheri_cs1_perm_gl: CS1 Global bit isolated [REQ_LOC_01]
- cp_cheri_cs1_address: CS1 address: 0, small, mid, near-max [REQ_BND_04, REQ_CPR]
- cp_cheri_cs1_base32: CS1 decoded base: 0, small (1–0xFFF), mid, near-max
  [REQ_BND_01, REQ_BND_08]
- cp_cheri_cs1_top33: CS1 decoded top (33-bit): 0, small, mid, at-4GB [REQ_BND_02,
  REQ_BND_08]
- cp_cheri_cs2_tag: Source CS2 valid/invalid tag [REQ_SEL_02–04]
- cp_cheri_cs2_otype: CS2 otype: same bins as CS1 [REQ_SEL_04]
- cp_cheri_cs2_sealed: CS2 otype ≠ 0 [REQ_SEL_02]
- cp_cheri_cs2_perms, cp_cheri_cs2_perm_se, cp_cheri_cs2_perm_us: CS2 permission
  field, and the seal/unseal permissions individually [REQ_PER, REQ_SEL]
- cp_cheri_cs2_perm_gl: CS2 Global permission bit [REQ_LOC_01]
- cp_cheri_cs2_seal_type: CS2 address (`rf_rdata_b`), which `CSeal` uses as the new
  otype: 0–7 one bin each (1–7 legal for an executable cs1), 8–15 one bin each (9–15
  legal for a data cs1), ≥16 (never legal) [REQ_SEL_02]
- cp_cheri_rs2_perm_mask: CAndPerm mask (rs2[11:0]): all-zero, all-one, clear-EX,
  clear-GL, random [REQ_MON_02, REQ_PER_07]
- cp_cheri_cd_tag: Destination tag after instruction: 0 (cleared), 1 (preserved)
  [REQ_TAG_01, REQ_MON_03]
- cp_cheri_cd_exp: Destination exponent — must track source or be updated correctly
  by CSetBounds [REQ_CPR_02]
- cp_cheri_cd_otype: Destination otype after instruction [REQ_SEL_02–04, REQ_SEL_06]
- cp_cheri_cd_cor: Destination correction bits [REQ_CPR_01]
- cp_cheri_cd_top: Destination top in bins [REQ_BND_02]
- cp_cheri_cd_base: Destination base in bins: 0, small, mid, near-max [REQ_BND_01]
- cp_cheri_cd_cperms: Destination compressed permissions word [REQ_MON_02,
  REQ_PER_07]
- cp_cheri_cd_address: Destination address [REQ_BND_04]
- cp_cheri_vio, cp_cheri_vio_slc, cp_cheri_fetch_tag_vio, cp_cheri_fetch_bound_vio:
  Capability violations: general, store-local, and the two fetch-side violations
  [REQ_EXC, REQ_PCC]
- cp_cheri_tag_clear_cs1cd: Tag cleared on the CS1→CD path [REQ_TAG, REQ_MON]
- cp_cheri_wb_exception_causes: capcause of a CHERI exception raised in writeback
  (non-memory CHERI instructions): 0x02 Tag, 0x03 Seal, 0x11 Permit_Execute, 0x18
  Permit_Access_System_Registers, plus no-exception; any other value is an illegal
  bin. Memory-access causes (0x01, 0x02, 0x03, 0x12, 0x13, 0x15) are in
  `cp_cheri_clsc_exception_causes`. Together they cover all eight codes CHERIoT-Sail
  raises [REQ_EXC_01–05]
- cp_cheri_clsc_exception_causes, cp_cheri_rv32lsu_exception_causes,
  cp_cheri_exception_reg_id: Exception causes on the capability and RV32 load/store
  paths, and the reported capability register index [REQ_EXC]
- cp_cheri_scr_addr: CSpecialRW SCR field: MTCC, MTDC, MEPCC, MScratchC,
  MScratchCModM [REQ_SCR_01–04]
- cp_cheri_scr_read_only, cp_cheri_scr_write, cp_cheri_mshwm_set,
  cp_cheri_illegal_mret: SCR writes, read-only SCR access, illegal MRET, and MSHWM
  update [REQ_SCR, REQ_EXC]
- cp_cheri_cpu_lsu_req, cp_cheri_cpu_lsu_err: LSU request and error signalling for
  capability accesses [REQ_EXC, REQ_CSC]
- cheriot_fetch_cross: PCC tag violation × PCC bounds violation at instruction fetch
  [REQ_BND_03, REQ_CFI_05]
- cp_cheri_fetch_bound_mepcc_clrtag: Trap entry for a fetch violation: a PCC bounds
  violation clears the saved MEPCC's tag; a PCC tag, permission or seal violation,
  which takes priority, does not [REQ_BND_03, REQ_BND_07, REQ_CFI_05]
- cp_cheri_rd_a_hz, cp_cheri_rd_b_hz: Register-file read hazard (load-use) on RS1/RS2
  ports; gated by `WritebackStage`. In `cheriot_uarch_cg`, independent of any stall
  signal [REQ_TMP_01]
- cp_cheri_clc_clrperm: What CLC strips from the loaded capability: nothing; GL and
  LG (the authority lacks LG); SD and LM (it lacks LM); both; the tag, which always
  comes with both (an authority without MC has no LM or LG, `cheriot_expand_perms`).
  The tag without both is an illegal bin. [REQ_TAG_03]
- cp_clc_csc_bounds_roundtrip, cp_clc_csc_perm_roundtrip, cp_clc_csc_otype_roundtrip,
  cp_clc_csc_tag_roundtrip: Capabilities returned by CLC: tagged and untagged; for
  tagged ones, the exponent (0, 1–13, 14, 24), the permission class (sealing,
  execute, data, mutable load) both local and global, and the object type (unsealed,
  each sentry type, each data-sealed type) [REQ_TAG_03]
- cp_cheri_mtcc_legalization_addr, cp_cheri_mtcc_legalization_perm,
  cp_cheri_mtcc_legalization_sealed, cp_cheri_mepcc_legalization_addr,
  cp_cheri_mepcc_legalization_perm, cp_cheri_mepcc_legalization_sealed: MTCC and
  MEPCC legalisation on write and on trap entry/return, by address, permission and
  sealed state [REQ_SCR, REQ_PCC]
- cp_cheri_cd_cs1_repr_cases: CIncAddr/CSetAddr/CAUICGP result representability: in-
  window, outside-window, exact-boundary [REQ_BND_04, REQ_CPR_03–04]
- cp_cheri_cd_pcc_repr_cases: AUIPCC result representability vs PCC window
  [REQ_BND_03]
- cp_cheri_cjal_bound: CJAL target vs PCC bounds, from bounded PCCs and from E = 24
  PCCs [REQ_BND_03, REQ_BRA_08]
- cp_cheri_cjalr_bound, cheriot_cjalr_cross0, cheriot_cjalr_cross1: CJALR: cs1 tag ×
  otype × rd (c0, c1–c14, c15) × mstatus.MIE × imm12 class; cs1 tag × Permit_Execute
  × target vs cs1 bounds (below/at base, inside, top−1…7, at/above top, base 0, top
  2^32) × imm12 class [REQ_CFI_01–03, REQ_SEL_05–08, REQ_INT_07]
- cp_cheri_branch_bound: RV32 branch/jump target vs PCC bounds [REQ_BND_03,
  REQ_CFI_02]
- cp_cheri_clsc_bound: Load/store address (`cheriot_ls_chkaddr`) vs CS1 bounds: base,
  top, range and room conditions, including the end-of-capability room check
  [REQ_BND_01–02]
- cp_cheri_seal_bound: CSeal sealing-type address vs sealing-cap bounds [REQ_SEL_02]
- cp_cheri_clsc_addr_lsb: CLC/CSC address alignment: naturally aligned vs misaligned
  [REQ_BND_02]
- cp_cheri_setbounds_cases, cp_cheri_setboundsimm_cases: CSetBounds and CSetBoundsImm
  outcome: exact fit, rounds-up, requested-length > current-length (clears tag)
  [REQ_BND_05–06, REQ_CPR_01–02]
- cp_cheri_rs2_req_len: CSetBounds requested length: 0, exact-power-2, imprecise, max
  [REQ_BND_05–06, REQ_CPR_02]
- cp_cheri_mstatus_mie: Machine interrupt enable at time of CJALR/CJAL instruction
  [REQ_INT_07, REQ_SEL_07]
- cp_instr_cauicgp, cp_instr_cauipcc, cp_instr_cincaddrimm, cp_instr_cincaddr,
  cp_instr_csetaddr, cp_instr_csub: Per-instruction execution: cursor arithmetic
  [REQ_MON, REQ_CPR]
- cp_instr_candperm, cp_instr_ccleartag, cp_instr_cmove, cp_instr_csethigh,
  cp_instr_cget_field: Per-instruction execution: permission masking, tag clearing,
  copy, field reads, high-half write [REQ_PER, REQ_TAG, REQ_MON]
- cp_instr_cseqx, cp_instr_ctestsubset: Per-instruction execution: capability
  comparison and subset test [REQ_PER, REQ_BND]
- cp_instr_cspecialrw: Per-instruction execution: SCR read/write [REQ_SCR]
- cp_instr_cjal, cp_instr_cjalr, cp_instr_branch: Per-instruction execution:
  capability jumps and RV32 branches [REQ_CFI, REQ_BRA]
- cp_instr_clc, cp_instr_csc: Per-instruction execution: capability load and store
  [REQ_TAG, REQ_CSC]
- cp_instr_cseal, cp_instr_cunseal: Per-instruction execution: seal and unseal
  [REQ_SEL]
- cp_instr_csetbounds, cp_instr_csetboundsexact, cp_instr_csetboundsimm,
  cp_instr_csetboundsrndn, cp_instr_cram, cp_instr_crrl: Per-instruction execution:
  the four bounds-setting forms and the two representability queries [REQ_BND,
  REQ_CPR]
- cheriot_cauicgp_cross, cheriot_cauipcc_cross, cheriot_cincaddrimm_cross,
  cheriot_cincaddr_cross, cheriot_csetaddr_cross: Address operations: cs1 (or c3, or
  PCC) tag, seal and exponent class × increment / imm12 / imm20 class × new address
  inside, below or above the source's representable window [REQ_BND_04, REQ_BND_10,
  REQ_CPR_04]
- cheriot_candperm_cross: CAndPerm: CS1 tag × sealed × CS1 permissions × class of the
  rs2 mask [REQ_MON_02, REQ_PER_09]
- cheriot_ccleartag_cross, cheriot_cmove_cross: CClearTag and CMove: CS1 tag × sealed
  [REQ_TAG_08, REQ_LOC_02]
- cheriot_cseqx_cross0, cheriot_ctestsubset_cross0: CSEQX / CTestSubset: cs1 tag ×
  cs1 otype × cs2 tag × cs2 otype [REQ_MON_04–05]
- cheriot_cseqx_cross1, cheriot_cseqx_cross2, cheriot_cseqx_cross3: CSEQX: CS1 and
  CS2 permissions × representability corrections; CS1 and CS2 top × base; CS1 address
  × CS2 address [REQ_MON_05]
- cheriot_ctestsubset_cross1, cheriot_ctestsubset_cross2: CTestSubset: CS1 and CS2
  permissions × representability corrections; CS1 and CS2 top × base [REQ_MON_04]
- cheriot_csub_cross: CSub: CS1 tag × address × CS2 tag × address [REQ_BND_09]
- cheriot_csethigh_cross0: CSetHigh: cd otype × cd compressed permissions (cd is
  never tagged) [REQ_TAG_09]
- cheriot_csethigh_cross1: CSetHigh: the result's correction × exponent × top × base
  × address [REQ_TAG_09]
- cheriot_cget_field_cross: CGet*: cs1 tag × number of zero bits in cs1.address
  (0–32) × field selector [REQ_ISA, REQ_PER_08]
- cheriot_cspecialrw_cross: CSpecialRW: SCR 28–31 / undefined × cs1 index class × cd
  index class × PCC.SR [REQ_SCR_01–08, REQ_PER_06]
- cp_cheri_cspecialrw_mode, cheriot_cspecialrw_mode_cross: CSpecialRW read-write,
  read-only (cs1 = c0), write-only (cd = c0) and no-op, per defined SCR [REQ_SCR_08]
- cheriot_csethigh_src_cross: CSetHigh from tagged/untagged × sealed/unsealed sources
  [REQ_TAG_09]
- cheriot_cjal_cross: CJAL: rd × target against PCC bounds × imm20 class ×
  mstatus.MIE [REQ_BRA_08, REQ_CFI_05]
- cheriot_clc_cross0, cheriot_csc_cross0: CSC / CLC: cs1 tag × seal × store (SD, SL,
  MC) or load (LD, LM, LG, MC) permissions × cs2 GL (CSC) [REQ_PER_01–05,
  REQ_LOC_01–02]
- cheriot_clc_cross1, cheriot_csc_cross1: CLC and CSC: CS1 tag × address against CS1
  bounds × imm12 class × address low bits [REQ_BND_01, REQ_CSC_01]
- cheriot_cseal_cross0, cheriot_cseal_cross1, cheriot_cunseal_cross0: CSeal: cs1
  Permit_Execute × cs2 tag × cs2 Permit_Seal × cs2.address (otype 0–15, ≥ 16) ×
  cs2.address vs cs2 bounds; tag and seal state of both operands. CUnseal: cs1 tag,
  seal, GL × cs2 tag, seal, Permit_Unseal, GL [REQ_SEL_02–04, REQ_LOC_01]
- cheriot_cunseal_cross1: CUnseal: CS1 otype × CS1 Permit_Execute × CS2 tag × CS2
  sealing-type class × CS2 address against its bounds [REQ_SEL_04]
- cheriot_csetbounds_cross0, cheriot_csetboundsexact_cross,
  cheriot_csetboundsimm_cross: CSetBounds, CSetBoundsExact and CSetBoundsImm: CS1 tag
  × sealed × requested-length case × CS1 base × top × exponent × CD tag. For
  CSetBounds, untagged sources are ignored, and so are the odd (inexact) cases except
  at E = 24 [REQ_MON_01, REQ_BND_11]
- cheriot_csetbounds_cross1: CSetBounds: cs1 tag × cursor vs bounds and req_len ≤
  length (`cp_cheri_setbounds_cases`) × req_len 0–8 / larger × cs1 exponent class ×
  cd tag [REQ_BND_05–06, REQ_MON_01, REQ_MON_03]
- cheriot_csetboundsrndn_cross, cheriot_cram_cross, cheriot_crrl_cross: rs1 tag ×
  bit-size of rs1 (0–32) [REQ_MON_06, REQ_BND_05]
- cheriot_jump_exception_cross, cheriot_scr_exception_cross: CHERIoT exception cause
  in writeback × CJALR, where causes 0, 1 and 0x18 cannot come from a CJALR (illegal
  bins); and the system-register-permission cause 0x18 × CSpecialRW [REQ_PER_03,
  REQ_PER_06]
- cheriot_cs1cd_tag_cross: CS1 tag × CD tag for every CGet* field read: the integer
  result is untagged whatever the source [REQ_ISA_06, REQ_TAG_06]
- instr_error_sequence_cross0, instr_error_sequence_cross1: Back-to-back faults: the
  ID and WB instruction categories × an interrupt being handled × an error in ID and
  in WB; and the category and exception/interrupt state of two consecutive ID-stage
  instructions [REQ_EXC_01, REQ_INT_08]
- rs_rd_cross: CS1 × CS2 × CD register address, so every source/destination aliasing
  combination (rd = rs1, rd = rs2, rs1 = rs2) is seen [REQ_ISA_06, REQ_TAG_05]
- cheriot_pcc2cd_tag_cross: PCC tag × CD tag for AUIPCC, CJAL and CJALR, the
  instructions whose result derives from PCC. An untagged PCC giving a tagged result,
  or a tagged PCC giving an untagged CJAL/CJALR link, is an illegal bin [REQ_SEL_05,
  REQ_CFI_02]
- cheriot_instr_branch_cross: A taken branch × its target against PCC bounds
  [REQ_BRA_08, REQ_BND_03]
- cp_exc_cap_idx, cp_exc_scr_flag, cp_mepcc_trap_save, cp_mepcc_mret_restore,
  cp_cjalr_unsealed, cp_cjalr_sentry_mie, cp_cs1_cursor_rel_bounds,
  cp_cs2_cursor_rel_bounds, cp_cs1_otype_sentry_detail, cp_cs2_otype_sentry_detail,
  cp_csc_alignment: `cheriot_uarch_cg`
- cp_int_store_tag_clear: An integer store completes, which clears the tag of the
  granule it writes [REQ_TAG_02]
- cp_arith_tag_clear: A non-CHERIoT instruction writes a register from a tagged and
  from an untagged source; the result is untagged either way [REQ_TAG_06]
- cp_cmove_full_copy: CMove of a tagged and of an untagged source; the result is the
  unmodified source [REQ_TAG_08]
- cp_ctestsubset_result, cp_cisequal_result: CTestSubset and CSEQX each return 0 and
  1 [REQ_MON_04, REQ_MON_05]
- cp_crrl_rounding: CRRL returns the requested length unchanged, and rounded up
  [REQ_MON_06]
- cp_non_monotone_tag_clear: A CHERIoT instruction other than CClearTag and CAndPerm
  turns a tagged source into an untagged result: CIncAddr/CSetAddr outside the
  representable range, an inexact CSetBoundsExact [REQ_MON_03]
- cp_cs1_cperms, cp_cs2_cperms: All 64 compressed permission encodings on each
  operand and on the result [REQ_LOC_01, REQ_PER_07]

Source: fcov/core_ibex_fcov_if.sv. 191 coverpoints and crosses, sampled in the main
core only (the lockstep shadow core is excluded).

Built by default: cp_cheri_rs1_regaddr, cp_cheri_rs2_regaddr, cp_cheri_rd_regaddr,
cp_cheri_rs2_as_inc, cp_cheri_instr_set, cp_cheri_cget_field, cp_cheri_pcc_tag,
cp_cheri_pcc_exp, cp_cheri_pcc_perm_asr, cp_cheri_pcc_perm_ex, cp_cheri_imm20,
cp_cheri_imm12, cp_cheri_cs1_tag, cp_cheri_cs1_exp, cp_cheri_cs1_otype,
cp_cheri_cs1_sealed, cp_cheri_cs1_sealed_tagged_cross, cp_cheri_cs1_cor,
cp_cheri_cs1_top, cp_cheri_cs1_base, cp_cheri_cs1_perms, cp_cheri_cs1_perms_load,
cp_cheri_cs1_perms_store, cp_cheri_cs1_perm_ex, cp_cheri_cs1_perm_gl,
cp_cheri_cs1_address, cp_cheri_cs1_base32, cp_cheri_cs1_top33, cp_cheri_cs2_tag,
cp_cheri_cs2_exp, cp_cheri_cs2_otype, cp_cheri_cs2_sealed, cp_cheri_cs2_cor,
cp_cheri_cs2_top, cp_cheri_cs2_base, cp_cheri_cs2_perms, cp_cheri_cs2_perm_gl,
cp_cheri_cs2_perm_se, cp_cheri_cs2_perm_us, cp_cheri_cs2_address,
cp_cheri_cs2_seal_type, cp_cheri_rs2_perm_mask, cp_cheri_cd_tag, cp_cheri_cd_exp,
cp_cheri_cd_otype, cp_cheri_cd_cor, cp_cheri_cd_top, cp_cheri_cd_base,
cp_cheri_cd_cperms, cp_cheri_cd_address, cp_cheri_vio, cp_cheri_vio_slc,
cp_cheri_tag_clear_cs1cd, cp_cheri_wb_exception_causes,
cp_cheri_clsc_exception_causes, cp_cheri_rv32lsu_exception_causes,
cp_cheri_exception_reg_id, cp_cheri_scr_addr, cp_cheri_scr_read_only,
cp_cheri_scr_write, cp_cheri_cpu_lsu_req, cp_cheri_cpu_lsu_err, cp_cheri_mshwm_set,
cp_cheri_fetch_tag_vio, cp_cheri_fetch_bound_vio, cheriot_fetch_cross,
cp_cheri_fetch_bound_mepcc_clrtag, cp_cheri_rd_a_hz, cp_cheri_rd_b_hz,
cp_cheri_clc_clrperm, cp_clc_csc_bounds_roundtrip, cp_clc_csc_perm_roundtrip,
cp_clc_csc_otype_roundtrip, cp_cheri_mtcc_legalization_addr,
cp_cheri_mtcc_legalization_perm, cp_cheri_mtcc_legalization_sealed,
cp_cheri_mepcc_legalization_addr, cp_cheri_mepcc_legalization_perm,
cp_cheri_mepcc_legalization_sealed, cp_cheri_illegal_mret,
cp_cheri_cd_cs1_repr_cases, cp_cheri_cd_pcc_repr_cases, cp_cheri_cjal_bound,
cp_cheri_cjalr_bound, cp_cheri_branch_bound, cp_cheri_clsc_bound,
cp_cheri_seal_bound, cp_cheri_clsc_addr_lsb, cp_cheri_setbounds_cases,
cp_cheri_setboundsimm_cases, cp_cheri_rs2_req_len, cp_cheri_rs1_bitsize,
cp_cheri_mstatus_mie, cp_instr_cauicgp, cp_instr_cauipcc, cp_instr_cincaddrimm,
cp_instr_cincaddr, cp_instr_csetaddr, cp_instr_candperm, cp_instr_ccleartag,
cp_instr_cmove, cp_instr_cseqx, cp_instr_ctestsubset, cp_instr_csub,
cp_instr_csethigh, cp_instr_cget_field, cp_instr_cspecialrw, cp_instr_cjal,
cp_instr_cjalr, cp_instr_clc, cp_instr_csc, cp_instr_cseal, cp_instr_cunseal,
cp_instr_csetbounds, cp_instr_csetboundsexact, cp_instr_csetboundsimm,
cp_instr_csetboundsrndn, cp_instr_cram, cp_instr_crrl, cheriot_cauicgp_cross,
cheriot_cauipcc_cross, cheriot_cincaddrimm_cross, cheriot_cincaddr_cross,
cheriot_csetaddr_cross, cheriot_ccleartag_cross, cheriot_cmove_cross,
cheriot_cseqx_cross0, cheriot_cseqx_cross2, cheriot_ctestsubset_cross0,
cheriot_ctestsubset_cross2, cheriot_csethigh_cross0, cheriot_cget_field_cross,
cheriot_cspecialrw_cross, cp_cheri_cspecialrw_mode, cheriot_cspecialrw_mode_cross,
cheriot_csethigh_src_cross, cheriot_cjalr_cross0, cheriot_cjalr_cross1,
cheriot_clc_cross0, cheriot_csc_cross0, cheriot_cseal_cross0, cheriot_cseal_cross1,
cheriot_cunseal_cross0, cheriot_csetbounds_cross1, cheriot_csetboundsrndn_cross,
cheriot_cram_cross, cheriot_crrl_cross, cheriot_jump_exception_cross,
cheriot_scr_exception_cross, cheriot_cs1cd_tag_cross, cp_cs2_sealed_tagged_cross,
rs_rd_cross, cheriot_pcc2cd_tag_cross, cp_instr_branch, cheriot_instr_branch_cross,
cp_exc_cap_idx, cp_exc_scr_flag, cp_mepcc_trap_save, cp_mepcc_mret_restore,
cp_clc_csc_tag_roundtrip, cp_int_store_tag_clear, cp_arith_tag_clear,
cp_cmove_full_copy, cp_ctestsubset_result, cp_cisequal_result, cp_crrl_rounding,
cp_cjalr_unsealed, cp_cjalr_sentry_mie, cp_non_monotone_tag_clear,
cp_cs1_cursor_rel_bounds, cp_cs2_cursor_rel_bounds, cp_cs1_otype_sentry_detail,
cp_cs2_otype_sentry_detail, cp_cs1_cperms, cp_cs2_cperms, cp_csc_alignment.

Compiled out unless CHERIOT_FCOV_LARGE_CROSSES is defined (make ...
FCOV_LARGE_CROSSES=1): cheriot_candperm_cross, cheriot_cseqx_cross1,
cheriot_cseqx_cross3, cheriot_ctestsubset_cross1, cheriot_csub_cross,
cheriot_csethigh_cross1, cheriot_cjal_cross, cheriot_clc_cross1, cheriot_csc_cross1,
cheriot_cunseal_cross1, cheriot_csetbounds_cross0, cheriot_csetboundsexact_cross,
cheriot_csetboundsimm_cross, instr_error_sequence_cross0,
instr_error_sequence_cross1.

### pmp_region_cg

PMP per-region configuration and access outcome

From the verification spec (Functional Coverage):

- cp_napot_addr_modes, cp_warl_check_pmpcfg, cp_region_mode, cp_region_priv_bits:
  Region matching mode, per-region permission bits, NAPOT address forms, and WARL
  behaviour of `pmpcfg` [REQ_ISA_05]
- cp_priv_lvl_iside, cp_priv_lvl_iside2, cp_priv_lvl_dside: Privilege level on each
  access channel and in the ID/LSU stages [REQ_ISA_05, REQ_ISA_08]
- cp_req_type_iside, cp_req_type_iside2, cp_req_type_dside: Request type per channel,
  and load/store PMP exceptions [REQ_LOC, REQ_EXC]
- pmp_iside_mode_cross, pmp_iside2_mode_cross, pmp_dside_mode_cross: Per region, for
  the accesses it matches: its matching mode (TOR, NA4, NAPOT) × whether the fetch
  (first and second half) or the data access was denied. A matching region in mode
  OFF is an illegal bin [REQ_ISA_05]
- pmp_iside_priv_bits_cross, pmp_iside2_priv_bits_cross, pmp_dside_priv_bits_cross:
  Per region, for the highest-priority region an access matches (mode not OFF, not a
  debug-module access): its permission bits × the access type × privilege level ×
  denied or allowed, for the fetch (both halves) and the data side. An access allowed
  against permission bits that forbid it is an illegal bin [REQ_ISA_05]
- cp_edit_locked_pmpcfg, cp_edit_locked_pmpaddr: A write to the `pmpcfg` and to the
  `pmpaddr` of a locked region while `mseccfg.RLB` is set, which allows editing
  locked entries [REQ_ISA_05]
- pmp_wr_exec_region: With `mseccfg.MML` set, a write to a region's `pmpcfg` that
  would make it executable: its current × written permission bits × RLB (only MML
  encodings sampled) [REQ_ISA_05]

Source: fcov/core_ibex_pmp_fcov_if.sv. 19 coverpoints and crosses, sampled in the
main core only (the lockstep shadow core is excluded).

Built by default: cp_napot_addr_modes, cp_warl_check_pmpcfg, cp_region_mode,
cp_region_priv_bits, cp_priv_lvl_iside, cp_req_type_iside, cp_priv_lvl_iside2,
cp_req_type_iside2, cp_priv_lvl_dside, cp_req_type_dside, pmp_iside_mode_cross,
pmp_iside2_mode_cross, pmp_dside_mode_cross, pmp_iside_priv_bits_cross,
pmp_iside2_priv_bits_cross, pmp_dside_priv_bits_cross, cp_edit_locked_pmpcfg,
cp_edit_locked_pmpaddr, pmp_wr_exec_region.

### pmp_top_cg

PMP/ePMP global state: mseccfg, privilege and access type

From the verification spec (Functional Coverage):

- cp_rlb, cp_mmwp, cp_mml, cp_wdata_rlb, cp_wdata_mmwp, cp_wdata_mml: `mseccfg` MML /
  MMWP / RLB, both current value and value being written [REQ_ISA_05]
- cp_priv_lvl_iside, cp_priv_lvl_iside2, cp_priv_lvl_dside: Privilege level on each
  access channel and in the ID/LSU stages [REQ_ISA_05, REQ_ISA_08]
- cp_req_type_iside, cp_req_type_iside2, cp_req_type_dside, cp_ls_pmp_exception:
  Request type per channel, and load/store PMP exceptions [REQ_LOC, REQ_EXC]
- rlb_csr_cross, mmwp_csr_cross, mml_sticky_cross: `mseccfg` writes: current ×
  written RLB, MMWP and MML, including the writes that must be ignored (setting RLB
  while it is clear and a region is locked; clearing MMWP or MML once set)
  [REQ_ISA_05]
- pmp_iside_nomatch_cross, pmp_iside2_nomatch_cross, pmp_dside_nomatch_cross: An
  access that matches no region: access type × privilege level × denied or allowed ×
  MMWP × MML. Allowing a U-mode access, or an M-mode access with MMWP or MML set, is
  an illegal bin [REQ_ISA_05]
- cp_pmp_iside_region_override, cp_pmp_iside2_region_override,
  cp_pmp_dside_region_override: An access that fails one matching region's check but
  is allowed because a higher-priority region matches it first, on each channel
  [REQ_ISA_05]
- cp_mprv: CSR writes, read-only CSR access, `mstatus.MPRV`, and the previous ID-
  stage instruction category [REQ_ISA_02, REQ_ISA_05]
- mprv_effect_cross: Loads and stores with mstatus.MPRV set: MPP × current privilege
  × denied at the current privilege × denied at the effective one (MPP equal to the
  current privilege is ignored) [REQ_ISA_05]
- pmp_instr_edge_cross, misaligned_lsu_access_cross: A PMP region boundary crossed by
  a fetch (first half, second half or both denied; never the second half of a
  compressed fetch, illegal bin) and by a misaligned load or store (first and second
  half denied) [REQ_ISA_05]
- dm_fetch_iside_debug_mode_cp, dm_fetch_iside2_debug_mode_cp,
  dm_load_store_debug_mode_cp, dm_fetch_access_iside_cross,
  dm_fetch_access_iside2_cross, dm_load_store_access_cross: Fetches and loads/stores
  to the debug module in debug mode, each under a PMP configuration that would allow
  and one that would deny them; a debug-mode access to the debug module that faults
  is an illegal bin (outside debug mode such accesses are ignored). The data-side
  cross uses the request's own PMP result (`pmp_dside_req_err`). [REQ_DBG_05,
  REQ_ISA_05]

Source: fcov/core_ibex_pmp_fcov_if.sv. 32 coverpoints and crosses, sampled in the
main core only (the lockstep shadow core is excluded).

Built by default: cp_rlb, cp_mmwp, cp_mml, cp_wdata_rlb, cp_wdata_mmwp, cp_wdata_mml,
cp_priv_lvl_iside, cp_req_type_iside, cp_priv_lvl_iside2, cp_req_type_iside2,
cp_priv_lvl_dside, cp_req_type_dside, rlb_csr_cross, mmwp_csr_cross,
mml_sticky_cross, pmp_iside_nomatch_cross, pmp_iside2_nomatch_cross,
pmp_dside_nomatch_cross, cp_pmp_iside_region_override, cp_pmp_iside2_region_override,
cp_pmp_dside_region_override, cp_mprv, mprv_effect_cross, pmp_instr_edge_cross,
misaligned_lsu_access_cross, dm_fetch_iside_debug_mode_cp,
dm_fetch_iside2_debug_mode_cp, dm_load_store_debug_mode_cp, cp_ls_pmp_exception,
dm_fetch_access_iside_cross, dm_fetch_access_iside2_cross,
dm_load_store_access_cross.

### trvk_cg

Load-barrier revocation check (ibex_trvk)

From the verification spec (Functional Coverage):

- cp_trvk_revoked: The revocation verdict, sampled on a valid bitmap response
  [REQ_TMP_01]
- cp_trvk_revoked_by_bitmap: Revoked via the bitmap bit — the functional path
  [REQ_TMP_01]
- cp_trvk_revbm_err, cp_trvk_intg_error: The two error paths into the same verdict
  [REQ_TMP_01]
- cp_trvk_bit_select: Bit position within the bitmap word; exercises the bit-select
  decode [REQ_TMP_01]
- cp_trvk_out_of_range: Capability base outside the bitmap range, so revocation is
  skipped [REQ_TMP_01]
- cp_trvk_sealing_cap: Sealing capabilities are exempt from revocation [REQ_TMP_01,
  REQ_SEL]
- cp_trvk_req_required, cp_trvk_misalign: Lookup required, and the second-word
  condition that triggers it [REQ_TMP_01]
- cp_trvk_revbm_handshake, cp_trvk_outstanding: Bitmap port handshake, including
  backpressure, and lookup serialisation [REQ_TMP_01]
- cp_trvk_upstream_tag: Tag presented to the core — the observable effect of the
  block [REQ_TMP_01, REQ_TAG]
- trvk_revoked_outstanding_cross: Revocation verdict × another lookup outstanding: a
  revocation that arrives while the next lookup is already in flight [REQ_TMP_01]

Described in the verification spec, section 'TRVK Revocation Coverage':
trvk_revoked_source_cross, trvk_sealing_cross.

Source: fcov/core_ibex_trvk_fcov_if.sv. 15 coverpoints and crosses, sampled in the
main core only (the lockstep shadow core is excluded).

Built by default: cp_trvk_revoked, cp_trvk_revoked_by_bitmap, cp_trvk_revbm_err,
cp_trvk_intg_error, cp_trvk_bit_select, cp_trvk_out_of_range, cp_trvk_sealing_cap,
cp_trvk_req_required, cp_trvk_misalign, cp_trvk_revbm_handshake, cp_trvk_outstanding,
cp_trvk_upstream_tag, trvk_revoked_source_cross, trvk_revoked_outstanding_cross,
trvk_sealing_cross.

### uarch_cg

Ibex microarchitecture: instruction categories, stalls, hazards and pipeline state

From the verification spec (Functional Coverage):

- cp_id_instr_category: Instruction category (ALU, mul, div, load, store, branch,
  CHERI, CSR, etc.) in the ID stage — confirms CHERIoT instructions are decoded into
  the correct pipeline category [REQ_TAG, REQ_BND]
- cp_id_instr_category_last, cp_mprv, cp_csr_read_only, cp_csr_write: CSR writes,
  read-only CSR access, `mstatus.MPRV`, and the previous ID-stage instruction
  category [REQ_ISA_02, REQ_ISA_05]
- cp_stall_type_id: Stall reason in ID stage: no stall, instr stall, CHERI stall, mem
  stall, TBRE stall [All pipeline reqs]
- cp_wb_reg_no_load_hz: Writeback-stage register hazard without load: confirming
  hazard forwarding [REQ_ISA_01]
- cp_mem_raw_hz: Memory read-after-write hazard [REQ_ISA_01]
- cp_ls_error_exception: Load/store bus-error exception during CHERI and non-CHERI
  operations [REQ_IBX_INT_01]
- cp_ls_pmp_exception: Request type per channel, and load/store PMP exceptions
  [REQ_LOC, REQ_EXC]
- cp_branch_taken, cp_branch_not_taken: Static prediction taken/not-taken for each
  branch type [REQ_BRA_02]
- cp_priv_mode_id, cp_priv_mode_lsu: Privilege level on each access channel and in
  the ID/LSU stages [REQ_ISA_05, REQ_ISA_08]
- cp_if_stage_state, cp_id_stage_state, cp_wb_stage_state: Stage
  valid/stalled/flushed states: all three stages in all states [REQ_ISA_01]
- cp_data_ind_timing, cp_data_ind_timing_instr: Data-independent timing mode, and
  instructions executed under it [REQ_IBX]
- cp_dummy_instr_en, cp_dummy_instr_mask, cp_dummy_instr_type, cp_dummy_instr,
  cp_dummy_instr_if_stage, cp_dummy_instr_id_stage, cp_dummy_instr_wb_stage: Dummy-
  instruction insertion: enable, type, mask, and presence in each stage [REQ_IBX]
- cp_rf_a_ecc_err, cp_rf_b_ecc_err, cp_rf_glitch_err: Each SecureIbex register-file
  countermeasure fires: an ECC error on read port A, on read port B, and a register-
  file glitch detection [— (no requirement covers register-file integrity)]
- cp_icache_ecc_err: An ICache ECC error is reported by the instruction fetch [— (no
  requirement covers ICache integrity)]
- cp_mem_load_ecc_err, cp_mem_store_ecc_err: A load response and a store response
  with a data-bus integrity error [REQ_IBX_INT_05 (load); — for the store]
- cp_lockstep_err, cp_pc_mismatch_err: The lockstep comparison detects a glitch, and
  the IF stage's PC-mismatch alert fires [— (no requirement covers the lockstep or
  PC-integrity countermeasures)]
- cp_fetch_enable, cp_pipe_flush, cp_controller_fsm, cp_controller_fsm_sleep:
  Controller FSM states including sleep, pipeline flush, and fetch enable [REQ_ISA]
- cp_mret_in_umode, cp_wfi_in_umode: `mret` and `wfi` decoded in U-mode, where both
  are illegal (the instruction category alone records them only as illegal)
  [REQ_ISA_08]
- cp_warl_check_mstatus, cp_warl_check_mie, cp_warl_check_mtvec, cp_warl_check_mepc,
  cp_warl_check_mtval, cp_warl_check_dcsr, cp_warl_check_cpuctrl: A CSR write whose
  value the WARL CSR legalises: the value stored differs from the value written, for
  mstatus, mie, mtvec, mepc, mtval, dcsr and cpuctrlsts [REQ_ISA_02]
- cp_double_fault: The `cpuctrlsts` double-fault-seen bit is set: a synchronous
  exception taken while the previous one's handler had not cleared the exception-seen
  state [— (no requirement covers double-fault detection)]
- cp_icache_enable: The `cpuctrlsts` ICache-enable bit is set [REQ_CAC_01]
- cp_irq_pending, cp_misaligned_first_data_bus_err,
  cp_misaligned_second_data_bus_err: Pending interrupts, and bus errors on each half
  of a misaligned access [REQ_INT, REQ_EXC]
- cp_debug_req, cp_debug_mode, cp_all_debug_req, cp_debug_entry_if,
  cp_single_step_instr: Debug mode, debug requests, entry from IF, and single-step
  [REQ_DBG]
- cp_csr_invalid_read_only, cp_csr_invalid_write: A CSR read and a CSR write that
  raise an illegal-CSR exception [REQ_ISA_02]
- cp_debug_wakeup, cp_debug_entry_id, cp_insn_trigger_enter_debug: Debug mode entered
  by waking from sleep, entered from the ID stage, and entered through an
  instruction-address trigger match [REQ_DBG_01]
- cp_single_step_taken, cp_single_step_exception: A single step completes, and a
  single-stepped instruction takes an exception (the step ends with the pipeline
  flush of the trap) [REQ_DBG_02]
- cp_nmi_taken: NMI assertion during CHERI instruction execution [REQ_INT_05]
- cp_interrupt_taken: Interrupt taken per source (IRQ0–31, NMI): confirms CHERI
  exception priority [REQ_INT_01–04]
- cp_irq_continue_sleep: The core stays in WFI sleep with an interrupt pending
  because that interrupt is disabled in `mie` [REQ_ISA_04]
- cp_imem_response_latency, cp_dmem_response_latency: Memory response in 1-cycle vs
  multi-cycle: confirms pipeline correctly handles backpressure [REQ_IBX_INT_01]
- cp_imem_req_gnt_rvalid, cp_dmem_req_gnt_rvalid: On the instruction and on the data
  bus, a new request is granted in the same cycle as the previous one's response
  arrives (back-to-back pipelining) [REQ_IBX_INT_01]
- cp_fetch_fifo_bypass: Fetch FIFO empty, so the instruction handed to IF comes
  straight from the bus response rather than a FIFO entry [REQ_BRA_03, REQ_IFE_05]
- cp_fetch_fifo_clear_while_full: An IF redirect clears the fetch FIFO while all
  three entries are occupied; every entry is invalidated in one cycle [REQ_BRA_07,
  REQ_IFE_04, REQ_IFE_06]
- cp_fetch_push_during_pop: A fetch response is pushed in the cycle entry 0 is
  popped, at a fill level of one and of two entries (an empty FIFO is the bypass; a
  full one cannot push) [REQ_IFE_05]
- cp_fetch_unaligned_compressed: A 16-bit instruction at PC[1] = 1, taken from the
  upper half of FIFO entry 0 or, with the FIFO empty, of the incoming bus word;
  includes the CHERIoT case where it is forced because less than 4 bytes of PCC
  remain [REQ_BRA_03, REQ_IFE_02]
- cp_fetch_unaligned_uncompressed: A 32-bit instruction at PC[1] = 1 straddling a
  word boundary, its upper half from FIFO entry 1 or from the incoming bus word
  [REQ_IFE_03]
- cp_if_stall_with_branch: A branch or jump redirect while a valid instruction waits
  in IF and must be discarded, both with ID stalled (the FIFO clear discards it) and
  with ID ready [REQ_BRA_01, REQ_BRA_07, REQ_IFE_04]
- misaligned_data_bus_err_cross, misaligned_insn_bus_err_cross: Bus error on the
  first half, the second half and both halves of a misaligned data access; fetch
  error on the first and on the second half of an instruction [REQ_ISA_03]
- irq_wfi_cross, debug_wfi_cross: Wake from each WFI sleep state by a pending
  interrupt, with mstatus.MIE set and clear (MIE must not change whether the core
  wakes), and by each kind of debug request [REQ_ISA_04, REQ_DBG_01]
- priv_mode_instr_cross, priv_mode_exception_cross: Every instruction category in
  each privilege mode (U-mode MRET is an illegal bin; CHERIoT-mode categories in
  U-mode are ignored, CHERIoT mode being M-only; a U-mode CSR access is a bin to
  cover, legal for the `mcounteren`-enabled counters); privilege mode × PMP and bus-
  error load/store exceptions (both at once is an illegal bin) [REQ_ISA_08,
  REQ_ISA_03]
- priv_mode_irq_cross: Privilege mode × interrupt taken × MIE [REQ_INT_02–03]
- stall_cross: Instruction category × stall type: every category must stall in each
  relevant way [REQ_ISA_01]
- wb_reg_no_load_hz_instr_cross, pipe_cross: Instruction category × a writeback-stage
  register hazard not from a load (only categories that read registers; others are
  illegal bins); instruction category × IF, ID and WB stage states (an empty ID stage
  only with no instruction) [REQ_ISA_01]
- interrupt_taken_instr_cross, debug_instruction_cross, debug_entry_if_instr_cross,
  pipe_flush_instr_cross: The instruction in ID, and whether it had just unstalled,
  when an interrupt or NMI is taken, when debug mode is entered from IF, and when the
  pipeline is flushed; every instruction category in and out of debug mode
  [REQ_INT_08, REQ_IBX_INT_03, REQ_DBG_01]
- exception_stall_instr_cross: Load/store PMP and bus-error exceptions × instruction
  category × ID stall type × unstalled × interrupt pending × debug request, with the
  stall/category combinations the pipeline cannot produce as illegal bins
  [REQ_ISA_01, REQ_ISA_03]
- csr_read_only_priv_cross, csr_write_priv_cross, csr_read_only_debug_cross,
  csr_write_debug_cross: Every CSR read and written in each privilege mode; the debug
  CSRs read and written in and out of debug mode [REQ_ISA_02, REQ_DBG_01]
- dummy_instr_config_cross, debug_req_dummy_instr_if_stage_cross,
  debug_req_dummy_instr_id_stage_cross, debug_req_dummy_instr_wb_stage_cross,
  irq_pending_dummy_instr_if_stage_cross, irq_pending_dummy_instr_id_stage_cross,
  irq_pending_dummy_instr_wb_stage_cross: Dummy-instruction insertion (SecureIbex):
  every dummy type × frequency setting while enabled; a debug request and a pending
  interrupt while a dummy instruction is in IF, in ID and in WB [— (no requirement
  covers dummy-instruction insertion)]
- rf_ecc_err_cross: Register-file ECC error on read port A, port B and both, for a
  valid instruction in ID [— (no requirement covers register-file integrity)]

Source: fcov/core_ibex_fcov_if.sv. 104 coverpoints and crosses, sampled in the main
core only (the lockstep shadow core is excluded).

Built by default: cp_id_instr_category, cp_id_instr_category_last, cp_stall_type_id,
cp_wb_reg_no_load_hz, cp_mem_raw_hz, cp_mprv, cp_ls_error_exception,
cp_ls_pmp_exception, cp_branch_taken, cp_branch_not_taken, cp_priv_mode_id,
cp_priv_mode_lsu, cp_if_stage_state, cp_id_stage_state, cp_wb_stage_state,
cp_data_ind_timing, cp_data_ind_timing_instr, cp_dummy_instr_en, cp_dummy_instr_mask,
cp_dummy_instr_type, cp_dummy_instr, cp_dummy_instr_if_stage,
cp_dummy_instr_id_stage, cp_dummy_instr_wb_stage, cp_rf_a_ecc_err, cp_rf_b_ecc_err,
cp_icache_ecc_err, cp_mem_load_ecc_err, cp_mem_store_ecc_err, cp_lockstep_err,
cp_rf_glitch_err, cp_pc_mismatch_err, cp_fetch_enable, cp_mret_in_umode,
cp_wfi_in_umode, cp_warl_check_mstatus, cp_warl_check_mie, cp_warl_check_mtvec,
cp_warl_check_mepc, cp_warl_check_mtval, cp_warl_check_dcsr, cp_warl_check_cpuctrl,
cp_double_fault, cp_icache_enable, cp_irq_pending, cp_debug_req, cp_csr_read_only,
cp_csr_write, cp_csr_invalid_read_only, cp_csr_invalid_write, cp_debug_mode,
cp_debug_wakeup, cp_all_debug_req, cp_debug_entry_if, cp_debug_entry_id,
cp_pipe_flush, cp_single_step_taken, cp_single_step_exception,
cp_insn_trigger_enter_debug, cp_nmi_taken, cp_interrupt_taken, cp_controller_fsm,
cp_controller_fsm_sleep, cp_irq_continue_sleep, cp_single_step_instr,
cp_misaligned_first_data_bus_err, cp_misaligned_second_data_bus_err,
cp_imem_response_latency, cp_imem_req_gnt_rvalid, cp_fetch_fifo_bypass,
cp_fetch_fifo_clear_while_full, cp_fetch_push_during_pop,
cp_fetch_unaligned_compressed, cp_fetch_unaligned_uncompressed,
cp_if_stall_with_branch, cp_dmem_response_latency, cp_dmem_req_gnt_rvalid,
misaligned_data_bus_err_cross, misaligned_insn_bus_err_cross, irq_wfi_cross,
debug_wfi_cross, priv_mode_instr_cross, priv_mode_irq_cross,
priv_mode_exception_cross, stall_cross, wb_reg_no_load_hz_instr_cross, pipe_cross,
interrupt_taken_instr_cross, debug_instruction_cross, debug_entry_if_instr_cross,
pipe_flush_instr_cross, exception_stall_instr_cross, csr_read_only_priv_cross,
csr_write_priv_cross, csr_read_only_debug_cross, csr_write_debug_cross,
dummy_instr_config_cross, rf_ecc_err_cross, debug_req_dummy_instr_if_stage_cross,
debug_req_dummy_instr_id_stage_cross, debug_req_dummy_instr_wb_stage_cross,
irq_pending_dummy_instr_if_stage_cross, irq_pending_dummy_instr_id_stage_cross,
irq_pending_dummy_instr_wb_stage_cross.


