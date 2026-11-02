`timescale 1ns/1ps
// Real top-level audio selection controller; peripheral interfaces are forced.
// Does not claim to model physical HDMI, SDRAM, SD SPI or PLL behavior.
module tb_audio_bookmarks;
reg clk=0,rst=1,mode=0,epoch=0,ack=0,sample=0;
reg [2:0] video=1;
reg [1:0] music=0,owner=0;
integer pulses=0,n;
always #5 clk=~clk;
top dut(.clk(clk),.key1(1'b1),.key2(1'b1),.key3(1'b1),.key4(1'b1));
always @(negedge clk)if(dut.audio_restart_pulse)pulses=pulses+1;
task ticks;input integer count;begin repeat(count)@(negedge clk);end endtask
task consume;input integer count;begin
 for(n=0;n<count;n=n+1)begin sample=1;ticks(1);sample=0;ticks(1);end
end endtask
task finish_switch;begin ack=1;ticks(8);ack=0;ticks(5);end endtask
initial begin
 force dut.rst_core=rst;force dut.rst_all=rst;force dut.audio_mclk=clk;
 force dut.video_clk=clk;force dut.mem_clk=clk;
 force dut.presented_video_mode=mode;force dut.raw_video_mode=mode;
 force dut.presented_video_index=video;force dut.presented_video_epoch=epoch;
 force dut.picture_music_index=music;force dut.audio_sample_advance_sys=sample;
 force dut.audio_pause_ack=ack;force dut.sd_owner=owner;
 force dut.wav_audio_total_samples=32'd1000;
 ticks(5);rst=0;ticks(8);consume(123);
 if(dut.audio_position!=123)$fatal(1,"consumed bookmark count");
 mode=1;epoch=1;ticks(10);
 if(!dut.audio_restart_pending||pulses)$fatal(1,"restart before pause ack");
 owner=2;ack=1;ticks(8);
 if(pulses)$fatal(1,"reset while old SD transaction owned");
 owner=0;ticks(8);ack=0;ticks(5);
 if(pulses!=1||!dut.active_audio_source_video||dut.audio_resume_sample!=0||dut.picture_audio_bookmark!=123)
  $fatal(1,"first video transition");
 consume(77);mode=0;ticks(8);finish_switch;
 if(pulses!=2||dut.active_audio_source_video||dut.audio_position!=123||dut.audio_resume_sample!=123||dut.video_audio_bookmark!=77)
  $fatal(1,"picture resume");
 consume(10);mode=1;ticks(8);finish_switch;
 if(pulses!=3||dut.audio_position!=77||dut.audio_resume_sample!=77||dut.picture_audio_bookmark!=133)
  $fatal(1,"video resume");
 video=2;epoch=0;ticks(8);finish_switch;
 if(pulses!=4||dut.active_audio_index!=1||dut.audio_position!=0||dut.audio_resume_sample!=0)
  $fatal(1,"next video did not restart from zero");
 consume(30);mode=0;ticks(8);finish_switch;
 if(dut.audio_resume_sample!=133)$fatal(1,"picture progress overwritten by video");
 music=1;ticks(8);finish_switch;
 if(dut.audio_resume_sample!=0||dut.audio_position!=0||dut.active_audio_index!=1)
  $fatal(1,"next MUSIC did not restart");
 consume(1003);if(dut.audio_position!=3)$fatal(1,"loop bookmark");
 rst=1;ticks(5);rst=0;ticks(5);
 if(dut.audio_position||dut.picture_audio_bookmark||dut.video_audio_bookmark||dut.audio_resume_sample)
  $fatal(1,"reset left bookmarks");
 $display("PASS top audio bookmarks: safe SD/pause drain, group resume, next-item zero, loop and reset");$finish;
end
initial begin #1000000;$fatal(1,"watchdog");end
endmodule
