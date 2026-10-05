// ============================================================================
// Module Name:  auth_controller
// Description:  Master Security Control FSM with Progressive Penalty Lockout,
//               Anti-Tamper Fast Path, and Autonomous Memory Zeroization
// Standard:     IEEE 1364-2001 Verilog HDL
// Target FPGA:  AMD Vivado (Artix-7 xc7a35tcsg324-1)
//
// 7-State FSM Specification:
//   S_IDLE     (3'b000): Wait for assertion of start_scan.
//   S_FETCH    (3'b001): Fetch 32-bit biometric template vector from vault.
//   S_COMPARE  (3'b010): Pipeline 4D Manhattan distance computation.
//   S_EVALUATE (3'b011): Determine access result.
//                       If match => assert access_granted, clear fail_count, return to S_IDLE.
//                       If fail => increment fail_count.
//   S_PENALTY  (3'b100): Apply temporary cycle penalty for failed match attempts (1 <= fail_count < 3).
//   S_ZEROIZE  (3'b101): Triggered if fail_count == 3, tamper_pin == 1, or ttl_expired == 1.
//                       Assert zeroize_trigger and wait for wipe_done.
//   S_LOCKDOWN (3'b110): Irreversible trap state. Silicon locked forever; access_denied=1, lockdown=1.
// ============================================================================

`timescale 1ns / 1ps

module auth_controller #(
    parameter [15:0] PENALTY_COOLDOWN = 16'd10 // Cooldown clock cycles between failed retries
)(
    input  wire       clk,              // System clock (100 MHz)
    input  wire       rst_n,            // Active-low asynchronous reset
    input  wire       start_scan,       // Trigger scan sequence
    input  wire       is_match,         // Result from matcher_engine
    input  wire       tamper_pin,       // Physical enclosure tamper breach sensor input
    input  wire       ttl_expired,      // Key lifetime expiry signal
    input  wire       wipe_done,        // Status from secure_template_vault zeroization
    output reg        zeroize_trigger,  // Trigger autonomous zeroization purge
    output reg        access_granted,   // Active-high unlock pulse
    output reg        access_denied,    // Active-high reject pulse
    output reg  [1:0] fail_count,       // Failed attempt counter [0..3]
    output reg        templates_wiped,  // Status indicating templates have been purged
    output reg        lockdown,         // Active-high permanent lockdown flag
    output reg        tamper_alert      // Active-high tamper alarm
);

    // FSM 7-State Encoding
    localparam [2:0] S_IDLE     = 3'b000;
    localparam [2:0] S_FETCH    = 3'b001;
    localparam [2:0] S_COMPARE  = 3'b010;
    localparam [2:0] S_EVALUATE = 3'b011;
    localparam [2:0] S_PENALTY  = 3'b100;
    localparam [2:0] S_ZEROIZE  = 3'b101;
    localparam [2:0] S_LOCKDOWN = 3'b110;

    reg [2:0]  state_reg, next_state;
    reg [15:0] penalty_timer;

    // ------------------------------------------------------------------------
    // FSM State Register Update
    // ------------------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state_reg <= S_IDLE;
        end else begin
            state_reg <= next_state;
        end
    end

    // ------------------------------------------------------------------------
    // Next State Logic
    // ------------------------------------------------------------------------
    always @(*) begin
        case (state_reg)
            S_IDLE: begin
                if (tamper_pin || ttl_expired) begin
                    next_state = S_ZEROIZE;
                end else if (start_scan) begin
                    next_state = S_FETCH;
                end else begin
                    next_state = S_IDLE;
                end
            end

            S_FETCH: begin
                if (tamper_pin || ttl_expired) begin
                    next_state = S_ZEROIZE;
                end else begin
                    next_state = S_COMPARE;
                end
            end

            S_COMPARE: begin
                if (tamper_pin || ttl_expired) begin
                    next_state = S_ZEROIZE;
                end else begin
                    next_state = S_EVALUATE;
                end
            end

            S_EVALUATE: begin
                if (tamper_pin || ttl_expired) begin
                    next_state = S_ZEROIZE;
                end else if (is_match) begin
                    next_state = S_IDLE; // Authenticated match => return to IDLE
                end else begin
                    // If fail_count was 2 (so next increment makes it 3), trigger zeroize!
                    if (fail_count >= 2'b10) begin
                        next_state = S_ZEROIZE; // Strike 3 => Autonomous Zeroization
                    end else begin
                        next_state = S_PENALTY; // Strike 1 or 2 => Cooldown Penalty
                    end
                end
            end

            S_PENALTY: begin
                if (tamper_pin || ttl_expired) begin
                    next_state = S_ZEROIZE;
                end else if (penalty_timer >= PENALTY_COOLDOWN) begin
                    next_state = S_IDLE;
                end else begin
                    next_state = S_PENALTY;
                end
            end

            S_ZEROIZE: begin
                if (wipe_done) begin
                    next_state = S_LOCKDOWN; // Purge complete => Irreversible lockdown
                end else begin
                    next_state = S_ZEROIZE;
                end
            end

            S_LOCKDOWN: begin
                next_state = S_LOCKDOWN; // Irreversible trap state
            end

            default: next_state = S_IDLE;
        endcase
    end

    // ------------------------------------------------------------------------
    // Output Registers & Datapath Execution
    // ------------------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            zeroize_trigger <= 1'b0;
            access_granted  <= 1'b0;
            access_denied   <= 1'b0;
            fail_count      <= 2'b00;
            templates_wiped <= 1'b0;
            lockdown        <= 1'b0;
            tamper_alert    <= 1'b0;
            penalty_timer   <= 16'd0;
        end else begin
            // Default pulse signals
            access_granted <= 1'b0;
            access_denied  <= 1'b0;

            case (state_reg)
                S_IDLE: begin
                    penalty_timer <= 16'd0;
                end

                S_FETCH, S_COMPARE: begin
                    // Pipelined processing steps
                end

                S_EVALUATE: begin
                    if (is_match) begin
                        access_granted <= 1'b1;
                        access_denied  <= 1'b0;
                        fail_count     <= 2'b00; // Reset strike counter on successful auth
                    end else begin
                        access_granted <= 1'b0;
                        access_denied  <= 1'b1;
                        fail_count     <= fail_count + 1'b1; // Increment strike count
                    end
                end

                S_PENALTY: begin
                    access_denied <= 1'b1; // Retain access_denied indication during penalty
                    penalty_timer <= penalty_timer + 1'b1;
                end

                S_ZEROIZE: begin
                    zeroize_trigger <= 1'b1;
                    access_granted  <= 1'b0;
                    access_denied   <= 1'b1;
                    tamper_alert    <= 1'b1;
                    if (wipe_done) begin
                        templates_wiped <= 1'b1;
                    end
                end

                S_LOCKDOWN: begin
                    zeroize_trigger <= 1'b0;
                    access_granted  <= 1'b0;
                    access_denied   <= 1'b1;
                    lockdown        <= 1'b1;
                    tamper_alert    <= 1'b1;
                    templates_wiped <= 1'b1;
                end
            endcase
        end
    end

endmodule
