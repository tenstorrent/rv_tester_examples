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

    function automatic bit [NCLKS-1:0][31:0] clk_set(int unsigned tb, int unsigned core, int unsigned axi,
                                                     int unsigned soc, int unsigned ref_clk);
        bit [NCLKS-1:0][31:0] freq_mhz = '0;
        freq_mhz[TB_CLK_IDX]   = tb;
        freq_mhz[CORE_CLK_IDX] = core;
        freq_mhz[AXI_CLK_IDX]  = axi;
        freq_mhz[SOC_CLK_IDX]  = soc;
        freq_mhz[REF_CLK_IDX]  = ref_clk;
        return freq_mhz;
    endfunction

    localparam bit [NCLKS-1:0][31:0] CLOCK_FREQ_MHZ = clk_set(2000, 2000, 2000, 2000, 2000);

    localparam CLK_PROFILE_FREQ_MHZ = {
        clk_set(2700, 2700, 1600, 400, 100),
        clk_set(2700, 1600, 1600, 400, 100),
        clk_set(2700, 1000, 1600, 400, 100),
        clk_set(2700, 2700,  600, 400, 100),
        clk_set(2700, 1600,  600, 400, 100),
        clk_set(2700, 1000,  600, 400, 100),
        CLOCK_FREQ_MHZ
    };

    rv_tester #(
        .EXTERNAL_CLOCK(EXTERNAL_CLOCK),
        .CLK_PROFILE_FREQ_MHZ(CLK_PROFILE_FREQ_MHZ),
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
