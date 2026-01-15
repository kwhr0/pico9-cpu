module timer #(parameter CLK = 3579545)(clk, wr, adr, data, active);
input clk, wr, adr;
input [7:0] data;
output active;

localparam FS = 44100; // VGM standard
localparam TIMER_DIV = $ceil($itor(CLK) / FS);

reg cnt_en;
reg [15:0] samplecnt;
reg [10:0] clkcnt;
assign active = |samplecnt;

always @(posedge clk)
	if (wr)
		if (~adr) begin
			cnt_en <= 0;
			samplecnt <= data;
		end
		else begin
			cnt_en <= 1;
			clkcnt <= 0;
			samplecnt <= { data, samplecnt[7:0] };
		end
	else if (cnt_en & active) begin
		if (|clkcnt) clkcnt <= clkcnt - 1;
		else begin
			clkcnt <= TIMER_DIV - 1;
			samplecnt <= samplecnt - 1;
		end
	end

endmodule
