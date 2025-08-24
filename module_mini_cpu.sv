module module_mini_cpu (
    input wire clk,
    input wire rst,
    input wire btn_power,
    input wire btn_send,
    input wire [17:0] switches,
    
    output reg [7:0] lcd_data,
    output reg lcd_rs,
    output reg lcd_rw,
    output reg lcd_enable,
    output reg lcd_on
);

    // Estados da máquina principal usando localparam
    localparam [2:0] OFF = 3'b000,
                     INIT_LCD = 3'b001,
                     READY = 3'b010,
                     EXECUTE = 3'b011,
                     WAIT_MEM = 3'b100,
                     DISPLAY_RESULT = 3'b101;
    
    reg [2:0] current_state, next_state;
    
    // Estados do LCD (expandidos para melhor controle)
    localparam [3:0] LCD_IDLE = 4'b0000,
                     LCD_INIT_FUNC = 4'b0010,
                     LCD_INIT_DISPLAY = 4'b0011,
                     LCD_INIT_CLEAR = 4'b0100,
                     LCD_INIT_ENTRY = 4'b0101,
                     LCD_WRITE_CHAR = 4'b0110,
                     LCD_DONE = 4'b0111;

    reg [3:0] lcd_current_state;
    
    // Sinais internos
    reg system_on;
    reg [17:0] instruction;
    reg [2:0] opcode;
    reg [3:0] dest_reg, src1_reg, src2_reg;
    reg [5:0] immediate;
    reg signed [15:0] imm_extended;
    
    // Sinais da memória
    reg mem_we;
    reg [3:0] mem_wa, mem_ra1, mem_ra2;
    reg signed [15:0] mem_wd;
    wire signed [15:0] mem_rd1, mem_rd2;
    reg mem_clear_all;
    
    // Sinais da ALU
    reg signed [15:0] alu_a, alu_b;
    wire signed [15:0] alu_result;
    wire alu_zero_flag;
    
    // Detecção de borda com debounce
    reg [2:0] btn_power_sync, btn_send_sync;
    reg btn_power_prev, btn_send_prev;
    wire btn_power_edge, btn_send_edge;
    
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            btn_power_sync <= 3'b000;
            btn_send_sync <= 3'b000;
            btn_power_prev <= 1'b0;
            btn_send_prev <= 1'b0;
        end else begin
            btn_power_sync <= {btn_power_sync[1:0], btn_power};
            btn_send_sync <= {btn_send_sync[1:0], btn_send};
            btn_power_prev <= btn_power_sync[2];
            btn_send_prev <= btn_send_sync[2];
        end
    end
    
    assign btn_power_edge = btn_power_sync[2] & ~btn_power_prev;
    assign btn_send_edge = btn_send_sync[2] & ~btn_send_prev;
    
    // Controle do LCD
    reg [19:0] lcd_delay_counter;
    reg [7:0] lcd_message [0:15];
    reg [3:0] lcd_char_index;
    reg [3:0] lcd_message_length;
    reg lcd_write_requested;
    reg signed [15:0] result_value;
    reg message_prepared;
    
    // Instanciação da memória
    memory mem_inst (
        .clk(clk),
        .rst(rst),
        .clear_all(mem_clear_all),
        .we(mem_we),
        .wa(mem_wa),
        .wd(mem_wd),
        .ra1(mem_ra1),
        .ra2(mem_ra2),
        .rd1(mem_rd1),
        .rd2(mem_rd2)
    );
    
    // Máquina de estados principal e controle do sistema
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            current_state <= OFF;
            system_on <= 1'b0;
            mem_we <= 1'b0;
            mem_clear_all <= 1'b0;
            lcd_write_requested <= 1'b0;
            message_prepared <= 1'b0;
            opcode <= 3'b0;
            result_value <= 16'b0;
            
        end else begin
            mem_we <= 1'b0;
            mem_clear_all <= 1'b0;
            
            case (current_state)
                OFF: begin
                    if (btn_power_edge) begin
                        system_on <= 1'b1;
                        mem_clear_all <= 1'b1;
                        current_state <= INIT_LCD;
                    end
                end
                
                INIT_LCD: begin
                    if (lcd_current_state == LCD_DONE) begin
                        current_state <= READY;
                    end
                end
                
                READY: begin
                    if (!system_on) begin
                        current_state <= OFF;
                    end else if (btn_send_edge) begin
                        instruction <= switches;
                        opcode <= switches[17:15];
                        dest_reg <= switches[14:11];
                        
                        // Mapeamento correto conforme formato das instruções
                        case (switches[17:15])
                            3'b001, 3'b011: begin // ADD, SUB (Reg x Reg) - CORRIGIDO
                                src1_reg <= switches[10:7];  // Posição correta para src1
                                src2_reg <= switches[6:3];   // Posição correta para src2
                            end
                            3'b000, 3'b010, 3'b100, 3'b101: begin // LOAD, ADDI, SUBI, MUL (com imediato)
                                src1_reg <= switches[10:7];  // Posição src1 para imediatos
                                src2_reg <= 4'b0;           // Não usado
                            end
                            3'b111: begin // DISPLAY
                                src1_reg <= switches[14:11]; // Para DISPLAY, registrador está em dest_reg
                                src2_reg <= 4'b0;           // Não usado
                            end
                            3'b110: begin // CLEAR
                                src1_reg <= 4'b0;           // Não usado
                                src2_reg <= 4'b0;           // Não usado
                            end
                            default: begin
                                src1_reg <= switches[10:7];
                                src2_reg <= switches[6:3];
                            end
                        endcase
                        
                        immediate <= switches[5:0];
                        // Extensão de sinal usando bit [6] para operações com imediato
                        imm_extended <= switches[6] ? {{10{1'b1}}, switches[5:0]} : {{10{1'b0}}, switches[5:0]};
                        message_prepared <= 1'b0;
                        lcd_write_requested <= 1'b1;
                        current_state <= EXECUTE;
                    end
                end
                
                EXECUTE: begin
                    mem_ra1 <= src1_reg;
                    mem_ra2 <= src2_reg;
                    current_state <= WAIT_MEM;
                end
                
                WAIT_MEM: begin
                    alu_a <= mem_rd1;
                    case (opcode)
                        3'b000, 3'b010, 3'b100, 3'b101: alu_b <= imm_extended; // LOAD, ADDI, SUBI, MUL
                        3'b001, 3'b011: alu_b <= mem_rd2;                      // ADD, SUB
                        default: alu_b <= imm_extended;
                    endcase
                    
                    case (opcode)
                        3'b000: result_value <= imm_extended;                   // LOAD
                        3'b001: result_value <= mem_rd1 + mem_rd2;             // ADD
                        3'b010: result_value <= mem_rd1 + imm_extended;        // ADDI
                        3'b011: result_value <= mem_rd1 - mem_rd2;             // SUB
                        3'b100: result_value <= mem_rd1 - imm_extended;        // SUBI
                        3'b101: result_value <= mem_rd1 * imm_extended;        // MUL
                        3'b110: begin mem_clear_all <= 1'b1; result_value <= 16'b0; end // CLEAR
                        3'b111: result_value <= mem_rd1;                       // DISPLAY
                        default: result_value <= 16'b0;
                    endcase
                    
                    if (opcode != 3'b110 && opcode != 3'b111) begin
                        mem_we <= 1'b1;
                        mem_wa <= dest_reg;
                        case (opcode)
                            3'b000: mem_wd <= imm_extended;                    // LOAD
                            3'b001: mem_wd <= mem_rd1 + mem_rd2;              // ADD
                            3'b010: mem_wd <= mem_rd1 + imm_extended;         // ADDI
                            3'b011: mem_wd <= mem_rd1 - mem_rd2;              // SUB
                            3'b100: mem_wd <= mem_rd1 - imm_extended;         // SUBI
                            3'b101: mem_wd <= mem_rd1 * imm_extended;         // MUL
                            default: mem_wd <= 16'b0;
                        endcase
                    end
                    current_state <= DISPLAY_RESULT;
                end
                
                DISPLAY_RESULT: begin
                    if (!message_prepared) begin
                        prepare_message();
                        message_prepared <= 1'b1;
                    end
                    if (lcd_current_state == LCD_DONE) begin
                        lcd_write_requested <= 1'b0;
                        current_state <= READY;
                    end
                end
                
                default: current_state <= OFF;
            endcase
        end
    end
    
    // Tarefa para preparar mensagem do LCD
    task prepare_message;
        reg [7:0] reg_char;
        reg [15:0] abs_value;
        reg [7:0] units, tens, hundreds, thousands;
        reg [15:0] temp_value;
        begin
            if (dest_reg < 10)
                reg_char = 8'h30 + dest_reg;
            else
                reg_char = 8'h37 + dest_reg;
            
            abs_value = (result_value < 0) ? (~result_value + 1) : result_value;
            
            temp_value = abs_value;
            units = temp_value % 10;
            temp_value = temp_value / 10;
            tens = temp_value % 10;
            temp_value = temp_value / 10;
            hundreds = temp_value % 10;
            temp_value = temp_value / 10;
            thousands = temp_value % 10;
            
            case (opcode)
                3'b000: begin // LOAD
                    lcd_message[0] = 8'h4C;  // 'L'
                    lcd_message[1] = 8'h4F;  // 'O'
                    lcd_message[2] = 8'h41;  // 'A'
                    lcd_message[3] = 8'h44;  // 'D'
                    lcd_message[4] = 8'h20;  // ' '
                    lcd_message[5] = 8'h52;  // 'R'
                    lcd_message[6] = reg_char;
                    lcd_message[7] = 8'h20;  // ' '
                    lcd_message[8] = (result_value < 0) ? 8'h2D : 8'h2B;
                    
                    if (abs_value >= 1000) begin
                        lcd_message[9] = 8'h30 + thousands;
                        lcd_message[10] = 8'h30 + hundreds;
                        lcd_message[11] = 8'h30 + tens;
                        lcd_message[12] = 8'h30 + units;
                        lcd_message_length = 14;
                    end else if (abs_value >= 100) begin
                        lcd_message[9] = 8'h30 + hundreds;
                        lcd_message[10] = 8'h30 + tens;
                        lcd_message[11] = 8'h30 + units;
                        lcd_message_length = 13;
                    end else if (abs_value >= 10) begin
                        lcd_message[9] = 8'h30 + tens;
                        lcd_message[10] = 8'h30 + units;
                        lcd_message_length = 12;
                    end else begin
                        lcd_message[9] = 8'h30 + units;
                        lcd_message_length = 11;
                    end
                end
                
                3'b001: begin // ADD
                    lcd_message[0] = 8'h41;  // 'A'
                    lcd_message[1] = 8'h44;  // 'D'
                    lcd_message[2] = 8'h44;  // 'D'
                    lcd_message[3] = 8'h20;  // ' '
                    lcd_message[4] = 8'h52;  // 'R'
                    lcd_message[5] = reg_char;
                    lcd_message[6] = 8'h20;  // ' '
                    lcd_message[7] = (result_value < 0) ? 8'h2D : 8'h2B;
                    
                    if (abs_value >= 1000) begin
                        lcd_message[8] = 8'h30 + thousands;
                        lcd_message[9] = 8'h30 + hundreds;
                        lcd_message[10] = 8'h30 + tens;
                        lcd_message[11] = 8'h30 + units;
                        lcd_message_length = 13;
                    end else if (abs_value >= 100) begin
                        lcd_message[8] = 8'h30 + hundreds;
                        lcd_message[9] = 8'h30 + tens;
                        lcd_message[10] = 8'h30 + units;
                        lcd_message_length = 12;
                    end else if (abs_value >= 10) begin
                        lcd_message[8] = 8'h30 + tens;
                        lcd_message[9] = 8'h30 + units;
                        lcd_message_length = 11;
                    end else begin
                        lcd_message[8] = 8'h30 + units;
                        lcd_message_length = 10;
                    end
                end
                
                3'b010: begin // ADDI
                    lcd_message[0] = 8'h41;  // 'A'
                    lcd_message[1] = 8'h44;  // 'D'
                    lcd_message[2] = 8'h44;  // 'D'
                    lcd_message[3] = 8'h49;  // 'I'
                    lcd_message[4] = 8'h20;  // ' '
                    lcd_message[5] = 8'h52;  // 'R'
                    lcd_message[6] = reg_char;
                    lcd_message[7] = 8'h20;  // ' '
                    lcd_message[8] = (result_value < 0) ? 8'h2D : 8'h2B;
                    
                    if (abs_value >= 1000) begin
                        lcd_message[9] = 8'h30 + thousands;
                        lcd_message[10] = 8'h30 + hundreds;
                        lcd_message[11] = 8'h30 + tens;
                        lcd_message[12] = 8'h30 + units;
                        lcd_message_length = 14;
                    end else if (abs_value >= 100) begin
                        lcd_message[9] = 8'h30 + hundreds;
                        lcd_message[10] = 8'h30 + tens;
                        lcd_message[11] = 8'h30 + units;
                        lcd_message_length = 13;
                    end else if (abs_value >= 10) begin
                        lcd_message[9] = 8'h30 + tens;
                        lcd_message[10] = 8'h30 + units;
                        lcd_message_length = 12;
                    end else begin
                        lcd_message[9] = 8'h30 + units;
                        lcd_message_length = 11;
                    end
                end
                
                3'b011: begin // SUB
                    lcd_message[0] = 8'h53;  // 'S'
                    lcd_message[1] = 8'h55;  // 'U'
                    lcd_message[2] = 8'h42;  // 'B'
                    lcd_message[3] = 8'h20;  // ' '
                    lcd_message[4] = 8'h52;  // 'R'
                    lcd_message[5] = reg_char;
                    lcd_message[6] = 8'h20;  // ' '
                    lcd_message[7] = (result_value < 0) ? 8'h2D : 8'h2B;
                    
                    if (abs_value >= 1000) begin
                        lcd_message[8] = 8'h30 + thousands;
                        lcd_message[9] = 8'h30 + hundreds;
                        lcd_message[10] = 8'h30 + tens;
                        lcd_message[11] = 8'h30 + units;
                        lcd_message_length = 13;
                    end else if (abs_value >= 100) begin
                        lcd_message[8] = 8'h30 + hundreds;
                        lcd_message[9] = 8'h30 + tens;
                        lcd_message[10] = 8'h30 + units;
                        lcd_message_length = 12;
                    end else if (abs_value >= 10) begin
                        lcd_message[8] = 8'h30 + tens;
                        lcd_message[9] = 8'h30 + units;
                        lcd_message_length = 11;
                    end else begin
                        lcd_message[8] = 8'h30 + units;
                        lcd_message_length = 10;
                    end
                end
                
                3'b100: begin // SUBI
                    lcd_message[0] = 8'h53;  // 'S'
                    lcd_message[1] = 8'h55;  // 'U'
                    lcd_message[2] = 8'h42;  // 'B'
                    lcd_message[3] = 8'h49;  // 'I'
                    lcd_message[4] = 8'h20;  // ' '
                    lcd_message[5] = 8'h52;  // 'R'
                    lcd_message[6] = reg_char;
                    lcd_message[7] = 8'h20;  // ' '
                    lcd_message[8] = (result_value < 0) ? 8'h2D : 8'h2B;
                    
                    if (abs_value >= 1000) begin
                        lcd_message[9] = 8'h30 + thousands;
                        lcd_message[10] = 8'h30 + hundreds;
                        lcd_message[11] = 8'h30 + tens;
                        lcd_message[12] = 8'h30 + units;
                        lcd_message_length = 14;
                    end else if (abs_value >= 100) begin
                        lcd_message[9] = 8'h30 + hundreds;
                        lcd_message[10] = 8'h30 + tens;
                        lcd_message[11] = 8'h30 + units;
                        lcd_message_length = 13;
                    end else if (abs_value >= 10) begin
                        lcd_message[9] = 8'h30 + tens;
                        lcd_message[10] = 8'h30 + units;
                        lcd_message_length = 12;
                    end else begin
                        lcd_message[9] = 8'h30 + units;
                        lcd_message_length = 11;
                    end
                end
                
                3'b101: begin // MUL
                    lcd_message[0] = 8'h4D;  // 'M'
                    lcd_message[1] = 8'h55;  // 'U'
                    lcd_message[2] = 8'h4C;  // 'L'
                    lcd_message[3] = 8'h20;  // ' '
                    lcd_message[4] = 8'h52;  // 'R'
                    lcd_message[5] = reg_char;
                    lcd_message[6] = 8'h20;  // ' '
                    lcd_message[7] = (result_value < 0) ? 8'h2D : 8'h2B;
                    
                    if (abs_value >= 1000) begin
                        lcd_message[8] = 8'h30 + thousands;
                        lcd_message[9] = 8'h30 + hundreds;
                        lcd_message[10] = 8'h30 + tens;
                        lcd_message[11] = 8'h30 + units;
                        lcd_message_length = 13;
                    end else if (abs_value >= 100) begin
                        lcd_message[8] = 8'h30 + hundreds;
                        lcd_message[9] = 8'h30 + tens;
                        lcd_message[10] = 8'h30 + units;
                        lcd_message_length = 12;
                    end else if (abs_value >= 10) begin
                        lcd_message[8] = 8'h30 + tens;
                        lcd_message[9] = 8'h30 + units;
                        lcd_message_length = 11;
                    end else begin
                        lcd_message[8] = 8'h30 + units;
                        lcd_message_length = 10;
                    end
                end
                
                3'b110: begin // CLEAR
                    lcd_message[0] = 8'h43;  // 'C'
                    lcd_message[1] = 8'h4C;  // 'L'
                    lcd_message[2] = 8'h45;  // 'E'
                    lcd_message[3] = 8'h41;  // 'A'
                    lcd_message[4] = 8'h52;  // 'R'
                    lcd_message_length = 6;
                end
                
                3'b111: begin // DISPLAY
                    if (src1_reg < 10)
                        reg_char = 8'h30 + src1_reg;
                    else
                        reg_char = 8'h37 + src1_reg;
                        
                    lcd_message[0] = 8'h44;  // 'D'
                    lcd_message[1] = 8'h49;  // 'I'
                    lcd_message[2] = 8'h53;  // 'S'
                    lcd_message[3] = 8'h50;  // 'P'
                    lcd_message[4] = 8'h20;  // ' '
                    lcd_message[5] = 8'h52;  // 'R'
                    lcd_message[6] = reg_char;
                    lcd_message[7] = 8'h20;  // ' '
                    lcd_message[8] = (result_value < 0) ? 8'h2D : 8'h2B; // '-' ou '+'
                    
                    if (abs_value >= 1000) begin
                        lcd_message[9] = 8'h30 + thousands;
                        lcd_message[10] = 8'h30 + hundreds;
                        lcd_message[11] = 8'h30 + tens;
                        lcd_message[12] = 8'h30 + units;
                        lcd_message_length = 14;
                    end else if (abs_value >= 100) begin
                        lcd_message[9] = 8'h30 + hundreds;
                        lcd_message[10] = 8'h30 + tens;
                        lcd_message[11] = 8'h30 + units;
                        lcd_message_length = 13;
                    end else if (abs_value >= 10) begin
                        lcd_message[9] = 8'h30 + tens;
                        lcd_message[10] = 8'h30 + units;
                        lcd_message_length = 12;
                    end else begin
                        lcd_message[9] = 8'h30 + units;
                        lcd_message_length = 11;
                    end
                end
                
                default: begin
                    lcd_message[0] = 8'h45;  // 'E'
                    lcd_message[1] = 8'h52;  // 'R'
                    lcd_message[2] = 8'h52;  // 'R'
                    lcd_message[3] = 8'h4F;  // 'O'
                    lcd_message[4] = 8'h52;  // 'R'
                    lcd_message_length = 6;
                end
            endcase
        end
    endtask
    
    // Máquina de estados do LCD
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            lcd_current_state <= LCD_IDLE;
            lcd_delay_counter <= 20'b0;
            lcd_char_index <= 4'b0;
            lcd_enable <= 1'b0;
            lcd_rs <= 1'b0;
            lcd_rw <= 1'b0;
            lcd_data <= 8'b0;
            lcd_on <= 1'b0;
        end else begin
            lcd_on <= system_on;
            
            if (lcd_delay_counter > 0) begin
                lcd_delay_counter <= lcd_delay_counter - 1;
                lcd_enable <= 1'b0;
            end else begin
                lcd_enable <= 1'b1; 
                
                case (lcd_current_state)
                    LCD_IDLE: begin
                        if (current_state == INIT_LCD) begin
                            lcd_current_state <= LCD_INIT_FUNC;
                            lcd_delay_counter <= 20'd500000;
                            lcd_data <= 8'h38;
                            lcd_rs <= 1'b0;
                        end else if (lcd_write_requested && message_prepared) begin
                            lcd_current_state <= LCD_INIT_CLEAR;
                            lcd_delay_counter <= 20'd76500;
                            lcd_data <= 8'h01;
                            lcd_rs <= 1'b0;
                            lcd_char_index <= 4'b0;
                        end
                    end
                    
                    LCD_INIT_FUNC: begin
                        lcd_current_state <= LCD_INIT_DISPLAY;
                        lcd_delay_counter <= 20'd2000;
                        lcd_data <= 8'h0C;
                        lcd_rs <= 1'b0;
                    end
                    
                    LCD_INIT_DISPLAY: begin
                        lcd_current_state <= LCD_INIT_CLEAR;
                        lcd_delay_counter <= 20'd2000;
                        lcd_data <= 8'h01;
                        lcd_rs <= 1'b0;
                    end
                    
                    LCD_INIT_CLEAR: begin
                        if (current_state == INIT_LCD) begin
                            lcd_current_state <= LCD_INIT_ENTRY;
                            lcd_delay_counter <= 20'd76500;
                            lcd_data <= 8'h06;
                            lcd_rs <= 1'b0;
                        end else begin
                            lcd_current_state <= LCD_WRITE_CHAR;
                            lcd_delay_counter <= 20'd76500;
                        end
                    end
                    
                    LCD_INIT_ENTRY: begin
                        lcd_current_state <= LCD_DONE;
                        lcd_delay_counter <= 20'd2000;
                        lcd_data <= 8'b0;
                    end

                    LCD_WRITE_CHAR: begin
                        if (lcd_char_index < lcd_message_length) begin
                            lcd_data <= lcd_message[lcd_char_index];
                            lcd_rs <= 1'b1;
                            lcd_char_index <= lcd_char_index + 1;
                            lcd_delay_counter <= 20'd2000;
                        end else begin
                            lcd_current_state <= LCD_DONE;
                            lcd_data <= 8'b0;
                            lcd_rs <= 1'b0;
                        end
                    end
                    
                    LCD_DONE: begin
                        lcd_current_state <= LCD_IDLE;
                    end
                    
                    default: begin
                        lcd_current_state <= LCD_IDLE;
                    end
                endcase
            end
        end
    end
endmodule
