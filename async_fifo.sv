module async_fifo #(
    parameter DATA_WIDTH = 8,
    parameter DEPTH      = 8,
    parameter PTR_WIDTH  = 4
)(
    input  logic                  wr_clk,
    input  logic 		  rd_clk,	
    input  logic                  rst_n,
    input  logic                  w_en,
    input  logic                  r_en,
    input  logic [DATA_WIDTH-1:0] data_in,
    output logic [DATA_WIDTH-1:0] data_out,
    output logic                  empty,
    output logic                  full
);

    logic [PTR_WIDTH-1:0] w_ptr_bin, r_ptr_bin;
    logic [PTR_WIDTH-1:0] w_ptr_gray, r_ptr_gray;
    logic [DATA_WIDTH-1:0] mem [0:DEPTH-1];
  
    assign w_ptr_gray = (w_ptr_bin >> 1) ^ w_ptr_bin;
    assign r_ptr_gray = (r_ptr_bin >> 1) ^ r_ptr_bin;
  
    logic [PTR_WIDTH-1:0] r_ptr_gray_sync1, r_ptr_gray_sync2;
  	
    always_ff @(posedge wr_clk or negedge rst_n) begin
      if(!rst_n) begin
        r_ptr_gray_sync1 <= 0;
        r_ptr_gray_sync2 <= 0;
      end
      else begin
        r_ptr_gray_sync1 <= r_ptr_gray;
        r_ptr_gray_sync2 <= r_ptr_gray_sync1;
      end
    end
  
     logic [PTR_WIDTH-1:0] w_ptr_gray_sync1, w_ptr_gray_sync2;

     always_ff @(posedge rd_clk or negedge rst_n) begin
        if(!rst_n) begin
          w_ptr_gray_sync1 <= 0;
          w_ptr_gray_sync2 <= 0;
        end
        else begin
          w_ptr_gray_sync1 <= w_ptr_gray;
          w_ptr_gray_sync2 <= w_ptr_gray_sync1;
        end
     end

     assign empty = (w_ptr_gray_sync2 == r_ptr_gray);

     logic [PTR_WIDTH-1:0] w_ptr_bin_next;
     logic [PTR_WIDTH-1:0] w_ptr_gray_next;
     logic full_next;
     
     assign w_ptr_bin_next =
       w_ptr_bin + ((w_en && !full) ? PTR_WIDTH'(1) : PTR_WIDTH'(0));

     assign w_ptr_gray_next =
      (w_ptr_bin_next >> 1) ^ w_ptr_bin_next;

     assign full_next =
       (w_ptr_gray_next ==
        {~r_ptr_gray_sync2[PTR_WIDTH-1:PTR_WIDTH-2],
         r_ptr_gray_sync2[PTR_WIDTH-3:0]});

     always_ff @(posedge wr_clk or negedge rst_n) begin
          if (!rst_n) begin
              w_ptr_bin    <= '0;
          end
          else begin
              if (w_en && !full) begin
                mem[w_ptr_bin[PTR_WIDTH-2:0]] <= data_in;
                w_ptr_bin <= w_ptr_bin + 1'b1;
		full <= full_next;
              end
          end
     end

     always_ff @(posedge rd_clk or negedge rst_n) begin
        if (!rst_n) begin
          r_ptr_bin    <= '0;
          data_out <= '0;
        end
        else begin
          if (r_en && !empty) begin
            data_out <= mem[r_ptr_bin[PTR_WIDTH-2:0]];
            r_ptr_bin <= r_ptr_bin + 1'b1;
          end
        end
     end
  
 endmodule
