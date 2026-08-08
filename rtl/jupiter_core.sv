//============================================================================
//
//  Jupiter Core Skeleton — Milestone 1A
//
//  Minimal deterministic RTL that proves Jupiter-owned code can:
//    - Compile
//    - Respond to reset
//    - Advance state deterministically
//
//  This module is intentionally NOT a CPU, GPU, DMA, audio, SDRAM, or
//  controller implementation. It is a counter heartbeat useful for
//  smoke-testing the simulation flow.
//
//============================================================================

module jupiter_core
(
    input  wire         clk,
    input  wire         reset,

    // Observables for smoke-test verification
    output reg  [7:0]   heartbeat,    // toggles every clock cycle
    output reg  [3:0]   tick_cnt,     // simple up-counter, advances on every clk after reset
    output reg          done_pulse      // single-cycle pulse when tick_cnt == 4'd15
);

//--- Initial / reset state -------------------------------------------
// On rising edge of active-high `reset`, heartbeat and tick_cnt return
// to their documented initial values.

always @(posedge clk) begin
    if (reset) begin
        heartbeat <= 8'h00;
        tick_cnt  <= 4'd0;
        done_pulse <= 1'b0;
    end else begin
        heartbeat <= ~heartbeat;          // toggles every cycle → known pattern
        tick_cnt  <= tick_cnt + 4'd1;     // deterministic increment

        // Single-cycle pulse when counter wraps near top
        done_pulse <= (tick_cnt == 4'd15);
    end
end

endmodule
