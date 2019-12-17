module usb_command #(
        parameter ID_VENDOR = 'h1d50,
        parameter ID_PRODUCT = 'h6130,
        parameter COMMAND_BYTES = 4,
        parameter REPLY_BYTES = 4,
        parameter UART_RESET_CYCLES = 480000
    )  (
        input  CLK,
        inout  USBP,
        inout  USBN,
        output USBPU,

        output CLK_48,
        output LED,

        // Interface to module which receives commands
        input wire i_reply,
        input wire [REPLY_BYTES*8-1:0] i_data,
        output reg o_overflow = 0,
        output reg o_command = 0,
        output reg [COMMAND_BYTES*8-1:0] o_data = 0
    );

    wire clk_locked;

    SB_PLL40_CORE #(
            .FEEDBACK_PATH("SIMPLE"),
            .DIVR(4'b0000),		// DIVR =  0
            .DIVF(7'b0101111),	// DIVF = 47
            .DIVQ(3'b100),		// DIVQ =  4
            .FILTER_RANGE(3'b001)	// FILTER_RANGE = 1
        ) clk_divider (
        .LOCK(clk_locked),
            .RESETB(1'b1),
            .BYPASS(1'b0),
            .REFERENCECLK(CLK),
            .PLLOUTGLOBAL(CLK_48)
        );

    // LED
    reg [23:0] ledCounter;
    always @(posedge CLK_48) ledCounter <= ledCounter + 1;
    assign LED = ledCounter[23];

    // Generate reset signal
    reg [5:0] reset_cnt = 0;
    wire reset = ~reset_cnt[5];
    always @(posedge CLK_48)
        if ( clk_locked ) reset_cnt <= reset_cnt + reset;

    // // uart pipeline in
    // wire [7:0] uart_in_data;
    // wire       uart_in_valid;
    // wire       uart_in_ready;

    // assign debug = { uart_in_valid, uart_in_ready, reset, CLK_48};

    reg [32:0] uart_reset_count = 0;
    reg [7:0] uart_read_cycle = 0;
    reg [7:0] fifo_write_cycle = 0;
    reg [1:0] fifo_read_cycle = 0;

    wire [7:0] uart_in_data;
    wire uart_in_valid;
    reg uart_in_ready = 1;
    reg [7:0] uart_out_data;
    reg uart_out_valid = 0;
    wire uart_out_ready;

    // usb uart - this instanciates the entire USB device.
    usb_uart_i40 #(.ID_VENDOR(ID_VENDOR), .ID_PRODUCT(ID_PRODUCT)) uart (
        .clk_48mhz  (CLK_48),
        .reset      (reset),

        // pins
        .pin_usb_p(USBP),
        .pin_usb_n(USBN),

        // uart pipeline in (out of the device, into the host)
        .uart_in_data(uart_out_data),
        .uart_in_valid(uart_out_valid),
        .uart_in_ready(uart_out_ready),

        // uart pipeline out (into the device, out of the host)
        .uart_out_data(uart_in_data),
        .uart_out_valid(uart_in_valid),
        .uart_out_ready(uart_in_ready)

        //.debug( debug )
        );

    assign USBPU = 1'b1;

    reg [8:0] fifo_bytes_ready = 0;
    reg [8:0] fifo_write_addr = 0;
    reg [8:0] fifo_read_addr = 0;
    wire [7:0] fifo_read_data;
    reg [REPLY_BYTES*8-1:0] fifo_write_data = 0;
    reg fifo_write = 0;
    reg fifo_read = 0;

    ram fifo(
        .wclk(CLK_48),
        .write_en(fifo_write),
        .waddr(fifo_write_addr),
        .din(fifo_write_data[REPLY_BYTES*8-1:REPLY_BYTES*8-8]),
        .rclk(CLK_48),
        .raddr(fifo_read_addr),
        .dout(fifo_read_data)
    );

    always @ (posedge CLK_48)

    begin
        #0.5;
        // Reset cycle: whole command must be received in 1 ms, or it resets.
        if (uart_reset_count > UART_RESET_CYCLES) begin
            uart_reset_count <= 0;
            uart_read_cycle <= 0;
        end else begin
            // If there is input data, shift it in
            if (uart_in_valid) begin
                uart_reset_count <= 0;
                o_data <= (o_data << 8) + uart_in_data;

                // If we have read the whole command, send the data over!
                if (uart_read_cycle == (COMMAND_BYTES-1)) begin
                    o_command <= 1;
                    uart_read_cycle <= 0;
                end else begin
                    o_command <= 0;
                    uart_read_cycle <= uart_read_cycle + 1;
                end
            end else begin
                o_command <= 0;
                if (uart_read_cycle > 0) uart_reset_count <= uart_reset_count + 1;
            end
        end

        // Move data from the input buffer into the FIFO one byte at a time
        if (fifo_write_cycle > 0) begin
            if (fifo_write_cycle == 1) o_overflow <= 0;
            else o_overflow <= 1;
            fifo_write <= 1;
            fifo_write_data <= fifo_write_data << 8;
            fifo_write_cycle <= fifo_write_cycle - 1;
        end
        // If we aren't moving data into the fifo, we _might_ be ready to receive
        //  a new reply...
        else begin
            // ... but not if the FIFO is fullish.
            if ((fifo_write_addr - fifo_read_addr) >= (500 - REPLY_BYTES)) begin
                o_overflow <= 1;
                fifo_write <= 0;
            end else begin
                if (i_reply) begin
                    fifo_write_data <= i_data;
                    o_overflow <= 1;
                    fifo_write <= 1;
                    fifo_write_cycle <= REPLY_BYTES - 1;
                end else begin
                    o_overflow <= 0;
                    fifo_write <= 0;
                end
            end
        end

        // if (fifo_bytes_ready > 0) begin
        //     uart_out_valid <= 1;
        // end else begin
        //     uart_out_valid <= 0;
        // end

        // fifo_read <= (uart_out_valid && uart_out_ready)

        // Move data from the FIFO to the output streaming port.
        case (fifo_read_cycle)
            0: if (fifo_read_addr != fifo_write_addr) begin
                uart_out_data <= fifo_read_data;
                fifo_read_addr <= fifo_read_addr + 1;
                // fifo_read <= 1;
                fifo_read_cycle <= 1;
                uart_out_valid <= 1;
            end
            //
            // 1: begin
            //     fifo_read <= 0;
            //     uart_out_valid <= 1;
            //     fifo_read_cycle <= 2;
            // end
            //
            default: if (uart_out_ready) begin
                uart_out_valid <= 0;
                fifo_read_cycle <= 0;
            end
        endcase

        // fifo_bytes_ready <= fifo_bytes_ready + (fifo_write ? 1 : 0) - ((uart_out_valid && uart_out_ready) ? 1 : 0);
        if (fifo_write) fifo_write_addr <= fifo_write_addr + 1;
        // if (uart_out_valid && uart_out_ready) fifo_read_addr <= fifo_read_addr + 1;

        // if (fifo_bytes_ready >= 0) begin
        //     uart_out_valid <= 1;
        //     fifo_read <= uart_out_ready;
        // end else begin
        //     fifo_read <= 0;
        //     if (uart_out_ready) uart_out_valid <= 0;
        // end
    end

endmodule
