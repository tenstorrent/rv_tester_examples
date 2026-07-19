#!/usr/bin/env python3
# SPDX-FileCopyrightText: © 2026 Tenstorrent USA, Inc.
# SPDX-License-Identifier: Apache-2.0
"""Apply the RVFI export taps + cold-boot bring-up edits onto a fetched
XUANTIE-RV/openc910 tree, in place. Invoked by //bazel:openc910_ext.bzl during
the @openc910 repository fetch (instead of a unified-diff patch) so the edits
are deterministic and robust to upstream whitespace.

Usage: apply_rvfi.py <repo_root>
  <repo_root> is the root of the fetched openc910 checkout (contains
  C910_RTL_FACTORY/gen_rtl/...).

All RTL edits are guarded by `ifdef RVFI so a non-RVFI build is byte-identical
to upstream. See openc910/README.md sections 2-3 and 6 for the design.
"""
import os
import re
import sys

ROOT = os.path.join(sys.argv[1], "C910_RTL_FACTORY", "gen_rtl")

def rd(f):
    with open(os.path.join(ROOT, f)) as fh:
        return fh.read()

def wr(f, s):
    with open(os.path.join(ROOT, f), "w") as fh:
        fh.write(s)

# Flattened RVFI export bus (NRET=3); field f of slot i occupies [i*W +: W].
PORTS = [("rvfi_valid", 2), ("rvfi_insn", 95), ("rvfi_pc_rdata", 191),
         ("rvfi_pc_wdata", 191), ("rvfi_rd_addr", 14), ("rvfi_rd_we", 2),
         ("rvfi_rd_fpr", 2), ("rvfi_rd_wdata", 191), ("rvfi_mem_addr", 191),
         ("rvfi_mem_rmask", 23), ("rvfi_mem_wmask", 23), ("rvfi_mem_rdata", 191),
         ("rvfi_mem_wdata", 191), ("rvfi_trap", 2), ("rvfi_cause", 191),
         ("rvfi_intr", 2), ("rvfi_mode", 5), ("rvfi_ixl", 5)]

def pnames(pfx=""):
    return [pfx + n for (n, _) in PORTS]

def pdecls(pfx=""):
    return "\n".join("output [%d :0]  %s;" % (m, pfx + n) for (n, m) in PORTS)

def decl(n, m, kw="output"):
    return ("%s %s;" % (kw, n)) if m == 0 else ("%s [%d :0]  %s;" % (kw, m, n))

def require(cond, msg):
    if not cond:
        sys.stderr.write("apply_rvfi: ERROR: " + msg + "\n")
        sys.exit(1)

# ---- ct_rtu_rob.v : export 4 universal per-slot create iids ----
r = rd("rtu/rtl/ct_rtu_rob.v")
require("module ct_rtu_rob(\n" in r, "ct_rtu_rob module header not found")
r = r.replace("module ct_rtu_rob(\n",
    "module ct_rtu_rob(\n`ifdef RVFI\n" +
    "\n".join("  rvfi_rob_create%d_iid," % i for i in range(4)) + "\n`endif\n", 1)
r = r.replace("\nendmodule",
    "\n`ifdef RVFI\n" +
    "\n".join("output [6 :0]  rvfi_rob_create%d_iid;" % i for i in range(4)) + "\n" +
    "\n".join("assign rvfi_rob_create%d_iid[6:0] = rob_create%d_iid[6:0];" % (i, i) for i in range(4)) +
    "\n`endif\n\nendmodule", 1)
wr("rtu/rtl/ct_rtu_rob.v", r)

