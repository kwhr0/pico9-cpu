module dcsg #(parameter CLK = 3579545)
	(clk, wr, data, sound_out)/*synthesis syn_romstyle="distributed_rom"*/;
input clk, wr;
input [7:0] data;
output [15:0] sound_out;

localparam DCSG_CLK = 3579545;
localparam DCSG_DIV = (CLK + DCSG_CLK / 8) / (DCSG_CLK / 4); // nearest

// access

reg [6:0] freq_u[0:3];
reg [3:0] freq_l[0:3], att_n[0:3];
reg [2:0] last;
reg [1:0] nf;
reg fb;

always @(posedge clk)
	if (wr)
		if (data[7]) begin
			last <= data[6:4];
			if (data[4]) att_n[data[6:5]] <= ~data[3:0];
			else begin
				freq_l[data[6:5]] <= data[3:0];
				if (&data[6:5]) { fb, nf } <= data[2:0];
			end
		end
		else if (~last[0]) freq_u[last[2:1]] <= data[6:0];

// update

reg [10:0] period[0:3];
reg update_period = 0, update_period3 = 0;
wire [1:0] period_adr = update_period ? last[2:1] : 2'b11;
wire [2:0] regsel = data[7] ? data[6:4] : last;

always @(posedge clk) begin
	if (update_period) begin
		update_period <= 1'b0;
		period[period_adr] <= { freq_u[last[2:1]], freq_l[last[2:1]] };
	end
	else if (wr & ~&regsel[2:1] & ~regsel[0])
		update_period <= 1'b1;
	//
	if (~update_period & update_period3) begin
		update_period3 <= 1'b0;
		period[period_adr] <= &nf ? { freq_u[2'b10], freq_l[2'b10], 1'b0 } : 11'h20 << nf;
	end
	else if (wr & (regsel[2] & (regsel[1] | &nf) & ~regsel[0]))
		update_period3 <= 1'b1;
end

// generate

function [12:0] tbl;
input [3:0] l;
	case (l)
		4'hf: tbl = 13'h1fff;
		4'he: tbl = 13'h196a;
		4'hd: tbl = 13'h1430;
		4'hc: tbl = 13'h1009;
		4'hb: tbl = 13'h0cbc;
		4'ha: tbl = 13'h0a1e;
		4'h9: tbl = 13'h0809;
		4'h8: tbl = 13'h0662;
		4'h7: tbl = 13'h0512;
		4'h6: tbl = 13'h0407;
		4'h5: tbl = 13'h0333;
		4'h4: tbl = 13'h028a;
		4'h3: tbl = 13'h0204;
		4'h2: tbl = 13'h019a;
		4'h1: tbl = 13'h0146;
		4'h0: tbl = 13'h0000;
	endcase
endfunction

reg [5:0] divcnt;
reg out[0:3];
reg [15:0] acc, sound_out;
reg [1:0] i = 0;
reg [10:0] count[0:3];
wire [10:0] count_next = count[i] - 1'b1;
wire trig = ~|count_next;
wire [12:0] level = tbl(att_n[i]);
wire [15:0] acc_d = out[i] ? acc + level : acc - level;
reg [14:0] lfsr = 1;

always @(posedge clk)
	if (|divcnt) divcnt <= divcnt - 1'b1;
	else begin
		divcnt <= DCSG_DIV - 1;
		count[i] <= trig ? period[i] : count_next;
		if (trig) out[i] <= &i ? lfsr[14] : ~out[i];
		if (wr & regsel == 3'b110) lfsr <= 15'b1;
		else if (trig & &i)
			lfsr <= { lfsr[13:0], lfsr[14] ^ lfsr[13] & fb };
		acc <= &i ? 0 : acc_d;
		if (&i) sound_out <= acc_d;
		i <= i + 1;
	end

endmodule
