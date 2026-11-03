`timescale 1ns/1ps
module median_3x3_tb;
    reg clk=0,rst_n=0;
    reg [7:0] p[0:8];
    reg v=0,w=0,h=0,f=0;
    wire [7:0] pixel; wire ov,ow,oh,of;
    reg [7:0] ep[0:2]; reg [3:0] ec[0:2];
    integer values[0:8];
    integer i,j,k,n,temp,seed,errors=0,checks=0;
    always #5 clk=~clk;
    median_3x3 dut(.clk(clk),.rst_n(rst_n),
        .in_p11(p[0]),.in_p12(p[1]),.in_p13(p[2]),
        .in_p21(p[3]),.in_p22(p[4]),.in_p23(p[5]),
        .in_p31(p[6]),.in_p32(p[7]),.in_p33(p[8]),
        .in_valid(v),.in_window_valid(w),.in_hsync(h),.in_vsync(f),
        .out_pixel(pixel),.out_valid(ov),.out_window_valid(ow),
        .out_hsync(oh),.out_vsync(of));
    always @(posedge clk) begin
        if(!rst_n) begin
            for(k=0;k<3;k=k+1) begin ep[k]=0;ec[k]=0;end
        end else begin
            for(k=2;k>0;k=k-1) begin ep[k]=ep[k-1];ec[k]=ec[k-1];end
            for(i=0;i<9;i=i+1) values[i]=p[i];
            for(i=0;i<8;i=i+1) for(j=i+1;j<9;j=j+1)
                if(values[i]>values[j]) begin temp=values[i];values[i]=values[j];values[j]=temp;end
            ep[0]=(v&&w)?values[4]:0;
            ec[0]={f,h,v&&w,v};
        end
        #1; checks=checks+1;
        if(pixel!==ep[2] || {of,oh,ow,ov}!==ec[2]) begin
            if(errors<8) $display("ERROR median pixel=%0d/%0d ctrl=%b/%b",pixel,ep[2],{of,oh,ow,ov},ec[2]);
            errors=errors+1;
        end
    end
    task drive_special;
        input [7:0] a0,a1,a2,a3,a4,a5,a6,a7,a8;
        begin @(negedge clk);p[0]=a0;p[1]=a1;p[2]=a2;p[3]=a3;p[4]=a4;p[5]=a5;p[6]=a6;p[7]=a7;p[8]=a8;v=1;w=1;h=1;f=1;end
    endtask
    initial begin
        seed=37;for(i=0;i<9;i=i+1)p[i]=0;
        repeat(4)@(negedge clk);rst_n=1;
        drive_special(8,8,8,8,8,8,8,8,8);
        drive_special(0,0,0,0,255,0,0,0,0);
        drive_special(255,255,255,255,0,255,255,255,255);
        drive_special(1,2,3,4,5,6,7,8,9);
        drive_special(9,8,7,6,5,4,3,2,1);
        drive_special(0,255,0,255,128,255,0,128,0);
        for(n=0;n<1024;n=n+1) begin
            @(negedge clk);for(i=0;i<9;i=i+1)p[i]=$random(seed);
            v=(n%7)!=0;w=(n%11)!=0;h=n[0];f=n[1];
            if(n==511) begin rst_n=0;@(negedge clk);rst_n=1;end
        end
        @(negedge clk);v=0;w=0;repeat(6)@(negedge clk);
        if(errors==0)$display("TEST PASSED: median_3x3");
        else $display("TEST FAILED: median_3x3, %0d error(s)",errors);
        $finish;
    end
endmodule
