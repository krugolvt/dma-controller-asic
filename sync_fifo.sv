module sync_fifo #(
    parameter DATA_WIDTH = 8,
    parameter DEPTH      = 8,
    parameter PTR_WIDTH  = 4
)(
    input  logic                  clk,
    input  logic                  rst_n,
    input  logic                  w_en,
    input  logic                  r_en,
    input  logic [DATA_WIDTH-1:0] data_in,

    output logic [DATA_WIDTH-1:0] data_out,
    output logic                  empty,
    output logic                  full
);

    logic [PTR_WIDTH-1:0] w_ptr, r_ptr;
    logic [DATA_WIDTH-1:0] mem [0:DEPTH-1];

    assign empty = (w_ptr == r_ptr);

    assign full =
        (w_ptr[PTR_WIDTH-1] != r_ptr[PTR_WIDTH-1]) &&
        (w_ptr[PTR_WIDTH-2:0] == r_ptr[PTR_WIDTH-2:0]);

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            w_ptr    <= '0;
            r_ptr    <= '0;
            data_out <= '0;
        end
        else begin
            if (w_en && !full) begin
                mem[w_ptr[PTR_WIDTH-2:0]] <= data_in;
                w_ptr <= w_ptr + 1'b1;
            end

            if (r_en && !empty) begin
                data_out <= mem[r_ptr[PTR_WIDTH-2:0]];
                r_ptr <= r_ptr + 1'b1;
            end
        end
    end

endmodule
