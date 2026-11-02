`timescale 1ns/1ps
module tb_four_state_keys;
reg clk=0,rst=1,k1=1,k2=1,k3=1,k4=1,can_switch=1;
always #5 clk=~clk;
wire mode,requested,pending,pp,vp,pn,vn,mn,reset,bui,vui;
wire [1:0] music;
wire [2:0] state;
wire [7:0] bright,volume;
wire info,clean;
integer pictures=0,videos=0,songs=0,resets=0,n,held;
key_function_control #(.CLK_FREQ_HZ(1000)) dut(
 .clk(clk),.rst(rst),.key1(k1),.key2(k2),.key3(k3),.key4(k4),.can_switch(can_switch),
 .video_mode(mode),.requested_video_mode(requested),.switch_pending(pending),
 .picture_paused(pp),.video_paused(vp),.picture_next(pn),.video_next(vn),.music_next(mn),
 .music_index(music),.function_state(state),.brightness_level(bright),.brightness_ui(bui),
 .volume_level(volume),.volume_ui(vui),.system_info_ui(info),.minimal_osd(clean),.soft_reset(reset));
always @(negedge clk)begin
 if(pn)pictures=pictures+1;if(vn)videos=videos+1;if(mn)songs=songs+1;if(reset)resets=resets+1;
 if((pn&&vn)||(pn&&mn)||(vn&&mn))$fatal(1,"duplicate media events");
end
task ticks;input integer t;begin repeat(t)@(negedge clk);end endtask
task down;input integer key;begin case(key)1:k2=0;2:k3=0;3:k4=0;4:k1=0;endcase end endtask
task up;begin k1=1;k2=1;k3=1;k4=1;ticks(30);end endtask
task tap;input integer key;begin down(key);ticks(35);up;end endtask
task longpress;input integer key;begin down(key);ticks(900);up;end endtask
initial begin
 ticks(5);rst=0;ticks(10);
 if(state!=1||mode||music||pp||vp)$fatal(1,"default state");
 // Bounce shorter than debounce is ignored.
 repeat(4)begin k4=0;ticks(3);k4=1;ticks(3);end ticks(30);
 if(pictures||songs)$fatal(1,"bounce generated event");
 down(3);ticks(40);if(pictures)$fatal(1,"short emitted before release");up;
 if(pictures!=1)$fatal(1,"short picture");
 longpress(3);if(songs!=1||music!=1||pictures!=1)$fatal(1,"long song also emitted short");
 down(3);ticks(3000);if(songs!=2)$fatal(1,"long repeated");up;
 longpress(3);if(music!=0||songs!=3)$fatal(1,"music wrap");
 tap(1);if(!pp||vp)$fatal(1,"picture pause");
 can_switch=0;tap(2);if(!pending||mode)$fatal(1,"unsafe mode commit");
 can_switch=1;ticks(5);if(!mode||!pp)$fatal(1,"mode switch lost saved pause");
 tap(3);longpress(3);if(videos!=1||pictures!=1||songs!=3)$fatal(1,"video short/long mapping");
 tap(1);if(!vp||!pp)$fatal(1,"independent pause");
 tap(2);if(mode||!pp||!vp)$fatal(1,"return lost pause");
 longpress(4);if(state!=4)$fatal(1,"reverse wrap");
 down(4);ticks(3000);if(state!=3)$fatal(1,"KEY4 long repeated");up;
 if(state!=3)$fatal(1,"KEY4 long release generated short");
 tap(4);tap(4);if(state!=1)$fatal(1,"forward wrap");
 tap(4);if(state!=2)$fatal(1,"brightness state");
 tap(2);if(bright!=16)$fatal(1,"closed UI changed value");
 tap(3);if(!bui)$fatal(1,"brightness UI");
 down(2);ticks(40);if(bright!=15)$fatal(1,"initial adjust");
 ticks(550);if(bright!=15)$fatal(1,"repeat started too early");
 ticks(65);if(bright!=14)$fatal(1,"first repeat");
 ticks(150);if(bright!=13)$fatal(1,"repeat interval");up;
 held=bright;ticks(500);if(bright!=held)$fatal(1,"repeat after release");
 down(2);ticks(5000);up;if(bright!=0)$fatal(1,"lower clamp");
 down(1);ticks(5000);up;if(bright!=16)$fatal(1,"upper clamp");
 // A key held across a state change must never control the new state.
 down(2);ticks(50);k1=0;ticks(40);k1=1;ticks(40);
 if(state!=3||bui||vui)$fatal(1,"state transition UI");
 ticks(1000);if(volume!=16)$fatal(1,"held key leaked across state");up;
 tap(3);down(2);ticks(1000);up;if(volume>=15)$fatal(1,"volume repeat");
 tap(4);if(state!=4||vui)$fatal(1,"system state");
 held=pictures+videos+songs;tap(2);tap(3);
 if(!info||!clean||held!=pictures+videos+songs||resets)$fatal(1,"system keys affected media");
 longpress(2);longpress(3);
 if(!info||!clean)$fatal(1,"system long hold repeated");
 tap(4);if(state!=1||info||!clean)$fatal(1,"info close/clean retention");
 longpress(4);if(state!=4||!clean)$fatal(1,"system return");
 tap(2);tap(3);if(!info||clean)$fatal(1,"system toggles");
 tap(1);ticks(20);
 if(resets!=1||state!=1||mode||pp||vp||music||bright!=16||volume!=16||info||clean)
  $fatal(1,"initialization");
 $display("PASS four-state gestures, bounce, repeat, clamps, pause retention and reset");$finish;
end
initial begin #1000000;$fatal(1,"watchdog");end
endmodule
