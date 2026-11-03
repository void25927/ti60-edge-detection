`timescale 1ns/1ps
module snapshot_axi_writer_tb;
    reg clk=0;always #5 clk=~clk;
    reg rst_n=0,cancel=0,iv=0,il=0;
    reg [31:0] ia=0;reg [15:0] ip=0;
    wire ir,av,wv,wl,br,done,fault,drained,cancel_ready;
    wire [3:0] aid;wire [31:0] aa;wire [7:0] al;
    wire [2:0] size;wire [1:0] burst;
    wire [127:0] wd;wire [15:0] ws;
    reg ar=0,wr=0,bv=0;reg [3:0] bi=8;reg [1:0] bp=0;
    integer errors=0,cycle=0,bursts=0,beats=0,checks=0,completions=0;
    integer remaining=0,delay_b=0,k,j;
    reg [31:0] address=0;
    reg [1:0] inject_response=0;
    reg [127:0] held_data;reg [15:0] held_strb;reg held_last;
    reg held_w=0,held_a=0;reg [31:0] held_addr;reg [7:0] held_len;
    snapshot_axi_writer dut(clk,rst_n,cancel,iv,ir,ia,ip,il,
        aid,aa,al,size,burst,av,ar,wd,ws,wl,wv,wr,bi,bp,bv,br,done,fault,drained,cancel_ready);
    task check;input condition;begin if(!condition)begin errors=errors+1;$display("FAIL t=%0t",$time);end end endtask
    task reset;begin
        @(negedge clk);rst_n=0;iv=0;cancel=0;repeat(3)@(negedge clk);rst_n=1;
    end endtask
    task send;input [31:0] a;input last;begin
        @(negedge clk);iv=1;ia=a;ip=a[16:1]^16'h5a3c;il=last;
        @(posedge clk);while(!ir)@(posedge clk);
        @(negedge clk);iv=0;
    end endtask
    // 地址、数据和响应分别施加确定性背压。
    always @(negedge clk)begin
        ar=(cycle%5==0);wr=(cycle%4!=0);
    end
    always @(posedge clk)begin
        if(!rst_n)begin
            cycle<=0;bv<=0;remaining<=0;delay_b<=0;held_w<=0;held_a<=0;
        end else begin
            cycle<=cycle+1;
            if(done)completions=completions+1;
            if(held_a)check(av&&aa==held_addr&&al==held_len);
            if(held_w)check(wv&&wd===held_data&&ws==held_strb&&wl==held_last);
            held_a<=av&&!ar;held_addr<=aa;held_len<=al;
            held_w<=wv&&!wr;held_data<=wd;held_strb<=ws;held_last<=wl;
            if(av&&ar)begin
                check(al<8&&size==4&&burst==1&&aid==8);
                check({1'b0,aa[11:0]}+((al+1)*16)<=4096);
                check(remaining==0&&!bv);remaining<=al+1;address<=aa;bursts=bursts+1;
            end
            if(wv&&wr)begin
                check(remaining>0);check(wl==(remaining==1));
                for(j=0;j<8;j=j+1)if(ws[j*2+:2]==3)begin
                    check(wd[j*16+:16]===((((address+j*2)>>1)^16'h5a3c)&32'hffff));
                    checks=checks+1;
                end
                remaining<=remaining-1;address<=address+16;beats=beats+1;
                if(wl)delay_b<=9;
            end
            if(delay_b>0)begin
                delay_b<=delay_b-1;
                if(delay_b==1)begin bv<=1;bp<=inject_response;end
            end
            if(bv&&br)bv<=0;
        end
    end
    initial begin
        reset;
        // 从4KB末尾起写，检验切分、完整突发及末拍字节掩码。
        for(k=0;k<75;k=k+1)send(32'hff0+k*2,k==74);
        wait(done);@(negedge clk);check(!fault&&drained);check(checks==75);check(bursts==3);
        // 已发布的事务被取消后仍完成握手，但不得报告截图成功。
        send(32'h2000,1);wait(av);@(negedge clk);cancel=1;
        @(negedge clk);cancel=0;wait(drained);repeat(3)@(negedge clk);check(completions==1);
        send(32'h3000,1);wait(done);@(negedge clk);check(!fault);
        inject_response=2;send(32'h4000,1);wait(fault);check(!done);check(drained);
        reset;inject_response=0;bi=7;send(32'h5000,1);wait(fault);check(!done);
        reset;bi=8;send(32'h6002,1);@(negedge clk);check(fault&&drained);
        reset;check(!fault&&drained);send(32'h7000,1);wait(done);@(negedge clk);
        if(errors==0)$display("TEST PASSED: snapshot_axi_writer, pixel_checks=%0d bursts=%0d beats=%0d",checks,bursts,beats);
        else $display("TEST FAILED: snapshot_axi_writer, %0d error(s)",errors);
        $finish;
    end
    initial begin #2000000;errors=errors+1;$display("TEST FAILED: timeout");$finish;end
endmodule
