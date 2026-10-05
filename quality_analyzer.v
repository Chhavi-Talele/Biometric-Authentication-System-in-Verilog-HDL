// ============================================================================
// Module Name:  quality_analyzer
// Description:  Multi-Factor Biometric Quality Fusion Engine
// Standard:     IEEE 1364-2001 Verilog HDL
// Target FPGA:  AMD Vivado (Artix-7 xc7a35tcsg324-1)
//
// Mathematical Specification:
//   Q = ((ridge_contrast + spatial_uniformity) / 2) - (sensor_noise / 2)
//
// Grade Decoding & Acceptability Rules:
//   Q >= 200          => Grade 2'b11 (Pristine),  quality_acceptable = 1
//   140 <= Q < 200    => Grade 2'b10 (Good),      quality_acceptable = 1
//   70  <= Q < 140    => Grade 2'b01 (Degraded),  quality_acceptable = 1
//   Q < 70            => Grade 2'b00 (Reject),    quality_acceptable = 0 (Anti-spoof auto-reject)
// ============================================================================

`timescale 1ns / 1ps

module quality_analyzer (
    input  wire [7:0] sensor_noise,         // 0 = clean, 255 = heavily degraded
    input  wire [7:0] ridge_contrast,       // 0 = blurred, 255 = sharp
    input  wire [7:0] spatial_uniformity,   // 0 = fractured, 255 = intact
    output reg  [7:0] quality_score,        // Fused quality index [0..255]
    output reg  [1:0] quality_grade,        // 2'b11=Pristine, 2'b10=Good, 2'b01=Degraded, 2'b00=Reject/Spoof
    output reg        quality_acceptable    // Active-high logic flag (1 = Pass to matcher, 0 = Reject)
);

    // Quality Grade Encodings
    localparam [1:0] GRADE_REJECT   = 2'b00; // Q < 70: Unacceptable (corrupted scan or rubber spoof)
    localparam [1:0] GRADE_DEGRADED = 2'b01; // 70 <= Q < 140: Sweaty / dry / noisy finger
    localparam [1:0] GRADE_GOOD     = 2'b10; // 140 <= Q < 200: Normal clean finger
    localparam [1:0] GRADE_PRISTINE = 2'b11; // Q >= 200: Studio-grade pristine scan

    // Internal intermediate registers (9-bit arithmetic prevents overflow/underflow)
    reg [8:0] positive_component;
    reg [8:0] noise_penalty;
    reg [8:0] q_raw;

    always @(*) begin
        // --------------------------------------------------------------------
        // 1. Multi-Factor Quality Index Fusion:
        //    Positive Component = (ridge_contrast + spatial_uniformity) >> 1
        //    Noise Penalty      = sensor_noise >> 1
        //    Q_raw              = Positive Component - Noise Penalty
        //    Uses hardware right-shifts (>> 1) instead of dividers for VLSI efficiency.
        // --------------------------------------------------------------------
        positive_component = (ridge_contrast + spatial_uniformity) >> 1;
        noise_penalty      = sensor_noise >> 1;

        if (positive_component >= noise_penalty) begin
            q_raw = positive_component - noise_penalty;
        end else begin
            q_raw = 9'd0; // Underflow protection (clamp lower bound to 0)
        end

        // --------------------------------------------------------------------
        // 2. Saturation Logic: Strictly clamp values to [0, 255]
        // --------------------------------------------------------------------
        if (q_raw > 9'd255) begin
            quality_score = 8'd255;
        end else begin
            quality_score = q_raw[7:0];
        end

        // --------------------------------------------------------------------
        // 3. Hardware Grade Decoding & Anti-Spoof Quality Guard Thresholds
        // --------------------------------------------------------------------
        if (quality_score >= 8'd200) begin
            quality_grade      = GRADE_PRISTINE;
            quality_acceptable = 1'b1;
        end else if (quality_score >= 8'd140) begin
            quality_grade      = GRADE_GOOD;
            quality_acceptable = 1'b1;
        end else if (quality_score >= 8'd70) begin
            quality_grade      = GRADE_DEGRADED;
            quality_acceptable = 1'b1;
        end else begin
            quality_grade      = GRADE_REJECT;
            quality_acceptable = 1'b0; // Forces instant anti-spoof auto-rejection
        end
    end

endmodule
