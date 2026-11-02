`timescale 1ns/1ps
// Real top-level mode gating; peripheral stubs do not model board behavior.
module tb_media_ack_cdc;
reg clk=0,mem_clk=0,rst=1,ack=0,busy=1,requested=0;
always #10 clk=~clk;
always #12.5 mem_clk=~mem_clk;
top dut(.clk(clk),.key1(1'b1),.key2(1'b1),.key3(1'b1),.key4(1'b1));
task ticks;input integer n;begin repeat(n)@(negedge clk);end endtask
initial begin
 force dut.rst_core=rst;force dut.rst_all=rst;
 force dut.mem_clk=mem_clk;force dut.video_clk=clk;force dut.audio_mclk=clk;
 force dut.selected_transport_busy=busy;
 force dut.selected_read_request=1'b0;force dut.selected_write_request=1'b0;
 force dut.sd_write_req_ack=ack;force dut.audio_pause_ack_sync=3'b111;
 force dut.sd_owner=2'b00;
 force dut.media_keys.requested_video_mode=requested;
 ticks(5);rst=0;ticks(3);requested=1;
 @(negedge mem_clk);ack=1;ticks(5);
 if(dut.raw_video_mode||dut.media_write_ack_sync!==3'b111)
  $fatal(1,"mode committed while transfer was busy or ack not sampled");
 busy=0;ticks(4);
 if(dut.media_can_switch||dut.raw_video_mode)$fatal(1,"ack-high did not block mode commit");
 @(negedge mem_clk);ack=0;
 // Clearing the memory-domain input must not bypass the synchronizer.
 #1;if(dut.media_can_switch)$fatal(1,"raw asynchronous ack bypass");
 ticks(6);
 if(!dut.raw_video_mode||dut.media_write_ack_sync!==3'b000)
  $fatal(1,"safe mode commit missing after synchronized ack drain");
 rst=1;#1;if(dut.media_write_ack_sync!==3'b000)$fatal(1,"sync reset");
 $display("PASS media ack CDC: busy guard, delayed ack drain, safe commit and reset");$finish;
end
initial begin #10000;$fatal(1,"watchdog");end
endmodule
