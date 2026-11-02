`timescale 1ns/1ps
module tb_bmp_directory;
reg clk=0;always #10 clk=~clk;
reg rst=1,valid=0,sec_end=0;
reg [7:0] data=0;
wire done;wire [3:0] count,status;
wire [319:0] clusters,sectors,sizes,offsets;
reg [7:0] bytes[0:511];
integer i,j,slot,id,gap,pass;
bmp_read_fat32 #(.MAX_BMP_NUM(10),.TIMEOUT_CYCLES(10000)) dut(
 .clk(clk),.rst(rst),.start_scan(1'b0),.boot_sector(32'd0),.target_count(4'd10),
 .scan_done(done),.image_count(count),.image_sector(sectors),.image_cluster(clusters),
 .image_size(sizes),.image_offset(offsets),.load_start(1'b0),.load_index(4'd0),
 .load_done(),.status(status),.write_req(),.write_req_ack(1'b0),
 .sd_sec_read(),.sd_sec_read_addr(),.sd_sec_read_data(data),
 .sd_sec_read_data_valid(valid),.sd_sec_read_end(sec_end),
 .bmp_data_wr_en(),.bmp_data(),.bmp_width(16'd640),.bmp_height(16'd480));
task put32;
 input integer addr;input [31:0] value;
 begin bytes[addr]=value[7:0];bytes[addr+1]=value[15:8];
 bytes[addr+2]=value[23:16];bytes[addr+3]=value[31:24];end
endtask
task entry;
 input integer n,number,cluster,size;input lower;input [7:0] attr;
 integer k;
 begin
 for(k=0;k<11;k=k+1)bytes[n*32+k]=8'h20;
 if(number==10)begin bytes[n*32]="1";bytes[n*32+1]="0";end
 else bytes[n*32]="0"+number;
 bytes[n*32+8]=lower?"b":"B";bytes[n*32+9]=lower?"m":"M";bytes[n*32+10]=lower?"p":"P";
 bytes[n*32+11]=attr;
 bytes[n*32+20]=cluster>>16;bytes[n*32+21]=cluster>>24;
 bytes[n*32+26]=cluster;bytes[n*32+27]=cluster>>8;
 put32(n*32+28,size);
 end
endtask
initial begin
 for(i=0;i<512;i=i+1)bytes[i]=0;
 // 1.BMP then 10.BMP, then 2..9: all ten indices, with mixed case.
 entry(0,1,101,400001,0,8'h20);
 entry(1,10,110,400010,1,8'h20);
 for(i=2;i<10;i=i+1)entry(i,i,100+i,400000+i,i%2,8'h20);
 entry(10,1,999,99,0,8'h20); // duplicate must retain first entry
 entry(11,2,998,98,0,8'h0f); // LFN must never be accepted
 entry(12,0,997,97,0,8'h20);
 entry(13,3,996,96,0,8'h20);bytes[13*32+2]="X";
 entry(14,4,995,95,0,8'h20);bytes[14*32+10]="G";
 entry(15,10,994,94,0,8'h20);
 for(pass=0;pass<2;pass=pass+1)begin
  @(negedge clk);rst=1;valid=0;sec_end=0;
  repeat(3)@(negedge clk);
  rst=0;dut.st=3;dut.cnt=0;dut.data_base=1000;
  dut.sectors_per_cluster=8;dut.dir_sector_no=0;
  for(j=0;j<512;j=j+1)begin
   if(pass)begin
    valid=0;gap=(j*7)%4;repeat(gap)@(negedge clk);
   end
   data=bytes[j];valid=1;sec_end=(j==511);
   @(negedge clk);
  end
  valid=0;sec_end=0;
  repeat(3)@(negedge clk);
  if(!done || count!==10 || status!==0)$fatal(1,"scan/count/status %b %d %h",done,count,status);
  for(slot=0;slot<10;slot=slot+1)begin
   id=slot+1;
   if(clusters[slot*32+:32]!==100+id)$fatal(1,"cluster slot %d",slot);
   if(sectors[slot*32+:32]!==1000+(100+id-2)*8)$fatal(1,"sector slot %d",slot);
   if(sizes[slot*32+:32]!==400000+id)$fatal(1,"size slot %d",slot);
   if(offsets[slot*32+:32]!==54)$fatal(1,"offset slot %d",slot);
  end
 end
 $display("PASS BMP directory: 1..10, mixed case, duplicates, LFN, invalid names, dense/sparse bytes, final-byte end");
 $finish;
end
initial begin #1000000;$fatal(1,"timeout");end
endmodule
