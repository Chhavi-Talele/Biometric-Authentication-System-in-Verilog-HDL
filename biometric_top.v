// ============================================================================
// Module Name:  biometric_top
// Description:  Top-Level Tamper-Resilient Edge Biometric Authentication System-on-Chip (SoC)
// Standard:     IEEE 1364-2001 Verilog HDL
// Target FPGA:  AMD Vivado (Artix-7 xc7a35tcsg324-1)
//
// Structural Integration of 5 Sub-Modules:
//   1. quality_analyzer        : Multi-Factor Biometric Quality Fusion Engine
//   2. threshold_calculator    : Continuous PWL Dynamic Threshold Generator T(Q)
//   3. secure_template_vault   : 4-User Storage & 3-Pass DoD/NIST Zeroization Engine
//   4. matcher_engine          : 4D Manhattan Distance Match Accelerator
//   5. auth_controller         : Master 7-State Security Control FSM
// ============================================================================

`timescale 1ns / 1ps

module biometric_top (
    input  wire        clk,                // 100 MHz System Clock
    input  wire        rst_n,              // Active-Low Asynchronous Reset
    input  wire        start_scan,         // Scan Trigger Command
    input  wire        tamper_pin,         // Physical Tamper Sensor Input
    input  wire        ttl_expired,        // Key Lifetime Expiry Signal
    input  wire [1:0]  user_addr,          // Target Enrolled User Index [0..3]
    input  wire [7:0]  scan_x,             // Scanned Centroid X Coordinate [0..255]
    input  wire [7:0]  scan_y,             // Scanned Centroid Y Coordinate [0..255]
    input  wire [7:0]  scan_theta,         // Scanned Ridge Orientation Theta [0..255]
    input  wire [7:0]  scan_density,       // Scanned Ridge Density [0..255]
    input  wire [7:0]  sensor_noise,       // Sensor Surface Noise [0..255]
    input  wire [7:0]  ridge_contrast,     // Ridge Contrast [0..255]
    input  wire [7:0]  spatial_uniformity, // Spatial Uniformity [0..255]
    output wire [7:0]  quality_score,      // Fused Quality Index [0..255]
    output wire [1:0]  quality_grade,      // Quality Grade: 11=Pristine, 10=Good, 01=Degraded, 00=Reject
    output wire        quality_acceptable, // Active-High Quality Flag
    output wire [7:0]  dynamic_threshold,  // Dynamic Threshold T(Q)
    output wire [11:0] total_distance,     // 4D Absolute Manhattan Error Distance
    output wire        is_match,           // Matcher Engine Output Flag
    output wire        zeroize_trigger,    // Hardware Memory Purge Trigger
    output wire        access_granted,     // Active-High Unlock Pulse
    output wire        access_denied,      // Active-High Reject Pulse
    output wire [1:0]  fail_count,         // Failed Attempt Strike Counter [0..3]
    output wire        templates_wiped,    // Zeroization Status Flag (wipe_done)
    output wire        lockdown,           // Permanent System Lock Flag
    output wire        tamper_alert        // Tamper Intrusion Alarm
);

    // Internal interconnect wires
    wire [31:0] template_out;
    wire        wipe_done;

    // Unpack 32-bit stored vector components from secure_template_vault
    wire [7:0] stored_x       = template_out[31:24];
    wire [7:0] stored_y       = template_out[23:16];
    wire [7:0] stored_theta   = template_out[15:8];
    wire [7:0] stored_density = template_out[7:0];

    // Connect templates_wiped to wipe_done
    assign templates_wiped = wipe_done;

    // ------------------------------------------------------------------------
    // Module 1: Quality Analyzer Engine
    // ------------------------------------------------------------------------
    quality_analyzer u_quality_analyzer (
        .sensor_noise       (sensor_noise),
        .ridge_contrast     (ridge_contrast),
        .spatial_uniformity (spatial_uniformity),
        .quality_score      (quality_score),
        .quality_grade      (quality_grade),
        .quality_acceptable (quality_acceptable)
    );

    // ------------------------------------------------------------------------
    // Module 2: Continuous Dynamic Threshold Calculator
    // ------------------------------------------------------------------------
    threshold_calculator #(
        .T_BASE (8'd8),
        .T_MAX  (8'd28)
    ) u_threshold_calculator (
        .quality_score     (quality_score),
        .dynamic_threshold (dynamic_threshold)
    );

    // ------------------------------------------------------------------------
    // Module 3: Secure Template Vault with 3-Pass Zeroization
    // ------------------------------------------------------------------------
    secure_template_vault u_secure_template_vault (
        .clk             (clk),
        .rst_n           (rst_n),
        .zeroize_trigger (zeroize_trigger),
        .user_addr       (user_addr),
        .template_out    (template_out),
        .wipe_done       (wipe_done)
    );

    // ------------------------------------------------------------------------
    // Module 4: 4-Dimensional Spatial Matcher Engine
    // ------------------------------------------------------------------------
    matcher_engine u_matcher_engine (
        .scan_x             (scan_x),
        .scan_y             (scan_y),
        .scan_theta         (scan_theta),
        .scan_density       (scan_density),
        .stored_x           (stored_x),
        .stored_y           (stored_y),
        .stored_theta       (stored_theta),
        .stored_density     (stored_density),
        .dynamic_threshold  (dynamic_threshold),
        .quality_acceptable (quality_acceptable),
        .total_distance     (total_distance),
        .is_match           (is_match)
    );

    // ------------------------------------------------------------------------
    // Module 5: Master Authentication Controller FSM
    // ------------------------------------------------------------------------
    auth_controller #(
        .PENALTY_COOLDOWN (16'd10)
    ) u_auth_controller (
        .clk             (clk),
        .rst_n           (rst_n),
        .start_scan      (start_scan),
        .is_match        (is_match),
        .tamper_pin      (tamper_pin),
        .ttl_expired     (ttl_expired),
        .wipe_done       (wipe_done),
        .zeroize_trigger (zeroize_trigger),
        .access_granted  (access_granted),
        .access_denied   (access_denied),
        .fail_count      (fail_count),
        .templates_wiped (templates_wiped),
        .lockdown        (lockdown),
        .tamper_alert    (tamper_alert)
    );

endmodule
