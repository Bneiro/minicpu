// Responsável por executar as operações ADD, ADDI, SUB, SUBI, MUL.
// LOAD, CLEAR e DISPLAY não passam pela ALU (são tratados na CPU).
// Resultado é assinado de 16 bits, zero_flag indica se o resultado é 0.
// Mapeamento de opcodes (conforme PDF):
// 000 = LOAD (ignorado na ALU)
// 001 = ADD   (reg/reg)
// 010 = ADDI  (reg/imm)
// 011 = SUB   (reg/reg)
// 100 = SUBI  (reg/imm)
// 101 = MUL   (reg/imm)
// 110 = CLEAR (ignorado na ALU)
// 111 = DISPLAY (ignorado na ALU)

module module_alu (
    input  wire [2:0] opcode,
    input  wire signed [15:0] a,
    input  wire signed [15:0] b,   // pode ser registrador ou imediato
    output reg  signed [15:0] result,
    output reg  zero_flag
);
    always @* begin
        case (opcode)
            3'b001: result = a + b; // ADD
            3'b010: result = a + b; // ADDI
            3'b011: result = a - b; // SUB
            3'b100: result = a - b; // SUBI
            3'b101: result = (a * b) & 16'hFFFF; // MUL (16 bits truncados)
            default: result = b;    // LOAD usa b como imediato
        endcase
        zero_flag = (result == 16'sd0);
    end
endmodule
