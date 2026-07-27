// SPDX-FileCopyrightText: © 2026 Tenstorrent USA, Inc.
// SPDX-License-Identifier: Apache-2.0

// RVFI capture + PMCI configuration for the openc910 <-> rv_tester harness.
// RVFI_TRACE / RVFI_MEM turn on the RISC-V Formal Interface + memory tracing
// path that rv_tester's cosim (Whisper lockstep) consumes. RVFI turns on the
// `ifdef RVFI export ports our patch adds to the C910 RTL. C910 exposes no
// rv_tester performance-monitor-counter interface, so disable rv_tester's PMCI.
`define RVFI_TRACE
`define RVFI_MEM
`define RVFI
`define RV_TESTER_PMCI_DISABLE
