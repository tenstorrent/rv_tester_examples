// SPDX-FileCopyrightText: © 2026 Tenstorrent USA, Inc.
// SPDX-License-Identifier: Apache-2.0

// Simulation top: the rv_tester platform plus the CVA6 DUT harness, wired
// together by name (`.*`) through the nets the `RV_TESTER_VARS` macro
// declares. `cvm_topology_gen` is emitted by the topology_gen genrule.
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

    cva6_test_harness #(
        .TOPOLOGY(cvm_topology_gen::topology_t),
        .topology(cvm_topology_gen::mods)
    ) dut_harness (
        .*
    );

endmodule
