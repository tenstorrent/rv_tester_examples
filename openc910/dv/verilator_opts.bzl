"""Shared verilator_cc_library `vopts` constants for the openc910 build."""

COMMON_VOPTS = [
    "--default-language",
    "1800-2017",
    "+define+TB_EXTERNAL_CLOCK",
    "-Wall",
    "-Wpedantic",
    "-Wno-UNUSEDSIGNAL",
    "-Wno-PROCASSINIT",
    "-Wno-UNUSEDPARAM",
    "-Wno-GENUNNAMED",
    "-Wno-UNDRIVEN",
    "-Wno-PINMISSING",
    "-Wno-DECLFILENAME",
    "-Wno-PINCONNECTEMPTY",
    "-Wno-WIDTHEXPAND",
    "-Wno-UNUSEDGENVAR",
    "-Wno-SYNCASYNCNET",
    "-Wno-BLKSEQ",
    "-Wno-EOFNEWLINE",
]

SW_TESTBENCH_VOPTS = COMMON_VOPTS + [
    "+define+DMI_TB_WRITES_UNSUPPORTED",
    "+define+TRACE_CHECKS_UNSUPPORTED",
]

# openc910 (XuanTie C910) build: enable rv_tester's RVFI capture path and our
# `RVFI export in the C910 RTL, disable the PMU counter interface (not mapped),
# and waive the lint rules stock C910 (legacy Verilog-2001) trips under -Wall.
OPENC910_VOPTS = SW_TESTBENCH_VOPTS + [
    "+define+RV_TESTER_PMCI_DISABLE",
    "+define+RVFI_TRACE",
    "+define+RVFI_MEM",
    "+define+RVFI",
    "-Wno-ALWCOMBORDER",
    "-Wno-BLKANDNBLK",
    "-Wno-CASEINCOMPLETE",
    "-Wno-CASEOVERLAP",
    "-Wno-CMPCONST",
    "-Wno-COMBDLY",
    "-Wno-IMPLICIT",
    "-Wno-IMPLICITSTATIC",
    "-Wno-IMPORTSTAR",
    "-Wno-LATCH",
    "-Wno-LITENDIAN",
    "-Wno-MULTIDRIVEN",
    "-Wno-SELRANGE",
    "-Wno-SYMRSVDWORD",
    "-Wno-UNOPTFLAT",
    "-Wno-UNPACKED",
    "-Wno-UNSIGNED",
    "-Wno-UNUSED",
    "-Wno-VARHIDDEN",
    "-Wno-WIDTH",
    "-Wno-WIDTHCONCAT",
    "-Wno-WIDTHTRUNC",
    "-Wno-ASCRANGE",
    "-Wno-PINNOCONNECT",
]
