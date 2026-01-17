// Pico9 CPU
// Copyright 2026 © Yasuo Kuwahara

// MIT License

module pico9(clk, reset, port, iord, iowr, data_in, data_out);
input clk, reset;
input [8:0] data_in;
output iord, iowr;
output [8:0] data_out;
output [IOMSB-1:0] port;

localparam PCMSB = 8;
localparam ADRMSB = 10;
localparam IOMSB = 3;

reg [31:0] i;
wire [ADRMSB:0] adr;
reg [8:0] data;
reg [3:0] flags;

// STATE

localparam M1 = 0;
localparam M2 = 1;
localparam M3 = 2;
localparam M4 = 3;

reg [3:0] s;
reg [1:0] cnt;
wire contd = ~i[31] & |cnt;
always @(posedge clk)
	if (reset) s <= 0;
	else s <= { s[2:1], s[3] & contd | s[0], s[3] & ~contd | ~|s };
always @(posedge clk)
	if (~i[31])
		if (s[M1]) cnt <= i[29:28];
		else if (s[M4]) cnt <= cnt - 2'b1;

// PC

reg [PCMSB:0] pc;
wire [PCMSB:0] pc_next = pc + 1'b1;
wire cond_ok = ~i[27] | flags[i[26:25]] ^ i[24];
always @(posedge clk)
	if (reset) pc <= 0;
	else if (s[M3])
		if (i[31] ? ~i[30] | ~i[29] & ~cond_ok : ~|cnt)
			pc <= pc_next;
		else if (&i[31:30])
			if (i[29:28] == 2'b10) begin
				pc[PCMSB:PCMSB-8] <= data;
				//pc[PCMSB-9:0] <= 0;
			end
			else pc <= i[PCMSB:0];

// MEMORY

reg [31:0] rom[0:2**(PCMSB+1)-1];
initial $readmemh("rom.mem", rom);
always @(posedge clk)
	i <= rom[pc];

reg [8:0] ram[0:2**(ADRMSB+1)-1];
initial $readmemh("ram.mem", ram);
wire isio = ~|adr[ADRMSB:IOMSB+1];
always @(posedge clk) begin
	if (wr) ram[adr] <= data_out;
	data <= isio & ~adr[IOMSB] ? data_in : ram[adr];
end

// ADDRESS

reg [ADRMSB:0] srcptr, srcadr, dstptr, dstadr;
wire [ADRMSB:0] srcadd_a, srcadd_b, srcadd_y, srcadr_d;
wire [ADRMSB:0] dstadd_a, dstadd_b, dstadd_y;
wire [ADRMSB:0] ptr_d = i[29] ? i[ADRMSB:0] : { data[ADRMSB-8:0], data[7:0] };

assign srcadd_a = |i[10:9] ? srcptr : 0;
assign srcadd_b = { {ADRMSB-8{ |i[10:9] & i[8] }}, i[8:0] };
assign srcadd_y = srcadd_a + srcadd_b;

assign dstadd_a = |i[22:21] ? dstptr : 0;
assign dstadd_b = { {ADRMSB-8{ |i[22:21] & i[20] }}, i[20:12] };
assign dstadd_y = dstadd_a + dstadd_b;

wire shr = ~i[31] & &i[26:25];
wire ptr2 = s[M2] & i[31:30] == 2'b10;
wire ptr3 = s[M3] & i[31:30] == 2'b10;
wire ptr4 = s[M4] & i[31:30] == 2'b10;
wire ptr_ld = (ptr3 | ptr4) & ~i[28];
wire ptr_st = (ptr2 | ptr3) &  i[28];

always @(posedge clk)
	if (s[M1] | s[M4] & ~i[31] | s[M2] & i[31:30] == 2'b10)
		srcadr <= s[M1] ? srcadd_y : srcadr + { {ADRMSB{ shr }}, 1'b1 };
always @(posedge clk)
	if (s[M1] | s[M4] & ~i[31])
		dstadr <= s[M1] ? dstadd_y : dstadr + { {ADRMSB{ shr }}, 1'b1 };
always @(posedge clk)
	if (s[M4] & ~i[31] & i[10] | ptr_ld & ~i[24])
		srcptr <= ptr3 ? { srcptr[ADRMSB:8], ptr_d[7:0] } :
			ptr4 ? { ptr_d[ADRMSB:8], srcptr[7:0] } :
			srcptr + { {ADRMSB{ i[9] }}, 1'b1 };
always @(posedge clk)
	if (s[M4] & ~i[31] & i[22] | ptr_ld & i[24])
		dstptr <= ptr3 ? { dstptr[ADRMSB:8], ptr_d[7:0] } :
			ptr4 ? { ptr_d[ADRMSB:8], dstptr[7:0] } :
			dstptr + { {ADRMSB{ i[21] }}, 1'b1 };

assign adr = |s[M4:M3] & ~i[31] | s[M2] & &i[31:30] ? dstadr : srcadr;
assign port = adr[IOMSB-1:0];
assign wr = s[M4] & ~i[31] & i[27] | s[M2] & &i[31:28] | ptr_st;
assign iord = s[M2] & ~i[31] & isio & ~adr[IOMSB] & ~i[11];
assign iowr = wr & isio & adr[IOMSB];

// DATA

reg [8:0] src;
always @(posedge clk)
	if (s[M3] & ~i[31])
		src <= i[11] ? cnt == i[29:28] ? i[8:0] : 9'b0 : data;

wire cy = flags[2];
wire [8:0] logic_y = i[25] ?
	i[24] ? src | data : src ^ data :
	i[24] ? src & data : src;
wire [9:0] add_y = data + (src ^ {9{ i[24] }}) + (cy ^ i[24]);
wire [8:0] shr_y = { |i[29:28] ? { 1'b0, cy } : { cy, src[8] }, src[7:1] };
wire [9:0] alu_y = i[26] ? i[25] ? shr_y : add_y : logic_y;
wire [8:0] ptr_y = i[24] ? ptr3 ? dstptr[ADRMSB:8] : dstptr[7:0] :
                           ptr3 ? srcptr[ADRMSB:8] : srcptr[7:0];
assign data_out = s[M2] & &i[31:28] ? pc_next[PCMSB:PCMSB-8] :
	ptr_st ? ptr_y : { ~|cnt & alu_y[8], alu_y[7:0] };

always @(posedge clk)
	if (~i[31])
		if (s[M1]) flags <= 4'b0011;
		else if (s[M4])
			flags <= {
				shr ? src[0] : add_y[9],
				shr ? src[0] : add_y[8],
				flags[1] & ~|alu_y[8:0],
				flags[0] & ~|alu_y[7:0]
			};

wire [7:0] store = wr ? 'h53 : 'h20;
initial $monitor("%x %x %b %x %c %x %x",
	pc, i, flags, s, store, adr, data_out);
endmodule
