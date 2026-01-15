module top(I_clk, btn_up_n, btn_dn_n, btn_vol_n,
	cs, sclk, miso, mosi, scl, sda, bclk, lrclk, sout, led);
input I_clk, btn_up_n, btn_dn_n, btn_vol_n, miso;
output [2:0] led;
output cs, sclk, mosi, scl, sda, bclk, lrclk, sout;

localparam SYSCLK = 36000000;
pll pll(.clkin(I_clk), .clkout(clk), .lock(rst_n));

wire [7:0] spi_data;
wire [2:0] port;
wire [8:0] data_in = port[1] ? { 1'b0, spi_data } :
	{ 1'b0, ~btn_up_n, ~btn_dn_n, ~btn_vol_n, 2'b00, i2c_busy, spi_busy, timer_active };
wire [8:0] cpu_data_out;

cpu cpu(.clk(clk), .reset(~rst_n), .iord(iord), .iowr(iowr),
	.port(port), .data_in(data_in), .data_out(cpu_data_out));

timer #(.CLK(SYSCLK)) timer(.clk(clk), .wr(iowr & ~|port[2:1]), .adr(port[0]), .data(cpu_data_out[7:0]), .active(timer_active));

i2c #(.CLK(SYSCLK)) i2c(.clk(clk), .data(cpu_data_out), .wr(iowr & port == 3'b011), .scl(scl_t), .sda(sda_t), .busy(i2c_busy));
assign sda = sda_t ? 1'bZ : 1'b0;
assign scl = scl_t ? 1'bZ : 1'b0;

wire [15:0] snd16;
wire [23:0] snd24;
wire snd_wr = iowr & port == 3'b010;
dcsg #(.CLK(SYSCLK)) dcsg(.clk(clk), .wr(snd_wr), .data(cpu_data_out[7:0]), .sound_out(snd16));

reg lrclk1;
always @(posedge clk) lrclk1 <= lrclk;
wire clken = ~lrclk1 & lrclk;
attled attled(.clk(clk), .clken(clken), .wr(snd_wr), .data(cpu_data_out[7:0]), .led(led));

reg [2:0] att = 7;
always @(posedge clk)
	if (iowr & port == 3'b100) att <= ~cpu_data_out[2:0];
volume volume(.clk(clk), .att(att), .sound_in(snd16), .sound_out(snd24));
i2s #(.CLK(SYSCLK)) i2s(.clk(clk), .sound_in(snd24), .bclk(bclk), .lrclk(lrclk), .sout(sout));

reg fast, cs;
always @(posedge clk)
	if (iowr & &port) { fast, cs } <= cpu_data_out[1:0];
spi #(.CLK(SYSCLK)) spi(.clk(clk), .wr(iowr & port == 3'b110), .fast(fast),
	.data_in(cpu_data_out[7:0]), .data_out(spi_data),
	.busy(spi_busy), .sclk(sclk), .miso(miso), .mosi(mosi));

endmodule
