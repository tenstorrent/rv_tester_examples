/*Copyright 2019-2021 T-Head Semiconductor Co., Ltd.

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
*/

// ---------------------------------------------------------------------------
// ct_rvfi_gen : RISC-V Formal Interface (RVFI) generation block for the C910.
//
// C910 is a 3-wide, out-of-order, register-renamed core; it retires up to 3
// instructions per cycle from the ROB and exports only retire-valid + retire-PC
// at its top. This block reconstructs the full per-retired-instruction RVFI
// record by capturing per-instruction metadata into an iid-keyed table at
// dispatch, filling in the GPR/FPR result at register writeback and the memory
// access at LSU commit, and reading the table out (in program order) at retire.
//
// SIMULATION / LOCKSTEP INSTRUMENTATION ONLY. Instantiated exclusively under
// `ifdef RVFI, so a normal (taped-out) build never includes it. The iid-keyed
// table below is a behavioural multi-write-port array intended for Verilator /
// event-simulation cosim, not for synthesis.
//
// All outputs are flattened (Verilog-2001 has no 2-D ports): field f of retire
// slot i occupies bus[i*W +: W].
// ---------------------------------------------------------------------------
module ct_rvfi_gen #(
  parameter NRET   = 3,      // retire ports (C910 ROB width)
  parameter NDISP  = 3,      // dispatch capture ports
  parameter NWB    = 4,      // register writeback capture ports
  parameter NLS    = 2,      // LSU commit capture ports
  parameter XLEN   = 64,
  parameter VLEN   = 40,     // C910 virtual/physical address width
  parameter IIDW   = 7       // ROB iid width (128 entries)
) (
  input                       cpuclk,
  input                       rst_b,

  // ---- retire (program order, slot 0 = oldest) ------------------------------
  input  [NRET-1:0]           retire_vld,
  input  [NRET*VLEN-1:0]      retire_pc,        // current PC of retired inst
  input  [NRET*VLEN-1:0]      retire_next_pc,   // architectural next PC
  input  [NRET*IIDW-1:0]      retire_iid,       // ROB entry id -> table index
  input  [NRET-1:0]           retire_trap,      // synchronous exception taken
  input  [NRET*XLEN-1:0]      retire_cause,     // mcause/scause value
  input  [NRET-1:0]           retire_intr,      // trap was an interrupt
  input  [NRET*2-1:0]         retire_mode,      // privilege at retire (00/01/11)

  // ---- dispatch capture (writes insn / arch-rd metadata by iid) -------------
  input  [NDISP-1:0]          disp_vld,
  input  [NDISP*IIDW-1:0]     disp_iid,
  input  [NDISP*32-1:0]       disp_insn,        // 32b insn (compressed left-aligned upstream)
  input  [NDISP*5-1:0]        disp_rd_areg,     // architectural dest reg
  input  [NDISP-1:0]          disp_rd_we,       // writes a register
  input  [NDISP-1:0]          disp_rd_fpr,      // dest is an FP register

  // ---- register writeback capture (fills rd_wdata by iid) -------------------
  input  [NWB-1:0]            wb_vld,
  input  [NWB*IIDW-1:0]       wb_iid,
  input  [NWB*XLEN-1:0]       wb_data,

  // ---- LSU commit capture (fills mem_* by iid) ------------------------------
  input  [NLS-1:0]            ls_vld,
  input  [NLS*IIDW-1:0]       ls_iid,
  input  [NLS*VLEN-1:0]       ls_addr,
  input  [NLS-1:0]            ls_is_load,
  input  [NLS*8-1:0]          ls_mask,          // byte mask within XLEN
  input  [NLS*XLEN-1:0]       ls_wdata,
  input  [NLS*XLEN-1:0]       ls_rdata,

  // ---- store-data capture (fills mem_wdata by iid, separate port because the
  //      store data resolves on a different pipe stage than the address) ------
  input                       sd_vld,
  input  [IIDW-1:0]           sd_iid,
  input  [XLEN-1:0]           sd_data,

  // ---- flattened RVFI export ------------------------------------------------
  output [NRET-1:0]           rvfi_valid,
  output [NRET*32-1:0]        rvfi_insn,
  output [NRET*XLEN-1:0]      rvfi_pc_rdata,
  output [NRET*XLEN-1:0]      rvfi_pc_wdata,
  output [NRET*5-1:0]         rvfi_rd_addr,
  output [NRET-1:0]           rvfi_rd_we,
  output [NRET-1:0]           rvfi_rd_fpr,
  output [NRET*XLEN-1:0]      rvfi_rd_wdata,
  output [NRET*XLEN-1:0]      rvfi_mem_addr,
  output [NRET*8-1:0]         rvfi_mem_rmask,
  output [NRET*8-1:0]         rvfi_mem_wmask,
  output [NRET*XLEN-1:0]      rvfi_mem_rdata,
  output [NRET*XLEN-1:0]      rvfi_mem_wdata,
  output [NRET-1:0]           rvfi_trap,
  output [NRET*XLEN-1:0]      rvfi_cause,
  output [NRET-1:0]           rvfi_intr,
  output [NRET*2-1:0]         rvfi_mode,
  output [NRET*2-1:0]         rvfi_ixl
);

  localparam DEPTH = (1 << IIDW);

  // iid-keyed metadata table.
  reg [31:0]      t_insn     [DEPTH-1:0];
  reg [4:0]       t_rd_areg  [DEPTH-1:0];
  reg             t_rd_we    [DEPTH-1:0];
  reg             t_rd_fpr   [DEPTH-1:0];
  reg [XLEN-1:0]  t_rd_data  [DEPTH-1:0];
  reg [VLEN-1:0]  t_mem_addr [DEPTH-1:0];
  reg [7:0]       t_mem_rmask[DEPTH-1:0];
  reg [7:0]       t_mem_wmask[DEPTH-1:0];
  reg [XLEN-1:0]  t_mem_rdata[DEPTH-1:0];
  reg [XLEN-1:0]  t_mem_wdata[DEPTH-1:0];

  integer d, w, l;

  // Single clocked block handling every capture write port. Ports touch either
  // distinct entries or distinct fields, so ordering is immaterial.
  always @(posedge cpuclk) begin
    // dispatch: latch decoded metadata and clear per-inst mem state
    for (d = 0; d < NDISP; d = d + 1) begin
      if (disp_vld[d]) begin
        t_insn    [disp_iid[d*IIDW +: IIDW]] <= disp_insn[d*32 +: 32];
        t_rd_areg [disp_iid[d*IIDW +: IIDW]] <= disp_rd_areg[d*5 +: 5];
        t_rd_we   [disp_iid[d*IIDW +: IIDW]] <= disp_rd_we[d];
        t_rd_fpr  [disp_iid[d*IIDW +: IIDW]] <= disp_rd_fpr[d];
        t_mem_rmask[disp_iid[d*IIDW +: IIDW]] <= 8'b0;
        t_mem_wmask[disp_iid[d*IIDW +: IIDW]] <= 8'b0;
      end
    end
    // register writeback: fill result data
    for (w = 0; w < NWB; w = w + 1) begin
      if (wb_vld[w]) begin
        t_rd_data[wb_iid[w*IIDW +: IIDW]] <= wb_data[w*XLEN +: XLEN];
      end
    end
    // LSU commit: fill memory access record
    for (l = 0; l < NLS; l = l + 1) begin
      if (ls_vld[l]) begin
        t_mem_addr [ls_iid[l*IIDW +: IIDW]] <= ls_addr[l*VLEN +: VLEN];
        t_mem_rdata[ls_iid[l*IIDW +: IIDW]] <= ls_rdata[l*XLEN +: XLEN];
        t_mem_wdata[ls_iid[l*IIDW +: IIDW]] <= ls_wdata[l*XLEN +: XLEN];
        t_mem_rmask[ls_iid[l*IIDW +: IIDW]] <=  ls_is_load[l] ? ls_mask[l*8 +: 8] : 8'b0;
        t_mem_wmask[ls_iid[l*IIDW +: IIDW]] <= !ls_is_load[l] ? ls_mask[l*8 +: 8] : 8'b0;
      end
    end
    // store data (resolves on a later pipe stage than the store address)
    if (sd_vld) begin
      t_mem_wdata[sd_iid] <= sd_data;
    end
  end

  // Retire read-out (combinational: retire uses the value captured on prior
  // cycles; writeback/LSU always precede retire in the pipeline).
  genvar i;
  generate
    for (i = 0; i < NRET; i = i + 1) begin : g_ret
      wire [IIDW-1:0] iid = retire_iid[i*IIDW +: IIDW];

      assign rvfi_valid[i]                 = retire_vld[i];
      assign rvfi_insn[i*32 +: 32]         = t_insn[iid];
      assign rvfi_pc_rdata[i*XLEN +: XLEN] = {{(XLEN-VLEN){retire_pc[i*VLEN+VLEN-1]}},
                                              retire_pc[i*VLEN +: VLEN]};
      assign rvfi_pc_wdata[i*XLEN +: XLEN] = {{(XLEN-VLEN){retire_next_pc[i*VLEN+VLEN-1]}},
                                              retire_next_pc[i*VLEN +: VLEN]};
      assign rvfi_rd_addr[i*5 +: 5]        = t_rd_areg[iid];
      assign rvfi_rd_we[i]                 = t_rd_we[iid];
      assign rvfi_rd_fpr[i]                = t_rd_fpr[iid];
      assign rvfi_rd_wdata[i*XLEN +: XLEN] = t_rd_data[iid];
      assign rvfi_mem_addr[i*XLEN +: XLEN] = {{(XLEN-VLEN){1'b0}}, t_mem_addr[iid]};
      assign rvfi_mem_rmask[i*8 +: 8]      = t_mem_rmask[iid];
      assign rvfi_mem_wmask[i*8 +: 8]      = t_mem_wmask[iid];
      assign rvfi_mem_rdata[i*XLEN +: XLEN]= t_mem_rdata[iid];
      assign rvfi_mem_wdata[i*XLEN +: XLEN]= t_mem_wdata[iid];
      assign rvfi_trap[i]                  = retire_trap[i];
      assign rvfi_cause[i*XLEN +: XLEN]    = retire_cause[i*XLEN +: XLEN];
      assign rvfi_intr[i]                  = retire_intr[i];
      assign rvfi_mode[i*2 +: 2]           = retire_mode[i*2 +: 2];
      assign rvfi_ixl[i*2 +: 2]            = 2'b10; // XLEN=64
    end
  endgenerate

endmodule
