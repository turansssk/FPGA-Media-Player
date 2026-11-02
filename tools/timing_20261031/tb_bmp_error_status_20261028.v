`timescale 1ns/1ps
// Separate the read-only FAT diagnostic from the multiplexed display number.
module tb_bmp_error_status_20261028;
reg clk=0,rst=1,sd=1;
wire [3:0] state_code,error_status;
integer code;
always #5 clk=~clk;
sd_card_single_bmp #(.CLK_FREQ_HZ(100),.MAX_BMP_NUM(10)) dut(
 .clk(clk),.rst(rst),.bmp_width(16'd640),.bmp_height(16'd480),
 .playback_enable(1'b0),.pause_playback(1'b0),.next_item(1'b0),
 .display_buffer_index(2'd0),.write_finish_toggle(1'b0),.write_finish_owner(1'b0),
 .display_valid(),.playback_paused(),.transport_busy(),.state_code(state_code),
 .error_status(error_status),.write_addr_index(),.read_addr_index(),
 .write_req(),.write_req_ack(1'b0),.write_en(),.write_data(),.sd_init_done(sd),
 .sd_sec_read(),.sd_sec_read_addr(),.sd_sec_read_data(8'd0),
 .sd_sec_read_data_valid(1'b0),.sd_sec_read_end(1'b0));
initial begin
 repeat(5)@(negedge clk);rst=0;
 force dut.display_valid=1;force dut.current_image=9;force dut.fat_status=0;#1;
 if(state_code!=10||error_status!=0)$fatal(1,"IMAGE10 mistaken for format error");
 for(code=10;code<=15;code=code+1)begin
  force dut.fat_status=code;#1;
  if(error_status!==code[3:0]||state_code!==code[3:0])$fatal(1,"raw FAT error lost");
 end
 force dut.fat_status=0;sd=0;force dut.init_wait=199;#1;
 if(error_status!=0)$fatal(1,"early TF init failure");
 force dut.init_wait=200;#1;if(error_status!=13)$fatal(1,"TF init timeout lost");
 sd=1;#1;if(error_status!=0)$fatal(1,"stale init error");
 $display("PASS BMP diagnostic separates IMAGE10, format/FAT/read errors and TF init timeout");$finish;
end
endmodule
