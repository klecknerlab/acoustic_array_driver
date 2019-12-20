// Error bits in reply:
//  0: invalid command
//  1: invalid data (usually address)
//  7: buffer overflow on last reply, output suppressed

// Commands:
// All commands take one command byte and two data bytes.
// All replies are 3 bytes -- one error bytes and two data bytes.
// Commands which are lowercase do not return replies; the upper case versions
//   do.  In general the reply will be the same as the written value, unless
//   it was invalid.
// 'a[XY]', 'A[XY]': Address to write; X = bank # (0-15), and Y = channel # (0-255)
// 'w[XY]', 'W[XY]': Write the phase/duty cycle to the given write address; returns the address just written.  Next write will take place at next address
// 'b[-X]', 'B[-X]': Select the output bank.
// 'n[XX]', 'N[XX]': Clock cycles per period (default: 1200 => 40 kHz)
// 'c[XX]', 'C[XX]': Updates per clock cycle (default: 60, N / C must be > 17)
// 'go!', 'Go!': Start running
// 'st!', 'St!': Stop running


`timescale 10ns/1ns

`define SELECT4x16(SEL, OUTPUT, INPUT) \
    case (SEL) \
         0: OUTPUT <= INPUT[ 3: 0]; \
         1: OUTPUT <= INPUT[ 7: 4]; \
         2: OUTPUT <= INPUT[11: 8]; \
         3: OUTPUT <= INPUT[15:12]; \
         4: OUTPUT <= INPUT[19:16]; \
         5: OUTPUT <= INPUT[23:20]; \
         6: OUTPUT <= INPUT[27:24]; \
         7: OUTPUT <= INPUT[31:28]; \
         8: OUTPUT <= INPUT[35:32]; \
         9: OUTPUT <= INPUT[39:36]; \
        10: OUTPUT <= INPUT[43:40]; \
        11: OUTPUT <= INPUT[47:44]; \
        12: OUTPUT <= INPUT[51:48]; \
        13: OUTPUT <= INPUT[55:52]; \
        14: OUTPUT <= INPUT[59:56]; \
        15: OUTPUT <= INPUT[63:60]; \
    endcase

