// Copyright lowRISC contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0
//
// Between a module testbench and the UVM side: the testbench asks the test to end (instead of
// calling $finish, which would skip the report phase), and gives the UART bytes it decodes.
class soc_cosim_tb_link;
  static bit           end_requested;
  static int           end_code;
  static soc_byte_item bytes[$];
  // Tags another bus master cleared in memory (a revocation engine's sweep), oldest first.
  static bit [31:0]       tag_clears[$];
  static longint unsigned tag_clear_times[$];

  static function void request_end(int code);
    if (!end_requested) end_code = code;
    end_requested = 1'b1;
  endfunction

  static function void tag_clear(bit [31:0] addr);
    tag_clears.push_back(addr);
    tag_clear_times.push_back(longint'($realtime / 1ps));
  endfunction

  static function void uart_byte(int unsigned idx, bit [7:0] data, bit rx = 1'b0);
    soc_byte_item b = soc_byte_item::type_id::create("b");
    b.time_ps = longint'($realtime / 1ps);
    b.idx     = idx;
    b.data    = data;
    b.rx      = rx;
    bytes.push_back(b);
  endfunction
endclass
