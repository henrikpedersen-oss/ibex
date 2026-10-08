// Copyright lowRISC contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

// Derived from sonata-system/rtl/system/cheriot_rev_ctl_trbe.sv, where it is an uncommitted local
// addition, so that this flow does not depend on a local change in another submodule. This copy
// follows the register map of lowRISC/opentitan PR #31515 (TRBE_STATUS, TRBE_EPOCH, the trbe_done
// interrupt); the sonata-system copy still targets PR #31470's TRBE_BUSY and no longer builds
// against opentitan-cheriot/.

// Drives the CHERIoT memory subsystem's revocation engine (TRBE) from Sonata's rev_ctl.
//
// rev_ctl keeps the register interface the CHERIoT RTOS hardware-revoker driver uses (base, top,
// go, epoch, interrupt; platform-hardware_revoker.hh). Its core-side interface is abstract: a go
// pulse with the [start, end) range, and a running bit it turns into the epoch's low bit, the epoch
// count (advanced whenever running falls) and the completion interrupt. This module implements
// that interface with the TRBE, programming the TRBE's CSRs over TL-UL exactly as firmware would,
// so the subsystem RTL is used unmodified:
//
//   first go: INTR_ENABLE <= trbe_done
//   go:       TRBE_BASE_ADDR <= start; TRBE_NUM_CAPS <= capabilities in [start, end);
//             TRBE_START <= 1; TRBE_STATUS read: start_err means the start was not taken; not
//             busy any more means a short sweep is already over (to the end step's check)
//   wait:     for the trbe_done interrupt (trbe_done_i)
//   end:      TRBE_STATUS read: busy and sweep_err must be clear; INTR_STATE <= trbe_done
//   running:  from the go pulse until the end of a sweep without an error
//
// rev_ctl's own epoch stays the firmware's epoch; TRBE_EPOCH is not read. rev_ctl advances its
// epoch whenever running falls, so the epoch keeps TRBE_EPOCH's guarantee as long as running only
// falls at the end of a sweep that resolved every capability. A sweep that cannot be shown to have
// done so -- a start the TRBE did not take, a sweep with STATUS.sweep_err, an interrupt while still
// busy, a bus error on the CSR port -- keeps running high: the epoch stays odd, the driver never
// sees a completed revocation and keeps the memory in quarantine, and err_o is raised, sticky until
// reset. Every one of these also follows a fault the subsystem raises its fatal alert for, or a
// broken guarantee of its register interface, so the shim does not retry. An empty range has no
// capability to resolve and completes without the TRBE.
//
// A go while a sweep is running is ignored (the driver only starts one when the epoch is even).
module cheriot_rev_ctl_trbe
  import cheriot_reg_pkg::*;
