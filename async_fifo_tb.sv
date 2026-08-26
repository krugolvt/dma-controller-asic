module async_fifo_tb;

    parameter DATA_WIDTH = 8;
    parameter DEPTH      = 8;
    parameter PTR_WIDTH  = 4;

    logic wr_clk;
    logic rd_clk;
    logic rst_n;

    logic w_en;
    logic r_en;
    logic [DATA_WIDTH-1:0] data_in;

    logic [DATA_WIDTH-1:0] data_out;
    logic empty;
    logic full;

    async_fifo #(
        .DATA_WIDTH(DATA_WIDTH),
        .DEPTH(DEPTH),
        .PTR_WIDTH(PTR_WIDTH)
    ) dut (
        .wr_clk(wr_clk),
        .rd_clk(rd_clk),
        .rst_n(rst_n),
        .w_en(w_en),
        .r_en(r_en),
        .data_in(data_in),
        .data_out(data_out),
        .empty(empty),
        .full(full)
    );

    // Write clock: 10 ns period
    initial begin
        wr_clk = 0;
        forever #5 wr_clk = ~wr_clk;
    end

    // Read clock: 14 ns period
    initial begin
        rd_clk = 0;
        forever #7 rd_clk = ~rd_clk;
    end

    initial begin
        $dumpfile("dump.vcd");
        $dumpvars(0, async_fifo_tb);

        rst_n   = 0;
        w_en    = 0;
        r_en    = 0;
        data_in = 0;

        #20;
        rst_n = 1;

        // Write 10
        @(posedge wr_clk);
        w_en    = 1;
        data_in = 8'd10;

        @(posedge wr_clk);
        w_en = 0;

        // Write 20
        @(posedge wr_clk);
        w_en    = 1;
        data_in = 8'd20;

        @(posedge wr_clk);
        w_en = 0;

        // Give pointer synchronization some time
        repeat (3) @(posedge rd_clk);

        // Read first value
        @(posedge rd_clk);
        r_en = 1;

        @(posedge rd_clk);
        r_en = 0;

        #1;
        if (data_out == 8'd10)
            $display("PASS: First read = %0d", data_out);
        else
            $error("FAIL: Expected 10, got %0d", data_out);

        // Read second value
        @(posedge rd_clk);
        r_en = 1;

        @(posedge rd_clk);
        r_en = 0;

        #1;
        if (data_out == 8'd20)
            $display("PASS: Second read = %0d", data_out);
        else
            $error("FAIL: Expected 20, got %0d", data_out);

        repeat (3) @(posedge rd_clk);

        if (empty)
            $display("PASS: FIFO is empty");
        else
            $error("FAIL: FIFO should be empty");

        #20;
        $finish;
    end

    initial begin
    	$dumpfile("waveform.vcd");
    	$dumpvars(0, async_fifo_tb);
    end

endmodule
      
      
