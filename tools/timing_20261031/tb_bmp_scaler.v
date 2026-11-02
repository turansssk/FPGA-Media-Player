`timescale 1ns/1ps

module tb_bmp_scaler;
  reg clk=0;
  reg rst=1;
  reg start_scan=0;
  reg load_start=0;
  reg write_req_ack=0;
  reg sd_valid=0;
  reg sd_end=0;
  reg [7:0] sd_data=0;
  wire write_req, sd_read, bmp_wr, load_done;
  wire [31:0] sd_addr;
  wire [23:0] bmp_data;
  wire scan_done;
  wire [3:0] image_count, status;
  wire [95:0] image_sector, image_cluster, image_size, image_offset;

  integer source_width;
  integer source_height;
  integer source_row_bytes;
  integer expected_width;
  integer expected_height;
  integer expected_x_offset;
  integer expected_y_offset;
  integer pixel_count;
  integer errors;
  integer cases_run;
  integer fifo_accepted_pixels;
  integer ack_hold_cycles;
  reg ack_active=0;
  reg actual_file_mode=0;
  reg [7:0] actual_file [0:1999999];
  integer actual_size, actual_fd;
  reg [1023:0] actual_path;

  integer sector_byte;
  reg [31:0] active_sector;
  reg sector_active;
  reg end_pending;
  reg wait_for_read_low;

  always #10 clk=~clk;

  bmp_read_fat32 #(
    .MAX_BMP_NUM(3),
    .TIMEOUT_CYCLES(32'd100000000),
    .MAX_SOURCE_WIDTH(2048)
  ) dut (
    .clk(clk),.rst(rst),.start_scan(start_scan),.boot_sector(0),.target_count(4'd3),
    .scan_done(scan_done),.image_count(image_count),.image_sector(image_sector),
    .image_cluster(image_cluster),.image_size(image_size),.image_offset(image_offset),
    .load_start(load_start),.load_index(4'd0),.load_done(load_done),.status(status),
    .write_req(write_req),.write_req_ack(write_req_ack),
    .sd_sec_read(sd_read),.sd_sec_read_addr(sd_addr),
    .sd_sec_read_data(sd_data),.sd_sec_read_data_valid(sd_valid),.sd_sec_read_end(sd_end),
    .bmp_data_wr_en(bmp_wr),.bmp_data(bmp_data),
    .bmp_width(16'd640),.bmp_height(16'd480)
  );

  function [7:0] sector_data;
    input [31:0] sector;
    input integer byte_number;
    integer file_offset;
    integer payload_offset;
    integer source_row;
    integer row_position;
    integer source_column;
    integer channel;
    begin
      file_offset=((sector-32'd100)*512)+byte_number;
      sector_data=0;
      if(actual_file_mode) begin
        if(file_offset>=0 && file_offset<actual_size)
          sector_data=actual_file[file_offset];
      end else if(file_offset>=54) begin
        payload_offset=file_offset-54;
        source_row=payload_offset/source_row_bytes;
        row_position=payload_offset%source_row_bytes;
        if((source_row<source_height) && (row_position<source_width*3)) begin
          source_column=row_position/3;
          channel=row_position%3;
          case(channel)
            0: sector_data=source_column[7:0];
            1: sector_data=source_row[7:0];
            default: sector_data=(source_column+source_row)&8'hff;
          endcase
        end
      end
    end
  endfunction

  // Sector-level SD model.  sd_end is deliberately a cycle after byte 511,
  // matching the real sd_card_sec_read_write interface.
  always @(posedge clk) begin
    sd_valid<=0;
    sd_end<=0;
    if(rst) begin
      sector_active<=0;
      end_pending<=0;
      wait_for_read_low<=0;
      sector_byte<=0;
    end else if(end_pending) begin
      end_pending<=0;
      sd_end<=1;
      wait_for_read_low<=1;
    end else if(sector_active) begin
      sd_valid<=1;
      sd_data<=sector_data(active_sector,sector_byte);
      if(sector_byte==511) begin
        sector_active<=0;
        end_pending<=1;
      end else begin
        sector_byte<=sector_byte+1;
      end
    end else if(wait_for_read_low) begin
      if(!sd_read) wait_for_read_low<=0;
    end else if(sd_read) begin
      active_sector<=sd_addr;
      sector_byte<=0;
      sector_active<=1;
    end
  end

  // The real writer keeps its FIFO in reset while ACK is high, including
  // the return synchronizer delay after the reader drops write_req.
  always @(posedge clk) begin
    if(rst) begin
      write_req_ack<=0;
      ack_active<=0;
      ack_hold_cycles<=0;
    end else if(!ack_active && write_req) begin
      ack_active<=1;
      write_req_ack<=1;
      ack_hold_cycles<=12;
    end else if(ack_active) begin
      if(ack_hold_cycles!=0) ack_hold_cycles<=ack_hold_cycles-1;
      else if(!write_req) begin
        write_req_ack<=0;
        ack_active<=0;
      end
    end
  end

  task check_output_pixel;
    integer x;
    integer y;
    integer source_x_expected;
    integer source_y_expected;
    integer actual_offset;
    reg [23:0] expected_pixel;
    begin
      x=pixel_count%640;
      y=pixel_count/640;
      if((x<expected_x_offset) || (x>=expected_x_offset+expected_width) ||
         (y<expected_y_offset) || (y>=expected_y_offset+expected_height)) begin
        expected_pixel=24'h000000;
      end else begin
        source_x_expected=((x-expected_x_offset)*source_width)/expected_width;
        source_y_expected=((y-expected_y_offset)*source_height)/expected_height;
        expected_pixel[23:16]=(source_x_expected+source_y_expected)&8'hff;
        expected_pixel[15:8]=source_y_expected&8'hff;
        expected_pixel[7:0]=source_x_expected&8'hff;
        if(actual_file_mode) begin
          actual_offset=54+source_y_expected*source_row_bytes+source_x_expected*3;
          expected_pixel={actual_file[actual_offset+2],actual_file[actual_offset+1],
                          actual_file[actual_offset]};
        end
      end
      if(bmp_data!==expected_pixel) begin
        if(errors<12)
          $display("PIXEL ERROR case=%0d x=%0d y=%0d got=%h expected=%h",
                   cases_run,x,y,bmp_data,expected_pixel);
        errors=errors+1;
      end
      pixel_count=pixel_count+1;
    end
  endtask

  always @(posedge clk) begin
    if(bmp_wr) begin
      check_output_pixel;
      if(!write_req_ack) fifo_accepted_pixels=fifo_accepted_pixels+1;
    end
  end

  task run_scale_case;
    input integer test_width;
    input integer test_height;
    begin
      source_width=test_width;
      source_height=test_height;
      source_row_bytes=((test_width*3)+3)&32'hfffffffc;
      if(test_width*480>=test_height*640) begin
        expected_width=640;
        expected_height=(test_height*640)/test_width;
        if(expected_height==0) expected_height=1;
      end else begin
        expected_width=(test_width*480)/test_height;
        if(expected_width==0) expected_width=1;
        expected_height=480;
      end
      expected_x_offset=(640-expected_width)/2;
      expected_y_offset=(480-expected_height)/2;
      pixel_count=0;
      fifo_accepted_pixels=0;
      cases_run=cases_run+1;

      // Start immediately after the header check.  FAT/header parsing is
      // covered by the existing BMP control test; this test focuses on the
      // new scale planning, row reads and pixel mapping.
      @(negedge clk);
      dut.bh_w=test_width;
      dut.bh_h=test_height;
      dut.bh_off=54;
      dut.row_bytes=source_row_bytes;
      dut.image_sector[31:0]=32'd100;
      dut.active_index=0;
      dut.scale_width_limited=(test_width*480>=test_height*640);
      dut.div_quotient=0;
      if(test_width*480>=test_height*640) begin
        dut.div_work=test_height*640;
        dut.div_denominator=test_width;
      end else begin
        dut.div_work=test_width*480;
        dut.div_denominator=test_height;
      end
      if(actual_file_mode) begin
        dut.image_size[31:0]=actual_size;
        dut.sd_sec_read_addr=100;
        dut.cnt=0;
        dut.hdr_eval_pending=0;
        dut.st=5'd5;
      end else dut.st=5'd6;

      wait(load_done);
      @(posedge clk);
      if(pixel_count!=640*480) begin
        $display("COUNT ERROR case=%0d got=%0d expected=%0d",cases_run,pixel_count,640*480);
        errors=errors+1;
      end
      if(status!=0) begin
        $display("STATUS ERROR case=%0d status=%h",cases_run,status);
        errors=errors+1;
      end
      if(fifo_accepted_pixels!=640*480) begin
        $display("FIFO RESET LOSS case=%0d accepted=%0d expected=%0d",
                 cases_run,fifo_accepted_pixels,640*480);
        errors=errors+1;
      end
      $display("CASE %0d PASS geometry %0dx%0d -> %0dx%0d offsets %0d,%0d",
               cases_run,test_width,test_height,expected_width,expected_height,
               expected_x_offset,expected_y_offset);
      repeat(4) @(posedge clk);
    end
  endtask

  task run_actual_file;
    input [1023:0] path;
    integer w,h;
    begin
      actual_fd=$fopen(path,"rb");
      if(actual_fd==0) $fatal(1,"Cannot open BMP %0s",path);
      actual_size=$fread(actual_file,actual_fd);
      $fclose(actual_fd);
      w={actual_file[21],actual_file[20],actual_file[19],actual_file[18]};
      h={actual_file[25],actual_file[24],actual_file[23],actual_file[22]};
      $display("ACTUAL BMP %0s: %0dx%0d, %0d bytes",path,w,h,actual_size);
      run_scale_case(w,h);
    end
  endtask

  initial begin
    errors=0;
    cases_run=0;
    repeat(5) @(posedge clk);
    rst=0;
    repeat(3) @(posedge clk);

    if($test$plusargs("cardfiles")) begin
      actual_file_mode=1;
      run_actual_file("D:/6.bmp");
      run_actual_file("D:/7.bmp");
      run_actual_file("D:/8.bmp");
      run_actual_file("D:/9.bmp");
      run_actual_file("D:/10.bmp");
    end else begin
      run_scale_case(320,240);
      run_scale_case(800,600);
      run_scale_case(640,360);
      run_scale_case(360,480);
      run_scale_case(854,480);
      run_scale_case(1280,720);
      run_scale_case(1920,1080);
      run_scale_case(2048,300);
    end

    if(errors==0) $display("PASS: BMP nearest-neighbour scaling regression");
    else $fatal(1,"FAIL: %0d BMP scaling errors",errors);
    $finish;
  end

  initial begin
    #500000000;
    $fatal(1,"FAIL: BMP scaler timeout");
  end
endmodule
