`timescale 1ns/1ps
// 多位宽验证；参考模型使用整数乘法和减法，独立于RTL流水实现。
module sobel_case #(parameter W=8)(output reg done, output integer errors);
    reg clk=0, rst_n=0;
    reg [W-1:0] p[0:8]; // 输入窗口，按行排列
    reg v=0,w=0,h=0,f=0;
    wire signed [W+2:0] gx,gy;
    wire [W+2:0] g;
    wire [1:0] direction;
    wire ov,ow,oh,of;
    integer ex[0:2],ey[0:2],eg[0:2]; // 三拍参考队列
    reg [1:0] ed[0:2];
    reg [3:0] ec[0:2];
    integer i,n,k,rx,ry,seed,checks;
    localparam MAX=(1<<W)-1;
    always #5 clk=~clk;
    sobel_3x3 #(.PIXEL_WIDTH(W)) dut(.clk(clk),.rst_n(rst_n),
.in_p11(p[0]),.in_p12(p[1]),.in_p13(p[2]),.in_p21(p[3]),.in_p22(p[4]),.in_p23(p[5]),.in_p31(p[6]),.in_p32(p[7]),.in_p33(p[8]),
        .in_valid(v),.in_window_valid(w),.in_hsync(h),.in_vsync(f),
        .out_gx(gx),.out_gy(gy),.out_gradient(g),
        .out_direction(direction),
        .out_valid(ov),.out_window_valid(ow),.out_hsync(oh),.out_vsync(of));
    function [1:0] reference_direction;
        input integer x,y;
        integer ax,ay;
        real angle; // 独立反正切参考，不重复RTL定点比较式
        begin
            ax=(x<0)?-x:x; ay=(y<0)?-y:y;
            if(ax==0) angle=(ay==0)?0.0:90.0;
            else angle=$atan(ay*1.0/ax)*180.0/3.141592653589793;
            if(angle<22.5) reference_direction=0;
            else if(angle>67.5) reference_direction=2;
            else if((x<0)!=(y<0)) reference_direction=1;
            else reference_direction=3;
        end
    endfunction
    always @(posedge clk) begin
        if (!rst_n) begin
            for(k=0;k<3;k=k+1) begin ex[k]=0;ey[k]=0;eg[k]=0;ed[k]=0;ec[k]=0;end
        end else begin
            for(k=2;k>0;k=k-1) begin
                ex[k]=ex[k-1];ey[k]=ey[k-1];eg[k]=eg[k-1];ed[k]=ed[k-1];ec[k]=ec[k-1];
            end
            rx=p[2]+2*p[5]+p[8]-p[0]-2*p[3]-p[6];
            ry=p[6]+2*p[7]+p[8]-p[0]-2*p[1]-p[2];
            ex[0]=(v&&w)?rx:0; ey[0]=(v&&w)?ry:0;
            eg[0]=(v&&w)?((rx<0?-rx:rx)+(ry<0?-ry:ry)):0;
            ed[0]=(v&&w)?reference_direction(rx,ry):0;
            ec[0]={f,h,v&&w,v};
        end
        #1;
        checks=checks+1;
        if ($signed(gx)!==ex[2] || $signed(gy)!==ey[2] || g!==eg[2] || direction!==ed[2] ||
            {of,oh,ow,ov}!==ec[2]) begin
            if(errors<8) $display("ERROR: Sobel W=%0d gx=%0d/%0d gy=%0d/%0d g=%0d/%0d",
                W,$signed(gx),ex[2],$signed(gy),ey[2],g,eg[2]);
            errors=errors+1;
        end
    end
    task reset_check;
        begin
            @(negedge clk); #2; rst_n=0; #1;
            if ({gx,gy,g,direction,ov,ow,oh,of}!==0) errors=errors+1;
            repeat(3) @(negedge clk);
            rst_n=1;
        end
    endtask
    initial begin
        errors=0;done=0;checks=0;seed=19+W;
        for(i=0;i<9;i=i+1) p[i]=0;
        reset_check();
        // 穷举全部512种0/最大值窗口，覆盖最大正负梯度和双向梯度。
        for(n=0;n<512;n=n+1) begin
            @(negedge clk); #1;
            for(i=0;i<9;i=i+1) p[i]=((n>>i)&1)?MAX:0;
            v=1;w=1;h=n%2;f=(n/2)%2;
        end
        // 全部灰度值的平坦窗口。
        for(n=0;n<=MAX;n=n+1) begin
            @(negedge clk); #1;
            for(i=0;i<9;i=i+1) p[i]=n;
        end
        for(n=0;n<1024;n=n+1) begin
            @(negedge clk); #1;
            for(i=0;i<9;i=i+1) p[i]=$random(seed);
            v=(n%5!=0);w=(n%7!=0);h=n%2;f=(n/2)%2;
            if(n==511) reset_check();
        end
        @(negedge clk); #1; v=0;w=0;
        repeat(6) @(negedge clk);
        $display("Sobel width=%0d checked_cycles=%0d errors=%0d",W,checks,errors);
        done=1;
    end
endmodule
module sobel_3x3_tb;
    wire d4,d8,d10; wire [31:0] e4,e8,e10;
    integer errors;
    sobel_case #(4) a(d4,e4);
    sobel_case #(8) b(d8,e8);
    sobel_case #(10) c(d10,e10);
    initial begin
        errors=0; wait(d4&&d8&&d10); #2; errors=e4+e8+e10;
        if(errors==0) $display("TEST PASSED: sobel_3x3");
        else $display("TEST FAILED: sobel_3x3, %0d error(s)",errors);
        $finish;
    end
    initial begin #1000000; errors=errors+1;$display("TEST FAILED: sobel_3x3 timeout"); $finish; end
endmodule
