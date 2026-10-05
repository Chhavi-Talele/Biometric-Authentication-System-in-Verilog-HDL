// ============================================================================
// Module Name:  matcher_engine
// Description:  Multi-Dimensional Spatial Minutiae Distance Accelerator
// Standard:     IEEE 1364-2001 Verilog HDL
// Target FPGA:  AMD Vivado (Artix-7 xc7a35tcsg324-1)
//
// Mathematical Specification:
//   D = |X_scan - X_stored| + |Y_scan - Y_stored| + 
//       |Theta_scan - Theta_stored| + |Density_scan - Density_stored|
//
// Decision Rules:
//   - If !quality_acceptable => is_match = 0 (Instant anti-spoof auto-rejection)
//   - Else if D <= dynamic_threshold => is_match = 1
//   - Else => is_match = 0
// ============================================================================

`timescale 1ns / 1ps

module matcher_engine (
    input  wire [7:0]  scan_x,              // Scanned X centroid [0..255]
    input  wire [7:0]  scan_y,              // Scanned Y centroid [0..255]
    input  wire [7:0]  scan_theta,          // Scanned Orientation Theta [0..255]
    input  wire [7:0]  scan_density,        // Scanned Ridge Density [0..255]
    input  wire [7:0]  stored_x,            // Stored vault X centroid [0..255]
    input  wire [7:0]  stored_y,            // Stored vault Y centroid [0..255]
    input  wire [7:0]  stored_theta,        // Stored vault Orientation Theta [0..255]
    input  wire [7:0]  stored_density,      // Stored vault Ridge Density [0..255]
    input  wire [7:0]  dynamic_threshold,   // Dynamic threshold T(Q) from threshold_calculator
    input  wire        quality_acceptable,  // Quality flag from quality_analyzer
    output reg  [11:0] total_distance,      // 12-bit Manhattan distance accumulator (max 4*255=1020)
    output reg         is_match             // Active-high match flag (1 = Match, 0 = Reject)
);

    // Individual absolute difference components
    wire [7:0] diff_x;
    wire [7:0] diff_y;
    wire [7:0] diff_theta;
    wire [7:0] diff_density;

    // Zero-overhead absolute subtraction hardware blocks
    assign diff_x       = (scan_x >= stored_x)             ? (scan_x - stored_x)             : (stored_x - scan_x);
    assign diff_y       = (scan_y >= stored_y)             ? (scan_y - stored_y)             : (stored_y - scan_y);
    assign diff_theta   = (scan_theta >= stored_theta)     ? (scan_theta - stored_theta)     : (stored_theta - scan_theta);
    assign diff_density = (scan_density >= stored_density) ? (scan_density - stored_density) : (stored_density - scan_density);

    always @(*) begin
        // Compute 4-dimensional absolute Manhattan distance
        total_distance = diff_x + diff_y + diff_theta + diff_density;

        // Hardware Gated Decision Engine
        if (!quality_acceptable) begin
            is_match = 1'b0; // Instant anti-spoof auto-rejection due to degraded/spoof quality
        end else if (total_distance <= {4'b0000, dynamic_threshold}) begin
            is_match = 1'b1; // Authenticated match (Distance <= Dynamic Threshold)
        end else begin
            is_match = 1'b0; // Mismatch / Imposter attempt
        end
    end

endmodule
