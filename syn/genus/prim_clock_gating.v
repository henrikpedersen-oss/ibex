// Copyright lowRISC contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

// Clock gate for Genus synthesis: NanGate45's integrated clock-gating cell, so the gate is one
// library cell with its timing checks rather than a latch and an AND gate (../rtl/prim_clock_gating.v,
// the Yosys flow's model).

module prim_clock_gating (
  input  clk_i,
  input  en_i,
  input  test_en_i,
  output clk_o
);

  CLKGATETST_X1 u_icg (
    .CK (clk_i),
    .E  (en_i),
    .SE (test_en_i),
    .GCK(clk_o)
  );

endmodule