# ---- ct_rtu_top.v : pass create iids + export retire next_pc/trap/cause ----
RTOP = [("rvfi_rob_create0_iid", 6, "rvfi_rob_create0_iid"),
        ("rvfi_rob_create1_iid", 6, "rvfi_rob_create1_iid"),
        ("rvfi_rob_create2_iid", 6, "rvfi_rob_create2_iid"),
        ("rvfi_rob_create3_iid", 6, "rvfi_rob_create3_iid"),
        ("rvfi_retire0_next_pc", 38, "rob_retire_inst0_next_pc"),
        ("rvfi_retire1_next_pc", 38, "rob_retire_inst1_next_pc"),
        ("rvfi_retire2_next_pc", 38, "rob_retire_inst2_next_pc"),
        ("rvfi_retire0_expt_vld", 0, "rob_retire_inst0_expt_vld"),
        ("rvfi_retire0_expt_vec", 3, "rob_retire_inst0_expt_vec"),
        ("rvfi_retire0_int_vld", 0, "rob_retire_inst0_int_vld"),
        ("rvfi_retire0_int_vec", 4, "rob_retire_inst0_int_vec")]
t = rd("rtu/rtl/ct_rtu_top.v")
require("module ct_rtu_top(\n" in t and "ct_rtu_rob  x_ct_rtu_rob (\n" in t,
        "ct_rtu_top anchors not found")
t = t.replace("module ct_rtu_top(\n",
    "module ct_rtu_top(\n`ifdef RVFI\n" +
    "\n".join("  %s," % n for (n, _, _) in RTOP) + "\n`endif\n", 1)
t = t.replace("\nendmodule",
    "\n`ifdef RVFI\n" + "\n".join(decl(n, m) for (n, m, _) in RTOP) + "\n" +
    "\n".join("assign %s = %s;" % (n, src) for (n, _, src) in RTOP if n != src) +
    "\n`endif\n\nendmodule", 1)
t = t.replace("ct_rtu_rob  x_ct_rtu_rob (\n",
    "ct_rtu_rob  x_ct_rtu_rob (\n`ifdef RVFI\n" +
    "\n".join("  .rvfi_rob_create%d_iid                (rvfi_rob_create%d_iid               )," % (i, i) for i in range(4)) +
    "\n`endif\n", 1)
wr("rtu/rtl/ct_rtu_top.v", t)

# ---- ct_lsu_top.v : export load/store DA taps + store-data (sd_ex1) ----
LSU = [("rvfi_ld_da_addr", 39, "ld_da_addr"), ("rvfi_ld_da_bytes_vld", 15, "ld_da_bytes_vld"),
       ("rvfi_ld_da_data", 63, "ld_da_data_ori"), ("rvfi_ld_da_iid", 6, "ld_da_iid"),
       ("rvfi_ld_da_inst_vld", 0, "ld_da_inst_vld"),
       ("rvfi_st_da_addr", 39, "st_da_addr"), ("rvfi_st_da_bytes_vld", 15, "st_da_sf_bytes_vld"),
       ("rvfi_st_da_iid", 6, "st_da_iid"), ("rvfi_st_da_inst_vld", 0, "st_da_inst_vld"),
       ("rvfi_sd_data", 63, "sd_ex1_data"), ("rvfi_sd_inst_vld", 0, "sd_ex1_inst_vld")]
l = rd("lsu/rtl/ct_lsu_top.v")
require("module ct_lsu_top(\n" in l, "ct_lsu_top module header not found")
l = l.replace("module ct_lsu_top(\n",
    "module ct_lsu_top(\n`ifdef RVFI\n" +
    "\n".join("  %s," % n for (n, _, _) in LSU) + "\n`endif\n", 1)
l = l.replace("\nendmodule",
    "\n`ifdef RVFI\n" + "\n".join(decl(n, m) for (n, m, _) in LSU) + "\n" +
    "\n".join("assign %s = %s;" % (n, src) for (n, _, src) in LSU) +
    "\n`endif\n\nendmodule", 1)
wr("lsu/rtl/ct_lsu_top.v", l)

# ---- ct_core.v : wires + connections + ct_rvfi_gen instance ----
c = rd("cpu/rtl/ct_core.v")
require("module ct_core(\n" in c and "ct_rtu_top  x_ct_rtu_top (\n" in c
        and "ct_lsu_top  x_ct_lsu_top (\n" in c
        and "\n// &ModuleEnd; @91\nendmodule" in c, "ct_core anchors not found")
c = c.replace("module ct_core(\n",
    "module ct_core(\n`ifdef RVFI\n" +
    "\n".join("  %s," % n for n in pnames()) + "\n`endif\n", 1)

