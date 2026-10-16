// Copyright lowRISC contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

// Clock gate for the equivalence check, read identically by gold and gate. The proof runs with one
// global clock, so a gated clock is never modelled; en_i is left unobserved.
module prim_clock_gating (
  input  clk_i,
  input  en_i,
  input  test_en_i,
  output clk_o
);
  assign clk_o = clk_i;
endmodule
