// Using the verilog reference code from Lattice
// This should synthesize to internal BRAM
module ram #(parameter addr_width=9, parameter data_width=8)(din, write_en, waddr, wclk, raddr, rclk, dout);  //Default is 512x8
    input [addr_width-1:0] waddr, raddr;
    input [data_width-1:0] din;
    input write_en, wclk, rclk;
    output reg [data_width-1:0] dout;
    reg [data_width-1:0] mem [(1<<addr_width)-1:0];

    always @(posedge wclk) begin
        if (write_en) mem[waddr] <= din;
    end

    always @(posedge rclk) begin
        dout <= mem[raddr];
    end
endmodule