rtu_wires = "\n".join(decl(n, m, "wire") for (n, m, _) in RTOP)
rtu_conn = "\n".join("  .%-22s (%s)," % (n, n) for (n, _, _) in RTOP)
c = c.replace("ct_rtu_top  x_ct_rtu_top (\n",
    "`ifdef RVFI\n" + rtu_wires + "\n`endif\nct_rtu_top  x_ct_rtu_top (\n`ifdef RVFI\n" +
    rtu_conn + "\n`endif\n", 1)

lsu_wires = "\n".join(decl(n, m, "wire") for (n, m, _) in LSU)
lsu_wires += "\nwire [7 :0]  rvfi_ld_mask8;\nwire [7 :0]  rvfi_st_mask8;\nreg  [6 :0]  rvfi_sd_iid_ff;\n"
lsu_wires += "assign rvfi_ld_mask8 = rvfi_ld_da_addr[3] ? rvfi_ld_da_bytes_vld[15:8] : rvfi_ld_da_bytes_vld[7:0];\n"
lsu_wires += "assign rvfi_st_mask8 = rvfi_st_da_addr[3] ? rvfi_st_da_bytes_vld[15:8] : rvfi_st_da_bytes_vld[7:0];\n"
lsu_wires += "always @(posedge forever_cpuclk) rvfi_sd_iid_ff[6:0] <= idu_lsu_rf_pipe4_iid[6:0];"
lsu_conn = "\n".join("  .%-22s (%s)," % (n, n) for (n, _, _) in LSU)
c = c.replace("ct_lsu_top  x_ct_lsu_top (\n",
    "`ifdef RVFI\n" + lsu_wires + "\n`endif\nct_lsu_top  x_ct_lsu_top (\n`ifdef RVFI\n" +
    lsu_conn + "\n`endif\n", 1)

cause0 = ("(rvfi_retire0_int_vld ? {1'b1, 58'b0, rvfi_retire0_int_vec[4:0]} : "
          "{60'b0, rvfi_retire0_expt_vec[3:0]})")
