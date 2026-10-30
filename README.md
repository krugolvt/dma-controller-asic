# Multi-Clock DMA Controller ASIC

SystemVerilog implementation of a multi-clock DMA controller with AXI4-Lite control, asynchronous FIFO based clock-domain crossing, and separate source/destination control FSMs.

## Features

- AXI4-Lite slave for DMA configuration and status
- Memory-mapped source address, destination address, transfer length, control, and status registers
- Source-side DMA FSM for memory reads
- Destination-side DMA FSM for memory writes
- Asynchronous FIFO for data transfer across independent clock domains
- Gray-code pointer synchronization with 2-FF synchronizers
- Full/empty detection across clock domains
- SystemVerilog and UVM verification

## Architecture

The DMA is configured through an AXI4-Lite slave exposing memory-mapped source address, destination address, transfer length, control, and status registers. A source-side FSM reads data from the source interface and pushes it into an asynchronous FIFO. The FIFO transfers payload data safely across independent clock domains using Gray-coded pointers and 2-FF synchronizers. A destination-side FSM reads data from the FIFO and writes it to the destination interface.

## Register Map

- `0x00` — `SRC_ADDR`
- `0x04` — `DST_ADDR`
- `0x08` — `LENGTH`
- `0x0C` — `CONTROL`
- `0x10` — `STATUS`

## RTL

- `rtl/dma_top.sv` — top level: registers, both FSMs, FIFO, clock gating
- `rtl/icg_cell.sv` — latch-based integrated clock gating cell
- `rtl/pulse_sync.sv` — toggle pulse synchronizer for start/done
- `async_fifo.sv`
- `axi4_lite.sv` (`dma_axi_lite_regs`)
- `dma_fsm_wr.sv` (`dma_fsm`, source side)
- `dma_fsm_rd.sv` (`dma_dst_fsm`, destination side)

## Verification

Directed SystemVerilog and UVM testbenches are used to verify FIFO ordering, AXI4-Lite register accesses, handshake behavior, and multi-clock data transfer.

Run everything with `./run_tests.sh` (needs Icarus Verilog and Verilator). The UVM testbenches run only when `UVM_HOME` points at a UVM library.

## Test-Aware Clock Gating

### What

Each DMA clock domain's control FSM runs on a gated clock produced by an `icg_cell`:

| Domain | Free-running clock | Gated clock | Enable |
|---|---|---|---|
| Source | `wr_clk` | `wr_gclk` → `dma_fsm` | `busy \| source_done \| start` |
| Destination | `rd_clk` | `rd_gclk` → `dma_dst_fsm` | `busy \| done \| start \| !fifo_empty` |

`done` is part of the enable because both FSMs report `busy=0` in `DONE` and need one more edge to get back to `IDLE`. The AXI4-Lite register block, the async FIFO and the start/done pulse synchronizers stay on free-running clocks. They are the logic that notices new work and wakes a gated FSM, so they must keep running.

The top-level `test_en` input drives the `te` pin of every ICG. Connect it to the DFT scan-enable so scan shift reaches every flop, and tie it low in functional mode.

### Why a latch-based ICG

The enable comes from flops clocked by the same clock, so it changes just after each rising edge, while the clock is high. A plain `clk & en` would pass those changes through, causing truncated pulses, runt pulses, and glitches from any combinational hazard on `en`. The ICG latches `en | te` while `clk` is low and holds it for the high phase. `gclk` is therefore either a full clock pulse or flat low.

### How it is verified

- **SVA in `icg_cell`** (checked by the Verilator run):
  - no `gclk` pulse on a cycle whose `en | te` was 0
  - `gclk` pulses on every cycle with `te=1`
  - the latched enable only changes while `clk` is low, and `gclk` only falls together with `clk`, so there are no glitches
- **Directed test `tb/dma_cg_tb.sv`** runs on both Verilator (with SVA) and Icarus (4-state, SVA compiled out). It checks:
  - both gated clocks stop after reset
  - a transfer starts them again and the destination data matches the source
  - they stop again once the transfer is done
  - a second transfer works the same way
  - `test_en=1` makes them run on every cycle while idle
  - a transfer with `test_en=1` still completes
- **Mutation check:** the test fails if the latch is made transparent-high, if it is replaced by a plain AND gate, if `done` is dropped from the enable, or if `te` is left unconnected.
- **Lint:** `verilator -Wall` is clean. The waivers are scoped: `COMBDLY` on the ICG latch line, and `DECLFILENAME` for the three existing files whose names differ from their modules (`lint/verilator.vlt`).

### Gated-cycle measurement

From one run of `dma_cg_tb`. These are percentages of clock edges suppressed at the FSMs. They are not power figures:

| | `wr_clk` (source) | `rd_clk` (destination) |
|---|---|---|
| During `test_en=0` transfers (register programming through `STATUS.done`) | ~34% | ~10% |
| Whole test, including idle windows and `test_en=1` phases | ~54% | ~44% |

Inside the transfer window an FSM's clock is gated only while that FSM is idle. That happens while software is still programming the registers, while the synchronized `start` is in flight, and on the source side after the source FSM finishes and the destination is still draining the FIFO. Once an FSM is busy, its clock runs. The whole-test figure depends mostly on how much idle time the test includes, so it says little about real workloads. The exact numbers vary slightly between simulators because the backpressure is random.

Only the FSM flops are gated: state plus three 32-bit registers per side. The power saving depends on the target library and on the cost of the clock tree, and has not been estimated.

### Known limitations (pre-existing, not changed here)

- `dma_fsm` mishandles `LENGTH=0`. It goes straight to `READ_REQ`, and `words_left` wraps to `0xFFFFFFFF`, so it tries to move about 2³² words. The destination FSM does handle `LENGTH=0`.
- `SRC_ADDR`/`DST_ADDR`/`LENGTH` cross into the DMA domains as quasi-static values. Do not rewrite them while `STATUS.busy` is set.
