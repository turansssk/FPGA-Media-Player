`timescale 1ns/1ps
// Includes the unchanged production HDMI I2S receiver so signed sample
// values are checked after actual serialization, not just at the multiplier.
module tb_runtime_volume;
reg clk=0,rxclk=0,rst=1,pause=0;
reg [7:0] volume=16;
reg [31:0] pcm=32'h7fff8000;
always #5 clk=~clk;
always #1 rxclk=~rxclk;
wire pop,bclk,lrck,dout,valid;
wire [23:0] left,right;
integer pops=0,g,i,held,checks=0;
reg signed [31:0] expected_left,expected_right;
hdmi_audio_pcm_i2s_64fs dut(.I_mclk(clk),.I_rst(rst),.I_pause(pause),.I_volume(volume),
 .O_pause_ack(),
 .I_fifo_data(pcm),.I_fifo_empty(1'b0),.O_fifo_rd_en(pop),
 .O_i2s_BCLK(bclk),.O_i2s_LRCK(lrck),.O_i2s_DOUT(dout));
I2S_receiver receiver(.I_clk(rxclk),.I_rst(rst),.I_i2s_BCLK(bclk),
 .I_i2s_LRCK(lrck),.I_i2s_DOUT(dout),.O_audio_valid(valid),
 .O_audio_left_data(left),.O_audio_right_data(right));
always @(negedge clk) if(pop) pops=pops+1;
task check_received;
 input integer gain;
 begin
  volume=gain;
  // Allow the synchronized gain and two complete stereo pairs to drain.
  repeat(4)begin @(posedge valid);@(negedge valid);end
  expected_left=$signed(pcm[31:16]);expected_left=expected_left*gain*16;
  expected_right=$signed(pcm[15:0]);expected_right=expected_right*gain*16;
  repeat(2)begin
   @(posedge valid);#1;
   if(left!==expected_left[23:0]||right!==expected_right[23:0])
    $fatal(1,"PCM gain=%0d got=%h/%h expected=%h/%h",gain,left,right,expected_left[23:0],expected_right[23:0]);
   checks=checks+1;@(negedge valid);
  end
 end
endtask
initial begin
 repeat(8)@(negedge clk);rst=0;
 for(g=0;g<=16;g=g+1)check_received(g);
 pcm=32'h80007fff;
 for(g=16;g>=0;g=g-1)check_received(g);
 pcm=32'h1234fedc;check_received(8);
 // Changing gain after left was accepted must not change this pair's right.
 wait(pop);@(negedge clk);volume=0;
 wait(lrck);#1;
 if(dut.volume_pair!==8 || dut.shift_reg[63:40]!==dut.scale_pcm(pcm[15:0],8))
  $fatal(1,"Left/right pair used different gains");
 check_received(0);held=pops;
 repeat(1200)@(negedge clk);
 if(pops<=held||dout!==0)$fatal(1,"Mute stopped playback/FIFO or emitted nonzero PCM");
 pause=1;repeat(600)@(negedge clk);held=pops;
 volume=16;repeat(1200)@(negedge clk);
 if(pops!=held||dout!==0)$fatal(1,"Gain change resumed paused playback");
 pause=0;check_received(16);
 $display("PASS volume: %0d serialized stereo checks, signed rails, unity/mute, pair gain, pause/FIFO preservation",checks);$finish;
end
initial begin #1500000;$fatal(1,"volume watchdog");end
endmodule
