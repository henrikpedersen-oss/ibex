// Copyright lowRISC contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0
//
// Revocation model for the UVM and TestRIG benches: what TRVK's bitmap port answers and what
// the CHERIoT-Sail cosim is told, from one definition.
//
// Two consumers read this package and nothing else:
//   ibex_revbm_responder     answers TRVK's bitmap lookups (rdata / err / integrity) and drives
//                            trvk_heap_base_addr_i.
//   ibex_cosim_scoreboard    writes the same revoked set into CHERIoT-Sail's own revocation
//                            shadow after every model init (cheriot_sail_load_revbm()).
// The model then decides every CLC itself -- base decode, sealing exemption, granule, range --
// from that bitmap, the way it decides a load from memory contents. Nothing is ever copied
// from the DUT into the model.
//
// The bitmap is a pure function of the plusargs and +revbm_seed, fixed at time 0 for the whole
// run ("stable per granule"): both consumers can build it independently, in any order, and a
// re-initialised model after a reset gets the identical set again.
//
// The two layouts
// ---------------
// TRVK (ibex_trvk.sv): granule g = (cap_base - heap_base) >> 3, looked up as bit g[4:0] of
//   word g >> 5 at RevBitmapBaseAddr + 4*word; g >= NumGranules (including bases below the
//   heap, which wrap) is out of range: no lookup, never revoked. A device error or an integrity
//   error on the response revokes, whatever the data says.
// CHERIoT-Sail (cheri_mem.sail mem_read_cap_revoked, cheri_insts.sail LoadCapImm): granule
//   s = (cap_base - plat_ram_base) >> 3 with plat_ram_base = 0x80000000 (cheriot_sail_cosim_dpi.cc
//   rv_ram_base), bit s[2:0] of the byte at 0x83000000 + (s >> 3) in the model's RAM; bases
//   below plat_ram_base are never revoked, bases above have no upper limit.
// So a TRVK granule maps to Sail granule s = g + (heap_base - 0x80000000)/8. Revocation that
// Sail cannot express -- a granule below 0x80000000, or an error-injected word containing one --
// is never generated: those granules are forced live and the word is not error-injected.
//
// Plusargs (all hex values accept an optional 0x prefix)
// ---------
//   +revbm_mode=off|random|range   default off: nothing revoked, no errors (the old behaviour).
//   +revbm_revoke_pct=<0..100>     random: each granule in the window revoked with this
//                                  probability (default 25).
//   +revbm_revoke_base=<hex>       range: revoke [base, base+size). Size default 8 (one granule).
//   +revbm_revoke_size=<hex>
//   +revbm_revoke_list=<b>:<s>,..  range: further [base, base+size) ranges, comma separated.
//   +revbm_err_pct=<0..100>        any active mode: each bitmap word answered with an error.
//   +revbm_err_list=<b>:<s>,..     any active mode: words covering these address ranges err.
//   +revbm_err_kind=dev|intg|both|mixed
//                                  default dev: trvk_revbm_err_i; intg: a flipped ECC bit
//                                  (needs MemECC); both: the two together on the same
//                                  response (a bus may return both; TRVK ORs them); mixed:
//                                  dev or intg, per word.
//   +revbm_heap_base=<hex>         trvk_heap_base_addr_i, 8-byte aligned. Default: drawn per
//                                  seed (see draw_heap_base) so both the in-range and the
//                                  out-of-range TRVK paths are reached across a regression.
//   +revbm_gnt_delay_max=<n>       bitmap port: random 0..n cycles before gnt (default 0).
//   +revbm_rsp_delay_max=<n>       bitmap port: random 0..n extra cycles before rvalid (default 0).
//   +revbm_seed=<n>                seed for every draw above (default: one $urandom).
//   +revbm_cosim_unfed=1           NEGATIVE CONTROL ONLY: do not give the model the bitmap, so
//                                  every revoked CLC must show up as a cd_wtag mismatch.

