"""Shared verilator_cc_library `vopts` constants."""

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

# CVA6 build: enable rv_tester's RVFI capture path, disable the PMU counter
# interface (CVA6 has none), and waive the lint rules stock CVA6 / cvfpu /
# common_cells trip under -Wall (mirrors chips' ariane_verilator_config.vlt,
# applied globally here — refine to file-scoped .vlt later if needed).
CVA6_VOPTS = SW_TESTBENCH_VOPTS + [
    "+define+RV_TESTER_PMCI_DISABLE",
    "+define+RVFI_TRACE",
    "+define+RVFI_MEM",
    "-Wno-ALWCOMBORDER",
    "-Wno-BLKANDNBLK",
    "-Wno-CASEINCOMPLETE",
    "-Wno-CMPCONST",
    "-Wno-IMPLICITSTATIC",
    "-Wno-IMPORTSTAR",
    "-Wno-LATCH",
    "-Wno-LITENDIAN",
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
    "-Wno-CASEOVERLAP",
    "-Wno-ASCRANGE",
]
