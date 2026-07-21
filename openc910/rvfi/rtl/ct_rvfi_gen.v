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
// C910 is a 3-wide, out-of-order, register-renamed core. Its ROB packs up to
// 3 sequential instructions into ONE ROB entry ("packet", one iid): entry
// fields carry INST_NUM (1..3) and a total PC span. Retire is therefore
// per-packet, exposing only each packet's base PC. This block reconstructs a
// per-instruction RVFI stream by:
//   * capturing, at dispatch, each packet's per-instruction metadata
//     (length, arch-rd, dst physical reg) keyed by (iid, sub-index),
//   * filling result data into a physical-register-keyed table at writeback
//     (writeback is per-preg, hence naturally per-instruction),
//   * at retire, unpacking each retiring packet (base PC from the retire
//     interface + captured per-sub lengths) into up to 3 per-instruction
//     records and flattening the (<=3 total) records onto the output lanes.
//
// SIMULATION / LOCKSTEP INSTRUMENTATION ONLY (instantiated under `ifdef RVFI).
// The tables are behavioural multi-write-port arrays for Verilator cosim.
//
// All ports are flattened (Verilog-2001 has no 2-D ports); field f of slot i
// occupies bus[i*W +: W].
// ---------------------------------------------------------------------------
module ct_rvfi_gen #(
  parameter NENT  = 4,       // ROB create entries (packets) per cycle
  parameter NRET  = 3,       // retire packet lanes (ROB retire width)
  parameter NOUT  = 3,       // per-instruction output records / cycle (3-wide)
  parameter NWB   = 5,       // register writeback capture ports
  parameter MAXPK = 3,       // max instructions per packet
  parameter XLEN  = 64,
  parameter VLEN  = 40,      // C910 virtual/physical address width (byte PC)
  parameter IIDW  = 7,       // ROB iid width (128 entries)
  parameter PREGW = 7        // physical register index width
) (
  input                       cpuclk,
  input                       rst_b,

  // ---- dispatch: NENT create entries (packets), each with up to MAXPK subs --
  input  [NENT-1:0]           disp_ent_vld,
  input  [NENT*IIDW-1:0]      disp_ent_iid,
  input  [NENT*2-1:0]         disp_ent_num,   // instructions in packet: 1..3
  // NENT physical dispatch slots (program order); an entry e owns the
  // contiguous slots [start_e, start_e+num_e), start_e = sum of prior nums.
  input  [NENT*3-1:0]         disp_slot_len,     // per-slot length in halfwords
  input  [NENT*5-1:0]         disp_slot_rd_areg,
  input  [NENT-1:0]           disp_slot_rd_we,
  input  [NENT-1:0]           disp_slot_rd_fpr,
  input  [NENT*PREGW-1:0]     disp_slot_preg,
  input  [NENT*32-1:0]        disp_slot_insn,    // per-slot instruction word

  // ---- register writeback capture (preg-keyed result data) -----------------
  input  [NWB-1:0]            wb_vld,
  input  [NWB*PREGW-1:0]      wb_preg,
  input  [NWB*XLEN-1:0]       wb_data,

  // ---- retire (per packet lane; program order, lane 0 = oldest) ------------
  input  [NRET-1:0]           retire_vld,
  input  [NRET*IIDW-1:0]      retire_iid,
  input  [NRET*VLEN-1:0]      retire_base_pc,  // packet base byte PC
  input  [NRET-1:0]           retire_split,    // ROB entry is a non-final micro-op
  input  [NRET-1:0]           retire_trap,
  input  [NRET*XLEN-1:0]      retire_cause,
  input  [NRET-1:0]           retire_intr,
  input  [NRET*2-1:0]         retire_mode,

  // ---- flattened per-instruction RVFI export -------------------------------
  output [NOUT-1:0]           rvfi_valid,
  output [NOUT*32-1:0]        rvfi_insn,
  output [NOUT*XLEN-1:0]      rvfi_pc_rdata,
  output [NOUT*XLEN-1:0]      rvfi_pc_wdata,
  output [NOUT*5-1:0]         rvfi_rd_addr,
  output [NOUT-1:0]           rvfi_rd_we,
  output [NOUT-1:0]           rvfi_rd_fpr,
  output [NOUT*XLEN-1:0]      rvfi_rd_wdata,
  output [NOUT*XLEN-1:0]      rvfi_mem_addr,
  output [NOUT*8-1:0]         rvfi_mem_rmask,
  output [NOUT*8-1:0]         rvfi_mem_wmask,
  output [NOUT*XLEN-1:0]      rvfi_mem_rdata,
  output [NOUT*XLEN-1:0]      rvfi_mem_wdata,
  output [NOUT-1:0]           rvfi_trap,
  output [NOUT*XLEN-1:0]      rvfi_cause,
  output [NOUT-1:0]           rvfi_intr,
  output [NOUT*2-1:0]         rvfi_mode,
  output [NOUT*2-1:0]         rvfi_ixl,
  output [NOUT-1:0]           rvfi_last_uop
);

  localparam DEPTH = (1 << IIDW);
  localparam PDEPTH = (1 << PREGW);

  // iid-keyed packet table: MAXPK sub-instructions packed per word.
  reg [1:0]           t_num    [DEPTH-1:0];             // instructions in packet
  reg [MAXPK*3-1:0]   t_len    [DEPTH-1:0];             // per-sub length (hw)
  reg [MAXPK*5-1:0]   t_rd_areg[DEPTH-1:0];
  reg [MAXPK-1:0]     t_rd_we  [DEPTH-1:0];
  reg [MAXPK-1:0]     t_rd_fpr [DEPTH-1:0];
  reg [MAXPK*PREGW-1:0] t_preg [DEPTH-1:0];
  reg [MAXPK*32-1:0]  t_insn   [DEPTH-1:0];             // per-sub instruction word
  // ir_inst*_opcode are one pipe stage (1 cycle) ahead of the is_dis/pst_dis
  // dispatch slots, so delay them one cycle to align with the dispatch capture.
  reg [NENT*32-1:0]   disp_insn_ff;
  // physical-register-keyed writeback data.
  reg [XLEN-1:0]      t_preg_data [PDEPTH-1:0];
  // per-preg "written since dispatch" scoreboard. C910 retires loads that miss
  // the dcache BEFORE their data writeback lands (non-blocking retire), so a
  // retired load's rd result may not be in t_preg_data yet at retire; this bit
  // lets the retire read-out stall until the writeback actually occurs.
  reg [PDEPTH-1:0]    t_preg_ready;

  integer e, k, w;
  integer start_slot;

  // ---- capture: dispatch (packet metadata) + writeback (preg data) ---------
  always @(posedge cpuclk) begin
    disp_insn_ff <= disp_slot_insn;
    start_slot = 0;
    for (e = 0; e < NENT; e = e + 1) begin
      if (disp_ent_vld[e]) begin
        t_num[disp_ent_iid[e*IIDW +: IIDW]] <= disp_ent_num[e*2 +: 2];
        for (k = 0; k < MAXPK; k = k + 1) begin
          // sub k of entry e is physical slot (start_slot + k)
          t_len   [disp_ent_iid[e*IIDW +: IIDW]][k*3 +: 3]       <= disp_slot_len[((start_slot+k) % NENT)*3 +: 3];
          t_rd_areg[disp_ent_iid[e*IIDW +: IIDW]][k*5 +: 5]      <= disp_slot_rd_areg[((start_slot+k) % NENT)*5 +: 5];
          t_rd_we [disp_ent_iid[e*IIDW +: IIDW]][k]              <= disp_slot_rd_we[(start_slot+k) % NENT];
          t_rd_fpr[disp_ent_iid[e*IIDW +: IIDW]][k]              <= disp_slot_rd_fpr[(start_slot+k) % NENT];
          t_preg  [disp_ent_iid[e*IIDW +: IIDW]][k*PREGW +: PREGW] <= disp_slot_preg[((start_slot+k) % NENT)*PREGW +: PREGW];
          t_insn  [disp_ent_iid[e*IIDW +: IIDW]][k*32 +: 32]      <= disp_insn_ff[((start_slot+k) % NENT)*32 +: 32];
          // a newly-allocated destination preg has not been written yet
          if (k < disp_ent_num[e*2 +: 2])
            t_preg_ready[disp_slot_preg[((start_slot+k) % NENT)*PREGW +: PREGW]] <= 1'b0;
        end
        start_slot = start_slot + disp_ent_num[e*2 +: 2];
      end
    end
    // writeback set AFTER dispatch clear so a same-cycle write wins.
    for (w = 0; w < NWB; w = w + 1) begin
      if (wb_vld[w]) begin
        t_preg_data [wb_preg[w*PREGW +: PREGW]] <= wb_data[w*XLEN +: XLEN];
        t_preg_ready[wb_preg[w*PREGW +: PREGW]] <= 1'b1;
      end
    end
  end

  // ---- retire read-out: unpack packets, flatten to <=NOUT records ----------
  // For each retiring lane, expand num sub-instructions in program order and
  // assign them to output records via a running index.
  reg [NOUT-1:0]      o_valid;
  reg [NOUT*32-1:0]   o_insn;
  reg [NOUT*XLEN-1:0] o_pc_rdata;
  reg [NOUT*XLEN-1:0] o_pc_wdata;
  reg [NOUT*5-1:0]    o_rd_addr;
  reg [NOUT-1:0]      o_rd_we;
  reg [NOUT-1:0]      o_rd_fpr;
  reg [NOUT*XLEN-1:0] o_rd_wdata;
  reg [NOUT-1:0]      o_trap;
  reg [NOUT*XLEN-1:0] o_cause;
  reg [NOUT-1:0]      o_intr;
  reg [NOUT*2-1:0]    o_mode;
  reg [NOUT-1:0]      o_last_uop;

  // ---- in-order retire FIFO ------------------------------------------------
  // C910 retires loads that miss the dcache BEFORE their data writeback lands.
  // Each cycle we push all retired sub-records into a FIFO and drain from the
  // head only when the head record's destination preg is ready (written). This
  // preserves program order, never drops a record, and stalls exactly the
  // records that depend on a not-yet-written result. The cosim is order-based,
  // so the extra (data-dependent) latency is harmless.
  localparam MAXR   = NRET * MAXPK;   // max sub-records retired per cycle
  localparam FDEPTH = 128;
  localparam FIDXW  = 7;              // log2(FDEPTH): array index width
  localparam FPTRW  = 8;              // FIDXW + 1 wrap bit (full/empty distinct)

  reg [XLEN-1:0]  f_pcr  [FDEPTH-1:0];
  reg [XLEN-1:0]  f_pcw  [FDEPTH-1:0];
  reg [4:0]       f_rda  [FDEPTH-1:0];
  reg             f_rdwe [FDEPTH-1:0];
  reg             f_rdfpr[FDEPTH-1:0];
  reg [PREGW-1:0] f_preg [FDEPTH-1:0];
  reg             f_trap [FDEPTH-1:0];
  reg [XLEN-1:0]  f_cause[FDEPTH-1:0];
  reg             f_intr [FDEPTH-1:0];
  reg [1:0]       f_mode [FDEPTH-1:0];
  reg             f_luop [FDEPTH-1:0];
  reg [31:0]      f_insn [FDEPTH-1:0];
  reg [FPTRW-1:0] fhead, ftail;

  // push candidates: this cycle's retired sub-records, compacted [0..p_cnt).
  reg [XLEN-1:0]  p_pcr  [MAXR-1:0];
  reg [XLEN-1:0]  p_pcw  [MAXR-1:0];
  reg [4:0]       p_rda  [MAXR-1:0];
  reg             p_rdwe [MAXR-1:0];
  reg             p_rdfpr[MAXR-1:0];
  reg [PREGW-1:0] p_preg [MAXR-1:0];
  reg             p_trap [MAXR-1:0];
  reg [XLEN-1:0]  p_cause[MAXR-1:0];
  reg             p_intr [MAXR-1:0];
  reg [1:0]       p_mode [MAXR-1:0];
  reg             p_luop [MAXR-1:0];
  reg [31:0]      p_insn [MAXR-1:0];
  integer         p_cnt;

  integer l, oi, di, pi, fi;
  reg [FPTRW-1:0] idx;
  reg [FPTRW-1:0] occ;    // occupancy, computed in pointer width so it wraps
  reg             stopped;
  reg [IIDW-1:0]   iid;
  reg [1:0]        num;
  reg [VLEN-1:0]   base_pc;
  reg [VLEN-1:0]   cur_pc;
  reg [PREGW-1:0]  preg;
  reg [XLEN-1:0]   pc_sx;
  reg [XLEN-1:0]   nxt_sx;
  reg [VLEN-1:0]   nxt_pc;
  reg [XLEN-1:0]   rd_val;

  // Read the physical-register result for `preg`, with same-cycle writeback
  // forwarding (the clocked table covers writebacks from prior cycles; the
  // bypass covers an instruction that retires the same cycle its result is
  // written back, common for the fast in-order register-init sequence).
  function [XLEN-1:0] preg_read;
    input [PREGW-1:0] p;
    integer wi;
    begin
      preg_read = t_preg_data[p];
      for (wi = 0; wi < NWB; wi = wi + 1) begin
        if (wb_vld[wi] && (wb_preg[wi*PREGW +: PREGW] == p))
          preg_read = wb_data[wi*XLEN +: XLEN];
      end
    end
  endfunction

  // A preg's result is available if it has been written since dispatch, or is
  // being written this cycle (same-cycle bypass, matching preg_read).
  function preg_ready_f;
    input [PREGW-1:0] p;
    integer wi;
    begin
      preg_ready_f = t_preg_ready[p];
      for (wi = 0; wi < NWB; wi = wi + 1) begin
        if (wb_vld[wi] && (wb_preg[wi*PREGW +: PREGW] == p))
          preg_ready_f = 1'b1;
      end
    end
  endfunction

  // ---- push flatten: unpack this cycle's retiring packets into p_* records --
  always @(*) begin
    for (pi = 0; pi < MAXR; pi = pi + 1) begin
      p_pcr[pi]  = {XLEN{1'b0}}; p_pcw[pi]  = {XLEN{1'b0}};
      p_rda[pi]  = 5'b0;         p_rdwe[pi] = 1'b0;
      p_rdfpr[pi]= 1'b0;         p_preg[pi] = {PREGW{1'b0}};
      p_trap[pi] = 1'b0;         p_cause[pi]= {XLEN{1'b0}};
      p_intr[pi] = 1'b0;         p_mode[pi] = 2'b0;
      p_luop[pi] = 1'b1;         p_insn[pi] = 32'b0;
    end
    oi = 0;
    for (l = 0; l < NRET; l = l + 1) begin
      if (retire_vld[l]) begin
        iid     = retire_iid[l*IIDW +: IIDW];
        num     = t_num[iid];
        base_pc = retire_base_pc[l*VLEN +: VLEN];
        cur_pc  = base_pc;
        for (k = 0; k < MAXPK; k = k + 1) begin
          if ((k < num) && (oi < MAXR)) begin
            preg   = t_preg[iid][k*PREGW +: PREGW];
            nxt_pc = cur_pc + {{(VLEN-4){1'b0}}, t_len[iid][k*3 +: 3], 1'b0}; // +2*len bytes
            p_pcr[oi]  = {{(XLEN-VLEN){cur_pc[VLEN-1]}}, cur_pc};
            p_pcw[oi]  = {{(XLEN-VLEN){nxt_pc[VLEN-1]}}, nxt_pc};
            p_rda[oi]  = t_rd_areg[iid][k*5 +: 5];
            // a write to x0 is architecturally a no-op: C910 may flag rd_we but
            // never writes back, so it must not block the retire FIFO waiting
            // for a preg that never becomes ready.
            p_rdwe[oi] = t_rd_we[iid][k] && (t_rd_areg[iid][k*5 +: 5] != 5'b0)
                         && !t_rd_fpr[iid][k];
            p_rdfpr[oi]= t_rd_fpr[iid][k];
            p_preg[oi] = preg;
            // trap/cause/intr reported on the last sub of the packet
            if (k == (num - 1)) begin
              p_trap[oi]  = retire_trap[l];
              p_cause[oi] = retire_cause[l*XLEN +: XLEN];
              p_intr[oi]  = retire_intr[l];
            end
            p_mode[oi] = retire_mode[l*2 +: 2];
            p_insn[oi] = t_insn[iid][k*32 +: 32];
            // ROB_SPLIT marks a non-final micro-op of a cracked instruction
            // (jal/jalr/amo); last_uop=0 so the cosim coalesces it.
            p_luop[oi] = ~retire_split[l];
            cur_pc = nxt_pc;
            oi = oi + 1;
          end
        end
      end
    end
    p_cnt = oi;
  end

  // ---- pop: drain head records whose destination result is ready -----------
  always @(*) begin
    o_valid    = {NOUT{1'b0}};
    o_insn     = {(NOUT*32){1'b0}};
    o_pc_rdata = {(NOUT*XLEN){1'b0}};
    o_pc_wdata = {(NOUT*XLEN){1'b0}};
    o_rd_addr  = {(NOUT*5){1'b0}};
    o_rd_we    = {NOUT{1'b0}};
    o_rd_fpr   = {NOUT{1'b0}};
    o_rd_wdata = {(NOUT*XLEN){1'b0}};
    o_trap     = {NOUT{1'b0}};
    o_cause    = {(NOUT*XLEN){1'b0}};
    o_intr     = {NOUT{1'b0}};
    o_mode     = {(NOUT*2){1'b0}};
    o_last_uop = {NOUT{1'b1}};
    stopped    = 1'b0;
    occ        = ftail - fhead;   // FPTRW-bit subtraction: wraps correctly
    for (di = 0; di < NOUT; di = di + 1) begin
      idx = (fhead + di[FPTRW-1:0]) & {{(FPTRW-FIDXW){1'b0}}, {FIDXW{1'b1}}};
      // entry di present and its result ready, and no earlier stall
      if (!stopped && (occ > di[FPTRW-1:0]) &&
          (!f_rdwe[idx[FIDXW-1:0]] || preg_ready_f(f_preg[idx[FIDXW-1:0]]))) begin
        o_valid[di]                 = 1'b1;
        o_pc_rdata[di*XLEN +: XLEN] = f_pcr[idx[FIDXW-1:0]];
        o_pc_wdata[di*XLEN +: XLEN] = f_pcw[idx[FIDXW-1:0]];
        o_rd_addr[di*5 +: 5]        = f_rda[idx[FIDXW-1:0]];
        o_rd_we[di]                 = f_rdwe[idx[FIDXW-1:0]];
        o_rd_fpr[di]                = f_rdfpr[idx[FIDXW-1:0]];
        o_rd_wdata[di*XLEN +: XLEN] = f_rdwe[idx[FIDXW-1:0]] ? preg_read(f_preg[idx[FIDXW-1:0]]) : {XLEN{1'b0}};
        o_trap[di]                  = f_trap[idx[FIDXW-1:0]];
        o_cause[di*XLEN +: XLEN]    = f_cause[idx[FIDXW-1:0]];
        o_intr[di]                  = f_intr[idx[FIDXW-1:0]];
        o_mode[di*2 +: 2]           = f_mode[idx[FIDXW-1:0]];
        o_last_uop[di]              = f_luop[idx[FIDXW-1:0]];
        o_insn[di*32 +: 32]         = f_insn[idx[FIDXW-1:0]];
      end else begin
        stopped = 1'b1;
      end
    end
  end

  // count of records drained this cycle = number of valid outputs.
  reg [FPTRW-1:0] drained;
  always @(*) begin
    drained = {FPTRW{1'b0}};
    for (di = 0; di < NOUT; di = di + 1)
      if (o_valid[di]) drained = drained + 1'b1;
  end


  // ---- FIFO pointer/storage update -----------------------------------------
  always @(posedge cpuclk) begin
    if (rst_b == 1'b0) begin
      fhead <= {FPTRW{1'b0}};
      ftail <= {FPTRW{1'b0}};
    end else begin
      for (fi = 0; fi < MAXR; fi = fi + 1) begin
        if (fi < p_cnt) begin
          idx                      = (ftail + fi[FPTRW-1:0]) & {{(FPTRW-FIDXW){1'b0}}, {FIDXW{1'b1}}};
          f_pcr  [idx[FIDXW-1:0]] <= p_pcr[fi];
          f_pcw  [idx[FIDXW-1:0]] <= p_pcw[fi];
          f_rda  [idx[FIDXW-1:0]] <= p_rda[fi];
          f_rdwe [idx[FIDXW-1:0]] <= p_rdwe[fi];
          f_rdfpr[idx[FIDXW-1:0]] <= p_rdfpr[fi];
          f_preg [idx[FIDXW-1:0]] <= p_preg[fi];
          f_trap [idx[FIDXW-1:0]] <= p_trap[fi];
          f_cause[idx[FIDXW-1:0]] <= p_cause[fi];
          f_intr [idx[FIDXW-1:0]] <= p_intr[fi];
          f_mode [idx[FIDXW-1:0]] <= p_mode[fi];
          f_luop [idx[FIDXW-1:0]] <= p_luop[fi];
          f_insn [idx[FIDXW-1:0]] <= p_insn[fi];
        end
      end
      ftail <= ftail + p_cnt[FPTRW-1:0];
      fhead <= fhead + drained;
    end
  end

  assign rvfi_valid    = o_valid;
  assign rvfi_insn     = o_insn;      // per-slot instruction word from ct_idu_ir_dp
  assign rvfi_pc_rdata = o_pc_rdata;
  assign rvfi_pc_wdata = o_pc_wdata;
  assign rvfi_rd_addr  = o_rd_addr;
  assign rvfi_rd_we    = o_rd_we;
  assign rvfi_rd_fpr   = o_rd_fpr;
  assign rvfi_rd_wdata = o_rd_wdata;
  assign rvfi_mem_addr  = {(NOUT*XLEN){1'b0}};
  assign rvfi_mem_rmask = {(NOUT*8){1'b0}};
  assign rvfi_mem_wmask = {(NOUT*8){1'b0}};
  assign rvfi_mem_rdata = {(NOUT*XLEN){1'b0}};
  assign rvfi_mem_wdata = {(NOUT*XLEN){1'b0}};
  assign rvfi_trap     = o_trap;
  assign rvfi_cause    = o_cause;
  assign rvfi_intr     = o_intr;
  assign rvfi_mode     = o_mode;
  assign rvfi_last_uop = o_last_uop;

  genvar g;
  generate
    for (g = 0; g < NOUT; g = g + 1) begin : g_ixl
      assign rvfi_ixl[g*2 +: 2] = 2'b10; // XLEN=64
    end
  endgenerate

endmodule
