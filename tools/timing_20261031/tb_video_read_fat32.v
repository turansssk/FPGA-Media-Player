`timescale 1ns/1ps
// Standalone regression: mocked FAT32 card and framebuffer handshake.
// Run with Icarus: iverilog -g2012 -s tb_video_read_fat32 -o video_tb
//   tools/tests/tb_video_read_fat32.v src/user_source/hdl_source/SD/video_read_fat32.v
// vvp video_tb +CASE=0 (cases 0..8, see final checks below).
module tb_video_read_fat32;
reg clk=0,rst=1,start=0,init_done=1,enabled=1;
always #5 clk=~clk;
reg global_pause=0,finish_toggle=0,ack=0,initial_buffer=0;
reg next_item=0;
wire scan_done,found,display_valid,paused,write_req,write_en,sd_read;
wire [3:0] status;
wire [1:0] write_index,read_index;
wire [31:0] write_data,sd_addr;
reg [7:0] sd_data=0;
reg sd_valid=0,sd_end=0;
integer test_case=0,requests=0,total_pixels=0,frame_pixels=0;
integer completed=0,shown=0,last_frame=-1;
integer ack_delay=0,ack_state=0,sd_sectors=0;
reg previous_display=0;
reg [1:0] previous_index=0;
reg [1:0] presented_index=0;
integer refresh_phase=0;
wire sync_hold;
wire [2:0] video_number;
reg [31:0] saved_frame,saved_sector,saved_phase;
reg saved_epoch;
integer sample_div=0,sample_period=110000,consumed=0,skipped=0,loops=0;
integer expected_frame=0,last_target=-1;
integer observed_debt=0,observed_phase=0;
reg initial_epoch;
wire sample_event=(sample_div==sample_period-1)&&display_valid&&!sync_hold&&enabled&&!global_pause;
always @(negedge clk)begin
 if(rst)sample_div=0;
 else if(display_valid&&!sync_hold&&enabled&&!global_pause)begin
  if(sample_div==sample_period-1)begin sample_div=0;consumed=consumed+1;end
  else sample_div=sample_div+1;
 end
 if(!rst&&dut.skip_frame)skipped=skipped+1;
end
video_read_fat32 #(.CLK_FREQ_HZ(1000),.AUDIO_SAMPLE_RATE(48),.TIMEOUT_CYCLES(2000)) dut(
 .clk(clk),.rst(rst),.start(start),.sd_init_done(init_done),
 .playback_enable(enabled),.pause_playback(global_pause),.next_item(next_item),
 .audio_sample_advance(sample_event),.audio_clock_enable(1'b1),
 .audio_sync_hold(sync_hold),.video_index(video_number),.stream_epoch(),.transport_busy(),
 .write_finish_owner(1'b1),.write_finish_toggle(finish_toggle),
 .display_buffer_index(presented_index),
 .scan_done(scan_done),.video_found(found),.display_valid(display_valid),
 .playback_paused(paused),.status(status),.write_addr_index(write_index),
 .read_addr_index(read_index),.write_req(write_req),.write_req_ack(ack),
 .write_en(write_en),.write_data(write_data),.sd_sec_read(sd_read),
 .sd_sec_read_addr(sd_addr),.sd_sec_read_data(sd_data),
 .sd_sec_read_data_valid(sd_valid),.sd_sec_read_end(sd_end));

function [7:0] card_byte;
 input integer address,offset;
 integer size,cluster,logical_sector,frame_number,next_cluster;
 reg [87:0] filename;
 reg [31:0] fat_value;
 begin
  card_byte=0;
  size=1229312; // header + two frames
  if(test_case>=10)size=2458112; // four frames, many missed deadlines
  if(test_case==4)size=614912; // truncated according to its two-frame header
  if(address==0)begin // unpartitioned FAT32 BPB
   case(offset)
    11:card_byte=0;12:card_byte=2;13:card_byte=64;
    14:card_byte=1;16:card_byte=1;36:card_byte=4;44:card_byte=2;
    510:card_byte=8'h55;511:card_byte=8'haa;default:card_byte=0;
   endcase
  end else if(address==5)begin
   filename="VIDEO_01VDO";
   if(test_case==2)filename="OTHER   BIN";
   if(offset<11)card_byte=filename[(10-offset)*8+:8];
   if(offset==11)card_byte=8'h20;
   if(offset==26)card_byte=10;
   if(offset>=28&&offset<=31)card_byte=(size>>((offset-28)*8));
   // A later non-video entry must not overwrite the selected file size.
   if(offset>=32&&offset<43)card_byte="X";
   if(offset==43)card_byte=8'h20;
   if(offset==60)card_byte=8'h7b;
   // Remaining directory entries are empty, with a zero size.
  end else if(address>=1&&address<=4)begin
   cluster=(address-1)*128+offset/4;
   if(test_case==1||test_case==11)next_cluster=cluster+3;else next_cluster=cluster+1;
   fat_value=next_cluster;
   if(test_case==5)fat_value=32'h0fffffff;
   card_byte=fat_value>>((offset%4)*8);
  end else if(address>=517)begin
   cluster=(address-5)/64+2;
   if(test_case==1||test_case==11)logical_sector=((cluster-10)/3)*64+(address-5)%64;
   else logical_sector=(cluster-10)*64+(address-5)%64;
   if(logical_sector==0)begin
    case(offset)
     0:card_byte=(test_case==3)?0:8'h56;
     1:card_byte=8'h44;2:card_byte=8'h4f;3:card_byte=8'h31;
     4:card_byte=8'h80;5:card_byte=2;6:card_byte=8'he0;7:card_byte=1;
     8:card_byte=4;12:card_byte=(test_case>=10)?4:2;default:card_byte=0;
    endcase
   end else begin
    frame_number=(logical_sector-1)/1200;
    if(frame_number%2==0)card_byte=(offset%2)?8'hf8:0;
    else card_byte=(offset%2)?8'h07:8'he0;
   end
  end
 end
endfunction

// Model complete 512-byte sectors, plus variable media/audio arbitration delay.
integer byte_i,selected_address;
initial begin
 wait(!rst);
 forever begin
  @(negedge clk);
  if(sd_read&&test_case!=6)begin
   selected_address=sd_addr;
   repeat(sd_sectors%7+1)@(negedge clk);
   if(dut.state==9&&ack)$fatal(1,"Frame read while write FIFO still reset");
   for(byte_i=0;byte_i<512;byte_i=byte_i+1)begin
    sd_data=card_byte(selected_address,byte_i);sd_valid=1;
    @(negedge clk);sd_valid=0;
    @(negedge clk);
   end
   sd_end=1;@(negedge clk);sd_end=0;
   sd_sectors=sd_sectors+1;
   @(negedge clk);
  end
 end
end

// Model memory-domain ACK held high until its delayed request synchronizer clears.
always @(negedge clk)begin
 if(!rst)begin
  // Mimic an independent HDMI refresh: pending selection is only applied
  // at vertical blank, long after the source completion event.
  refresh_phase=refresh_phase+1;
  if(refresh_phase==100)begin refresh_phase=0;presented_index=read_index;end
  case(ack_state)
   0:if(write_req)begin
    if(requests>0&&write_index==presented_index)$fatal(1,"Overwriting currently displayed buffer");
    requests=requests+1;expected_frame=dut.current_frame;
    frame_pixels=0;ack_delay=3;ack_state=1;end
   1:if(ack_delay==0)begin ack=1;ack_state=2;end else ack_delay=ack_delay-1;
   2:if(!write_req)begin ack_delay=8;ack_state=3;end
   3:if(ack_delay==0)begin ack=0;ack_state=0;end else ack_delay=ack_delay-1;
  endcase
  if(write_en)begin
   if(ack)$fatal(1,"Pixel written while FIFO clear is asserted");
   if(write_data!==((expected_frame%2==0)?32'hff000000:32'h00ff0000))
    $fatal(1,"RGB565/order mismatch request=%0d data=%h",requests,write_data);
   frame_pixels=frame_pixels+1;total_pixels=total_pixels+1;
   if(frame_pixels>307200)$fatal(1,"Too many pixels");
   if(frame_pixels==307200)begin
    completed=completed+1;
    if(test_case!=7)finish_toggle=~finish_toggle;
   end
  end
  if(display_valid&&(!previous_display||presented_index!=previous_index))begin
   if(frame_pixels!=307200)$fatal(1,"Displaying incomplete frame");
   shown=shown+1;last_frame=dut.current_frame;
  end
  previous_display=display_valid;previous_index=presented_index;
  if(test_case>=10&&display_valid&&!dut.first_file_frame&&!dut.epoch_commit&&
     !dut.next_pending&&!next_item&&!dut.restart_pending&&sync_hold)
   $fatal(1,"ordinary frame swap interrupted PCM");
 end
end

task press_pause;
 begin @(negedge clk);global_pause=~global_pause;repeat(25)@(negedge clk);end
endtask

initial begin
 if(!$value$plusargs("CASE=%d",test_case))test_case=0;
 if(test_case>=10)sample_period=50000;
 repeat(5)@(negedge clk);rst=0;start=1;
 case(test_case)
  0,1:begin
   wait(shown>=3); // first frame, next frame, then rewind
   if(status!=1||dut.file_size!=1229312||dut.frame_count!=2)
    $fatal(1,"Selected file metadata/status not preserved");
  end
  2:begin wait(scan_done);if(found||display_valid||write_req)$fatal(1,"Missing file must allow BMP fallback");end
  3,4:begin wait(status==4'ha);if(display_valid||requests)$fatal(1,"Invalid header/size accepted");end
  5:begin wait(status==4'hb);if(display_valid)$fatal(1,"Truncated FAT displayed");end
  6:begin wait(status==4'hf);end
  7:begin wait(status==4'hd);if(display_valid)$fatal(1,"Missing SDRAM completion displayed");end
  8:begin
   wait(shown==1);wait(requests==2);press_pause();if(!paused)$fatal(1,"Pause failed");
   wait(completed==2);repeat(300)@(negedge clk);
   if(shown!=1)$fatal(1,"Frame changed while paused");
   repeat(2500)@(negedge clk);
   if(shown!=1||requests!=2)$fatal(1,"Pause advanced media");
   press_pause();wait(shown==3);if(paused)$fatal(1,"Resume failed");
  end
  9:begin
   wait(shown==1);global_pause=1;enabled=0;
   wait(!sd_read&&!write_req&&!ack&&(dut.state==13||dut.state==16||dut.state==12));
   repeat(20)@(negedge clk);
   saved_frame=dut.current_frame;saved_sector=dut.next_file_sector;
   saved_phase=dut.frame_phase;saved_epoch=dut.stream_epoch;
   repeat(2300)@(negedge clk);
   if(status!=1||dut.current_frame!=saved_frame||dut.next_file_sector!=saved_sector||dut.frame_phase!=saved_phase)
    $fatal(1,"disabled video lost cursor/phase or timed out");
   enabled=1;repeat(50)@(negedge clk);
   if(dut.current_frame!=saved_frame||dut.next_file_sector!=saved_sector||dut.stream_epoch!=saved_epoch||dut.restart_pending)
    $fatal(1,"return to video restarted file");
   global_pause=0;wait(shown==3);
  end
  10,11:begin
   wait(shown==1);initial_epoch=dut.stream_epoch;
   wait(consumed>=25);@(negedge clk);global_pause=1;enabled=0;
   saved_phase=dut.frame_phase;saved_frame=consumed;
   repeat(4000)@(negedge clk);
   if(dut.frame_phase!=saved_phase||consumed!=saved_frame)
    $fatal(1,"slow-card mode/pause changed audio timeline");
   enabled=1;global_pause=0;
   // At least two complete audio/video timelines, under a card too slow
   // to deliver all four frames/sec. No per-frame audio holds are allowed.
   wait(consumed>=110);wait(shown>=5);@(posedge clk);#1;
   if(skipped==0)$fatal(1,"slow card never skipped overdue frames");
   if(dut.stream_epoch!=initial_epoch)$fatal(1,"natural wrap restarted WAV/subtitles");
   observed_debt=dut.frames_due;observed_phase=dut.frame_phase;
   if(observed_phase!=((consumed*4)%48))$fatal(1,"fractional audio timeline was lost");
   // current_frame is the next/current loader frame. Each successful
   // timed commit or skip consumes exactly one deadline, even across wrap.
   if(dut.current_frame!=((1+consumed/12-observed_debt)%4))
    $fatal(1,"video cursor diverged from consumed PCM timeline");
   if(observed_debt>3)$fatal(1,"unbounded video time debt=%0d",observed_debt);
   if(status!=1)$fatal(1,"catchup/FAT error=%h",status);
   $display("SYNC consumed=%0d skipped=%0d debt=%0d fractional=%0d",consumed,skipped,observed_debt,observed_phase);
  end
  12:begin
   wait(shown==1);initial_epoch=dut.stream_epoch;
   wait(dut.state==19);@(negedge clk);next_item=1;
   @(negedge clk);next_item=0;
   wait(dut.stream_epoch!=initial_epoch);wait(dut.state==13);
   if(video_number!=1||status!=1||dut.next_pending)
    $fatal(1,"next-file request while seeking failed to drain/commit");
   initial_epoch=dut.stream_epoch;wait(shown>=4);
   if(dut.stream_epoch!=initial_epoch)$fatal(1,"next pulse consumed more than once");
  end
 endcase
 $display("PASS CASE=%0d requests=%0d pixels=%0d shown=%0d status=%h",test_case,requests,total_pixels,shown,status);
 $finish;
end
initial begin #100000000;$display("watchdog CASE=%0d",test_case);$fatal(1,"Simulation watchdog");end
endmodule
