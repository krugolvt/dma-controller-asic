module dma_dst_fsm (
    input  logic        rd_clk,
    input  logic        rst_n,

    input  logic        start_rd,
    input  logic [31:0] dst_addr_start,
    input  logic [31:0] length_start,

    input  logic        fifo_empty,
    input  logic [31:0] fifo_r_data,
    output logic        fifo_r_en,

    output logic [31:0] dst_addr,
    output logic [31:0] dst_write_data,
    output logic        dst_write_req,
    input  logic        dst_write_ready,

    output logic        busy,
    output logic        done
);

    typedef enum logic [2:0] {
        IDLE,
        WAIT_FIFO,
        POP_FIFO,
        CAPTURE_DATA,
        WRITE_REQ,
        DONE
    } state_t;

    state_t state;

    logic [31:0] current_addr;
    logic [31:0] words_left;
    logic [31:0] data_buffer;

    always_ff @(posedge rd_clk or negedge rst_n) begin
        if (!rst_n) begin
            state        <= IDLE;
            current_addr <= '0;
            words_left   <= '0;
            data_buffer  <= '0;
        end
        else begin
            case (state)

                IDLE: begin
                    if (start_rd) begin
                        current_addr <= dst_addr_start;
                        words_left   <= length_start;

                        if (length_start == 0)
                            state <= DONE;
                        else
                            state <= WAIT_FIFO;
                    end
                end

                WAIT_FIFO: begin
                    if (!fifo_empty)
                        state <= POP_FIFO;
                end

                POP_FIFO: begin
                    if (!fifo_empty)
                        state <= CAPTURE_DATA;
                    else
                        state <= WAIT_FIFO;
                end

                CAPTURE_DATA: begin
                    data_buffer <= fifo_r_data;
                    state       <= WRITE_REQ;
                end

                WRITE_REQ: begin
                    if (dst_write_ready) begin
                        if (words_left == 1) begin
                            words_left <= '0;
                            state      <= DONE;
                        end
                        else begin
                            current_addr <= current_addr + 32'd4;
                            words_left   <= words_left - 32'd1;
                            state        <= WAIT_FIFO;
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
        fifo_r_en     = 1'b0;

        dst_addr      = current_addr;
        dst_write_data = data_buffer;
        dst_write_req = 1'b0;

        busy = 1'b1;
        done = 1'b0;

        case (state)

            IDLE: begin
                busy = 1'b0;
            end

            POP_FIFO: begin
                if (!fifo_empty)
                    fifo_r_en = 1'b1;
            end

            WRITE_REQ: begin
                dst_write_req = 1'b1;
            end

            DONE: begin
                busy = 1'b0;
                done = 1'b1;
            end

            default: begin
            end

        endcase
    end

endmodule
