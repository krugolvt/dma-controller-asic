// Latch-based integrated clock gating (ICG) cell.
//
// Why not just `assign gclk = clk & en;`?
//   `en` is produced by logic clocked on (a gated version of) `clk`, so it
//   changes shortly after every rising edge, i.e. while clk is HIGH. An AND
//   gate would pass those changes straight through: en falling mid-high-phase
//   truncates the pulse, en rising mid-high-phase creates a runt pulse, and
//   any combinational hazard on en shows up as a glitch on the clock. Any of
//   these can clock a flop with a pulse that violates its minimum width.
//
// Fix: a level-sensitive latch that is transparent only while clk is LOW.
//   The enable is allowed to settle during the low phase, the latch closes at
//   the rising edge, and the value is held for the whole high phase. gclk is
//   then either a full-width copy of the clk high pulse or flat low. It cannot
//   glitch, because the AND gate's second input never changes while clk is high.
//
// te (test enable) is ORed in ahead of the latch so that during scan shift
// every flop downstream of this cell receives a clock regardless of the
// functional enable. It goes through the same latch, so it is glitch-free too.
//
// In a real flow this module is replaced by the library ICG cell (e.g.
// a CKLNQD/ICGx cell); this behavioral model matches its function.
module icg_cell (
    input  logic clk,
    input  logic en,
    input  logic te,
    output logic gclk
);

    logic en_latched;

    // Intentional latch: this is the whole point of the cell.
    // Lint (COMBDLY) flags '<=' in always_latch; a non-blocking
    // assignment is the standard way to model a latch and is race-free
    // here (en_latched only changes while clk is low), so waive it locally.
    /* verilator lint_off COMBDLY */
    always_latch begin
        if (!clk)
            en_latched <= en | te;
    end
    /* verilator lint_on COMBDLY */

    assign gclk = clk & en_latched;

`ifndef SYNTHESIS
    // ------------------------------------------------------------------
    // Assertions
    // ------------------------------------------------------------------

    // (en | te) as seen by the latch at each rising edge of clk. Read in the
    // active region, before any NBA triggered by this edge lands, so it is
    // the pre-edge value -- the same value the latch closed on.
    logic en_at_rise;
    logic te_at_rise;

    always @(posedge clk) begin
        en_at_rise <= en | te;
        te_at_rise <= te;
    end

    // Sampled at the falling edge of clk, $sampled(gclk) is the value gclk
    // held during the preceding high phase.

    // No gclk pulse on a cycle whose enable (en | te) was 0.
    a_no_edge_when_disabled: assert property (
        @(negedge clk) (en_at_rise === 1'b0) |-> !gclk
    ) else $error("icg_cell %m: gclk pulsed while en=0 and te=0");

    // te=1 forces gclk on (scan shift must reach every flop).
    a_te_forces_clock: assert property (
        @(negedge clk) (te_at_rise === 1'b1) |-> gclk
    ) else $error("icg_cell %m: te=1 but gclk did not toggle");

    // Glitch freedom: the latched enable may only change while clk is low ...
    always @(en_latched) begin
        a_latch_stable_when_high: assert (clk !== 1'b1)
            else $error("icg_cell %m: latched enable changed while clk high");
    end

    // ... so gclk can only fall together with clk (never a truncated pulse).
    always @(negedge gclk) begin
        a_no_truncated_pulse: assert (clk === 1'b0)
            else $error("icg_cell %m: gclk fell while clk was high");
    end
`endif

endmodule
