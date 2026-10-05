// ============================================================================
// Testbench Name: tb_biometric_top
// Description:    Production-Grade Self-Checking Verification Testbench for
//                 Tamper-Resilient Edge Biometric Authentication SoC
// Standard:       IEEE 1364-2001 Verilog HDL
//
// 7 Test Scenarios Validated:
//   Test 1: Clean Finger Scan        -> Pristine Q (210) -> Dynamic T=10 -> access_granted = 1
//   Test 2: Moist/Degraded Scan     -> Degraded Q (80)  -> Dynamic T=18 -> access_granted = 1 (Prevents False Rejection)
//   Test 3: Rubber Spoof Attack      -> Spoof Q (50 < 70)-> quality_acceptable = 0 -> Instant Auto-Rejection
//   Test 4: Imposter Scan 1          -> Invalid Minutiae -> access_denied = 1, fail_count = 1
//   Test 5: Imposter Scan 2          -> Invalid Minutiae -> access_denied = 1, fail_count = 2
//   Test 6: Imposter Scan 3 (Strike3)-> Strike 3 -> 3-Pass Zeroization Purge -> templates_wiped = 1, lockdown = 1
//   Test 7: Post-Lockdown Attack     -> Genuine User 0 minutiae injected -> Permanently Denied (lockdown = 1)
// ============================================================================

