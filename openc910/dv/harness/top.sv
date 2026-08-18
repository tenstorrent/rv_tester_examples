// SPDX-FileCopyrightText: © 2026 Tenstorrent USA, Inc.
// SPDX-License-Identifier: Apache-2.0

// Simulation top: rv_tester platform + openc910 (XuanTie C910) DUT harness
module top
    import rv_tester_params::*;
#(
  parameter int EXTERNAL_CLOCK =
  `ifdef TB_EXTERNAL_CLOCK
      1
  `else
      0
  `endif
) (
    input clk_ext [NCLKS-1:0]
);

    `RV_TESTER_VARS(cvm_topology_gen::mods)

    rv_tester #(
        .EXTERNAL_CLOCK(EXTERNAL_CLOCK),
        .TOPOLOGY(cvm_topology_gen::topology_t),
        .topology(cvm_topology_gen::mods)
    ) tester (
        .*
    );

    openc910_test_harness #(
        .TOPOLOGY(cvm_topology_gen::topology_t),
        .topology(cvm_topology_gen::mods)
    ) dut_harness (
        .*
    );

endmodule
