`default_nettype none
`define DUMPSTR(x) `"x.vcd`"
`timescale 10ns/1ns

module shift_with_latch (
        input wire i_ser_clk,
        input wire i_reg_clk,
        input wire i_data,
        output reg [15:0] o_data = 0
    );

    reg [15:0] data = 0;

    always @ (posedge i_ser_clk) begin
        // data <= {data[6:0], i_data};
        data <= (data << 1) + i_data;
    end

    always @ (posedge i_reg_clk) begin
        o_data <= data;
    end

endmodule

module phase_tb;
    reg CLK = 0;

    wire [15:0] CHANNEL;
    wire DATA_CLK;
    wire LATCH;
    wire SYNC;

    wire [15:0] OUTPUT_0;
    wire [15:0] OUTPUT_1;

    reg COMMAND = 0;
    reg [23:0] COMMAND_DATA = 0;
    reg OVERFLOW = 0;
    wire REPLY = 0;
    wire [23:0] REPLY_DATA;

    // Instantiate the Unit Under Test (UUT)
    phase #(.PHASE_CYCLES(64), .PERIOD_CYCLES(1200)) UUT
    (
        .i_clk(CLK),
        .o_channel(CHANNEL),
        .o_data_clk(DATA_CLK),
        .o_latch(LATCH),
        .o_sync(SYNC),

        .i_command(COMMAND),
        .i_command_data(COMMAND_DATA),
        .i_overflow(OVERFLOW),
        .o_reply(REPLY),
        .o_reply_data(REPLY_DATA)
    );

    shift_with_latch S0 (
        .i_ser_clk(DATA_CLK), .i_reg_clk(LATCH), .i_data(CHANNEL[0]), .o_data(OUTPUT_0)
    );

    shift_with_latch S1 (
        .i_ser_clk(DATA_CLK), .i_reg_clk(LATCH), .i_data(CHANNEL[1]), .o_data(OUTPUT_0)
    );


    always begin
        #1.0;
        CLK <= ~CLK;
    end

    initial begin
        $dumpfile(`DUMPSTR(`VCD_OUTPUT));
        $dumpvars(0, phase_tb);



        #10000

        $display("Test Complete");
        $finish;
    end

endmodule
