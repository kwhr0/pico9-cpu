module i2c #(parameter CLK = 3579545)(clk, data, wr, scl, sda, busy);
input clk, wr;
input [8:0] data;
output scl, sda, busy;

localparam SCL_FREQ = 400000;
localparam I2C_DIV = $ceil($itor(CLK) / (4 * SCL_FREQ));

localparam START = 0;
localparam SEND = 1;
localparam STOP = 2;
localparam WAIT = 3;
localparam SN = 4;

reg [4:0] divcnt = 0;
reg [3:0] bitcnt = 0;
reg [1:0] scnt = 0;
reg [SN-1:0] s = 0;
reg [7:0] sr = 0;
reg scl = 1, sda = 1;
assign busy = s[START] | s[SEND] | s[STOP];
wire ren = ~|divcnt;
always @(posedge clk)
	divcnt <= busy ? ren ? I2C_DIV - 1'b1 : divcnt - 1'b1 : 2'b0;
always @(posedge clk)
	if (wr & ~busy) begin
		if (~|s & ~data[8]) s <= 1 << START;
		else if (s[WAIT]) s <= data[8] ? 1 << STOP : 1 << SEND;
	end
	else if (ren & &scnt)
		if (s[START]) s <= 1 << SEND;
		else if (s[SEND] & bitcnt[3]) s <= 1 << WAIT;
		else if (s[STOP]) s <= 0;
always @(posedge clk)
	if (wr & ~busy) sr <= data[7:0];
	else if (ren & s[SEND] & &scnt) sr <= { sr[6:0], 1'b0 };
always @(posedge clk)
	if (ren)
		scnt <= busy ? scnt + 2'b1 : 2'b0;
always @(posedge clk)
	if (ren)
		if (~s[SEND]) bitcnt <= 0;
		else if (&scnt) bitcnt <= bitcnt + 4'b1;
always @(posedge clk)
	if (ren)
		if (busy & scnt == 2'b01) scl <= 1;
		else if ((s[START] | s[SEND]) & &scnt) scl <= 0;
always @(posedge clk)
	if (ren)
		if ((s[START] & scnt == 2'b10 | s[STOP] & ~|scnt)) sda <= 0;
		else if (s[STOP] & scnt == 2'b10) sda <= 1;
		else if (s[SEND] & ~|scnt) sda <= bitcnt[3] | sr[7];

endmodule
