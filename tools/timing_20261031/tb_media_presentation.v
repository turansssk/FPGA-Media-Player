`timescale 1ns/1ps
// Presentation/CDC test only. Vendor PLL/HDMI/SDRAM modules are black boxes
// (-i); force their clock/reset and the completed-frame producer interfaces.
module tb_media_presentation;
reg clk=0,rst=1,mode=1,bmp_valid=0,video_valid=0,request=0;
reg [1:0] bmp_index=0,video_index=0;
reg [3:0] bmp_code=1,video_code=1;
always #5 clk=~clk;
top dut(.clk(clk),.key1(1'b1),.key2(1'b1),.key3(1'b1),.key4(1'b1));
task refresh;
 begin
  @(negedge clk);request=1;@(negedge clk);request=0;
 end
endtask
initial begin
 force dut.video_clk=clk;force dut.rst_all=rst;
 force dut.raw_video_mode=mode;
 force dut.bmp_display_valid=bmp_valid;force dut.raw_video_display_valid=video_valid;
 force dut.bmp_read_addr_index=bmp_index;force dut.raw_video_read_addr_index=video_index;
 force dut.bmp_state_code=bmp_code;force dut.raw_video_status=video_code;
 force dut.video_read_req=request;force dut.media_paused=1'b0;
 repeat(5)@(negedge clk);rst=0;
 repeat(5)@(negedge clk);refresh();
 if(dut.display_valid_video_sync[1])$fatal(1,"Unloaded frame displayed");
 // First valid and index update arrive together just before refresh.
 video_valid=1;video_index=1;refresh();
 if(dut.display_valid_video_sync[1])$fatal(1,"Validity bypassed the buffer synchronizer");
 repeat(4)@(negedge clk);refresh();
 if(!dut.display_valid_video_sync[1]||dut.video_read_addr_index!=3||!dut.presented_video_mode)
  $fatal(1,"First video frame was not committed to physical slot3");
 mode=0;repeat(5)@(negedge clk);refresh();
 if(dut.video_read_addr_index!=3||!dut.presented_video_mode)
  $fatal(1,"Switch to unloaded BMP discarded old video");
 bmp_valid=1;bmp_index=0;bmp_code=4;repeat(5)@(negedge clk);
 if(dut.video_read_addr_index!=3)$fatal(1,"Index changed outside vertical blank");
 refresh();
 if(dut.video_read_addr_index!=0||dut.presented_video_mode||dut.presented_code!=4)
  $fatal(1,"BMP mode/index/OSD commit mismatch");
 bmp_index=1;repeat(5)@(negedge clk);refresh();
 if(dut.video_read_addr_index!=1)$fatal(1,"BMP second buffer not presented");
 mode=1;repeat(5)@(negedge clk);refresh();
 if(dut.video_read_addr_index!=3||!dut.presented_video_mode)
  $fatal(1,"Switch did not restore preserved video buffer");
 $display("PASS presentation: first-valid CDC, old-frame retention, four slots, blank-only switching");
 $finish;
end
initial begin #10000;$fatal(1,"Presentation watchdog");end
endmodule
