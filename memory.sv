// =============================
// Banco de Registradores 16x16 bits
// =============================
// Permite duas leituras combinacionais e uma escrita síncrona.
// Sinal clear_all zera todos os registradores (usado no CLEAR ou desligar).
// rst também zera todos.
// Endereços e dados definidos conforme formato do PDF.

module memory(
    input  wire        clk,
    input  wire        rst,
    input  wire        clear_all,
    input  wire        we,
    input  wire [3:0]  wa,  // write address
    input  wire [15:0] wd,  // write data
    input  wire [3:0]  ra1, // read address 1
    input  wire [3:0]  ra2, // read address 2
    output reg  [15:0] rd1,
    output reg  [15:0] rd2
);

    reg [15:0] regs [0:15];
    integer i;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            for (i = 0; i < 16; i = i + 1) regs[i] <= 16'b0;
        end else if (clear_all) begin
            for (i = 0; i < 16; i = i + 1) regs[i] <= 16'b0;
        end else if (we) begin
            regs[wa] <= wd;
        end
    end

    always @(*) begin
        rd1 = regs[ra1];
        rd2 = regs[ra2];
    end

endmodule
