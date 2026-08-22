module Piccolo_Core (iclk, rst_n, istart, imode, iData, iKey, oData, odone);

    input  wire         iclk;
    input  wire         rst_n;
    input  wire         istart;
    input  wire         imode; // 1: Encrypt, 0: Decrypt
    input  wire [127:0] iKey;
    input  wire [63:0]  iData;
    output reg  [63:0]  oData;
    output reg          odone;

    localparam IDLE = 2'd0, RUN = 2'd1, DONE = 2'd2;
    reg [1:0] state;
    reg [4:0] round_cnt;
    reg [63:0] current_data;

    wire [4:0] iround = imode ? round_cnt : (5'd30 - round_cnt);

    wire [15:0] wk0, wk1, wk2, wk3;
    wire [15:0] rk_even, rk_odd;

    Piccolo_KeySchedule KS_inst(
        .KS(iKey), 
        .iround(iround), 
        .imode(imode),
        .wk0(wk0), .wk1(wk1), .wk2(wk2), .wk3(wk3), 
        .rk_even(rk_even), .rk_odd(rk_odd)
    );

    wire [15:0] X0 = current_data[63:48];
    wire [15:0] X1 = current_data[47:32];
    wire [15:0] X2 = current_data[31:16];
    wire [15:0] X3 = current_data[15:0];

    wire [15:0] f_out_0, f_out_2;
    Piccolo_F_Function F0 (.idata(X0), .odata(f_out_0));
    Piccolo_F_Function F2 (.idata(X2), .odata(f_out_2));

    wire [15:0] next_X1 = X1 ^ f_out_0 ^ rk_even;
    wire [15:0] next_X3 = X3 ^ f_out_2 ^ rk_odd;

    wire [15:0] rp_X0 = {next_X1[15:8], next_X3[7:0]}; 
    wire [15:0] rp_X1 = {X2[15:8],      X0[7:0]};      
    wire [15:0] rp_X2 = {next_X3[15:8], next_X1[7:0]}; 
    wire [15:0] rp_X3 = {X0[15:8],      X2[7:0]};      

    always @(posedge iclk or posedge rst_n) begin
        if (rst_n) begin
            state <= IDLE;
            round_cnt <= 0;
            odone <= 0;
            oData <= 0;
            current_data <= 0;
        end else begin
            case(state)
                IDLE: begin
                    odone <= 0;
                    if (istart) begin
                        state <= RUN;
                        round_cnt <= 0;
                        current_data <= { iData[63:48] ^ wk0, iData[47:32], iData[31:16] ^ wk1, iData[15:0] };
                    end
                end
                
                RUN: begin
                    if (round_cnt < 30) begin
                        current_data <= {rp_X0, rp_X1, rp_X2, rp_X3};
                        round_cnt <= round_cnt + 1;
                    end else begin
                        current_data <= {X0 ^ wk2, next_X1, X2 ^ wk3, next_X3};
                        state <= DONE;
                    end
                end
                
                DONE: begin
                    odone <= 1;
                    oData <= current_data;
                    if (!istart) state <= IDLE;
                end
                
                default: state <= IDLE;
            endcase
        end
    end
endmodule

module Piccolo_KeySchedule(
    input  wire [127:0] KS,
    input  wire [4:0]   iround,
    input  wire         imode,
    output wire [15:0]  wk0, wk1, wk2, wk3,
    output wire [15:0]  rk_even, rk_odd
);
    wire [15:0] K7 = KS[15:0];   wire [15:0] K6 = KS[31:16];
    wire [15:0] K5 = KS[47:32];  wire [15:0] K4 = KS[63:48];
    wire [15:0] K3 = KS[79:64];  wire [15:0] K2 = KS[95:80];
    wire [15:0] K1 = KS[111:96]; wire [15:0] K0 = KS[127:112];
 
    assign wk0 = imode ? {K0[15:8], K1[7:0]} : {K4[15:8], K7[7:0]};
    assign wk1 = imode ? {K1[15:8], K0[7:0]} : {K7[15:8], K4[7:0]};
    assign wk2 = imode ? {K4[15:8], K7[7:0]} : {K0[15:8], K1[7:0]};
    assign wk3 = imode ? {K7[15:8], K4[7:0]} : {K1[15:8], K0[7:0]};

    wire [2:0] state_idx = (iround + 5'd1) >> 2; 
    reg [127:0] pKS;
    always @(*) begin
        case (state_idx)
            3'd0: pKS = {K0, K1, K2, K3, K4, K5, K6, K7};
            3'd1: pKS = {K2, K1, K6, K7, K0, K3, K4, K5};
            3'd2: pKS = {K6, K1, K4, K5, K2, K7, K0, K3};
            3'd3: pKS = {K4, K1, K0, K3, K6, K5, K2, K7};
            3'd4: pKS = {K0, K1, K2, K7, K4, K3, K6, K5};
            3'd5: pKS = {K2, K1, K6, K5, K0, K7, K4, K3};
            3'd6: pKS = {K6, K1, K4, K3, K2, K5, K0, K7};
            3'd7: pKS = {K4, K1, K0, K7, K6, K3, K2, K5};
         default: pKS = {K0, K1, K2, K3, K4, K5, K6, K7};
        endcase
    end
    
    wire [15:0] pK7 = pKS[15:0];   wire [15:0] pK6 = pKS[31:16];
    wire [15:0] pK5 = pKS[47:32];  wire [15:0] pK4 = pKS[63:48];
    wire [15:0] pK3 = pKS[79:64];  wire [15:0] pK2 = pKS[95:80];
    wire [15:0] pK1 = pKS[111:96]; wire [15:0] pK0 = pKS[127:112];

    reg [15:0] Sel_K_even, Sel_K_odd;
    always @(*) begin
        case (iround[1:0])
            2'd0: begin Sel_K_even = pK2; Sel_K_odd = pK3; end
            2'd1: begin Sel_K_even = pK4; Sel_K_odd = pK5; end
            2'd2: begin Sel_K_even = pK6; Sel_K_odd = pK7; end
            2'd3: begin Sel_K_even = pK0; Sel_K_odd = pK1; end
        endcase
    end

    wire [4:0] c = iround + 1'b1; 
    wire [15:0] base_even = { c, 5'b00000, c, 1'b0 };
    
    wire [15:0] con_even = base_even ^ 16'h6547;
    wire [15:0] con_odd  = (base_even >> 1) ^ 16'ha98b;
    
    assign rk_even = (!imode && iround[0]) ? Sel_K_odd  ^ con_odd : Sel_K_even ^ con_even;
    assign rk_odd  = (!imode && iround[0]) ? Sel_K_even ^ con_even : Sel_K_odd  ^ con_odd;
endmodule


module Piccolo_F_Function(idata, odata);
    input  wire [15:0] idata;
    output wire [15:0] odata;

    //SLICE 
    wire [3:0] X3 = idata[3:0];
    wire [3:0] X2 = idata[7:4];
    wire [3:0] X1 = idata[11:8];
    wire [3:0] X0 = idata[15:12];
    
    //Sbox stage 1
    wire [3:0] X0_sbox_Stage1; wire [3:0] X1_sbox_Stage1;
    wire [3:0] X2_sbox_Stage1; wire [3:0] X3_sbox_Stage1;
    Piccolo_Sbox Sbox0_Stage1 (.iData(X0), .Sbox_out(X0_sbox_Stage1));
    Piccolo_Sbox Sbox1_Stage1 (.iData(X1), .Sbox_out(X1_sbox_Stage1));
    Piccolo_Sbox Sbox2_Stage1 (.iData(X2), .Sbox_out(X2_sbox_Stage1));
    Piccolo_Sbox Sbox3_Stage1 (.iData(X3), .Sbox_out(X3_sbox_Stage1));
    
    //diffusion function
    //GM2
    function [3 : 0] gm2(input [3 : 0] op); 
     begin
        gm2 = {op[2:1], op[0] ^ op[3], op[3]}; 
     end
    endfunction 
    //GM3
    function [3 : 0] gm3(input [3 : 0] op); 
     begin
        gm3 = {op[2] ^ op[3], op[1] ^ op[2], op[0] ^ op[3] ^ op[1], op[3] ^ op[0]}; //gm2(op) ^ op
     end
    endfunction 

    wire [3:0] X0_diff = gm2(X0_sbox_Stage1) ^ gm3(X1_sbox_Stage1) ^     X2_sbox_Stage1  ^     X3_sbox_Stage1; // y0 = 2*x0 ^ 3*x1 ^ 1*x2 ^ 1*x3
    wire [3:0] X1_diff =     X0_sbox_Stage1  ^ gm2(X1_sbox_Stage1) ^ gm3(X2_sbox_Stage1) ^     X3_sbox_Stage1; // y1 = 1*x0 ^ 2*x1 ^ 3*x2 ^ 1*x3
    wire [3:0] X2_diff =     X0_sbox_Stage1  ^     X1_sbox_Stage1  ^ gm2(X2_sbox_Stage1) ^ gm3(X3_sbox_Stage1); // y2 = 1*x0 ^ 1*x1 ^ 2*x2 ^ 3*x3
    wire [3:0] X3_diff = gm3(X0_sbox_Stage1) ^     X1_sbox_Stage1  ^     X2_sbox_Stage1  ^ gm2(X3_sbox_Stage1); // y3 = 3*x0 ^ 1*x1 ^ 1*x2 ^ 2*x3

    //Sbox stage 2
    wire [3:0] X0_sbox_Stage2; wire [3:0] X1_sbox_Stage2;
    wire [3:0] X2_sbox_Stage2; wire [3:0] X3_sbox_Stage2;
    Piccolo_Sbox Sbox0_Stage2 (.iData(X0_diff), .Sbox_out(odata[15:12]));
    Piccolo_Sbox Sbox1_Stage2 (.iData(X1_diff), .Sbox_out(odata[11:8]));
    Piccolo_Sbox Sbox2_Stage2 (.iData(X2_diff), .Sbox_out(odata[7:4]));
    Piccolo_Sbox Sbox3_Stage2 (.iData(X3_diff), .Sbox_out(odata[3:0]));

endmodule

module Piccolo_Sbox (
    input   wire [3:0] iData,
    output  reg  [3:0] Sbox_out
);
    always @(*) begin
            case (iData)
                4'h0: Sbox_out = 4'he; 4'h1: Sbox_out = 4'h4; 4'h2: Sbox_out = 4'hb; 4'h3: Sbox_out = 4'h2;
                4'h4: Sbox_out = 4'h3; 4'h5: Sbox_out = 4'h8; 4'h6: Sbox_out = 4'h0; 4'h7: Sbox_out = 4'h9;
                4'h8: Sbox_out = 4'h1; 4'h9: Sbox_out = 4'ha; 4'ha: Sbox_out = 4'h7; 4'hb: Sbox_out = 4'hf;
                4'hc: Sbox_out = 4'h6; 4'hd: Sbox_out = 4'hc; 4'he: Sbox_out = 4'h5; 4'hf: Sbox_out = 4'hd;
                default: Sbox_out = 4'he;
            endcase
    end
endmodule
