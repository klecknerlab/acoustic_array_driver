`define HALF_OUTPUT_FREQ 1

module top (
        input CLK,
        output USBPU, // USB pull-up resistor
        inout USBP,
        inout USBN,
        output PIN_1,
        output PIN_2,
        output PIN_3,
        output PIN_4,
        output PIN_5,
        output PIN_6,
        output PIN_7,
        output PIN_8,
        output PIN_9,
        output PIN_10,
        output PIN_11,
        output PIN_12,
        output PIN_13,
        output PIN_14,
        output PIN_15,
        output PIN_16,
        output PIN_17,
        output PIN_18,
        output PIN_19
        // output PIN_20
    );

    wire [31:0] cmd_data;
    wire cmd;
    wire overflow;

    wire [31:0] reply_data;
    wire reply;

    wire CLK_48;

    `ifdef HALF_OUTPUT_FREQ
        reg CLK_24 = 0;

        always @ (posedge CLK_48) begin
            CLK_24 <= ~CLK_24;
        end

        phase #(.PERIOD_CYCLES(600), .PHASE_CYCLES(32)) phase_generator (
            .i_data_clk(CLK_24),
            .o_channel({PIN_16, PIN_15, PIN_14, PIN_13, PIN_12, PIN_11, PIN_10, PIN_9, PIN_8, PIN_7, PIN_6, PIN_5, PIN_4, PIN_3, PIN_2, PIN_1}),
            .o_data_clk(PIN_18),
            .o_latch(PIN_17),
            .o_sync(PIN_19),
            .i_command_clk(CLK_48),
            .i_command(cmd),
            .i_command_data(cmd_data),
            .i_overflow(overflow),
            .o_reply(reply),
            .o_reply_data(reply_data)
        );
    `else
        phase #(.PERIOD_CYCLES(1200), .PHASE_CYCLES(64)) phase_generator (
            .i_data_clk(CLK_48),
            .o_channel({PIN_16, PIN_15, PIN_14, PIN_13, PIN_12, PIN_11, PIN_10, PIN_9, PIN_8, PIN_7, PIN_6, PIN_5, PIN_4, PIN_3, PIN_2, PIN_1}),
            .o_data_clk(PIN_18),
            .o_latch(PIN_17),
            .o_sync(PIN_19),
            .i_command_clk(CLK_48),
            .i_command(cmd),
            .i_command_data(cmd_data),
            .i_overflow(overflow),
            .o_reply(reply),
            .o_reply_data(reply_data)
        );
    `endif

    usb_command #(.ID_VENDOR('h1209), .ID_PRODUCT('h6130)) command_decoder (
        .CLK(CLK),
        .USBP(USBP),
        .USBN(USBN),
        .USBPU(USBPU),
        .LED(LED),
        .CLK_48(CLK_48),

        .i_reply(reply),
        .i_data(reply_data),
        .o_overflow(overflow),
        .o_command(cmd),
        .o_data(cmd_data)
    );

endmodule
