`timescale 1ns/1ps
module tb_audio_pause;
reg clk=0,rst=1,paused=0;
always #5 clk=~clk;
wire pop,bclk,lrck,dout,ack;
reg [31:0] sample_word=32'h12345678;
integer pops=0,edges=0,held_pops;
reg last_bclk=0;
hdmi_audio_pcm_i2s_64fs dut(.I_mclk(clk),.I_rst(rst),.I_pause(paused),.I_volume(8'd16),
 .O_pause_ack(ack),
 .I_fifo_data(sample_word),.I_fifo_empty(1'b0),.O_fifo_rd_en(pop),
 .O_i2s_BCLK(bclk),.O_i2s_LRCK(lrck),.O_i2s_DOUT(dout));
always @(negedge clk) begin
 if(pop)begin pops=pops+1;sample_word=sample_word+32'h00010001;end
 if(last_bclk!=bclk)edges=edges+1;
 last_bclk=bclk;
end
initial begin
 repeat(5)@(negedge clk);rst=0;
 wait(pops==3);@(posedge clk);paused=1;
 repeat(600)@(negedge clk);held_pops=pops;edges=0;
 if(!ack)$fatal(1,"Pause not acknowledged at stereo-pair boundary");
 repeat(1200)@(negedge clk);
 if(pops!=held_pops)$fatal(1,"PCM FIFO consumed while paused");
 if(edges!=1200)$fatal(1,"Paused I2S clock stopped");
 if(dut.sample_word!=0||dut.shift_reg!=0)$fatal(1,"Paused audio was not silent");
 @(posedge clk);paused=0;wait(pops==held_pops+2);
 if(ack)$fatal(1,"Stale pause acknowledgement after resume");
 $display("PASS audio pause: continuous clocks, silence, FIFO preservation and resume");$finish;
end
initial begin #100000;$fatal(1,"watchdog");end
endmodule
