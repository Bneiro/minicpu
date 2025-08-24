//topl level para implementacao no Quartus Prime, a placa utilizada nao possuia backlight
module top_level_de2115 (
    // Clock principal da placa
    input CLOCK_50,
    
    // Botões (ativos baixo na DE2-115)
    input [3:0] KEY,
    
    // Switches (18 bits disponíveis)
    input [17:0] SW,
    
    // LEDs para debug
    output [17:0] LEDR,
    output [8:0] LEDG,
    
    // Interface LCD da DE2-115
    output [7:0] LCD_DATA,
    output LCD_RW,
    output LCD_EN,
    output LCD_RS,
    output LCD_ON
);


    
    // Reset global (KEY[0] é ativo baixo)
    wire rst;
    assign rst = ~KEY[0];
    
    // Botões condicionados (ativos baixo -> ativos alto)
    wire btn_power, btn_send;
    assign btn_power = ~KEY[1];  // KEY[1] para power
    assign btn_send = ~KEY[2];   // KEY[2] para send
    
    // Switches diretos
    wire [17:0] switches;
    assign switches = SW;
    

    
    wire [7:0] lcd_data_internal;
    wire lcd_rs_internal;
    wire lcd_rw_internal;
    wire lcd_enable_internal;
    wire lcd_on_internal;
    

    
    module_mini_cpu cpu_inst (
        .clk(CLOCK_50), // Usando o clock principal de 50 MHz
        .rst(rst),
        .btn_power(btn_power),
        .btn_send(btn_send),
        .switches(switches),
        // Interface LCD
        .lcd_data(lcd_data_internal),
        .lcd_rs(lcd_rs_internal),
        .lcd_rw(lcd_rw_internal),
        .lcd_enable(lcd_enable_internal),
        .lcd_on(lcd_on_internal)
    );
    

    
    assign LCD_DATA = lcd_data_internal;
    assign LCD_RS = lcd_rs_internal;
    assign LCD_RW = lcd_rw_internal;
    assign LCD_EN = lcd_enable_internal;
    assign LCD_ON = lcd_on_internal;
    

    
    // LEDs vermelhos mostram estado dos switches
    assign LEDR = switches;
    
    // LEDs verdes para debug do sistema
    reg [25:0] heartbeat_counter;
    always @(posedge CLOCK_50 or posedge rst) begin
        if (rst)
            heartbeat_counter <= 26'b0;
        else
            heartbeat_counter <= heartbeat_counter + 1;
    end
    
    assign LEDG[0] = lcd_on_internal;
    assign LEDG[1] = btn_power;
    assign LEDG[2] = btn_send;
    assign LEDG[3] = lcd_enable_internal;
    assign LEDG[4] = lcd_rs_internal;
    assign LEDG[5] = |lcd_data_internal;
    assign LEDG[6] = 1'b0;
    assign LEDG[7] = heartbeat_counter[25];
    assign LEDG[8] = ~lcd_rw_internal;

endmodule
