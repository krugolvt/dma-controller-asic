// Toggle-based single-pulse synchronizer.
//
// A one-cycle pulse in the src_clk domain flips a toggle flop; the toggle is
// passed through a 2-FF synchronizer into dst_clk, and an edge detector turns
// each change back into a one-cycle pulse. Pulses must be spaced at least a few
// dst_clk cycles apart (true for DMA start/done).
//
// Both clocks must be free-running: this logic is what wakes a gated domain
// up, so it cannot sit behind that domain's clock gate.
module pulse_sync (
    input  logic src_clk,
    input  logic dst_clk,
    input  logic rst_n,
    input  logic src_pulse,
    output logic dst_pulse
);

    logic src_toggle;
    logic sync1, sync2, sync3;

    always_ff @(posedge src_clk or negedge rst_n) begin
        if (!rst_n)
            src_toggle <= 1'b0;
        else if (src_pulse)
            src_toggle <= ~src_toggle;
    end

    always_ff @(posedge dst_clk or negedge rst_n) begin
        if (!rst_n) begin
            sync1 <= 1'b0;
            sync2 <= 1'b0;
            sync3 <= 1'b0;
        end
        else begin
            sync1 <= src_toggle;
            sync2 <= sync1;
            sync3 <= sync2;
        end
    end

    assign dst_pulse = sync2 ^ sync3;

endmodule
