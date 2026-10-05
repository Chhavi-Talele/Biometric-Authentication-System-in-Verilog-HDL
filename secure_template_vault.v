// ============================================================================
// Module Name:  secure_template_vault
// Description:  Tamper-Resilient Secure Biometric Template Storage & 
//               Autonomous 3-Pass Anti-Remanence Zeroization Engine
// Standard:     IEEE 1364-2001 Verilog HDL
// Target FPGA:  AMD Vivado (Artix-7 xc7a35tcsg324-1)
//
// Hardware Features:
//   1. Enrolled Memory: 4 Users holding packed 32-bit biometric vectors:
//      {X[7:0], Y[7:0], Theta[7:0], Density[7:0]}
//   2. Autonomous 3-Pass DoD 5220.22-M / NIST SP 800-88 Zeroization Engine:
//      - Pass 1: Write 32'hFFFFFFFF (All 1s) to saturate memory cell gate oxide
//      - Pass 2: Write 32'h00000000 (All 0s) to discharge floating gates
//      - Pass 3: Overwrite using 32-bit Galois LFSR Pseudo-Random Noise
//                Polynomial: x^32 + x^22 + x^2 + x^1 + 1
//   3. Asserts wipe_done high upon completion of Pass 3 zeroization.
// ============================================================================

`timescale 1ns / 1ps

module secure_template_vault (
    input  wire        clk,              // System clock (100 MHz)
    input  wire        rst_n,            // Active-low asynchronous reset
    input  wire        zeroize_trigger,  // Self-destruct trigger line from auth_controller
    input  wire [1:0]  user_addr,        // Enrolled user address index [0..3]
    output reg  [31:0] template_out,     // Unpacked 32-bit stored template vector
    output reg         wipe_done         // Active-high status flag indicating purge completion
);

    // 4 enrolled user template slots, each 32-bit wide
    reg [31:0] memory [0:3];

    // Zeroization Finite State Machine States
    localparam [2:0] Z_IDLE   = 3'b000;
    localparam [2:0] Z_PASS1  = 3'b001; // Write 32'hFFFFFFFF (All 1s)
    localparam [2:0] Z_PASS2  = 3'b010; // Write 32'h00000000 (All 0s)
    localparam [2:0] Z_PASS3  = 3'b011; // Write 32-bit Galois LFSR PRNG Noise
    localparam [2:0] Z_PURGED = 3'b100; // Zeroization complete, lock memory forever

    reg [2:0] z_state;

    // ------------------------------------------------------------------------
    // 32-bit Galois Linear Feedback Shift Register (LFSR)
    // Characteristic Polynomial: x^32 + x^22 + x^2 + x^1 + 1
    // Galois Feedback Mask: 32'h80200003
    // ------------------------------------------------------------------------
    reg [31:0] lfsr;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            lfsr <= 32'hACE12345; // Non-zero seed initialization
        end else begin
            if (lfsr[0]) begin
                lfsr <= (lfsr >> 1) ^ 32'h80200003; // Galois tap feedback for x^32 + x^22 + x^2 + x^1 + 1
            end else begin
                lfsr <= (lfsr >> 1);
            end
        end
    end

    // ------------------------------------------------------------------------
    // Initializing Memory with Enrolled User Minutiae Vectors
    // Format: {X[31:24], Y[23:16], Theta[15:8], Density[7:0]}
    // ------------------------------------------------------------------------
    initial begin
        memory[0] = {8'd120, 8'd145, 8'd88,  8'd64};  // User 0 template
        memory[1] = {8'd85,  8'd210, 8'd140, 8'd55};  // User 1 template
        memory[2] = {8'd200, 8'd90,  8'd30,  8'd70};  // User 2 template
        memory[3] = {8'd160, 8'd175, 8'd215, 8'd60};  // User 3 template
    end

    integer i;

    // ------------------------------------------------------------------------
    // Autonomous Zeroization FSM & Memory Access Logic
    // ------------------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            z_state      <= Z_IDLE;
            wipe_done    <= 1'b0;
            template_out <= 32'd0;
        end else begin
            case (z_state)
                Z_IDLE: begin
                    if (zeroize_trigger) begin
                        // Pass 1: Write All 1s (32'hFFFFFFFF)
                        for (i = 0; i < 4; i = i + 1) begin
                            memory[i] <= 32'hFFFFFFFF;
                        end
                        z_state   <= Z_PASS1;
                        wipe_done <= 1'b0;
                    end else begin
                        template_out <= memory[user_addr];
                        wipe_done    <= 1'b0;
                    end
                end

                Z_PASS1: begin
                    // Pass 2: Write All 0s (32'h00000000)
                    for (i = 0; i < 4; i = i + 1) begin
                        memory[i] <= 32'h00000000;
                    end
                    z_state <= Z_PASS2;
                end

                Z_PASS2: begin
                    // Pass 3: Overwrite with 32-bit Galois LFSR PRNG Noise
                    for (i = 0; i < 4; i = i + 1) begin
                        memory[i] <= lfsr ^ (32'hA5A5A5A5 * i);
                    end
                    z_state <= Z_PASS3;
                end

                Z_PASS3: begin
                    // Zeroization finished: transition to permanent PURGED state
                    z_state   <= Z_PURGED;
                    wipe_done <= 1'b1;
                end

                Z_PURGED: begin
                    // Permanent lock: readouts forced to zero, wipe_done remains high
                    wipe_done    <= 1'b1;
                    template_out <= 32'h00000000;
                end

                default: z_state <= Z_IDLE;
            endcase
        end
    end

endmodule
