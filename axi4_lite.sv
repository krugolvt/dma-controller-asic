module dma_axi_lite_regs (
    input  logic        clk,
    input  logic        rst_n,

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

    output logic [31:0] src_addr_reg,
    output logic [31:0] dst_addr_reg,
    output logic [31:0] length_reg,

    output logic        start,
    input  logic        busy,
    input  logic        done
);

    assign s_axi_awready = s_axi_awvalid &&
                           s_axi_wvalid &&
                           !s_axi_bvalid;

    assign s_axi_wready = s_axi_awready;

    assign s_axi_bresp = 2'b00;   

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            src_addr_reg <= '0;
            dst_addr_reg <= '0;
            length_reg   <= '0;
            start        <= 1'b0;
            s_axi_bvalid <= 1'b0;
        end
        else begin

            start <= 1'b0;

	    if (s_axi_awready && s_axi_wready) begin

                case (s_axi_awaddr)

                    5'h00:
                        src_addr_reg <= s_axi_wdata;

                    5'h04:
                        dst_addr_reg <= s_axi_wdata;

                    5'h08:
                        length_reg <= s_axi_wdata;

                    5'h0C:
                        start <= s_axi_wdata[0];

                endcase

                s_axi_bvalid <= 1'b1;
            end

	    if (s_axi_bvalid && s_axi_bready)
                s_axi_bvalid <= 1'b0;
        end
    end


    assign s_axi_arready = !s_axi_rvalid;
    assign s_axi_rresp   = 2'b00;   

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            s_axi_rdata  <= '0;
            s_axi_rvalid <= 1'b0;
        end
        else begin

            if (s_axi_arvalid && s_axi_arready) begin

                case (s_axi_araddr)

                    5'h00:
                        s_axi_rdata <= src_addr_reg;

                    5'h04:
                        s_axi_rdata <= dst_addr_reg;

                    5'h08:
                        s_axi_rdata <= length_reg;

                    5'h0C:
                        s_axi_rdata <= {31'b0, start};

                    5'h10:
                        s_axi_rdata <= {30'b0, done, busy};

                    default:
                        s_axi_rdata <= 32'b0;

                endcase

                s_axi_rvalid <= 1'b1;
            end

	    if (s_axi_rvalid && s_axi_rready)
                s_axi_rvalid <= 1'b0;
        end
    end

endmodule
