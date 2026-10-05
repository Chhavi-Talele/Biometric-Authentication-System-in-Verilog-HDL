// ============================================================================
// Module Name:  threshold_calculator
// Description:  Continuous Piecewise-Linear (PWL) Dynamic Threshold Generator
// Standard:     IEEE 1364-2001 Verilog HDL
// Target FPGA:  AMD Vivado (Artix-7 xc7a35tcsg324-1)
//
// Mathematical Specification:
//   T(Q) = 8 + ((255 - Q) >> 4)
//
// Constraints:
//   - Zero hardware dividers (uses right-shift >> 4 for 1/16 scaling)
//   - Saturate upper boundary at T_max = 28
// ============================================================================

`timescale 1ns / 1ps

module threshold_calculator #(
    parameter [7:0] T_BASE = 8'd8,   // Base strict threshold for pristine scans (Q=255)
    parameter [7:0] T_MAX  = 8'd28   // Maximum boundary saturation threshold for degraded scans
)(
    input  wire [7:0] quality_score,      // Input Quality Index Q in range [0..255]
    output reg  [7:0] dynamic_threshold   // Dynamic Matching Acceptance Threshold T(Q)
);

    // Internal wire arithmetic (divider-free bit-shift hardware scaling)
    wire [7:0] quality_deficit;
    wire [7:0] shift_delta;
    wire [7:0] raw_threshold;

    // Quality Deficit = (255 - Q)
    assign quality_deficit = 8'd255 - quality_score;

    // Hardware Bit-Shift: ((255 - Q) >> 4) scales deficit by 1/16 without DSP multipliers or dividers
    assign shift_delta     = quality_deficit >> 4;

    // Base Offset Addition: T(Q) = 8 + shift_delta
    assign raw_threshold   = T_BASE + shift_delta;

    always @(*) begin
        // Saturate upper boundary strictly at T_max = 28
        if (raw_threshold > T_MAX) begin
            dynamic_threshold = T_MAX;
        end else begin
            dynamic_threshold = raw_threshold;
        end
    end

endmodule
