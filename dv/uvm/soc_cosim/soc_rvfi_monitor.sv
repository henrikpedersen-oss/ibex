// Copyright lowRISC contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0
//
// Where the checking stack's inputs come from, and how a run is recorded and replayed.
//
// soc_rvfi_monitor: passive, samples soc_cosim_if each clock and writes one soc_rvfi_item per
//   retired instruction, per interrupt-only notification and per reset release, stamped with the
//   simulation time. Modelled on Ibex's ibex_rvfi_monitor, with the whole RVFI (instruction, memory
//   access, capabilities).
//
// soc_cosim_record: +soc_cosim_record=<file> writes everything that enters the checking stack, in
//   time order: the configuration ("H" lines), every RVFI item ("I"), every UART byte ("U" sent,
//   "X" received), every input the SystemC model takes ("M <key> <value>": clocks), every
//   backdoor write into memory ("B <addr> <byte>") and every tag another bus master cleared
//   ("T <addr>": a revocation engine's sweep).
//
// soc_cosim_replay: the same inputs, read back from a recording instead of the RTL. A replay top
//   (soc_cosim_replay_tb.sv) has no RTL at all: the ISS, the scoreboard and the SystemC model run
//   at their own speed on what the recorded run did, as often as a fix needs trying.

class soc_cosim_record;
  static int fd;

  // Opens the recording if +soc_cosim_record=<file> asks for one; writes the configuration.
  static function void open(soc_cosim_cfg cfg);
    string path;
    if (fd || !$value$plusargs("soc_cosim_record=%s", path)) return;
    fd = $fopen(path, "w");
    if (!fd) begin
      `uvm_error("SOC_COSIM", $sformatf("cannot open the recording %s", path))
      return;
    end
    $fdisplay(fd, "# soc_cosim recording: H configuration, I RVFI item, U/X UART byte sent/received,");
    $fdisplay(fd, "# M model input, B backdoor write; times in ps");
    cfg.to_header(fd);
    `uvm_info("SOC_COSIM", $sformatf("recording the checking stack's inputs to %s", path), UVM_LOW)
  endfunction

  static function bit on();
    return fd != 0;
  endfunction

  static function void item(soc_rvfi_item it);
    if (fd) $fdisplay(fd, "%s", it.to_record());
  endfunction

  static function void uart(soc_byte_item b);
    if (fd) $fdisplay(fd, "%s %0d %0d %02h", b.rx ? "X" : "U", b.time_ps, b.idx, b.data);
  endfunction

  static function void model_input(longint unsigned t_ps, string key, int unsigned value);
    if (fd) $fdisplay(fd, "M %0d %s %0d", t_ps, key, value);
  endfunction

  static function void tag_clear(longint unsigned t_ps, bit [31:0] addr);
    if (fd) $fdisplay(fd, "T %0d %h", t_ps, addr);
  endfunction

  static function void backdoor(longint unsigned t_ps, bit [31:0] addr, bit [7:0] data);
    if (fd) $fdisplay(fd, "B %0d %h %02h", t_ps, addr, data);
  endfunction

  static function void close();
    if (fd) $fclose(fd);
    fd = 0;
  endfunction
endclass