(
  input  logic clk_i,
  input  logic rst_ni,

  // rev_ctl core-side interface: ctl_to_core = {63'b0, go, end_addr, start_addr}.
  input  logic [127:0] ctl_to_core_i,
  output logic [ 63:0] core_to_ctl_o,

  // TL-UL host towards the subsystem's CSRs (regs_tl_d).
  output tlul_pkg::tl_h2d_t tl_o,
  input  tlul_pkg::tl_d2h_t tl_i,

  // The subsystem's trbe_done interrupt (intr_trbe_done_o).
  input  logic trbe_done_i,

  output logic err_o
);
  // Fields of TRBE_STATUS
  localparam int unsigned StatusBusyBit     = 0;
  localparam int unsigned StatusStartErrBit = 8;
  localparam int unsigned StatusSweepErrBit = 9;

  typedef enum logic [3:0] {
    Idle,
    WrIntrEnable,
    WrBase,
    WrNumCaps,
    WrStart,
    RdStarted,
    WaitDone,
    RdDone,
    WrIntrState,
    Empty,
    Failed
  } state_e;

  state_e      state_q;
  logic        pending_q;   // request granted, response not yet received
  logic        running_q;
  logic        err_q;
  logic        intr_en_q;   // INTR_ENABLE written
  logic [31:0] base_q;
  logic [31:0] num_caps_q;
  logic [31:0] status_q;    // last TRBE_STATUS read, for the testbench

  logic        go;
  logic [31:0] start_addr, end_addr;
  logic [31:0] start_cap;

  logic        req, gnt, we, valid, rsp_err;
  logic [31:0] addr, wdata, rdata;

  assign start_addr = ctl_to_core_i[31:0];
  assign end_addr   = ctl_to_core_i[63:32];
  assign go         = ctl_to_core_i[64];

  // TRBE_BASE_ADDR holds a capability address, so the sweep starts at the capability start_addr
  // is in.
  assign start_cap = {start_addr[31:3], 3'b000};

  // One request at a time: issue, then wait for its response before the next.
  assign req = (state_q inside {WrIntrEnable, WrBase, WrNumCaps, WrStart, RdStarted, RdDone,
                                WrIntrState}) && !pending_q;
  assign we  = !(state_q inside {RdStarted, RdDone});

  always_comb begin
    addr  = '0;
    wdata = '0;
    unique case (state_q)
      WrIntrEnable: begin addr = 32'(CHERIOT_INTR_ENABLE_OFFSET);    wdata = 32'h1;      end
      WrBase:       begin addr = 32'(CHERIOT_TRBE_BASE_ADDR_OFFSET); wdata = base_q;     end
      WrNumCaps:    begin addr = 32'(CHERIOT_TRBE_NUM_CAPS_OFFSET);  wdata = num_caps_q; end
      WrStart:      begin addr = 32'(CHERIOT_TRBE_START_OFFSET);     wdata = 32'h1;      end
      RdStarted,
      RdDone:       begin addr = 32'(CHERIOT_TRBE_STATUS_OFFSET);                        end
      WrIntrState:  begin addr = 32'(CHERIOT_INTR_STATE_OFFSET);     wdata = 32'h1;      end
      default:      ;
    endcase
  end

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      state_q    <= Idle;
      pending_q  <= 1'b0;
      running_q  <= 1'b0;
      err_q      <= 1'b0;
      intr_en_q  <= 1'b0;
      base_q     <= '0;
      num_caps_q <= '0;
      status_q   <= '0;
    end else begin
      if (req && gnt) begin
        pending_q <= 1'b1;
      end
      if (valid) begin
        pending_q <= 1'b0;
      end

      unique case (state_q)
        Idle: begin
          if (go) begin
            base_q     <= start_cap;
            // A capability is 8 bytes; round up so a partial last one is still swept.
            num_caps_q <= (end_addr > start_addr) ? (end_addr - start_cap + 32'd7) >> 3 : '0;
            running_q  <= 1'b1;
            if (!(end_addr > start_addr)) begin
              // Nothing to revoke. The TRBE would ignore the start and flag it, so it is not asked.
              state_q <= Empty;
            end else if (!intr_en_q) begin
              state_q <= WrIntrEnable;
            end else begin
              state_q <= WrBase;
            end
          end
        end
        // running_q has been high for a cycle, which rev_ctl counts as a sweep.
        Empty: begin
          running_q <= 1'b0;
          state_q   <= Idle;
        end
        WaitDone: begin
          if (trbe_done_i) begin
            state_q <= RdDone;
          end
        end
        WrIntrEnable, WrBase, WrNumCaps, WrStart, RdStarted, RdDone, WrIntrState: begin
          if (valid && rsp_err) begin
            err_q   <= 1'b1;
            state_q <= Failed;
          end else if (valid) begin
            unique case (state_q)
              WrIntrEnable: begin
                intr_en_q <= 1'b1;
                state_q   <= WrBase;
              end
              WrBase:    state_q <= WrNumCaps;
              WrNumCaps: state_q <= WrStart;
              WrStart:   state_q <= RdStarted;
              // An ignored start sets STATUS.start_err (this shim starts no other sweep), and nothing
              // was revoked. Otherwise the sweep is running, or a short one is already over, which
              // is then checked as at the end (its interrupt is acknowledged there).
              RdStarted: begin
                status_q <= rdata;
                if (rdata[StatusStartErrBit] || rdata[StatusSweepErrBit]) begin
                  err_q   <= 1'b1;
                  state_q <= Failed;
                end else if (rdata[StatusBusyBit]) begin
                  state_q <= WaitDone;
                end else begin
                  state_q <= WrIntrState;
                end
              end
              // The interrupt is raised once the TRBE is no longer active, with or without an
              // error.
              RdDone: begin
                status_q <= rdata;
                if (rdata[StatusBusyBit] || rdata[StatusSweepErrBit]) begin
                  err_q   <= 1'b1;
                  state_q <= Failed;
                end else begin
                  state_q <= WrIntrState;
                end
              end
              // The TRBE is idle, so no sweep can end while the interrupt is acknowledged.
              default: begin
                running_q <= 1'b0;
                state_q   <= Idle;
              end
            endcase
          end
        end
        // Holds running_q until reset; see the top of this file.
        Failed: ;
        default: state_q <= Idle;
      endcase
    end
  end

  assign core_to_ctl_o = {63'b0, running_q};
  assign err_o         = err_q;

  // The subsystem's CSR block checks command integrity and refuses writes that fail it, so this
  // host generates command and data integrity (Sonata's own hosts do not).
  tlul_adapter_host #(
    .MAX_REQS         (1),
    .EnableCmdIntgGen (1'b1),
    .EnableDataIntgGen(1'b1)
  ) u_tlul_adapter_host (
    .clk_i,
    .rst_ni,
    .req_i        (req),
    .gnt_o        (gnt),
    .addr_i       (addr),
    .we_i         (we),
    .wdata_i      (wdata),
    .wdata_cap_i  (1'b0),
    .wdata_intg_i ('0),
    .be_i         ('1),
    .instr_type_i (prim_mubi_pkg::MuBi4False),
    .valid_o      (valid),
    .rdata_o      (rdata),
    .rdata_cap_o  (),
    .rdata_intg_o (),
    .err_o        (rsp_err),
    .intg_err_o   (),
    .tl_o,
    .tl_i
  );

  logic unused_ctl_to_core;
  assign unused_ctl_to_core = ^ctl_to_core_i[127:65];
endmodule