package ibex_revbm_pkg;

  ///////////////
  // Geometry  //
  ///////////////

  // Must match the DUT's CheriotRevBitmapAddrWidth / CheriotRevBitmapBaseAddr; core_ibex_tb_top
  // passes these constants to both the DUT and the responder.
  parameter int unsigned RevBitmapAddrWidth = 32'd11;
  parameter int unsigned RevBitmapBaseAddr  = 32'h0;
  parameter int unsigned NumWords           = 32'd1 << (RevBitmapAddrWidth - 2);
  parameter int unsigned NumGranules        = NumWords * 32;
  parameter int unsigned WindowBytes        = NumGranules * 8;  // heap bytes TRVK can revoke

  // CHERIoT-Sail's fixed revocation layout (see header).
  parameter int unsigned SailRamBase        = 32'h8000_0000;
  parameter int unsigned SailShadowBase     = 32'h8300_0000;

  typedef enum int unsigned {RevbmOff, RevbmRandom, RevbmRange} revbm_mode_e;
  typedef enum int unsigned {
    RevbmErrDev, RevbmErrIntg, RevbmErrBoth, RevbmErrMixed
  } revbm_err_kind_e;

  ///////////
  // State //
  ///////////

  bit              initialised;
  revbm_mode_e     mode;
  revbm_err_kind_e err_kind;
  int unsigned     revoke_pct;
  int unsigned     err_pct;
  int unsigned     gnt_delay_max;
  int unsigned     rsp_delay_max;
  bit [31:0]       seed;
  bit [31:0]       heap_base;
  bit              cosim_unfed;

  bit [31:0]       revoked_words [NumWords];  // bit g[4:0] of word g>>5: granule g revoked
  bit              err_words     [NumWords];  // word answered with an error
  bit              err_is_dev    [NumWords];  // ...and the error includes a device error
  bit              err_is_intg   [NumWords];  // ...and the error includes an integrity error

  int unsigned     num_revoked;
  int unsigned     num_err_words;
  int unsigned     num_unmodelable;           // requested but not expressible in Sail

  ///////////////
  // Utilities //
  ///////////////

  // 32-bit integer hash (lowbias32). Every random decision is hash(seed, salt, index), so the
  // bitmap does not depend on which consumer builds it first.
  function automatic bit [31:0] mix32(bit [31:0] x);
    x = x ^ (x >> 16);
    x = x * 32'h7feb352d;
    x = x ^ (x >> 15);
    x = x * 32'h846ca68b;
    x = x ^ (x >> 16);
    return x;
  endfunction

  function automatic int unsigned draw_pct(bit [31:0] salt, bit [31:0] idx);
    return int'(mix32(mix32(seed ^ salt) ^ idx) % 100);
  endfunction

  // Parse a hex number with an optional 0x prefix. Returns 0 on any non-hex character.
  function automatic bit parse_hex(string s, output bit [31:0] v);
    int start;
    v = '0;
    start = 0;
    if (s.len() >= 2 && s[0] == "0" && (s[1] == "x" || s[1] == "X")) start = 2;
    if (s.len() <= start) return 1'b0;
    for (int i = start; i < s.len(); i++) begin
      bit [7:0] c;
      c = s[i];
      v = v << 4;
      if (c >= "0" && c <= "9")      v[3:0] = 4'(c - 8'd48);
      else if (c >= "a" && c <= "f") v[3:0] = 4'(c - 8'd87);
      else if (c >= "A" && c <= "F") v[3:0] = 4'(c - 8'd55);
      else if (c == "_")             v = v >> 4;
      else                           return 1'b0;
    end
    return 1'b1;
  endfunction

  function automatic bit [31:0] get_hex_plusarg(string name, bit [31:0] dflt);
    string     s;
    bit [31:0] v;
    if (!$value$plusargs({name, "=%s"}, s)) return dflt;
    if (!parse_hex(s, v)) $fatal(1, "[REVBM] +%s=%s is not a hex number", name, s);
    return v;
  endfunction

  // Can CHERIoT-Sail express "TRVK granule g is revoked"? Only if its base is at or above the
  // model's plat_ram_base (the model never revokes below it).
  function automatic bit granule_modelable(int unsigned g);
    longint unsigned addr;
    addr = longint'(heap_base) + 64'(g) * 8;
    return addr >= 64'(SailRamBase) && addr <= 64'hFFFF_FFF8;
  endfunction

  function automatic bit word_modelable(int unsigned w);
    // Granules rise with the address, so the lowest one decides.
    return granule_modelable(w * 32);
  endfunction

  // TRVK granule index of an absolute address, or -1 outside the window.
  function automatic longint addr_to_granule(longint unsigned addr);
    if (addr < longint'(heap_base)) return -1;
    if (addr - 64'(heap_base) >= 64'(WindowBytes)) return -1;
    return longint'((addr - 64'(heap_base)) >> 3);
  endfunction

  // Apply fn to every granule of [base, base+size) that is inside the window.
  // What = 0: revoke the granule; 1: error-inject its word.
  function automatic void mark_range(bit [31:0] base, bit [31:0] size, bit what, string src);
    longint unsigned a, last;
    int unsigned     outside;
    outside = 0;
    if (size == 0) return;
    last = longint'(base) + 64'(size) - 1;
    for (a = longint'(base) & ~64'h7; a <= last; a += 8) begin
      longint g;
      g = addr_to_granule(a);
      if (g < 0) begin
        outside++;
        continue;
      end
      if (what == 1'b0) begin
        if (!granule_modelable(int'(g))) begin
          num_unmodelable++;
          continue;
        end
        revoked_words[int'(g >> 5)][g[4:0]] = 1'b1;
      end else begin
        if (!word_modelable(int'(g >> 5))) begin
          num_unmodelable++;
          continue;
        end
        err_words[int'(g >> 5)] = 1'b1;
      end
    end
    if (outside != 0) begin
      $display("[REVBM] %s: %0d granule(s) of 0x%08x+0x%0x lie outside TRVK's window [0x%08x, 0x%09x): TRVK never looks them up, so they can never be revoked",
               src, outside, base, size, heap_base, longint'(heap_base) + 64'(WindowBytes));
    end
  endfunction

  // "b:s,b:s,..." -> mark_range for each entry.
  function automatic void mark_list(string name, bit what);
    string     s, item, b_str, s_str;
    int        i, start, colon;
    bit [31:0] b, sz;
    if (!$value$plusargs({name, "=%s"}, s)) return;
    start = 0;
    for (i = 0; i <= s.len(); i++) begin
      if (i == s.len() || s[i] == ",") begin
        item = s.substr(start, i - 1);
        start = i + 1;
        if (item.len() == 0) continue;
        colon = -1;
        for (int j = 0; j < item.len(); j++) if (item[j] == ":") colon = j;
        if (colon < 0) begin
          b_str = item;
          s_str = "8";
        end else begin
          b_str = item.substr(0, colon - 1);
          s_str = item.substr(colon + 1, item.len() - 1);
        end
        if (!parse_hex(b_str, b) || !parse_hex(s_str, sz)) begin
          $fatal(1, "[REVBM] +%s: bad entry '%s' (expected <hexbase>[:<hexsize>])", name, item);
        end
        mark_range(b, sz, what, name);
      end
    end
  endfunction

  // Default heap base, per seed. TRVK needs [2:0] == 0 (HeapBaseAligned_A) and nothing else;
  // the window must not wrap past 2^32. The mix is chosen so a regression reaches both
  // cp_trvk_out_of_range bins from both directions:
  //   0x00000000  root/full-range caps (base 0) are in range, program objects are not.
  //   0x80000000  CHERIoT-Sail's own heap base: program objects in range, base-0 caps not.
  //   otherwise   an 8-aligned base in [0x7FFF0000, 0x80010000], which splits the program
  //               image (code from 0x80000000, .data from ~0x80010000) across the edge.
  function automatic bit [31:0] draw_heap_base();
    bit [31:0] r;
    r = mix32(seed ^ 32'h4EA9_BA5E);
    case (r % 4)
      0:       return 32'h0000_0000;
      1:       return 32'h8000_0000;
      default: return (32'h7FFF_0000 + (mix32(r) % 32'h0002_0001)) & ~32'h7;
    endcase
  endfunction

  ////////////
  // Build  //
  ////////////

  // Idempotent; every accessor calls it, so call order between consumers does not matter.
  function automatic void init();
    string m, k;
    if (initialised) return;
    initialised = 1'b1;

    if (!$value$plusargs("revbm_seed=%d", seed)) seed = $urandom;

    mode = RevbmOff;
    if ($value$plusargs("revbm_mode=%s", m)) begin
      case (m)
        "off":    mode = RevbmOff;
        "random": mode = RevbmRandom;
        "range":  mode = RevbmRange;
        default:  $fatal(1, "[REVBM] +revbm_mode=%s: expected off, random or range", m);
      endcase
    end

    err_kind = RevbmErrDev;
    if ($value$plusargs("revbm_err_kind=%s", k)) begin
      case (k)
        "dev":   err_kind = RevbmErrDev;
        "intg":  err_kind = RevbmErrIntg;
        "both":  err_kind = RevbmErrBoth;
        "mixed": err_kind = RevbmErrMixed;
        default: $fatal(1, "[REVBM] +revbm_err_kind=%s: expected dev, intg, both or mixed", k);
      endcase
    end

    revoke_pct = 25;
    void'($value$plusargs("revbm_revoke_pct=%d", revoke_pct));
    err_pct = 0;
    void'($value$plusargs("revbm_err_pct=%d", err_pct));
    if (revoke_pct > 100 || err_pct > 100) $fatal(1, "[REVBM] percentages must be 0..100");
    gnt_delay_max = 0;
    void'($value$plusargs("revbm_gnt_delay_max=%d", gnt_delay_max));
    rsp_delay_max = 0;
    void'($value$plusargs("revbm_rsp_delay_max=%d", rsp_delay_max));
    cosim_unfed = $test$plusargs("revbm_cosim_unfed");

    heap_base = get_hex_plusarg("revbm_heap_base", draw_heap_base());
    if (heap_base[2:0] != 3'b0) begin
      $fatal(1, "[REVBM] +revbm_heap_base=0x%08x is not 8-byte aligned (HeapBaseAligned_A)",
             heap_base);
    end
    if (64'(heap_base) + 64'(WindowBytes) > 64'h1_0000_0000) begin
      $fatal(1, "[REVBM] +revbm_heap_base=0x%08x: the 0x%0x-byte window would wrap past 2^32",
             heap_base, WindowBytes);
    end

    foreach (revoked_words[w]) begin
      revoked_words[w] = '0;
      err_words[w]     = 1'b0;
      err_is_dev[w]    = 1'b0;
      err_is_intg[w]   = 1'b0;
    end
    num_unmodelable = 0;

    if (mode == RevbmRandom) begin
      for (int unsigned g = 0; g < NumGranules; g++) begin
        if (draw_pct(32'h5EED_0001, g) < revoke_pct) begin
          if (granule_modelable(g)) revoked_words[g >> 5][g % 32] = 1'b1;
          else                      num_unmodelable++;
        end
      end
    end

    if (mode == RevbmRange) begin
      bit [31:0] b, sz;
      if ($test$plusargs("revbm_revoke_base")) begin
        b  = get_hex_plusarg("revbm_revoke_base", 32'h0);
        sz = get_hex_plusarg("revbm_revoke_size", 32'h8);
        mark_range(b, sz, 1'b0, "revbm_revoke_base");
      end
      mark_list("revbm_revoke_list", 1'b0);
    end

    if (mode != RevbmOff) begin
      for (int unsigned w = 0; w < NumWords; w++) begin
        if (err_pct != 0 && draw_pct(32'hE220_0002, w) < err_pct) begin
          if (word_modelable(w)) err_words[w] = 1'b1;
          else                   num_unmodelable++;
        end
      end
      mark_list("revbm_err_list", 1'b1);
    end else if (err_pct != 0 || $test$plusargs("revbm_err_list")) begin
      $fatal(1, "[REVBM] error injection needs +revbm_mode=random or range");
    end

    num_revoked   = 0;
    num_err_words = 0;
    for (int unsigned w = 0; w < NumWords; w++) begin
      num_revoked += $countones(revoked_words[w]);
      if (err_words[w]) begin
        num_err_words++;
        case (err_kind)
          RevbmErrDev:  err_is_intg[w] = 1'b0;
          RevbmErrIntg: err_is_intg[w] = 1'b1;
          RevbmErrBoth: err_is_intg[w] = 1'b1;
          default:      err_is_intg[w] = mix32(seed ^ 32'h1A76_0003 ^ w) % 2 == 1;
        endcase
        err_is_dev[w] = (err_kind == RevbmErrBoth) || !err_is_intg[w];
      end
    end

    // One literal format string: see the note on [TRVK] in core_ibex_tb_top.sv.
    $display("[REVBM] mode=%s seed=%0d heap_base=0x%08x window=[0x%08x,0x%09x) revoked_granules=%0d err_words=%0d (kind %s) unmodelable_skipped=%0d gnt_delay_max=%0d rsp_delay_max=%0d%s",
             mode.name(), seed, heap_base, heap_base, longint'(heap_base) + 64'(WindowBytes),
             num_revoked, num_err_words, err_kind.name(), num_unmodelable,
             gnt_delay_max, rsp_delay_max,
             cosim_unfed ? " COSIM UNFED (negative control)" : "");
  endfunction

  ///////////////
  // Accessors //
  ///////////////

  function automatic bit is_active();
    init();
    return mode != RevbmOff;
  endfunction

  function automatic bit [31:0] get_heap_base();
    init();
    return heap_base;
  endfunction

  function automatic bit uses_intg_errors();
    init();
    for (int unsigned w = 0; w < NumWords; w++) if (err_words[w] && err_is_intg[w]) return 1'b1;
    return 1'b0;
  endfunction

  // Bitmap word at TRVK word index w, as the memory holds it.
  function automatic bit [31:0] bitmap_word(int unsigned w);
    init();
    return revoked_words[w];
  endfunction

  function automatic bit word_err(int unsigned w);
    init();
    return err_words[w];
  endfunction

  // Bitmap word w is answered with an integrity error (a flipped ECC bit).
  function automatic bit word_err_is_intg(int unsigned w);
    init();
    return err_words[w] && err_is_intg[w];
  endfunction

  // Bitmap word w is answered with trvk_revbm_err_i (alone, or with an integrity error when
  // +revbm_err_kind=both).
  function automatic bit word_dev_err(int unsigned w);
    init();
    return err_words[w] && err_is_dev[w];
  endfunction

  // TRVK's verdict for TRVK granule g: an error revokes the whole word (ibex_trvk.sv
  // revbm_revoked = rdata[bit] || err || |intg_error).
  function automatic bit granule_revoked(int unsigned g);
    init();
    return revoked_words[g >> 5][g % 32] || err_words[g >> 5];
  endfunction

  // CHERIoT-Sail shadow byte address and bit for TRVK granule g (granule_modelable(g) only).
  function automatic void sail_bit_of_granule(int unsigned g, output bit [31:0] byte_addr,
                                              output int unsigned bit_idx);
    longint unsigned addr, s;
    addr      = longint'(heap_base) + 64'(g) * 8;  // the granule's base address
    s         = (addr - 64'(SailRamBase)) >> 3;         // Sail granule (addr >= SailRamBase here)
    byte_addr = 32'(SailShadowBase + (s >> 3));
    bit_idx   = int'(s % 8);
  endfunction

endpackage