`define SET4x16(SEL, OUTPUT, INPUT) \
    case (SEL) \
         0: OUTPUT[ 3: 0] <= INPUT; \
         1: OUTPUT[ 7: 4] <= INPUT; \
         2: OUTPUT[11: 8] <= INPUT; \
         3: OUTPUT[15:12] <= INPUT; \
         4: OUTPUT[19:16] <= INPUT; \
         5: OUTPUT[23:20] <= INPUT; \
         6: OUTPUT[27:24] <= INPUT; \
         7: OUTPUT[31:28] <= INPUT; \
         8: OUTPUT[35:32] <= INPUT; \
         9: OUTPUT[39:36] <= INPUT; \
        10: OUTPUT[43:40] <= INPUT; \
        11: OUTPUT[47:44] <= INPUT; \
        12: OUTPUT[51:48] <= INPUT; \
        13: OUTPUT[55:52] <= INPUT; \
        14: OUTPUT[59:56] <= INPUT; \
        15: OUTPUT[63:60] <= INPUT; \
    endcase


module phase #(parameter PERIOD_CYCLES=600, PHASE_CYCLES=32, INIT_CYCLES=520) (
    input wire i_data_clk,
    output reg [15:0] o_channel = 0,
    output wire o_data_clk,
    output reg o_latch = 0,
    output reg o_sync = 0,
    output reg o_led_flash = 0,
    output reg o_camera_sync = 0,

    input wire i_command_clk,
    input wire i_command,
    input wire [31:0] i_command_data,
    input wire i_overflow,
    output reg o_reply,
    output reg [31:0] o_reply_data
);

    assign o_data_clk = ~i_data_clk;

    // Startup count
    reg [15:0] i_startup = 0;

    // Indicates if last command queue overflowed -- this should never happen...
    reg last_overflow = 0;

    // The current count in this period
    reg [15:0] i_period = 0;
    reg [15:0] n_period = PERIOD_CYCLES;
    reg [15:0] nn_period = PERIOD_CYCLES;

    reg [15:0] i_update = 0;

    reg [7:0] i_phase = 0;
    reg [7:0] phase_per_update = 256/PHASE_CYCLES;

    // reg [7:0] n_phase = PHASE_CYCLES;
    // reg [7:0] nn_phase = PHASE_CYCLES;

    reg [8:0] i_shift = 0;


    reg [3:0] write_bank = 0;
    reg [7:0] write_channel = 0;
    // reg start_write = 0;
    // reg [7:0] write_address;
    reg [15:0] channel_write = 0;
    reg [15:0] write_data = 0;

    reg [7:0] phase_mask = 8'h3F;

    reg [3:0] read_bank = 0;

    reg [7:0] read_addr = 0;
    reg [7:0] write_addr = 0;

    reg [15:0] led_count = 1;
    reg [15:0] led_periods = 400;
    reg [7:0] led_duty = 64;
    reg [7:0] led_phase = 0;
    reg [7:0] led_cycle = 0;

    // This block implements the switching between the physical and virtual
    // channels.

    // reg [63:0] channel_swap_odd =  64'hBA98EFCD32106745;
    // reg [63:0] channel_swap_even = 64'h32106745BA98EFCD;
    reg [63:0] channel_swap_odd =  64'h54760123DCFE89AB;
    reg [63:0] channel_swap_even = 64'hDCFE89AB54760123;

    reg [3:0] next_physical_channel = 0;



    reg [3:0] channel_read_odd;
    reg [3:0] channel_read_even;


    // reg [3:0] current_read_bank = 0;

    always @ (next_physical_channel) begin
        // channel_read_odd <= next_physical_channel;
        // channel_read_even <= next_physical_channel;
        `SELECT4x16(next_physical_channel, channel_read_odd, channel_swap_odd)
        `SELECT4x16(next_physical_channel, channel_read_even, channel_swap_even)
    end

    // Duty cycle, and phase for each output
    wire [7:0] phase_0;
    wire [7:0] duty_0;
    ram #(.addr_width(8), .data_width(16)) data_0 (
        .din(write_data), .write_en(channel_write[0]), .waddr(write_addr), .wclk(i_command_clk),
        .raddr({read_bank, channel_read_odd}), .rclk(i_data_clk), .dout({phase_0, duty_0})
    );

    wire [7:0] phase_1;
    wire [7:0] duty_1;
    ram #(.addr_width(8), .data_width(16)) data_1 (
        .din(write_data), .write_en(channel_write[1]), .waddr(write_addr), .wclk(i_command_clk),
        .raddr({read_bank, channel_read_even}), .rclk(i_data_clk), .dout({phase_1, duty_1})
    );

    wire [7:0] phase_2;
    wire [7:0] duty_2;
    ram #(.addr_width(8), .data_width(16)) data_2 (
        .din(write_data), .write_en(channel_write[2]), .waddr(write_addr), .wclk(i_command_clk),
        .raddr({read_bank, channel_read_odd}), .rclk(i_data_clk), .dout({phase_2, duty_2})
    );

    wire [7:0] phase_3;
    wire [7:0] duty_3;
    ram #(.addr_width(8), .data_width(16)) data_3 (
        .din(write_data), .write_en(channel_write[3]), .waddr(write_addr), .wclk(i_command_clk),
        .raddr({read_bank, channel_read_even}), .rclk(i_data_clk), .dout({phase_3, duty_3})
    );

    wire [7:0] phase_4;
    wire [7:0] duty_4;
    ram #(.addr_width(8), .data_width(16)) data_4 (
        .din(write_data), .write_en(channel_write[4]), .waddr(write_addr), .wclk(i_command_clk),
        .raddr({read_bank, channel_read_odd}), .rclk(i_data_clk), .dout({phase_4, duty_4})
    );

    wire [7:0] phase_5;
    wire [7:0] duty_5;
    ram #(.addr_width(8), .data_width(16)) data_5 (
        .din(write_data), .write_en(channel_write[5]), .waddr(write_addr), .wclk(i_command_clk),
        .raddr({read_bank, channel_read_even}), .rclk(i_data_clk), .dout({phase_5, duty_5})
    );

    wire [7:0] phase_6;
    wire [7:0] duty_6;
    ram #(.addr_width(8), .data_width(16)) data_6 (
        .din(write_data), .write_en(channel_write[6]), .waddr(write_addr), .wclk(i_command_clk),
        .raddr({read_bank, channel_read_odd}), .rclk(i_data_clk), .dout({phase_6, duty_6})
    );

    wire [7:0] phase_7;
    wire [7:0] duty_7;
    ram #(.addr_width(8), .data_width(16)) data_7 (
        .din(write_data), .write_en(channel_write[7]), .waddr(write_addr), .wclk(i_command_clk),
        .raddr({read_bank, channel_read_even}), .rclk(i_data_clk), .dout({phase_7, duty_7})
    );

    wire [7:0] phase_8;
    wire [7:0] duty_8;
    ram #(.addr_width(8), .data_width(16)) data_8 (
        .din(write_data), .write_en(channel_write[8]), .waddr(write_addr), .wclk(i_command_clk),
        .raddr({read_bank, channel_read_odd}), .rclk(i_data_clk), .dout({phase_8, duty_8})
    );

    wire [7:0] phase_9;
    wire [7:0] duty_9;
    ram #(.addr_width(8), .data_width(16)) data_9 (
        .din(write_data), .write_en(channel_write[9]), .waddr(write_addr), .wclk(i_command_clk),
        .raddr({read_bank, channel_read_even}), .rclk(i_data_clk), .dout({phase_9, duty_9})
    );

    wire [7:0] phase_10;
    wire [7:0] duty_10;
    ram #(.addr_width(8), .data_width(16)) data_10 (
        .din(write_data), .write_en(channel_write[10]), .waddr(write_addr), .wclk(i_command_clk),
        .raddr({read_bank, channel_read_odd}), .rclk(i_data_clk), .dout({phase_10, duty_10})
    );

    wire [7:0] phase_11;
    wire [7:0] duty_11;
    ram #(.addr_width(8), .data_width(16)) data_11 (
        .din(write_data), .write_en(channel_write[11]), .waddr(write_addr), .wclk(i_command_clk),
        .raddr({read_bank, channel_read_even}), .rclk(i_data_clk), .dout({phase_11, duty_11})
    );

    wire [7:0] phase_12;
    wire [7:0] duty_12;
    ram #(.addr_width(8), .data_width(16)) data_12 (
        .din(write_data), .write_en(channel_write[12]), .waddr(write_addr), .wclk(i_command_clk),
        .raddr({read_bank, channel_read_odd}), .rclk(i_data_clk), .dout({phase_12, duty_12})
    );

    wire [7:0] phase_13;
    wire [7:0] duty_13;
    ram #(.addr_width(8), .data_width(16)) data_13 (
        .din(write_data), .write_en(channel_write[13]), .waddr(write_addr), .wclk(i_command_clk),
        .raddr({read_bank, channel_read_even}), .rclk(i_data_clk), .dout({phase_13, duty_13})
    );

    wire [7:0] phase_14;
    wire [7:0] duty_14;
    ram #(.addr_width(8), .data_width(16)) data_14 (
        .din(write_data), .write_en(channel_write[14]), .waddr(write_addr), .wclk(i_command_clk),
        .raddr({read_bank, channel_read_odd}), .rclk(i_data_clk), .dout({phase_14, duty_14})
    );

    wire [7:0] phase_15;
    wire [7:0] duty_15;
    ram #(.addr_width(8), .data_width(16)) data_15 (
        .din(write_data), .write_en(channel_write[15]), .waddr(write_addr), .wclk(i_command_clk),
        .raddr({read_bank, channel_read_even}), .rclk(i_data_clk), .dout({phase_15, duty_15})
    );

    always @ (posedge i_data_clk) begin
        #0.5;

        // This is the normal code section.
        if (i_startup >= INIT_CYCLES) begin

            // Manage the period/cycle count
            if (i_period < n_period) begin
                i_period <= i_period + 1;

                if (i_update >= n_period - PHASE_CYCLES) begin
                    i_update <= i_update + PHASE_CYCLES - n_period;
                    i_shift <= 0;
                    i_phase <= i_phase + phase_per_update;
                end else begin
                    i_update <= i_update + PHASE_CYCLES;
                    i_shift <= i_shift + 1;
                end
            end else begin
                i_period <= 1;
                n_period <= nn_period;

                i_phase <= 0;
                i_update <= 0;
                i_shift <= 0;

                if (led_count >= led_periods) begin
                    led_count <= 1;

                    if (led_cycle == 4) begin
                        led_cycle <= 0;
                    end else begin
                        led_cycle <= led_cycle + 1;
                        led_phase <= led_cycle << 6;
                    end
                    o_camera_sync <= 1;
                end else begin
                    led_count <= led_count + 1;
                    o_camera_sync <= 0;
                end


            end

            // This code generates the outputs.  At the 18th cycle it latches the data.
            if (i_shift == 17) begin
                o_latch <= 1;
                // if (i_phase < (n_phase >> 1)) o_sync <= 1;
                if (i_phase < 128) o_sync <= 1;
                else o_sync <= 0;

                next_physical_channel <= 4'hF;
                // read_addr <= {read_bank, 4'hF};

            // Why 17 instead of 16?  There is a one cycle delay in generating usable data when reading from RAM.
            end else if (i_shift < 17) begin
                o_latch <= 0;
                // read_addr <= read_addr - 1;
                next_physical_channel <= next_physical_channel - 1;

                o_channel[0] <= ((i_phase + phase_0) < duty_0) ? 1 : 0;
                o_channel[1] <= ((i_phase + phase_1) < duty_1) ? 1 : 0;
                o_channel[2] <= ((i_phase + phase_2) < duty_2) ? 1 : 0;
                o_channel[3] <= ((i_phase + phase_3) < duty_3) ? 1 : 0;
                o_channel[4] <= ((i_phase + phase_4) < duty_4) ? 1 : 0;
                o_channel[5] <= ((i_phase + phase_5) < duty_5) ? 1 : 0;
                o_channel[6] <= ((i_phase + phase_6) < duty_6) ? 1 : 0;
                o_channel[7] <= ((i_phase + phase_7) < duty_7) ? 1 : 0;
                o_channel[8] <= ((i_phase + phase_8) < duty_8) ? 1 : 0;
                o_channel[9] <= ((i_phase + phase_9) < duty_9) ? 1 : 0;
                o_channel[10] <= ((i_phase + phase_10) < duty_10) ? 1 : 0;
                o_channel[11] <= ((i_phase + phase_11) < duty_11) ? 1 : 0;
                o_channel[12] <= ((i_phase + phase_12) < duty_12) ? 1 : 0;
                o_channel[13] <= ((i_phase + phase_13) < duty_13) ? 1 : 0;
                o_channel[14] <= ((i_phase + phase_14) < duty_14) ? 1 : 0;
                o_channel[15] <= ((i_phase + phase_15) < duty_15) ? 1 : 0;
                o_led_flash <= (led_cycle == 0) ? 0: (((i_phase + led_phase) < led_duty) ? 1 : 0);
                // o_led_flash <= (led_cycle == 0) ? 0: 1;
            end
        end
    end

    always @ (posedge i_command_clk) begin
        #0.5;

        if (i_startup < INIT_CYCLES) begin
            // If we don't wait a little bit after startup, erratic behavior often results
            // By 256 cycles, it should be good to go!
            if (i_startup < 256) begin
                write_addr <= i_startup[7:0];
                channel_write <= 16'hFFFF;
                // write_data <= {2'b00, i_startup[3:0], 2'b00, 8'h20};
                write_data <= {i_startup[3:0], 12'h080};
            end else begin
                channel_write <= 16'h0000;
                write_bank <= 0;
            end

            i_startup <= i_startup + 1;
        end

        if (i_command) begin
            case (i_command_data[31:24])
                "s", "S": begin
                    // Physical address must be valid!
                    if (i_command_data[23:16] < 16) begin

                        // If virtual address isn't valid, return current.
                        if (i_command_data[15:8] < 16) begin
                            `SET4x16(i_command_data[19:16], channel_swap_odd, i_command_data[11:8])
                            o_reply_data[15:8] <= {4'h0, i_command_data[11:8]};
                        end else begin
                            o_reply_data[15:12] <= 4'h0;
                            `SELECT4x16(i_command_data[19:16], o_reply_data[11:8], channel_swap_odd)
                        end

                        if (i_command_data[7:0] < 16) begin
                            `SET4x16(i_command_data[19:16], channel_swap_even, i_command_data[3:0])
                            o_reply_data[7:0] <= {4'h0, i_command_data[3:0]};
                        end else begin
                            // o_reply_data[7:0] <= {4'h0, channel_swap_even[(i_command_data[19:16]<<2)+3 : i_command_data[19:16]<<2]};
                            o_reply_data[7:4] <= 4'h0;
                            `SELECT4x16(i_command_data[19:16], o_reply_data[3:0], channel_swap_even)
                        end

                        o_reply_data[23:16] <= i_command_data[23:16];
                        o_reply_data[30:24] <= 7'b0000000;
                    end else begin
                        o_reply_data[30:0] <= {7'b0000010, i_command_data[23:0]};
                    end
                end

                "w", "W": begin
                    write_data <= i_command_data[15:0];
                    // write_addr <= {write_bank, write_channel[3:0]};
                    // channel_write <= 1 << write_channel[7:4];
                    write_addr <= {write_bank, i_command_data[19:16]};
                    channel_write <= 1 << i_command_data[23:20];
                    // o_reply_data[22:0] <= {7'b0000000, 4'b0000, write_bank, write_channel};
                    o_reply_data[30:0] <= {7'b0000000, i_command_data[23:0]};
                end

                "b", "B": begin
                    if (i_command_data[7:0] < 32) begin
                        read_bank <= i_command_data[3:0];
                        o_reply_data[7:0] <= {4'h0, i_command_data[3:0]};
                    end else begin
                        o_reply_data[7:0] <= {4'h0, read_bank};
                    end

                    if (i_command_data[15:8] < 32) begin
                        write_bank <= i_command_data[11:8];
                        o_reply_data[15:8] <= {4'h0, i_command_data[11:8]};
                    end else begin
                        o_reply_data[15:8] <= {4'h0, write_bank};
                    end

                    o_reply_data[23:16] <= 8'h00;
                    o_reply_data[30:24] <= 7'b0000000;

                    // if (i_command_data[7:0] < 32) && (i_command_data[15:8] < 32) begin
                    //     read_bank <= i_command_data[3:0];
                    //     write_bank <= i_command_data[11:8];
                    //     o_reply_data[22:0] <= {7'b0000000, 12'h000, i_command_data[11:8], 4'h0, i_command_data[3:0]};
                    // end else begin
                    //     o_reply_data[30:0] <= {7'b0000010, 12'h000, write_bank, 4'h0, read_bank};
                    // end
                end

                "l", "L": begin
                    led_duty <= i_command_data[23:16];
                    led_periods <= i_command_data[15:0];
                    o_reply_data[30:0] <= {7'b000000, i_command_data[23:0]};
                end

                default: begin
                    // Invalid commands always get a reply!
                    o_reply_data <= {last_overflow, 7'b0000001, 24'h000000};
                    last_overflow <= 0;
                    o_reply <= 1;
                end
            endcase

            if (~i_command_data[29]) begin //This bit incidates capitalized in ASCII, so reply!
                o_reply_data[31] <= last_overflow;
                last_overflow <= 0;
                o_reply <= 1;
            end else o_reply <= 0;

        end else begin
            // if (channel_write != 0) write_channel <= write_channel + 1;
            channel_write <= 0;
            o_reply <= 0;
        end

        if (o_reply && i_overflow) last_overflow <= 1;
    end

endmodule