conn = [
    ("cpuclk", "forever_cpuclk"), ("rst_b", "idu_rst_b"),
    ("retire_vld", "{rtu_pad_retire2, rtu_pad_retire1, rtu_pad_retire0}"),
    ("retire_pc", "{rtu_pad_retire2_pc, rtu_pad_retire1_pc, rtu_pad_retire0_pc}"),
    ("retire_next_pc", "{ {rvfi_retire2_next_pc[38:0],1'b0}, {rvfi_retire1_next_pc[38:0],1'b0}, {rvfi_retire0_next_pc[38:0],1'b0} }"),
    ("retire_iid", "{rtu_yy_xx_commit2_iid, rtu_yy_xx_commit1_iid, rtu_yy_xx_commit0_iid}"),
    ("retire_trap", "{2'b0, (rvfi_retire0_expt_vld | rvfi_retire0_int_vld)}"),
    ("retire_cause", "{128'b0, " + cause0 + "}"),
    ("retire_intr", "{2'b0, rvfi_retire0_int_vld}"),
    ("retire_mode", "{cp0_yy_priv_mode, cp0_yy_priv_mode, cp0_yy_priv_mode}"),
    ("disp_vld", "{idu_rtu_rob_create3_dp_en, idu_rtu_rob_create2_dp_en, idu_rtu_rob_create1_dp_en, idu_rtu_rob_create0_dp_en}"),
    ("disp_iid", "{rvfi_rob_create3_iid, rvfi_rob_create2_iid, rvfi_rob_create1_iid, rvfi_rob_create0_iid}"),
    ("disp_insn", "128'b0"),
    ("disp_rd_areg", "{(idu_rtu_pst_dis_inst3_preg_vld ? idu_rtu_pst_dis_inst3_dst_reg : idu_rtu_pst_dis_inst3_ereg), (idu_rtu_pst_dis_inst2_preg_vld ? idu_rtu_pst_dis_inst2_dst_reg : idu_rtu_pst_dis_inst2_ereg), (idu_rtu_pst_dis_inst1_preg_vld ? idu_rtu_pst_dis_inst1_dst_reg : idu_rtu_pst_dis_inst1_ereg), (idu_rtu_pst_dis_inst0_preg_vld ? idu_rtu_pst_dis_inst0_dst_reg : idu_rtu_pst_dis_inst0_ereg)}"),
    ("disp_rd_we", "{(idu_rtu_pst_dis_inst3_preg_vld | idu_rtu_pst_dis_inst3_freg_vld), (idu_rtu_pst_dis_inst2_preg_vld | idu_rtu_pst_dis_inst2_freg_vld), (idu_rtu_pst_dis_inst1_preg_vld | idu_rtu_pst_dis_inst1_freg_vld), (idu_rtu_pst_dis_inst0_preg_vld | idu_rtu_pst_dis_inst0_freg_vld)}"),
    ("disp_rd_fpr", "{idu_rtu_pst_dis_inst3_freg_vld, idu_rtu_pst_dis_inst2_freg_vld, idu_rtu_pst_dis_inst1_freg_vld, idu_rtu_pst_dis_inst0_freg_vld}"),
    ("wb_vld", "{vfpu_rtu_ex5_pipe7_wb_vreg_fr_vld, vfpu_rtu_ex5_pipe6_wb_vreg_fr_vld, lsu_idu_wb_pipe3_wb_preg_vld, iu_rtu_ex2_pipe1_wb_preg_vld, iu_rtu_ex2_pipe0_wb_preg_vld}"),
    ("wb_iid", "{vfpu_rtu_pipe7_iid, vfpu_rtu_pipe6_iid, lsu_rtu_wb_pipe3_iid, iu_rtu_pipe1_iid, iu_rtu_pipe0_iid}"),
    ("wb_data", "{vfpu_idu_ex5_pipe7_wb_vreg_fr_data, vfpu_idu_ex5_pipe6_wb_vreg_fr_data, lsu_idu_wb_pipe3_wb_preg_data, iu_idu_ex2_pipe1_wb_preg_data, iu_idu_ex2_pipe0_wb_preg_data}"),
    ("ls_vld", "{rvfi_st_da_inst_vld, rvfi_ld_da_inst_vld}"),
    ("ls_iid", "{rvfi_st_da_iid, rvfi_ld_da_iid}"),
    ("ls_addr", "{rvfi_st_da_addr, rvfi_ld_da_addr}"),
    ("ls_is_load", "2'b01"),
    ("ls_mask", "{rvfi_st_mask8, rvfi_ld_mask8}"),
    ("ls_wdata", "128'b0"),
    ("ls_rdata", "{64'b0, rvfi_ld_da_data}"),
    ("sd_vld", "rvfi_sd_inst_vld"),
    ("sd_iid", "rvfi_sd_iid_ff"),
    ("sd_data", "rvfi_sd_data"),
] + [(n, n) for n in pnames()]
inst_lines = ",\n".join("  .%-16s (%s)" % (k, v) for (k, v) in conn)
block = ("\n`ifdef RVFI\n// RVFI export ports (simulation/lockstep only)\n" + pdecls() + "\n\n"
         "// RISC-V Formal Interface generator (retire + dispatch/wb + mem + FP,\n"
         "// with ROB next_pc/trap/cause and SQ store-data taps).\n"
         "ct_rvfi_gen #(.NRET(3), .NDISP(4), .NWB(5), .NLS(2)) x_ct_rvfi_gen (\n" +
         inst_lines + "\n);\n`endif\n")
c = c.replace("\n// &ModuleEnd; @91\nendmodule", block + "\n// &ModuleEnd; @91\nendmodule", 1)
wr("cpu/rtl/ct_core.v", c)

# ---- ct_top.v : forward the RVFI export bus from its ct_core ----
tt = rd("cpu/rtl/ct_top.v")
require("module ct_top(\n" in tt and "ct_core  x_ct_core (\n" in tt, "ct_top anchors not found")
tt = tt.replace("module ct_top(\n",
    "module ct_top(\n`ifdef RVFI\n" + "\n".join("  %s," % n for n in pnames()) + "\n`endif\n", 1)
