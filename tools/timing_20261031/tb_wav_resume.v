`timescale 1ns/1ps
// Full mocked FAT32 transactions: all six names, both PCM channel layouts,
// non-sector-aligned data offset and seek through fragmented cluster links.
module tb_wav_resume;
reg clk=0,rst=1,source=0,paused=0,valid=0,done=0;
reg [1:0] index=0;
reg [31:0] resume=0;
reg [7:0] data=0;
wire req,we,ready,playing,sub_we,sub_ready;
wire [31:0] addr,pcm,total;
wire [12:0] sub_addr;
wire [7:0] sub_data;
wire [5:0] lines;
wire [3:0] status,sub_status;
integer channels=2,offset=44,expected=0,received=0,transactions=0;
integer byte_i,selected,scenario,held_received;
reg check_samples=0,busy=0;
always #5 clk=~clk;
wav_read_fat32 #(.TIMEOUT_CYCLES(50000)) dut(
 .clk(clk),.rst(rst),.sd_init_done(1'b1),.audio_source_video(source),.music_index(index),
 .next_item(1'b0),.pause_playback(paused),.resume_sample(resume),
 .sd_sec_read(req),.sd_sec_read_addr(addr),.sd_sec_read_data(data),
 .sd_sec_read_data_valid(valid),.sd_sec_read_end(done),
 .fifo_wr_en(we),.fifo_wr_data(pcm),.fifo_wrusedw(9'd0),
 .audio_ready(ready),.audio_playing(playing),.status(status),.audio_total_samples(total),
 .subtitle_wr_en(sub_we),.subtitle_wr_addr(sub_addr),.subtitle_wr_data(sub_data),
 .subtitle_ready(sub_ready),.subtitle_line_count(lines),.subtitle_status(sub_status));
function [7:0] card;
 input integer a,b;
 integer entry,field,cluster,logical_sector,pos,frame,part,value,size;
 reg [87:0] name;
 begin
 card=0;size=offset+2048*channels*2;
 if(a==0)begin
  case(b)11:card=0;12:card=2;13:card=2;14:card=1;16:card=1;36:card=1;44:card=2;endcase
 end else if(a==2||a==3)begin
  entry=(a-2)*16+b/32;field=b%32;
  if(entry<12)begin
   if(entry<6)name="MUSIC_01WAV";else name="VIDEO_01WAV";
   name[31:24]="1"+(entry%6)/2;
   if(entry%2)name[23:0]="SUB";
   cluster=(entry%2)?60:10;
   if(field<11)card=name[(10-field)*8+:8];
   if(field==11)card=8'h20;
   if(field==26)card=cluster;
   if(field>=28&&field<=31)card=((entry%2)?512:size)>>((field-28)*8);
  end
 end else if(a==1)begin
  cluster=b/4;value=cluster+3;
  card=value>>((b%4)*8);
 end else if(a==118)begin // cluster60, valid one-sector SUB1
  case(b)0:card="S";1:card="U";2:card="B";3:card="1";
   4:card=1;5:card=1;6:card=20;8:card=8'h80;9:card=8'hbb;endcase
 end else if(a>=18)begin
  cluster=(a-2)/2+2;logical_sector=((cluster-10)/3)*2+(a-2)%2;
  pos=logical_sector*512+b;
  if(pos<offset)begin
   case(pos)
    0:card="R";1:card="I";2:card="F";3:card="F";
    8:card="W";9:card="A";10:card="V";11:card="E";
    12:card="f";13:card="m";14:card="t";15:card=" ";16:card=16;
    20:card=1;22:card=channels;24:card=8'h80;25:card=8'hbb;
    28:card=(48000*channels*2)&255;29:card=(48000*channels*2)>>8;
    30:card=(48000*channels*2)>>16;32:card=channels*2;34:card=16;
   endcase
   if(offset>44)begin
    if(pos==36)card="J";if(pos==37)card="U";if(pos==38)card="N";if(pos==39)card="K";
    if(pos>=40&&pos<=43)card=(offset-52)>>((pos-40)*8);
   end
   if(pos==offset-8)card="d";if(pos==offset-7)card="a";
   if(pos==offset-6)card="t";if(pos==offset-5)card="a";
   if(pos>=offset-4)card=(2048*channels*2)>>((pos-offset+4)*8);
  end else begin
   frame=(pos-offset)/(channels*2);part=(pos-offset)%(channels*2);
   value=frame+((channels==2&&part>=2)?1000:0);
   card=value>>((part%2)*8);
  end
 end
 end
endfunction
initial begin
 forever begin
  @(negedge clk);
  if(!rst&&req)begin
   busy=1;selected=addr;transactions=transactions+1;
   for(byte_i=0;byte_i<512;byte_i=byte_i+1)begin
    data=card(selected,byte_i);valid=1;@(negedge clk);valid=0;@(negedge clk);
   end
   done=1;@(negedge clk);done=0;busy=0;repeat(2)@(negedge clk);
  end
 end
end
always @(negedge clk)begin
 if(check_samples&&we)begin
  if(pcm[31:16]!==expected[15:0] ||
     pcm[15:0]!==((channels==1)?expected[15:0]:(expected+16'd1000)))
   $fatal(1,"PCM position mismatch scenario=%0d sample=%0d data=%h",scenario,expected,pcm);
  expected=(expected+1)%2048;received=received+1;
 end
 if(!rst&&status>=2)$fatal(1,"unexpected WAV error %h scenario=%0d",status,scenario);
end
initial begin
 for(scenario=0;scenario<6;scenario=scenario+1)begin
  rst=1;check_samples=0;repeat(5)@(negedge clk);
  source=(scenario>=3);index=scenario%3;channels=(scenario%2)?1:2;
  offset=(scenario%2)?600:44;resume=(scenario==0)?0:((scenario==5)?1700:300);
  expected=resume;received=0;paused=0;check_samples=1;rst=0;
  wait(received>=100);paused=1;
  wait(!busy&&!req&&dut.state==6);repeat(10)@(negedge clk);
  if(!ready||!sub_ready||total!=2048||sub_status!=1)$fatal(1,"WAV/SUB metadata");
  held_received=received;repeat(50)@(negedge clk);
  if(received!=held_received)$fatal(1,"paused transport continued");
  paused=0;wait(received>=held_received+50);paused=1;
  wait(!busy&&!req&&dut.state==6);repeat(10)@(negedge clk);
 end
 $display("PASS all 6 WAV/SUB selections, PCM mono/stereo, offset44/600, fragmented seek and pause continuity");$finish;
end
initial begin #10000000;$fatal(1,"watchdog");end
endmodule