class soc_rvfi_monitor extends uvm_monitor;
  `uvm_component_utils(soc_rvfi_monitor)

  soc_cosim_vif vif;
  uvm_analysis_port #(soc_rvfi_item) analysis_port;

  `uvm_component_new

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    analysis_port = new("analysis_port", this);
  endfunction

  virtual task run_phase(uvm_phase phase);
    bit in_reset = 1'b1;
    bit data_err_seen;
    if (vif == null) return;
    forever begin
      @(vif.monitor_cb);
      if (vif.monitor_cb.rst_n !== 1'b1) begin
        in_reset = 1'b1;
        continue;
      end
      if (in_reset) begin
        // Out of reset: tell the subscribers before the first instruction.
        soc_rvfi_item item = soc_rvfi_item::type_id::create("item");
        item.time_ps   = now_ps();
        item.reset     = 1'b1;
        item.boot_addr = vif.monitor_cb.boot_addr;
        publish(item);
        in_reset      = 1'b0;
        data_err_seen = 1'b0;
      end
      // An error response belongs to the next instruction that retires (the access's instruction
      // retires after its response).
      if (vif.monitor_cb.data_err === 1'b1) data_err_seen = 1'b1;
      if (vif.monitor_cb.valid === 1'b1 || vif.monitor_cb.ext_irq_valid === 1'b1) begin
        soc_rvfi_item item = sample();
        if (!item.irq_only) begin
          item.mem_error = data_err_seen;
          data_err_seen  = 1'b0;
        end
        publish(item);
      end
    end
  endtask

  protected function void publish(soc_rvfi_item item);
    soc_cosim_record::item(item);
    analysis_port.write(item);
  endfunction

  static function longint unsigned now_ps();
    return longint'($realtime / 1ps);
  endfunction

  protected function soc_rvfi_item sample();
    soc_rvfi_item item = soc_rvfi_item::type_id::create("item");
    item.time_ps        = now_ps();
    item.irq_only       = vif.monitor_cb.valid !== 1'b1;
    item.order          = vif.monitor_cb.order;
    item.insn           = vif.monitor_cb.insn;
    item.trap           = vif.monitor_cb.trap;
    item.halt           = vif.monitor_cb.halt;
    item.intr           = vif.monitor_cb.intr;
    item.mode           = vif.monitor_cb.mode;
    item.pc             = vif.monitor_cb.pc_rdata;
    item.pc_next        = vif.monitor_cb.pc_wdata;
    item.rd_addr        = vif.monitor_cb.rd_addr;
    item.rd_wdata       = vif.monitor_cb.rd_wdata;
    item.rd_wcap        = vif.monitor_cb.rd_wcap;
    item.mem_addr       = vif.monitor_cb.mem_addr;
    // Ibex sets the masks for every instruction, from the LSU type and data_we_o, whether or not
    // it accessed memory (ibex_core.sv, rvfi_stage_mem_rmask): a jal reports a 4-byte load at its
    // target. They are kept only for loads and stores.
    if (is_data_access(item.insn)) begin
      item.mem_rmask    = vif.monitor_cb.mem_rmask;
      item.mem_wmask    = vif.monitor_cb.mem_wmask;
    end
    item.mem_rdata      = vif.monitor_cb.mem_rdata;
    item.mem_wdata      = vif.monitor_cb.mem_wdata;
    item.mem_is_cap     = vif.monitor_cb.mem_is_cap;
    item.mem_rcap       = vif.monitor_cb.mem_rcap;
    item.mem_wcap       = vif.monitor_cb.mem_wcap;
    item.pre_mip        = vif.monitor_cb.ext_pre_mip;
    item.post_mip       = vif.monitor_cb.ext_post_mip;
    item.nmi            = vif.monitor_cb.ext_nmi;
    item.nmi_int        = vif.monitor_cb.ext_nmi_int;
    item.debug_req      = vif.monitor_cb.ext_debug_req;
    item.debug_mode     = vif.monitor_cb.ext_debug_mode;
    item.rf_wr_suppress = vif.monitor_cb.ext_rf_wr_suppress;
    item.mcycle         = vif.monitor_cb.ext_mcycle;
    foreach (item.mhpmcounters[i]) begin
      item.mhpmcounters[i]  = vif.monitor_cb.ext_mhpmcounters[i];
      item.mhpmcountersh[i] = vif.monitor_cb.ext_mhpmcountersh[i];
    end
    item.ic_scr_key_valid = vif.monitor_cb.ext_ic_scr_key_valid;
    // As the core bench: a trapping micro-operation ends the instruction even if not flagged last.
    item.more_ops         = vif.monitor_cb.ext_expanded_insn_valid &&
                            !vif.monitor_cb.ext_expanded_insn_last && !vif.monitor_cb.trap;
    item.nmi_int_mtval    = vif.monitor_cb.nmi_int_mtval;
    item.cheriot          = vif.monitor_cb.cheriot_ena;
    return item;
  endfunction

  // Loads and stores, by encoding: LOAD and STORE (CLC and CSC included); in quadrant 0 every
  // funct3 but c.addi4spn (c.lw, c.sw, c.clc, c.csc and Zcb's c.lbu, c.lhu, c.lh, c.sb, c.sh); in
  // quadrant 2 c.lwsp, c.swsp, c.clcsp, c.cscsp. An encoding the mode does not have traps, and a
  // trap's access is not used.
  static function bit is_data_access(bit [31:0] insn);
    bit [2:0] f3 = insn[15:13];
    case (insn[1:0])
      2'b11:   return insn[6:0] inside {7'b0000011, 7'b0100011};
      2'b00:   return f3 != 3'b000;
      2'b10:   return f3 inside {3'b010, 3'b011, 3'b110, 3'b111};
      default: return 1'b0;
    endcase
  endfunction
endclass

// Replays a recording: the configuration first (cfg()), then every input at its recorded time, into
// the same ports and calls the RTL run used.
class soc_cosim_replay extends uvm_component;
  `uvm_component_utils(soc_cosim_replay)

  uvm_analysis_port #(soc_rvfi_item) rvfi_port;
  uvm_analysis_port #(soc_byte_item) uart_port;
  // Model inputs and backdoor writes go to these hooks (soc_cosim_env sets them).
  soc_model_hook model_hook;

  protected int fd;
  protected string pending;
  protected int unsigned replayed_items;

  `uvm_component_new

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    rvfi_port = new("rvfi_port", this);
    uart_port = new("uart_port", this);
  endfunction

  // Opens +soc_cosim_replay=<file> and reads its configuration; null if there is none.
  static function soc_cosim_cfg read_cfg(ref int fd, ref string pending);
    string path, line;
    soc_cosim_cfg cfg;
    if (!$value$plusargs("soc_cosim_replay=%s", path)) return null;
    fd = $fopen(path, "r");
    if (!fd) begin
      uvm_pkg::uvm_report_fatal("SOC_COSIM", $sformatf("cannot open the recording %s", path));
    end
    cfg = soc_cosim_cfg::type_id::create("cfg");
    while ($fgets(line, fd)) begin
      if (line.len() == 0 || line[0] == "#") continue;
      if (!cfg.from_header(line)) begin
        pending = line;
        break;
      end
    end
    uvm_pkg::uvm_report_info("SOC_COSIM", $sformatf("replaying %s", path), UVM_LOW);
    return cfg;
  endfunction

  function void set_source(int fd_i, string pending_i);
    fd = fd_i;
    pending = pending_i;
  endfunction

  virtual task run_phase(uvm_phase phase);
    string line;
    if (!fd) return;
    phase.raise_objection(this);
    line = pending;
    do begin
      if (line.len() > 0) dispatch(line);
    end while ($fgets(line, fd));
    $fclose(fd);
    `uvm_info(`gfn, $sformatf("replay done: %0d RVFI items", replayed_items), UVM_LOW)
    phase.drop_objection(this);
  endtask

  protected task wait_until(longint unsigned t_ps);
    longint unsigned now = soc_rvfi_monitor::now_ps();
    if (t_ps > now) #((t_ps - now) * 1ps);
  endtask

  protected task dispatch(string line);
    string w[$];
    longint unsigned t;
    soc_split(line, w);
    if (w.size() == 0) return;
    case (w[0])
      "I": begin
        soc_rvfi_item item = soc_rvfi_item::type_id::create("item");
        if (!item.from_record(line)) `uvm_fatal(`gfn, {"bad RVFI record: ", line})
        wait_until(item.time_ps);
        replayed_items++;
        rvfi_port.write(item);
      end
      "U", "X": begin
        soc_byte_item b = soc_byte_item::type_id::create("b");
        void'($sscanf(w[1], "%d", b.time_ps));
        void'($sscanf(w[2], "%d", b.idx));
        void'($sscanf(w[3], "%h", b.data));
        b.rx = w[0] == "X";
        wait_until(b.time_ps);
        uart_port.write(b);
      end
      "M": begin
        int unsigned v;
        void'($sscanf(w[1], "%d", t));
        void'($sscanf(w[3], "%d", v));
        wait_until(t);
        if (model_hook != null) model_hook.model_input(w[2], v);
      end
      "B": begin
        bit [31:0] a;
        bit [7:0]  d;
        void'($sscanf(w[1], "%d", t));
        void'($sscanf(w[2], "%h", a));
        void'($sscanf(w[3], "%h", d));
        wait_until(t);
        if (model_hook != null) model_hook.backdoor(a, d);
      end
      "T": begin
        bit [31:0] a;
        void'($sscanf(w[1], "%d", t));
        void'($sscanf(w[2], "%h", a));
        wait_until(t);
        soc_cosim_tb_link::tag_clear(a);
      end
      "#", "H": ;
      default: `uvm_warning(`gfn, {"unknown recording line: ", line})
    endcase
  endtask
endclass
