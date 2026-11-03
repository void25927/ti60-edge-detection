`timescale 1ns/1ps
module gaussian_3x3_tb;
    reg clk=0,rst_n=0; reg [7:0] p[0:8]; reg v=0,w=0,h=0,f=0;
    wire [7:0] pixel; wire ov,ow,oh,of;
    reg [7:0] ep[0:1]; reg [3:0] ec[0:1];
    integer i,k,n,sum,seed,errors=0;
    always #5 clk=~clk;
    gaussian_3x3 dut(.clk(clk),.rst_n(rst_n),
        .in_p11(p[0]),.in_p12(p[1]),.in_p13(p[2]),.in_p21(p[3]),.in_p22(p[4]),.in_p23(p[5]),.in_p31(p[6]),.in_p32(p[7]),.in_p33(p[8]),
        .in_valid(v),.in_window_valid(w),.in_hsync(h),.in_vsync(f),.out_pixel(pixel),.out_valid(ov),.out_window_valid(ow),.out_hsync(oh),.out_vsync(of));
    always @(posedge clk) begin
        if(!rst_n)begin for(k=0;k<2;k=k+1)begin ep[k]=0;ec[k]=0;end end
        else begin
            ep[1]=ep[0];ec[1]=ec[0];
            sum=p[0]+2*p[1]+p[2]+2*p[3]+4*p[4]+2*p[5]+p[6]+2*p[7]+p[8];
            ep[0]=(v&&w)?(sum>>4):0;ec[0]={f,h,v&&w,v};
        end
        #1;if(pixel!==ep[1]||{of,oh,ow,ov}!==ec[1])begin if(errors<8)$display("ERROR gaussian %0d/%0d",pixel,ep[1]);errors=errors+1;end
    end
    initial begin seed=51;for(i=0;i<9;i=i+1)p[i]=0;repeat(4)@(negedge clk);rst_n=1;
        for(n=0;n<1024;n=n+1)begin @(negedge clk);for(i=0;i<9;i=i+1)p[i]=$random(seed);v=(n%5)!=0;w=(n%9)!=0;h=n[0];f=n[1];end
        @(negedge clk);v=0;w=0;repeat(5)@(negedge clk);
        if(errors==0)$display("TEST PASSED: gaussian_3x3");else $display("TEST FAILED: gaussian_3x3, %0d error(s)",errors);$finish;end
endmodule
