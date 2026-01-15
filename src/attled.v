module attled(clk, clken, wr, data, led);
input clk, clken, wr;
input [7:0] data;
output reg [2:0] led;

reg [3:0] r, g, b, cnt;
always @(posedge clk) begin
	if (wr & data[7] & data[4])
		case (data[6:5])
			2'b00: r <= data[3:0];
			2'b01: g <= data[3:0];
			2'b10: b <= data[3:0];
		endcase
	if (clken) cnt <= cnt + 1;
	led <= { r >= cnt, g >= cnt, b >= cnt };
end

endmodule
