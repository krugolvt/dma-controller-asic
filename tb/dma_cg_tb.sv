`timescale 1ns/1ps

// Directed test for test-aware clock gating in dma_top.
//
//   1. After reset, both DMA domains idle -> gated clocks stop.
//   2. Transfer A -> gated clocks resume, data lands correctly.
//   3. Back to idle -> gated clocks stop again.
//   4. Transfer B (new request) -> resumes and completes correctly.
//   5. test_en=1 while idle -> gated clocks run every cycle.
//   6. test_en=0 -> gated clocks stop.
//   7. Transfer C with test_en=1 -> still completes correctly.
//
// The ICG SVA (rtl/icg_cell.sv) run throughout. Reports the fraction of
// clock edges suppressed in each gated domain.
module dma_cg_tb;

    // Mutually asynchronous clocks
    logic clk = 0, wr_clk = 0, rd_clk = 0;
    always #5 clk    = ~clk;     // AXI, 100 MHz
    always #4 wr_clk = ~wr_clk;  // source, 125 MHz
    always #7 rd_clk = ~rd_clk;  // destination, ~71 MHz

    logic rst_n;
    logic test_en;

    logic [4:0]  awaddr, araddr;
    logic        awvalid, wvalid, bready, arvalid, rready;
    logic [31:0] wdata;
    logic        awready, wready, bvalid, arready, rvalid;
    logic [1:0]  bresp, rresp;
    logic [31:0] rdata;

    logic [31:0] src_addr;
    logic        src_read_req;
    logic [31:0] src_read_data;
    logic        src_read_valid;

    logic [31:0] dst_addr;
    logic [31:0] dst_write_data;
    logic        dst_write_req;
    logic        dst_write_ready;

    dma_top u_top (
        .clk(clk), .wr_clk(wr_clk), .rd_clk(rd_clk),
        .rst_n(rst_n), .test_en(test_en),
        .s_axi_awaddr(awaddr), .s_axi_awvalid(awvalid), .s_axi_awready(awready),
        .s_axi_wdata(wdata), .s_axi_wvalid(wvalid), .s_axi_wready(wready),
        .s_axi_bresp(bresp), .s_axi_bvalid(bvalid), .s_axi_bready(bready),
        .s_axi_araddr(araddr), .s_axi_arvalid(arvalid), .s_axi_arready(arready),
        .s_axi_rdata(rdata), .s_axi_rresp(rresp), .s_axi_rvalid(rvalid),
        .s_axi_rready(rready),
        .src_addr(src_addr), .src_read_req(src_read_req),
        .src_read_data(src_read_data), .src_read_valid(src_read_valid),
        .dst_addr(dst_addr), .dst_write_data(dst_write_data),
        .dst_write_req(dst_write_req), .dst_write_ready(dst_write_ready)
    );

    int errors = 0;

    // ------------------------------------------------------------------
    // Edge counters
    // ------------------------------------------------------------------
    longint wr_clk_edges = 0, wr_gclk_edges = 0;
    longint rd_clk_edges = 0, rd_gclk_edges = 0;

    always @(posedge wr_clk)          wr_clk_edges++;
    always @(posedge u_top.wr_gclk)   wr_gclk_edges++;
    always @(posedge rd_clk)          rd_clk_edges++;
    always @(posedge u_top.rd_gclk)   rd_gclk_edges++;

    // ------------------------------------------------------------------
    // Memory models
    // ------------------------------------------------------------------
    logic [31:0] salt;

    function automatic logic [31:0] src_word(logic [31:0] addr);
        return {addr[15:0], ~addr[15:0]} ^ salt;
    endfunction

    // Source memory: one-cycle read latency, free-running wr_clk.
    always_ff @(posedge wr_clk or negedge rst_n) begin
        if (!rst_n) begin
            src_read_valid <= 1'b0;
            src_read_data  <= '0;
        end
        else begin
            src_read_valid <= src_read_req;
            src_read_data  <= src_word(src_addr);
        end
    end

    // Destination memory with random backpressure, indexed by word offset
    // from the current transfer's DST_ADDR.
    localparam int MAX_WORDS = 64;
    logic [31:0] dst_base;
    logic [31:0] dst_mem   [MAX_WORDS];
    bit          dst_valid [MAX_WORDS];
    int          dst_writes;
    int          dst_stray;

    always_ff @(posedge rd_clk or negedge rst_n) begin
        if (!rst_n)
            dst_write_ready <= 1'b0;
        else
            dst_write_ready <= ($urandom_range(0, 3) != 0);
    end

    always @(posedge rd_clk) begin
        if (rst_n && dst_write_req && dst_write_ready) begin
            logic [31:0] idx;
            idx = (dst_addr - dst_base) >> 2;
            if (idx < MAX_WORDS && dst_addr[1:0] == 2'b00) begin
                dst_mem[idx]   = dst_write_data;
                dst_valid[idx] = 1'b1;
            end
            else
                dst_stray++;
            dst_writes++;
        end
    end

    // ------------------------------------------------------------------
    // AXI4-Lite tasks (same handshake style as axi4_uvm_tb.sv)
    // ------------------------------------------------------------------
    task automatic axi_write(input logic [4:0] addr, input logic [31:0] data);
        @(negedge clk);
        awaddr = addr; awvalid = 1; wdata = data; wvalid = 1; bready = 1;
        do @(posedge clk); while (!(awready && wready));
        @(negedge clk);
        awvalid = 0; wvalid = 0;
        do @(posedge clk); while (!bvalid);
        @(negedge clk);
        bready = 0;
    endtask

    task automatic axi_read(input logic [4:0] addr, output logic [31:0] data);
        @(negedge clk);
        araddr = addr; arvalid = 1; rready = 1;
        do @(posedge clk); while (!arready);
        @(negedge clk);
        arvalid = 0;
        do @(posedge clk); while (!rvalid);
        data = rdata;
        @(negedge clk);
        rready = 0;
    endtask

    // ------------------------------------------------------------------
    // Checks
    // ------------------------------------------------------------------
    task automatic check(input bit cond, input string msg);
        if (cond) $display("PASS: %s", msg);
        else begin
            $display("FAIL: %s", msg);
            errors++;
        end
    endtask

    // Count gated-clock edges over n source-clock cycles (window bounded by
    // negedges so the counters are stable when read).
    task automatic measure(input int n,
                           output longint wr_c, output longint wr_g,
                           output longint rd_c, output longint rd_g);
        longint wc0, wg0, rc0, rg0;
        @(negedge wr_clk);
        wc0 = wr_clk_edges; wg0 = wr_gclk_edges;
        rc0 = rd_clk_edges; rg0 = rd_gclk_edges;
        repeat (n) @(negedge wr_clk);
        wr_c = wr_clk_edges - wc0; wr_g = wr_gclk_edges - wg0;
        rd_c = rd_clk_edges - rc0; rd_g = rd_gclk_edges - rg0;
    endtask

    task automatic expect_stopped(input string when);
        longint wc, wg, rc, rg;
        measure(100, wc, wg, rc, rg);
        check(wg == 0, $sformatf("%s: wr_gclk stopped (%0d/%0d edges)", when, wg, wc));
        check(rg == 0, $sformatf("%s: rd_gclk stopped (%0d/%0d edges)", when, rg, rc));
    endtask

    task automatic expect_running(input string when);
        longint wc, wg, rc, rg;
        measure(100, wc, wg, rc, rg);
        check(wg == wc, $sformatf("%s: wr_gclk free-running (%0d/%0d edges)", when, wg, wc));
        check(rg == rc, $sformatf("%s: rd_gclk free-running (%0d/%0d edges)", when, rg, rc));
    endtask

    longint xfer_wr_c = 0, xfer_wr_g = 0, xfer_rd_c = 0, xfer_rd_g = 0;

    task automatic run_transfer(input string name, input logic [31:0] src,
                                input logic [31:0] dst, input int len,
                                input logic [31:0] new_salt);
        logic [31:0] status;
        longint      wc0, wg0, rc0, rg0, wg_mid, rg_mid;
        int          polls, bad;

        salt     = new_salt;
        dst_base = dst;
        for (int i = 0; i < MAX_WORDS; i++) dst_valid[i] = 1'b0;
        dst_writes = 0;
        dst_stray  = 0;

        wc0 = wr_clk_edges; wg0 = wr_gclk_edges;
        rc0 = rd_clk_edges; rg0 = rd_gclk_edges;

        axi_write(5'h00, src);
        axi_write(5'h04, dst);
        axi_write(5'h08, len);
        axi_write(5'h0C, 32'h1);

        polls = 0;
        do begin
            axi_read(5'h10, status);
            polls++;
        end while (!status[1] && polls < 10000);

        check(status[1] && !status[0],
              $sformatf("%s: STATUS reports done (0x%0h)", name, status));

        wg_mid = wr_gclk_edges - wg0;
        rg_mid = rd_gclk_edges - rg0;
        check(wg_mid > 0 && rg_mid > 0,
              $sformatf("%s: gated clocks resumed (wr %0d, rd %0d edges)",
                        name, wg_mid, rg_mid));

        bad = 0;
        for (int i = 0; i < len; i++) begin
            if (!dst_valid[i] || dst_mem[i] !== src_word(src + 4 * i)) begin
                if (bad < 5)
                    $display("  word %0d @0x%08h: expected 0x%08h got 0x%08h",
                             i, dst + 4 * i, src_word(src + 4 * i),
                             dst_valid[i] ? dst_mem[i] : 32'hx);
                bad++;
            end
        end
        check(bad == 0 && dst_writes == len && dst_stray == 0,
              $sformatf("%s: %0d/%0d words correct, %0d writes, %0d out of range",
                        name, len - bad, len, dst_writes, dst_stray));

        // Transfers run with test_en=1 have gating forced off; leave them out.
        if (!test_en) begin
            xfer_wr_c += wr_clk_edges - wc0; xfer_wr_g += wr_gclk_edges - wg0;
            xfer_rd_c += rd_clk_edges - rc0; xfer_rd_g += rd_gclk_edges - rg0;
        end
    endtask

    function automatic real pct_gated(longint c, longint g);
        return (c == 0) ? 0.0 : 100.0 * real'(c - g) / real'(c);
    endfunction

    // ------------------------------------------------------------------
    // Test sequence
    // ------------------------------------------------------------------
    longint tot_wr_c, tot_wr_g, tot_rd_c, tot_rd_g;

    initial begin
        rst_n   = 0;
        test_en = 0;
        awaddr = 0; awvalid = 0; wdata = 0; wvalid = 0; bready = 0;
        araddr = 0; arvalid = 0; rready = 0;
        salt = 0;

        #50;
        rst_n = 1;

        repeat (10) @(posedge wr_clk);
        expect_stopped("after reset");

        run_transfer("transfer A", 32'h0000_1000, 32'h0000_8000, 20, 32'h1234_5678);

        repeat (10) @(posedge rd_clk);
        expect_stopped("idle after A");

        run_transfer("transfer B", 32'h0002_0000, 32'h0004_0100, 37, 32'hCAFE_F00D);

        repeat (10) @(posedge rd_clk);
        expect_stopped("idle after B");

        // Scan / test mode: te forces the gated clocks on even when idle.
        @(negedge wr_clk);
        test_en = 1;
        repeat (5) @(posedge rd_clk);
        expect_running("test_en=1, idle");

        @(negedge wr_clk);
        test_en = 0;
        repeat (5) @(posedge rd_clk);
        expect_stopped("test_en=0, idle");

        @(negedge wr_clk);
        test_en = 1;
        run_transfer("transfer C (test_en=1)", 32'h0000_0400, 32'h0000_C000, 9, 32'h0BAD_BEEF);
        @(negedge wr_clk);
        test_en = 0;

        tot_wr_c = wr_clk_edges; tot_wr_g = wr_gclk_edges;
        tot_rd_c = rd_clk_edges; tot_rd_g = rd_gclk_edges;

        $display("");
        $display("Gated-cycle report (edges suppressed / free-running edges):");
        $display("  whole test     wr_clk: %5.1f%% (%0d/%0d)  rd_clk: %5.1f%% (%0d/%0d)",
                 pct_gated(tot_wr_c, tot_wr_g), tot_wr_c - tot_wr_g, tot_wr_c,
                 pct_gated(tot_rd_c, tot_rd_g), tot_rd_c - tot_rd_g, tot_rd_c);
        $display("  in transfers   wr_clk: %5.1f%% (%0d/%0d)  rd_clk: %5.1f%% (%0d/%0d)",
                 pct_gated(xfer_wr_c, xfer_wr_g), xfer_wr_c - xfer_wr_g, xfer_wr_c,
                 pct_gated(xfer_rd_c, xfer_rd_g), xfer_rd_c - xfer_rd_g, xfer_rd_c);
        $display("  (transfer window = first AXI register write to STATUS.done read,");
        $display("   test_en=0 transfers only; whole-test figure includes the test_en=1");
        $display("   phases and depends on the idle time this test chose)");
        $display("");

        if (errors == 0) $display("TEST PASSED");
        else             $display("TEST FAILED: %0d error(s)", errors);
        $finish;
    end

    initial begin
        #2ms;
        $display("FAIL: timeout");
        $display("TEST FAILED");
        $finish;
    end

endmodule
