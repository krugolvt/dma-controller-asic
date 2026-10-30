// DMA controller top level.
//
// Clock domains (all mutually asynchronous):
//   clk    - AXI4-Lite register interface. Never gated.
//   wr_clk - source side: dma_fsm reads memory and pushes into the async FIFO.
//   rd_clk - destination side: dma_dst_fsm pops the FIFO and writes memory.
//
// Clock gating: one ICG per DMA domain gates only that domain's control FSM.
// The async FIFO, the start/done pulse synchronizers and the register block
// stay on free-running clocks, because they are what detect work and wake a
// gated FSM back up. In particular the FIFO's empty flag comes from pointer
// synchronizer flops in the rd_clk domain: if those were gated, empty could
// not change while the clock is stopped and the !fifo_empty wake term would
// be dead.
//
// test_en: drive from the DFT scan-enable; forces both gated clocks on so scan
// shift reaches every flop. Tie low in functional mode.
//
// SRC_ADDR/DST_ADDR/LENGTH are quasi-static: they cross into wr_clk/rd_clk
// unsynchronized and are only sampled when the synchronized start pulse
// arrives, so software must not rewrite them while STATUS.busy is set.
module dma_top (
    input  logic        clk,
    input  logic        wr_clk,
    input  logic        rd_clk,
    input  logic        rst_n,
    input  logic        test_en,

    // AXI4-Lite slave
    input  logic [4:0]  s_axi_awaddr,
    input  logic        s_axi_awvalid,
    output logic        s_axi_awready,
    input  logic [31:0] s_axi_wdata,
    input  logic        s_axi_wvalid,
    output logic        s_axi_wready,
    output logic [1:0]  s_axi_bresp,
    output logic        s_axi_bvalid,
    input  logic        s_axi_bready,
    input  logic [4:0]  s_axi_araddr,
    input  logic        s_axi_arvalid,
    output logic        s_axi_arready,
    output logic [31:0] s_axi_rdata,
    output logic [1:0]  s_axi_rresp,
    output logic        s_axi_rvalid,
    input  logic        s_axi_rready,

    // Source memory (wr_clk domain)
    output logic [31:0] src_addr,
    output logic        src_read_req,
    input  logic [31:0] src_read_data,
    input  logic        src_read_valid,

    // Destination memory (rd_clk domain)
    output logic [31:0] dst_addr,
    output logic [31:0] dst_write_data,
    output logic        dst_write_req,
    input  logic        dst_write_ready
);

    // ------------------------------------------------------------------
    // Register block (clk, ungated)
    // ------------------------------------------------------------------
    logic [31:0] src_addr_reg, dst_addr_reg, length_reg;
    logic        start;
    logic        status_busy, status_done;

    dma_axi_lite_regs u_regs (
        .clk           (clk),
        .rst_n         (rst_n),
        .s_axi_awaddr  (s_axi_awaddr),
        .s_axi_awvalid (s_axi_awvalid),
        .s_axi_awready (s_axi_awready),
        .s_axi_wdata   (s_axi_wdata),
        .s_axi_wvalid  (s_axi_wvalid),
        .s_axi_wready  (s_axi_wready),
        .s_axi_bresp   (s_axi_bresp),
        .s_axi_bvalid  (s_axi_bvalid),
        .s_axi_bready  (s_axi_bready),
        .s_axi_araddr  (s_axi_araddr),
        .s_axi_arvalid (s_axi_arvalid),
        .s_axi_arready (s_axi_arready),
        .s_axi_rdata   (s_axi_rdata),
        .s_axi_rresp   (s_axi_rresp),
        .s_axi_rvalid  (s_axi_rvalid),
        .s_axi_rready  (s_axi_rready),
        .src_addr_reg  (src_addr_reg),
        .dst_addr_reg  (dst_addr_reg),
        .length_reg    (length_reg),
        .start         (start),
        .busy          (status_busy),
        .done          (status_done)
    );

    // ------------------------------------------------------------------
    // Start/done pulse synchronizers (free-running clocks)
    // ------------------------------------------------------------------
    logic start_src, start_dst;
    logic dst_done, done_clk;

    pulse_sync u_start_to_src (
        .src_clk(clk), .dst_clk(wr_clk), .rst_n(rst_n),
        .src_pulse(start), .dst_pulse(start_src)
    );

    pulse_sync u_start_to_dst (
        .src_clk(clk), .dst_clk(rd_clk), .rst_n(rst_n),
        .src_pulse(start), .dst_pulse(start_dst)
    );

    // The destination side finishing implies every word went through the FIFO,
    // so its done pulse alone marks the end of the transfer.
    pulse_sync u_done_to_clk (
        .src_clk(rd_clk), .dst_clk(clk), .rst_n(rst_n),
        .src_pulse(dst_done), .dst_pulse(done_clk)
    );

    // STATUS bits as levels in the clk domain: busy from start until the
    // synchronized done arrives, done sticky until the next start.
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            status_busy <= 1'b0;
            status_done <= 1'b0;
        end
        else if (start) begin
            status_busy <= 1'b1;
            status_done <= 1'b0;
        end
        else if (done_clk) begin
            status_busy <= 1'b0;
            status_done <= 1'b1;
        end
    end

    // ------------------------------------------------------------------
    // Clock gating
    // ------------------------------------------------------------------
    // Both FSMs report busy=0 in DONE as well as IDLE, so done is ORed in:
    // the FSM needs one more edge to get from DONE back to IDLE.
    logic src_busy, src_done;
    logic dst_busy;
    logic fifo_full, fifo_empty;
    logic src_cg_en, dst_cg_en;
    logic wr_gclk, rd_gclk;

    assign src_cg_en = src_busy | src_done | start_src;
    assign dst_cg_en = dst_busy | dst_done | start_dst | !fifo_empty;

    icg_cell u_icg_src (
        .clk(wr_clk), .en(src_cg_en), .te(test_en), .gclk(wr_gclk)
    );

    icg_cell u_icg_dst (
        .clk(rd_clk), .en(dst_cg_en), .te(test_en), .gclk(rd_gclk)
    );

    // ------------------------------------------------------------------
    // Datapath
    // ------------------------------------------------------------------
    logic        fifo_w_en, fifo_r_en;
    logic [31:0] fifo_w_data, fifo_r_data;

    dma_fsm u_src_fsm (
        .wr_clk         (wr_gclk),
        .rst_n          (rst_n),
        .start          (start_src),
        .src_addr_reg   (src_addr_reg),
        .length_reg     (length_reg),
        .src_addr       (src_addr),
        .src_read_req   (src_read_req),
        .src_read_data  (src_read_data),
        .src_read_valid (src_read_valid),
        .fifo_full      (fifo_full),
        .fifo_w_en      (fifo_w_en),
        .fifo_w_data    (fifo_w_data),
        .busy           (src_busy),
        .source_done    (src_done)
    );

    async_fifo #(
        .DATA_WIDTH (32),
        .DEPTH      (8),
        .PTR_WIDTH  (4)
    ) u_fifo (
        .wr_clk   (wr_clk),
        .rd_clk   (rd_clk),
        .rst_n    (rst_n),
        .w_en     (fifo_w_en),
        .r_en     (fifo_r_en),
        .data_in  (fifo_w_data),
        .data_out (fifo_r_data),
        .empty    (fifo_empty),
        .full     (fifo_full)
    );

    dma_dst_fsm u_dst_fsm (
        .rd_clk          (rd_gclk),
        .rst_n           (rst_n),
        .start_rd        (start_dst),
        .dst_addr_start  (dst_addr_reg),
        .length_start    (length_reg),
        .fifo_empty      (fifo_empty),
        .fifo_r_data     (fifo_r_data),
        .fifo_r_en       (fifo_r_en),
        .dst_addr        (dst_addr),
        .dst_write_data  (dst_write_data),
        .dst_write_req   (dst_write_req),
        .dst_write_ready (dst_write_ready),
        .busy            (dst_busy),
        .done            (dst_done)
    );

endmodule
