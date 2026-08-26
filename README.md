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

- `async_fifo.sv`
- `dma_axi_lite_regs.sv`
- `dma_fsm_wr.sv`
- `dma_fsm_rd.sv`

## Verification

Directed SystemVerilog and UVM testbenches are used to verify FIFO ordering, AXI4-Lite register accesses, handshake behavior, and multi-clock data transfer.
