// SPDX-FileCopyrightText: © 2026 Tenstorrent USA, Inc.
// SPDX-License-Identifier: Apache-2.0

// RVFI capture + PMCI configuration for the CVA6 <-> rv_tester harness.
// RVFI_TRACE / RVFI_MEM turn on the RISC-V Formal Interface + memory tracing
// path that rv_tester's cosim (Whisper lockstep) consumes.  CVA6 exposes no
// performance-monitor-counter interface, so disable rv_tester's PMCI ports.
`define RVFI_TRACE
`define RVFI_MEM
`define RV_TESTER_PMCI_DISABLE
