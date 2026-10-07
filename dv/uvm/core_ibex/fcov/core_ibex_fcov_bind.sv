// Copyright lowRISC contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

module core_ibex_fcov_bind;
  bind ibex_core core_ibex_fcov_if
  #(.ICache(ICache),
    .BranchTargetALU(BranchTargetALU)
  ) u_fcov_bind (
    .*
  );

  bind ibex_core core_ibex_pmp_fcov_if
  #(.PMPGranularity(PMPGranularity),
    .PMPNumRegions(PMPNumRegions),
    .PMPEnable(PMPEnable)
  ) u_pmp_fcov_bind (
    .*
  );

  // TRVK is instantiated at ibex_top (i_ibex_trvk), outside the ibex_core scope the
  // two binds above use, so it needs its own bind to the module itself.
  bind ibex_trvk core_ibex_trvk_fcov_if u_trvk_fcov_bind (
    .*
  );
endmodule