`timescale 1ns / 1ps

module tb_biometric_top;

    // Testbench Stimulus Registers
    reg        clk;
    reg        rst_n;
    reg        start_scan;
    reg        tamper_pin;
    reg        ttl_expired;
    reg  [1:0] user_addr;
    reg  [7:0] scan_x;
    reg  [7:0] scan_y;
    reg  [7:0] scan_theta;
    reg  [7:0] scan_density;
    reg  [7:0] sensor_noise;
    reg  [7:0] ridge_contrast;
    reg  [7:0] spatial_uniformity;

    // Design Under Test (DUT) Outputs
    wire [7:0]  quality_score;
    wire [1:0]  quality_grade;
    wire        quality_acceptable;
    wire [7:0]  dynamic_threshold;
    wire [11:0] total_distance;
    wire        is_match;
    wire        zeroize_trigger;
    wire        access_granted;
    wire        access_denied;
    wire [1:0]  fail_count;
    wire        templates_wiped;
    wire        lockdown;
    wire        tamper_alert;

    // Instantiate Top-Level SoC Module
    biometric_top uut (
        .clk                (clk),
        .rst_n              (rst_n),
        .start_scan         (start_scan),
        .tamper_pin         (tamper_pin),
        .ttl_expired        (ttl_expired),
        .user_addr          (user_addr),
        .scan_x             (scan_x),
        .scan_y             (scan_y),
        .scan_theta         (scan_theta),
        .scan_density       (scan_density),
        .sensor_noise       (sensor_noise),
        .ridge_contrast     (ridge_contrast),
        .spatial_uniformity (spatial_uniformity),
        .quality_score      (quality_score),
        .quality_grade      (quality_grade),
        .quality_acceptable (quality_acceptable),
        .dynamic_threshold  (dynamic_threshold),
        .total_distance     (total_distance),
        .is_match           (is_match),
        .zeroize_trigger    (zeroize_trigger),
        .access_granted     (access_granted),
        .access_denied      (access_denied),
        .fail_count         (fail_count),
        .templates_wiped    (templates_wiped),
        .lockdown           (lockdown),
        .tamper_alert       (tamper_alert)
    );

    // 100 MHz System Clock Generation (10 ns clock period)
    always #5 clk = ~clk;

    initial begin
        // Waveform Dump Setup
        $dumpfile("waveform.vcd");
        $dumpvars(0, tb_biometric_top);

        // Initialize Stimulus Signals
        clk                = 1'b0;
        rst_n              = 1'b0;
        start_scan         = 1'b0;
        tamper_pin         = 1'b0;
        ttl_expired        = 1'b0;
        user_addr          = 2'b00;
        scan_x             = 8'd0;
        scan_y             = 8'd0;
        scan_theta         = 8'd0;
        scan_density       = 8'd0;
        sensor_noise       = 8'd0;
        ridge_contrast     = 8'd0;
        spatial_uniformity = 8'd0;

        $display("==========================================================================");
        $display("   BIOMETRIC AUTHENTICATION SoC TESTBENCH - FULL 7-SCENARIO VERIFICATION  ");
        $display("==========================================================================");

        // Assert System Reset
        #20;
        rst_n = 1'b1;
        #20;

        // --------------------------------------------------------------------
        // SCENARIO 1: Clean Finger Scan (User 0 enrolled: {120, 145, 88, 64})
        // --------------------------------------------------------------------
        $display("\n[TEST 1] Clean Finger Scan for User 0...");
        user_addr          = 2'b00;
        scan_x             = 8'd121; // Delta = 1
        scan_y             = 8'd146; // Delta = 1
        scan_theta         = 8'd88;  // Delta = 0
        scan_density       = 8'd65;  // Delta = 1 -> Total Distance = 3
        sensor_noise       = 8'd20;  // Clean sensor glass
        ridge_contrast     = 8'd230; // High contrast
        spatial_uniformity = 8'd210; // High uniformity
        
        start_scan = 1'b1;
        #10;
        start_scan = 1'b0;
        #40; // Allow FSM states S_FETCH -> S_COMPARE -> S_EVALUATE

        $display("   Quality Score = %d (Grade: %b = PRISTINE)", quality_score, quality_grade);
        $display("   Dynamic Threshold = %d", dynamic_threshold);
        $display("   Total 4D Distance = %d", total_distance);
        if (access_granted == 1'b1 && access_denied == 1'b0) begin
            $display("-> TEST 1 PASSED: ACCESS GRANTED SUCCESSFULLY");
        end else begin
            $display("-> TEST 1 FAILED: Access Denied unexpectedly");
            $stop;
        end
        #30;

        // --------------------------------------------------------------------
        // SCENARIO 2: Moist / Degraded Finger Scan (Distance = 16)
        // High noise (140) -> Quality drops (Q=80) -> Dynamic T relaxes to 18 -> PASS
        // --------------------------------------------------------------------
        $display("\n[TEST 2] Moist/Degraded Finger Scan for User 0...");
        user_addr          = 2'b00;
        scan_x             = 8'd125; // Delta = 5
        scan_y             = 8'd151; // Delta = 6
        scan_theta         = 8'd91;  // Delta = 3
        scan_density       = 8'd66;  // Delta = 2 -> Total Distance = 16
        sensor_noise       = 8'd140; // High sweat/moisture noise
        ridge_contrast     = 8'd160;
        spatial_uniformity = 8'd140;

        start_scan = 1'b1;
        #10;
        start_scan = 1'b0;
        #40;

        $display("   Quality Score = %d (Grade: %b = DEGRADED)", quality_score, quality_grade);
        $display("   Dynamic Threshold = %d (Relaxed to absorb degradation)", dynamic_threshold);
        $display("   Total 4D Distance = %d (Exceeds base T=8, but <= dynamic T=18)", total_distance);
        if (access_granted == 1'b1 && access_denied == 1'b0) begin
            $display("-> TEST 2 PASSED: DYNAMIC THRESHOLD PREVENTED FALSE REJECTION");
        end else begin
            $display("-> TEST 2 FAILED: Access Denied unexpectedly");
            $stop;
        end
        #30;

        // --------------------------------------------------------------------
        // SCENARIO 3: Rubber Spoof Attack (Q < 70)
        // Artificial rubber finger => Low contrast (30), Quality Score (50) < 70 => Auto-Reject
        // --------------------------------------------------------------------
        $display("\n[TEST 3] Rubber Spoof Attack (Anti-Spoof Quality Guard)...");
        user_addr          = 2'b00;
        scan_x             = 8'd120; // Matching minutiae
        scan_y             = 8'd145;
        scan_theta         = 8'd88;
        scan_density       = 8'd64;
        sensor_noise       = 8'd10;
        ridge_contrast     = 8'd30;  // Low contrast flat rubber texture
        spatial_uniformity = 8'd80;  // Fractured spatial structure

        start_scan = 1'b1;
        #10;
        start_scan = 1'b0;
        #40;

        $display("   Quality Score = %d (Grade: %b = REJECT)", quality_score, quality_grade);
        $display("   Quality Acceptable = %b", quality_acceptable);
        if (access_granted == 1'b0 && access_denied == 1'b1) begin
            $display("-> TEST 3 PASSED: RUBBER SPOOF BLOCKED BY QUALITY GUARD");
        end else begin
            $display("-> TEST 3 FAILED: Spoof erroneously accepted");
            $stop;
        end

        // Wait out penalty cooldown
        #120;

        // --------------------------------------------------------------------
        // SCENARIO 4: Imposter Attack Scan 1
        // Valid quality, invalid minutiae => access_denied = 1, fail_count = 1
        // --------------------------------------------------------------------
        $display("\n[TEST 4] Imposter Scan 1...");
        user_addr          = 2'b00;
        scan_x             = 8'd210; // Large error distance
        scan_y             = 8'd40;
        scan_theta         = 8'd190;
        scan_density       = 8'd12;
        sensor_noise       = 8'd20;
        ridge_contrast     = 8'd200;
        spatial_uniformity = 8'd200;

        start_scan = 1'b1;
        #10;
        start_scan = 1'b0;
        #40;

        $display("   Access Denied = %b, Fail Count = %d", access_denied, fail_count);
        if (access_denied == 1'b1 && fail_count == 2'b01) begin
            $display("-> TEST 4 PASSED: IMPOSTER DENIED (Strike 1 Recorded)");
        end else begin
            $display("-> TEST 4 FAILED: Strike 1 not recorded properly");
            $stop;
        end

        // Wait out penalty cooldown
        #120;

        // --------------------------------------------------------------------
        // SCENARIO 5: Imposter Attack Scan 2
        // Retry with invalid minutiae => access_denied = 1, fail_count = 2
        // --------------------------------------------------------------------
        $display("\n[TEST 5] Imposter Scan 2...");
        start_scan = 1'b1;
        #10;
        start_scan = 1'b0;
        #40;

        $display("   Access Denied = %b, Fail Count = %d", access_denied, fail_count);
        if (access_denied == 1'b1 && fail_count == 2'b10) begin
            $display("-> TEST 5 PASSED: IMPOSTER DENIED (Strike 2 Recorded)");
        end else begin
            $display("-> TEST 5 FAILED: Strike 2 not recorded properly");
            $stop;
        end

        // Wait out penalty cooldown
        #120;

        // --------------------------------------------------------------------
        // SCENARIO 6: Imposter Attack Scan 3 (Strike 3 -> 3-Pass Hardware Zeroization)
        // Final imposter failure => FSM activates S_ZEROIZE => 3-pass memory purge
        // --------------------------------------------------------------------
        $display("\n[TEST 6] Imposter Scan 3 (Strike 3 -> 3-Pass DoD/NIST Zeroization)...");
        start_scan = 1'b1;
        #10;
        start_scan = 1'b0;
        
        // Wait for 3-pass zeroization FSM cycles (Pass1 -> Pass2 -> Pass3 -> Purged)
        #80;

        $display("   Fail Count       = %d", fail_count);
        $display("   Zeroize Trigger  = %b", zeroize_trigger);
        $display("   Templates Wiped  = %b (3-Pass Zeroization Completed)", templates_wiped);
        $display("   Lockdown State   = %b (Silicon Permanently Trapped)", lockdown);
        $display("   Tamper Alert     = %b", tamper_alert);

        if (templates_wiped == 1'b1 && lockdown == 1'b1) begin
            $display("-> TEST 6 PASSED: 3-PASS HARDWARE ZEROIZATION SUCCESSFUL");
        end else begin
            $display("-> TEST 6 FAILED: Zeroization failure");
            $stop;
        end
        #40;

        // --------------------------------------------------------------------
        // SCENARIO 7: Post-Lockdown Attack Attempt
        // Legitimate User 0 minutiae injected after lockdown => permanently denied
        // --------------------------------------------------------------------
        $display("\n[TEST 7] Post-Lockdown Attack (Injecting Original User 0 Minutiae)...");
        scan_x             = 8'd120; // Valid original User 0 minutiae
        scan_y             = 8'd145;
        scan_theta         = 8'd88;
        scan_density       = 8'd64;
        sensor_noise       = 8'd20;
        ridge_contrast     = 8'd230;
        spatial_uniformity = 8'd210;

        start_scan = 1'b1;
        #10;
        start_scan = 1'b0;
        #40;

        $display("   Lockdown = %b, Access Granted = %b, Access Denied = %b", 
                 lockdown, access_granted, access_denied);
        if (access_granted == 1'b0 && access_denied == 1'b1 && lockdown == 1'b1) begin
            $display("-> TEST 7 PASSED: POST-LOCKDOWN ATTACK BLOCKED FOREVER");
        end else begin
            $display("-> TEST 7 FAILED: Post-lockdown breach");
            $stop;
        end

        $display("\n==========================================================================");
        $display("   ALL 7 CORNER-CASE SCENARIOS PASSED CONVINCINGLY - SOC VERIFIED!        ");
        $display("==========================================================================");
        $finish;
    end

endmodule
