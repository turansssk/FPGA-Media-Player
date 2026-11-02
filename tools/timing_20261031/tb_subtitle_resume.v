`timescale 1ns/1ps
module tb_subtitle_resume;
reg clk=0,rst=1,ready=0,advance=0,vs=0;
reg [31:0] resume=250;
wire visible;
integer i;
always #5 clk=~clk;
subtitle_sync dut(.wr_clk(clk),.wr_en(1'b0),.wr_addr(13'd0),.wr_data(8'd0),
 .clk(clk),.rst(rst),.subtitle_ready(ready),.subtitle_line_count(6'd4),
 .audio_sample_advance(advance),.audio_total_samples(32'd400),.resume_sample(resume),
 .video_vs(vs),.pixel_x(10'd320),.pixel_y(9'd470),.subtitle_pixel(),.subtitle_visible(visible));
initial begin
 for(i=0;i<4;i=i+1)begin dut.cue_start[i]=i*100;dut.cue_end[i]=(i+1)*100;dut.cue_len[i]=1;end
 repeat(5)@(negedge clk);rst=0;repeat(8)@(negedge clk);ready=1;
 repeat(20)@(negedge clk);vs=1;repeat(5)@(negedge clk);
 if(dut.sample_count!=250||dut.current_line!=2||dut.displayed_line!=2||!visible)
  $fatal(1,"resume cue mismatch");
 repeat(30)@(negedge clk);if(dut.sample_count!=250)$fatal(1,"pause changed time");
 advance=1;repeat(150)@(negedge clk);advance=0;repeat(5)@(negedge clk);
 if(dut.sample_count!=0||dut.current_line!=0)$fatal(1,"loop reset");
 rst=1;ready=0;resume=0;repeat(5)@(negedge clk);rst=0;repeat(10)@(negedge clk);
 ready=1;repeat(10)@(negedge clk);if(dut.sample_count!=0)$fatal(1,"new song inherited bookmark");
 $display("PASS subtitle resume cue selection, pause retention, loop and reset");$finish;
end
initial begin #100000;$fatal(1,"watchdog");end
endmodule
