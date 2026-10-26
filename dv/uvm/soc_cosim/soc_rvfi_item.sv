// Copyright lowRISC contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0
//
// One retired instruction, an interrupt-only notification, or a reset, as RVFI reports it, with
// everything a reference model needs to follow the core (interrupt, NMI and debug inputs, the
// counters, the CHERIoT state). The monitor stamps it with the simulation time; a recording keeps
// every field (to_record/from_record), so a replay feeds the checking stack exactly what the run did.

class soc_rvfi_item extends uvm_sequence_item;
  // Simulation time of the sample, in ps.
  longint unsigned     time_ps;
  // Not an instruction: the core left reset (boot_addr valid) ...
  bit                  reset;
  // ... or an interrupt was taken with no instruction retiring.
  bit                  irq_only;
  bit [63:0]           order;
  bit [31:0]           insn;
  bit                  trap;
  bit                  halt;
  bit                  intr;
  bit [1:0]            mode;
  bit [31:0]           pc;
  bit [31:0]           pc_next;
  bit [4:0]            rd_addr;
  bit [31:0]           rd_wdata;
  bit [SOC_CAP_W-1:0]  rd_wcap;
  bit [31:0]           mem_addr;
  bit [3:0]            mem_rmask;
  bit [3:0]            mem_wmask;
  bit [31:0]           mem_rdata;
  bit [31:0]           mem_wdata;
  bit                  mem_is_cap;
  bit [SOC_CAP_W-1:0]  mem_rcap;
  bit [SOC_CAP_W-1:0]  mem_wcap;
  // Events for a reference model.
  bit [31:0]           pre_mip;
  bit [31:0]           post_mip;
  bit                  nmi;
  bit                  nmi_int;
  bit                  debug_req;
  bit                  debug_mode;
  bit                  rf_wr_suppress;
  bit [63:0]           mcycle;
  bit [31:0]           mhpmcounters [10];
  bit [31:0]           mhpmcountersh [10];
  bit                  ic_scr_key_valid;
  // A Zcmp micro-operation that is not the instruction's last (the ISS steps on the last).
  bit                  more_ops;
  // The mtval of an internal NMI (ibex_controller's irq_nm_int_mtval).
  bit [31:0]           nmi_int_mtval;
  // A data response of this instruction came back with an error.
  bit                  mem_error;
  // The core runs in CHERIoT mode (cheriot_enable at the core).
  bit                  cheriot;
  // The core's boot address (reset items).
  bit [31:0]           boot_addr;

  `uvm_object_utils(soc_rvfi_item)
  `uvm_object_new

  // One line of rvfi.chip.log. Only what the instruction did is printed, so two logs of the same
  // run (chip and model) can be compared with diff.
  virtual function string log_line();
    string s;
    if (reset) return "reset";
    if (irq_only) return $sformatf("%0d irq mip=%08h", order, post_mip);
    s = $sformatf("%0d pc=%08h insn=%08h", order, pc, insn);
    if (trap) s = {s, " trap"};
    if (intr) s = {s, " intr"};
    if (rd_addr != 0) s = {s, $sformatf(" x%0d=%08h", rd_addr, rd_wdata)};
    if (rd_addr != 0 && rd_wcap[32]) s = {s, $sformatf(" cap=%09h", rd_wcap)};
    if (mem_rmask != 0) s = {s, $sformatf(" ld[%08h/%h]=%08h", mem_addr, mem_rmask, mem_rdata)};
    if (mem_wmask != 0) s = {s, $sformatf(" st[%08h/%h]=%08h", mem_addr, mem_wmask, mem_wdata)};
    if (mem_is_cap) s = {s, $sformatf(" mcap r=%09h w=%09h", mem_rcap, mem_wcap)};
    return s;
  endfunction

  // The whole item as one line of a recording ("I <time> <fields...>", every field in hex, in a
  // fixed order). from_record() reads it back.
  function string to_record();
    string s;
    s = $sformatf("I %0d %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h", time_ps,
                  reset, irq_only, order, insn, trap, halt, intr, mode, pc, pc_next, rd_addr,
                  rd_wdata, rd_wcap, mem_addr, mem_rmask, mem_wmask, mem_rdata, mem_wdata,
                  mem_is_cap, mem_rcap);
    s = {s, $sformatf(" %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h", mem_wcap, pre_mip,
                      post_mip, nmi, nmi_int, debug_req, debug_mode, rf_wr_suppress, mcycle,
                      ic_scr_key_valid, more_ops, nmi_int_mtval, mem_error, cheriot, boot_addr)};
    foreach (mhpmcounters[i]) s = {s, $sformatf(" %h %h", mhpmcounters[i], mhpmcountersh[i])};
    return s;
  endfunction

  // Fills the item from a to_record() line; 0 if the line is not one.
  function bit from_record(string line);
    string f[$];
    soc_split(line, f);
    if (f.size() != 2 + 20 + 15 + 20 || f[0] != "I") return 1'b0;
    void'($sscanf(f[1], "%d", time_ps));
    void'($sscanf(f[2], "%h", reset));         void'($sscanf(f[3], "%h", irq_only));
    void'($sscanf(f[4], "%h", order));         void'($sscanf(f[5], "%h", insn));
    void'($sscanf(f[6], "%h", trap));          void'($sscanf(f[7], "%h", halt));
    void'($sscanf(f[8], "%h", intr));          void'($sscanf(f[9], "%h", mode));
    void'($sscanf(f[10], "%h", pc));           void'($sscanf(f[11], "%h", pc_next));
    void'($sscanf(f[12], "%h", rd_addr));      void'($sscanf(f[13], "%h", rd_wdata));
    void'($sscanf(f[14], "%h", rd_wcap));      void'($sscanf(f[15], "%h", mem_addr));
    void'($sscanf(f[16], "%h", mem_rmask));    void'($sscanf(f[17], "%h", mem_wmask));
    void'($sscanf(f[18], "%h", mem_rdata));    void'($sscanf(f[19], "%h", mem_wdata));
    void'($sscanf(f[20], "%h", mem_is_cap));   void'($sscanf(f[21], "%h", mem_rcap));
    void'($sscanf(f[22], "%h", mem_wcap));     void'($sscanf(f[23], "%h", pre_mip));
    void'($sscanf(f[24], "%h", post_mip));     void'($sscanf(f[25], "%h", nmi));
    void'($sscanf(f[26], "%h", nmi_int));      void'($sscanf(f[27], "%h", debug_req));
    void'($sscanf(f[28], "%h", debug_mode));   void'($sscanf(f[29], "%h", rf_wr_suppress));
    void'($sscanf(f[30], "%h", mcycle));       void'($sscanf(f[31], "%h", ic_scr_key_valid));
    void'($sscanf(f[32], "%h", more_ops));     void'($sscanf(f[33], "%h", nmi_int_mtval));
    void'($sscanf(f[34], "%h", mem_error));    void'($sscanf(f[35], "%h", cheriot));
    void'($sscanf(f[36], "%h", boot_addr));
    foreach (mhpmcounters[k]) begin
      void'($sscanf(f[37 + 2 * k], "%h", mhpmcounters[k]));
      void'($sscanf(f[38 + 2 * k], "%h", mhpmcountersh[k]));
    end
    return 1'b1;
  endfunction
endclass

// The expected side of one instruction: the reference model's verdict on it.
class soc_rvfi_exp_item extends uvm_sequence_item;
  bit [63:0]    order;
  bit [31:0]    pc;
  bit           match;
  string        errors;
  soc_rvfi_item act;

  `uvm_object_utils(soc_rvfi_exp_item)
  `uvm_object_new
endclass

// One byte a SoC's UART sent (tx) or received (rx), for the scoreboard and the SystemC model.
class soc_byte_item extends uvm_sequence_item;
  longint unsigned time_ps;
  int unsigned     idx;
  bit              rx;
  bit [7:0]        data;

  `uvm_object_utils(soc_byte_item)
  `uvm_object_new
endclass
