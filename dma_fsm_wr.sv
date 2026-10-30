module dma_fsm (
    input  logic        wr_clk,
    input  logic        rst_n,

    input  logic        start,
    input  logic [31:0] src_addr_reg,
    input  logic [31:0] length_reg,

    output logic [31:0] src_addr,
    output logic        src_read_req,
    input  logic [31:0] src_read_data,
    input  logic        src_read_valid,

    input  logic        fifo_full,
    output logic        fifo_w_en,
    output logic [31:0] fifo_w_data,

    output logic        busy,
    output logic        source_done
);

    typedef enum logic [2:0] {
        IDLE,
        READ_REQ,
        WAIT_DATA,
        WRITE_FIFO,
        DONE
    } state_t;

    state_t state;

    logic [31:0] current_addr;
    logic [31:0] words_left;
    logic [31:0] data_buffer;


    always_ff @(posedge wr_clk or negedge rst_n) begin
        if (!rst_n) begin
            state         <= IDLE;
            current_addr  <= '0;
            words_left    <= '0;
            data_buffer   <= '0;
        end
        else begin

            case (state)

                IDLE: begin
                    if (start) begin
                        current_addr <= src_addr_reg;
                        words_left   <= length_reg;
                        state        <= READ_REQ;
                    end
                end


                READ_REQ: begin
                    state <= WAIT_DATA;
                end


                WAIT_DATA: begin
                    if (src_read_valid) begin
                        data_buffer <= src_read_data;
                        state       <= WRITE_FIFO;
                    end
                end


                WRITE_FIFO: begin
                    if (!fifo_full) begin

                        if (words_left == 1) begin
                            words_left <= 0;
                            state      <= DONE;
                        end
                        else begin
                            current_addr <= current_addr + 4;
                            words_left   <= words_left - 1;
                            state        <= READ_REQ;
                        end

                    end
                end


                DONE: begin
                    state <= IDLE;
                end

                default:
                    state <= IDLE;

            endcase
        end
    end


    always_comb begin

        src_addr     = current_addr;
        src_read_req = 1'b0;

        fifo_w_en    = 1'b0;
        fifo_w_data  = data_buffer;

        busy         = 1'b1;
        source_done  = 1'b0;

        case (state)

            IDLE: begin
                busy = 1'b0;
            end

            READ_REQ: begin
                src_read_req = 1'b1;
            end

            WRITE_FIFO: begin
                if (!fifo_full)
                    fifo_w_en = 1'b1;
            end

            DONE: begin
                busy        = 1'b0;
                source_done = 1'b1;
            end

            default: begin
            end

        endcase
    end

endmodule
