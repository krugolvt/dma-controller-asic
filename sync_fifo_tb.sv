// or browse Examples
module sync_fifo_tb;

    logic clk;
    logic rst_n;
    logic w_en;
    logic r_en;
    logic [7:0] data_in;

    logic [7:0] data_out;
    logic empty;
    logic full;

    sync_fifo dut (
        .clk(clk),
        .rst_n(rst_n),
        .w_en(w_en),
        .r_en(r_en),
        .data_in(data_in),
        .data_out(data_out),
        .empty(empty),
        .full(full)
    );

    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    initial begin
        $dumpfile("dump.vcd");
        $dumpvars(0, sync_fifo_tb);

        rst_n   = 0;
        w_en    = 0;
        r_en    = 0;
        data_in = 0;

        #20;
        rst_n = 1;

        // Write 10
        @(posedge clk);
        w_en = 1;
        data_in = 8'd10;

        @(posedge clk);
        w_en = 0;

        // Write 20
        @(posedge clk);
        w_en = 1;
        data_in = 8'd20;

        @(posedge clk);
        w_en = 0;

        // Read first value
        @(posedge clk);
        r_en = 1;

        @(posedge clk);
        r_en = 0;

        #1;
        if (data_out == 8'd10)
            $display("PASS: First read = %0d", data_out);
        else
            $error("FAIL: Expected 10, got %0d", data_out);

        // Read second value
        @(posedge clk);
        r_en = 1;

        @(posedge clk);
        r_en = 0;

        #1;
        if (data_out == 8'd20)
            $display("PASS: Second read = %0d", data_out);
        else
            $error("FAIL: Expected 20, got %0d", data_out);

        #20;
        $finish;
    end

endmodule
