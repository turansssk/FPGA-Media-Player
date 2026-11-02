`timescale 1ns/1ps
module tb_subtitle_bottom_layout;
reg clk=0,rst=1,ready=0,advance=0,vs=0;
reg [9:0] x=320;
reg [8:0] y=0;
wire pixel,visible;
integer row;
always #5 clk=~clk;
subtitle_sync dut(.wr_clk(clk),.wr_en(1'b0),.wr_addr(13'd0),.wr_data(8'd0),
 .clk(clk),.rst(rst),.subtitle_ready(ready),.subtitle_line_count(6'd1),
 .audio_sample_advance(advance),.audio_total_samples(32'd200),
 .resume_sample(32'd0),
 .video_vs(vs),.pixel_x(x),.pixel_y(y),.subtitle_pixel(pixel),.subtitle_visible(visible));
task probe;
 input [8:0] py;
 input expected;
 begin
   @(negedge clk);y=py;repeat(5)@(negedge clk);
   if(pixel!==expected)$fatal(1,"subtitle y=%0d got=%b expected=%b",py,pixel,expected);
 end
endtask
initial begin
 repeat(5)@(negedge clk);rst=0;
 // A real character/glyph memory lookup, not a forced output pixel.
 dut.cue_start[0]=0;dut.cue_end[0]=100;dut.cue_len[0]=1;dut.cue_char[0]=0;
 for(row=0;row<16;row=row+1)begin
   dut.glyph_hi[row]=8'hff;dut.glyph_lo[row]=8'hff;
 end
 ready=1;repeat(10)@(negedge clk);vs=1;repeat(5)@(negedge clk);
 if(!visible)$fatal(1,"cue did not become visible at frame boundary");
 probe(446,0);probe(461,0);probe(463,0);
 for(row=464;row<480;row=row+1)probe(row,1);
 probe(480,0);
 advance=1;repeat(7)@(negedge clk);advance=0;
 if(dut.sample_count!==7)$fatal(1,"sample timing changed");
 repeat(20)@(negedge clk);
 if(dut.sample_count!==7)$fatal(1,"pause did not hold cue position");
 probe(479,1);
 $display("PASS subtitle: actual BRAM pipeline renders all bottom 16 rows, old area blank, cue sample timing/pause unchanged");
 $finish;
end
initial begin #100000;$fatal(1,"subtitle watchdog");end
endmodule
