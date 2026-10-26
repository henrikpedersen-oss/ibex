// Copyright lowRISC contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0
//
// What the checking stack needs to know about the SoC it checks. Everything SoC-specific lives
// here, filled by the SoC's environment (Earl Grey 2: chip_env from chip_env_cfg; the CHERIoT RTOS
// test SoC: its testbench), so the stack itself is the same for every SoC.

// The words of a line, split at spaces.
function automatic void soc_split(string line, ref string words[$]);
  int start = -1;
  words.delete();
  for (int i = 0; i <= line.len(); i++) begin
    bit space = (i == line.len()) || line[i] inside {" ", "\t", "\n", "\r"};
    if (!space && start < 0) start = i;
    if (space && start >= 0) begin
      words.push_back(line.substr(start, i - 1));
      start = -1;
    end
  end
endfunction

class soc_cosim_cfg extends uvm_object;
  // How the reference model starts:
  //   SocStartRiscv:  Spike from reset, in RISC-V mode; at the store to `lock_addr` that switches
  //                   the core to CHERIoT mode, the state passes from Spike to CHERIoT-Sail (Earl
  //                   Grey 2, REQ_SOC_07).
  //   SocStartCheriot: CHERIoT-Sail from reset (a core that is CHERIoT from reset: the RTOS SoC).
  typedef enum int {SocStartRiscv, SocStartCheriot} start_e;
  start_e      start_mode = SocStartRiscv;

  // The ELF images the core runs, loaded into the ISS at every reset (at their load addresses).
  string       images[$];
  // SocStartRiscv: the store that locks CHERIoT mode, and the memories CHERIoT-Sail takes over from
  // Spike at that point.
  bit [31:0]   lock_addr;
  bit [31:0]   mem_base[$];
  bit [31:0]   mem_size[$];
  // The SoC's revocation, for CHERIoT-Sail's load barrier: the revocable heap
  // [rev_heap_base, rev_heap_base + rev_heap_size) and its bitmap at rev_bits_base (one bit per
  // 8-byte granule, as the TRVK reads it). rev_bits_base 0: CHERIoT-Sail's own default layout.
  bit [31:0]   rev_heap_base, rev_heap_size, rev_bits_base;
  // Non-empty: the reference model is off for this run, for this reason (said once).
  string       iss_off_reason;

  // The core's configuration (Spike's ISA string and CSRs).
  int unsigned pmp_num_regions, pmp_granularity, mhpm_counter_num, rv32b, rv32zc;
  bit          secure_ibex, icache;
  bit [31:0]   dm_base_addr, dm_addr_mask;

  // UARTs: how many the scoreboard compares, and which of them the test must reach.
  int unsigned num_uarts;
  bit          uart_required[];

  // The SystemC model (SOC_COSIM_SYSMODEL builds): its board and what it loads.
  string       model_board = "eg2";
  string       model_rom;
  string       model_test;
  string       model_otp;

  `uvm_object_utils(soc_cosim_cfg)
  `uvm_object_new

  // Everything a replay needs to rebuild this configuration, as "H <key> <value>" lines at the top
  // of a recording.
  function void to_header(int fd);
    $fdisplay(fd, "H start_mode %0d", int'(start_mode));
    foreach (images[i]) $fdisplay(fd, "H image %s", images[i]);
    $fdisplay(fd, "H lock_addr %h", lock_addr);
    foreach (mem_base[i]) $fdisplay(fd, "H mem %h %h", mem_base[i], mem_size[i]);
    if (iss_off_reason != "") $fdisplay(fd, "H iss_off %s", iss_off_reason);
    $fdisplay(fd, "H revocation %h %h %h", rev_heap_base, rev_heap_size, rev_bits_base);
    $fdisplay(fd, "H core %0d %0d %0d %0d %0d %0d %0d %h %h", pmp_num_regions, pmp_granularity,
              mhpm_counter_num, rv32b, rv32zc, secure_ibex, icache, dm_base_addr, dm_addr_mask);
    $fdisplay(fd, "H uarts %0d", num_uarts);
    foreach (uart_required[i]) if (uart_required[i]) $fdisplay(fd, "H uart_required %0d", i);
    $fdisplay(fd, "H model %s %s %s %s", model_board,
              model_rom == "" ? "-" : model_rom, model_test == "" ? "-" : model_test,
              model_otp == "" ? "-" : model_otp);
  endfunction

  // Reads one header line; 0 if it is not one.
  function bit from_header(string line);
    string w[$];
    soc_split(line, w);
    if (w.size() < 2 || w[0] != "H") return 1'b0;
    case (w[1])
      "start_mode": begin
        int m;
        void'($sscanf(w[2], "%d", m));
        start_mode = start_e'(m);
      end
      "image":      images.push_back(w[2]);
      "lock_addr":  void'($sscanf(w[2], "%h", lock_addr));
      "mem": begin
        bit [31:0] b, s;
        void'($sscanf(w[2], "%h", b));
        void'($sscanf(w[3], "%h", s));
        mem_base.push_back(b);
        mem_size.push_back(s);
      end
      "revocation": begin
        void'($sscanf(w[2], "%h", rev_heap_base));
        void'($sscanf(w[3], "%h", rev_heap_size));
        void'($sscanf(w[4], "%h", rev_bits_base));
      end
      "iss_off": begin
        iss_off_reason = w[2];
        for (int i = 3; i < w.size(); i++) iss_off_reason = {iss_off_reason, " ", w[i]};
      end
      "core": begin
        void'($sscanf(w[2], "%d", pmp_num_regions));
        void'($sscanf(w[3], "%d", pmp_granularity));
        void'($sscanf(w[4], "%d", mhpm_counter_num));
        void'($sscanf(w[5], "%d", rv32b));
        void'($sscanf(w[6], "%d", rv32zc));
        void'($sscanf(w[7], "%d", secure_ibex));
        void'($sscanf(w[8], "%d", icache));
        void'($sscanf(w[9], "%h", dm_base_addr));
        void'($sscanf(w[10], "%h", dm_addr_mask));
      end
      "uarts": begin
        void'($sscanf(w[2], "%d", num_uarts));
        uart_required = new[num_uarts];
      end
      "uart_required": begin
        int i;
        void'($sscanf(w[2], "%d", i));
        if (i < uart_required.size()) uart_required[i] = 1'b1;
      end
      "model": begin
        model_board = w[2];
        model_rom   = w[3] == "-" ? "" : w[3];
        model_test  = w[4] == "-" ? "" : w[4];
        model_otp   = w[5] == "-" ? "" : w[5];
      end
      default: return 1'b0;
    endcase
    return 1'b1;
  endfunction

  // Spike's ISA string for this core, by the Ibex UVM bench's rule (core_ibex_base_test).
  function string isa_string();
    string isa = "rv32imc";
    case (rv32b)
      int'(ibex_pkg::RV32BBalanced): isa = {isa, "_Zba_Zbb_Zbs"};
      int'(ibex_pkg::RV32BFull):     isa = {isa, "_Zba_Zbb_Zbc_Zbs_Zbkb_Zbkx"};
      default: ;
    endcase
    case (rv32zc)
      int'(ibex_pkg::RV32ZcaZcb):     isa = {isa, "_Zcb"};
      int'(ibex_pkg::RV32ZcaZcmp):    isa = {isa, "_Zcmp"};
      int'(ibex_pkg::RV32ZcaZcbZcmp): isa = {isa, "_Zcb_Zcmp"};
      default: ;
    endcase
    if (mhpm_counter_num > 0) isa = {isa, "_Zihpm"};
    return isa;
  endfunction
endclass

// Where model inputs go: the SystemC model bridge implements it (soc_sysmodel_hook), the replay
// calls it with what the recorded run gave the model.
virtual class soc_model_hook;
  pure virtual function void model_input(string key, int unsigned value);
  pure virtual function void backdoor(bit [31:0] addr, bit [7:0] data);
endclass
