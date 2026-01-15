module volume(clk, att, sound_in, sound_out);
input clk;
input [2:0] att;
input [15:0] sound_in;
output reg [23:0] sound_out;

reg [2:0] cnt;
reg [23:0] sr;
always @(posedge clk) begin
	if (~|cnt) begin
		sr <= { sound_in, 8'b0 };
		sound_out <= sr;
	end
	else if (att >= cnt) sr <= { sr[23], sr[23:1] };
	cnt <= cnt + 1'b1;
end

endmodule
