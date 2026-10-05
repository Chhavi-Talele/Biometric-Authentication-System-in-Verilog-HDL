// ============================================================================
// Module: template_ram.v
// Description: Stores enrolled fingerprint feature codes for registered users.
// ============================================================================

module template_ram (
    input  wire       clk,
    input  wire       write_en,
    input  wire [1:0] user_id,        // Supports up to 4 users (0 to 3)
    input  wire [7:0] in_feature,     // Fingerprint feature vector to store
    output reg  [7:0] stored_feature  // Retreived stored feature vector
);

    // Memory array: 4 locations, each 8 bits wide
    reg [7:0] memory [0:3];

    // Initialize RAM with default enrolled user fingerprints
    initial begin
        memory[0] = 8'hA5; // Registered Fingerprint for User 0 (165 decimal)
        memory[1] = 8'h7E; // Registered Fingerprint for User 1 (126 decimal)
        memory[2] = 8'h3C; // Registered Fingerprint for User 2 (60 decimal)
        memory[3] = 8'hF0; // Registered Fingerprint for User 3 (240 decimal)
    end

    // Memory Write & Read Logic
    always @(posedge clk) begin
        if (write_en) begin
            memory[user_id] <= in_feature; // Enroll / Update fingerprint
        end
        stored_feature <= memory[user_id]; // Read registered fingerprint
    end

endmodule
