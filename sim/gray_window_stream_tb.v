`timescale 1ns/1ps
// 行内空拍、场同步重定位和中途复位；逐项核对9个窗口像素。
module gray_window_stream_tb;
    localparam W=8,H=6,L=3;
    reg clk=0,rst_n=0;
    reg [7:0] pixel=0;
    reg v=0,hs=0,vs=0;
    wire [7:0] p[0:8];
    wire ov,ow,oh,of;
    reg [7:0] frame_mem[0:W*H-1];
    reg [7:0] expected[0:26]; // 3拍×9像素
    reg [3:0] ctrl[0:2];
    integer errors=0,checks=0,windows=0,x=0,y=0,i,j,k,xx,yy,frame;
    always #5 clk=~clk;
    gray_3x3_window #(.IMAGE_WIDTH(W),.ADDR_WIDTH(3)) dut(
        .clk(clk),.rst_n(rst_n),.in_pixel(pixel),.in_valid(v),
        .in_hsync(hs),.in_vsync(vs),
        .out_p11(p[0]),.out_p12(p[1]),.out_p13(p[2]),.out_p21(p[3]),.out_p22(p[4]),.out_p23(p[5]),.out_p31(p[6]),.out_p32(p[7]),.out_p33(p[8]),
        .out_valid(ov),.out_window_valid(ow),.out_hsync(oh),.out_vsync(of));
    always @(posedge clk) begin
        if(!rst_n) begin
            x=0;y=0;
            for(k=0;k<27;k=k+1) expected[k]=0;
            for(k=0;k<3;k=k+1) ctrl[k]=0;
        end else begin
            for(k=26;k>=9;k=k-1) expected[k]=expected[k-9];
            for(k=2;k>0;k=k-1) ctrl[k]=ctrl[k-1];
            ctrl[0]={vs,hs,1'b0,v};
            if(!vs) begin x=0;y=0;end
            else if(v) begin
                frame_mem[y*W+x]=pixel;
                expected[8]=pixel;
                if(x>=2 && y>=2) begin
                    ctrl[0][1]=1;
                    for(i=0;i<3;i=i+1)
                        for(j=0;j<3;j=j+1) expected[i*3+j]=frame_mem[(y-2+i)*W+x-2+j];
                end
                if(x==W-1) begin x=0;y=y+1;end else x=x+1;
            end
        end
        #1;checks=checks+1;
        if({of,oh,ow,ov}!==ctrl[2]) errors=errors+1;
        if(ow) begin
            windows=windows+1;
            for(k=0;k<9;k=k+1)
                if(p[k]!==expected[18+k]) begin
                    if(errors<8) $display("ERROR: stream window p%0d got=%0d expected=%0d",k,p[k],expected[18+k]);
                    errors=errors+1;
                end
        end
        if(ov && p[8]!==expected[26]) errors=errors+1;
    end
    task send;
        input integer value;
        input valid,sync;
        begin @(negedge clk);#1;pixel=value;v=valid;hs=~hs;vs=sync;end
    endtask
    initial begin
        repeat(4) @(negedge clk);rst_n=1;
        for(frame=0;frame<3;frame=frame+1) begin
            repeat(5) send(0,0,0);
            for(yy=0;yy<H;yy=yy+1) begin
                for(xx=0;xx<W;xx=xx+1) begin
                    send(frame*43+yy*W+xx,1,1);
                    if(xx==3) repeat(2) send(0,0,1);
                end
                repeat(3) send(0,0,1);
            end
            repeat(5) send(0,0,1);
            // 提前终止下一帧，随后由场同步重新归零。
            repeat(4) send(0,0,0);
            send(123,1,1);send(234,1,1);send(56,1,1);
            repeat(5) send(0,0,1);
            if(frame==1) begin
                #2;rst_n=0;#1;
                if({p[0],p[1],p[2],p[3],p[4],p[5],p[6],p[7],p[8],ov,ow,oh,of}!==0) errors=errors+1;
                repeat(3) @(negedge clk);rst_n=1;
            end
        end
        repeat(5) send(0,0,1);
        if(windows!=72) errors=errors+1;
        $display("Window stream checks=%0d full_windows=%0d errors=%0d",checks,windows,errors);
        if(errors==0) $display("TEST PASSED: gray_window_stream");
        else $display("TEST FAILED: gray_window_stream, %0d error(s)",errors);
        $finish;
    end
    initial begin #1000000;errors=errors+1;$display("TEST FAILED: gray_window_stream timeout");$finish;end
endmodule