tt = tt.replace("\nendmodule", "\n`ifdef RVFI\n" + pdecls() + "\n`endif\n\nendmodule", 1)
tt = tt.replace("ct_core  x_ct_core (\n",
    "ct_core  x_ct_core (\n`ifdef RVFI\n" +
    "\n".join("  .%-16s (%s)," % (n, n) for n in pnames()) + "\n`endif\n", 1)
wr("cpu/rtl/ct_top.v", tt)

# ---- openC910.v : expose core0_rvfi_*, wire x_ct_top_0, tie off x_ct_top_1 ----
o = rd("cpu/rtl/openC910.v")
require("module openC910(\n" in o and "ct_top  x_ct_top_0 (\n" in o
        and "ct_top  x_ct_top_1 (\n" in o, "openC910 anchors not found")
o = o.replace("module openC910(\n",
    "module openC910(\n`ifdef RVFI\n" + "\n".join("  core0_%s," % n for n in pnames()) + "\n`endif\n", 1)
o = o.replace("\nendmodule", "\n`ifdef RVFI\n" + pdecls(pfx="core0_") + "\n`endif\n\nendmodule", 1)
o = o.replace("ct_top  x_ct_top_0 (\n",
    "ct_top  x_ct_top_0 (\n`ifdef RVFI\n" +
    "\n".join("  .%-16s (core0_%s)," % (n, n) for n in pnames()) + "\n`endif\n", 1)
o = o.replace("ct_top  x_ct_top_1 (\n",
    "ct_top  x_ct_top_1 (\n`ifdef RVFI\n" +
    "\n".join("  .%-16s ()," % n for n in pnames()) + "\n`endif\n", 1)
wr("cpu/rtl/openC910.v", o)

# ---- mmu/rtl/sysmap.h : PMA remap so rv_tester's memmap is executable ----
# Sysmap compares PA[39:12] (4KB units): a 0x8000_0000 fetch looks up 0x80000.
#   boot [0,0x0200_0000)         exec   BASE0=0x02000  FLG0=01111
#   MMIO [0x0200_0000,0x8000_0000) device BASE1=0x80000  FLG1=10000
#   DRAM [0x8000_0000,0x1_0000_0000) exec BASE2=0x100000 FLG2=01111
#   rest device
sm = rd("mmu/rtl/sysmap.h")
_vals = {0: ("02000", "01111"), 1: ("80000", "10000"), 2: ("100000", "01111"),
         3: ("fffffff", "10000"), 4: ("fffffff", "10000"), 5: ("fffffff", "10000"),
         6: ("fffffff", "10000"), 7: ("fffffff", "10000")}
for i, (ba, fl) in _vals.items():
    sm, n1 = re.subn(r"`define SYSMAP_BASE_ADDR%d\s+28'h[0-9a-fA-F]+" % i,
                     "`define SYSMAP_BASE_ADDR%d  28'h%s" % (i, ba), sm)
    sm, n2 = re.subn(r"`define SYSMAP_FLG%d\s+5'b[01]+" % i,
                     "`define SYSMAP_FLG%d        5'b%s" % (i, fl), sm)
    require(n1 >= 1 and n2 >= 1, "sysmap SYSMAP_BASE_ADDR%d/FLG%d not found" % (i, i))
wr("mmu/rtl/sysmap.h", sm)

# ---- cp0/rtl/ct_cp0_regs.v : enable I/D cache at reset (mhcr.IE/DE) ----
# C910 cannot fetch cacheable memory with the icache off and has no
# cold-executable uncached region, so both caches are enabled at reset.
cp = rd("cp0/rtl/ct_cp0_regs.v")
require("    de  <= 1'b0;\n    ie  <= 1'b0;\n" in cp, "mhcr de/ie reset not found")
cp = cp.replace("    de  <= 1'b0;\n    ie  <= 1'b0;\n",
                "    de  <= 1'b1;\n    ie  <= 1'b1;\n", 1)
wr("cp0/rtl/ct_cp0_regs.v", cp)

print("apply_rvfi: applied RVFI taps + sysmap remap + mhcr reset to " + ROOT)
