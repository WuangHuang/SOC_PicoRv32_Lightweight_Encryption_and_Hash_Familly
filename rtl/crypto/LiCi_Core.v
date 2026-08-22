module LiCi_Core (iclk, rst_n, istart, imode, iData, iKey, oData, odone);

    input  wire         iclk;
    input  wire         rst_n;      
    input  wire         istart;
    input  wire         imode;    
    input  wire [63:0]  iData;    
    input  wire [127:0] iKey;    
    
    output reg  [63:0]  oData;    
    output reg          odone;     

    localparam IDLE         = 3'd0,
               ENC_CALC     = 3'd1,
               DEC_KEY_FWD  = 3'd2,
               DEC_CALC     = 3'd3,
               DONE         = 3'd4;

    reg [2:0] state, next_state;

    reg [63:0]  reg_Data;
    reg [127:0] reg_Key;
    reg [4:0]   round_counter; 

    wire ks_imode = (state == DEC_CALC) ? 1'b1 : 1'b0; 
    
    wire [31:0]  Rk1, Rk2;
    wire [127:0] NextKey;
    
    LiCi_KeySchedule unified_ks (
        .iKey(reg_Key),
        .iRound(round_counter),
        .imode(ks_imode),
        .oRk1(Rk1),
        .oRk2(Rk2),
        .oOutKey(NextKey)
    );

    wire [63:0]  enc_NextData;
    LiCi_EncBlock enc_blk (
        .iPT(reg_Data), .iRk1(Rk1), .iRk2(Rk2), .oCT(enc_NextData)
    );

    wire [63:0]  dec_PrevData;
    LiCi_DecBlock dec_blk (
        .iCT(reg_Data), .iRk1(Rk1), .iRk2(Rk2), .oPT(dec_PrevData)
    );

    always @(*) begin
        next_state = state; 
        case (state)
            IDLE: begin
                if (istart) begin
                    if (imode == 1'b0) next_state = ENC_CALC;
                    else              next_state = DEC_KEY_FWD;
                end
            end
            ENC_CALC:    if (round_counter == 5'd30) next_state = odone;   
            DEC_KEY_FWD: if (round_counter == 5'd30) next_state = DEC_CALC; 
            DEC_CALC:    if (round_counter == 5'd0)  next_state = odone;
            DONE:        next_state = IDLE; 
            default:     next_state = IDLE;
        endcase
    end

    always @(posedge iclk or negedge rst_n) begin
        if (!rst_n) begin
            state         <= IDLE;
            reg_Data      <= 64'd0;
            reg_Key       <= 128'd0;
            round_counter <= 5'd0;
            oData         <= 64'd0;
            odone          <= 1'b0;
        end else begin
            state <= next_state;
            case (state)
                IDLE: begin
                    odone <= 1'b0;
                    if (istart) begin
                        reg_Data      <= iData;
                        reg_Key       <= iKey;
                        round_counter <= 5'd0;
                    end
                end
                
                ENC_CALC: begin
                    reg_Data      <= enc_NextData;
                    reg_Key       <= NextKey;      
                    round_counter <= round_counter + 1'b1;
                end
                
                DEC_KEY_FWD: begin
                    reg_Key <= NextKey;          
                    if (round_counter == 5'd30) begin
                        round_counter <= 5'd30;   
                    end else begin
                        round_counter <= round_counter + 1'b1;
                    end
                end

                DEC_CALC: begin
                    reg_Data      <= dec_PrevData;
                    reg_Key       <= NextKey;     
                    round_counter <= round_counter - 1'b1; 
                end
                
                odone: begin
                    oData <= reg_Data;
                    odone  <= 1'b1;
                end
            endcase
        end
    end
endmodule

module LiCi_EncBlock (iPT, iRk1, iRk2, oCT);
    input  wire [63:0] iPT;
    input  wire [31:0] iRk1, iRk2;
    output wire [63:0] oCT;

    wire [31:0] Sbox_PT_MSB;
    LiCi_Sbox s1(.iSbox(iPT[63:60]), .oSbox(Sbox_PT_MSB[31:28]));    
    LiCi_Sbox s2(.iSbox(iPT[59:56]), .oSbox(Sbox_PT_MSB[27:24]));
    LiCi_Sbox s3(.iSbox(iPT[55:52]), .oSbox(Sbox_PT_MSB[23:20]));
    LiCi_Sbox s4(.iSbox(iPT[51:48]), .oSbox(Sbox_PT_MSB[19:16]));
    LiCi_Sbox s5(.iSbox(iPT[47:44]), .oSbox(Sbox_PT_MSB[15:12]));
    LiCi_Sbox s6(.iSbox(iPT[43:40]), .oSbox(Sbox_PT_MSB[11:8]));
    LiCi_Sbox s7(.iSbox(iPT[39:36]), .oSbox(Sbox_PT_MSB[7:4]));
    LiCi_Sbox s8(.iSbox(iPT[35:32]), .oSbox(Sbox_PT_MSB[3:0]));

    wire [31:0] xor_lsb        = iPT[31:0] ^ Sbox_PT_MSB ^ iRk1;
    wire [31:0] pt_lsb_shifted = {xor_lsb[28:0], xor_lsb[31:29]}; 

    wire [31:0] xor_msb        = Sbox_PT_MSB ^ pt_lsb_shifted ^ iRk2;
    wire [31:0] pt_msb_shifted = {xor_msb[6:0], xor_msb[31:7]};  
    
    assign oCT = {pt_lsb_shifted, pt_msb_shifted};
endmodule

module LiCi_DecBlock (iCT, iRk1, iRk2, oPT);
    input  wire [63:0] iCT;
    input  wire [31:0] iRk1, iRk2;
    output wire [63:0] oPT;

    wire [31:0] CT_MSB = iCT[63:32];
    wire [31:0] CT_LSB = iCT[31:0];

    wire [31:0] ct_lsb_shifted = {CT_LSB[24:0], CT_LSB[31:25]};
    wire [31:0] T1 = ct_lsb_shifted ^ CT_MSB ^ iRk2;

    wire [31:0] PT_MSB_out;
    LiCi_InvSbox is1(.iSbox(T1[31:28]), .oSbox(PT_MSB_out[31:28]));    
    LiCi_InvSbox is2(.iSbox(T1[27:24]), .oSbox(PT_MSB_out[27:24]));
    LiCi_InvSbox is3(.iSbox(T1[23:20]), .oSbox(PT_MSB_out[23:20]));
    LiCi_InvSbox is4(.iSbox(T1[19:16]), .oSbox(PT_MSB_out[19:16]));
    LiCi_InvSbox is5(.iSbox(T1[15:12]), .oSbox(PT_MSB_out[15:12]));
    LiCi_InvSbox is6(.iSbox(T1[11:8]),  .oSbox(PT_MSB_out[11:8]));
    LiCi_InvSbox is7(.iSbox(T1[7:4]),   .oSbox(PT_MSB_out[7:4]));
    LiCi_InvSbox is8(.iSbox(T1[3:0]),   .oSbox(PT_MSB_out[3:0]));

    wire [31:0] ct_msb_shifted = {CT_MSB[2:0], CT_MSB[31:3]};
    wire [31:0] PT_LSB_out = ct_msb_shifted ^ T1 ^ iRk1;

    assign oPT = {PT_MSB_out, PT_LSB_out};
endmodule

module LiCi_KeySchedule(
    input  wire [127:0] iKey,
    input  wire [4:0]   iRound,
    input  wire         imode,
    output wire [31:0]  oRk1,
    output wire [31:0]  oRk2,
    output wire [127:0] oOutKey
);

    wire [31:0]  fwd_Rk1 = iKey[31:0];
    wire [31:0]  fwd_Rk2 = iKey[63:32];

    wire [127:0] wKey_fwd = {iKey[114:0], iKey[127:115]}; 
    
    wire [127:0] fwd_NextKey;
    assign fwd_NextKey[127:64] = wKey_fwd[127:64];
    assign fwd_NextKey[63:59]  = wKey_fwd[63:59] ^ iRound;
    assign fwd_NextKey[58:8]   = wKey_fwd[58:8];
    LiCi_Sbox sbox1_fwd(.iSbox(wKey_fwd[7:4]), .oSbox(fwd_NextKey[7:4]));
    LiCi_Sbox sbox0_fwd(.iSbox(wKey_fwd[3:0]), .oSbox(fwd_NextKey[3:0]));

    wire [127:0] wKey_inv;
    assign wKey_inv[127:64] = iKey[127:64];
    assign wKey_inv[63:59]  = iKey[63:59] ^ iRound;
    assign wKey_inv[58:8]   = iKey[58:8];
    LiCi_InvSbox sbox1_inv(.iSbox(iKey[7:4]), .oSbox(wKey_inv[7:4]));
    LiCi_InvSbox sbox0_inv(.iSbox(iKey[3:0]), .oSbox(wKey_inv[3:0]));

    wire [127:0] inv_PrevKey = {wKey_inv[12:0], wKey_inv[127:13]}; 
    
    wire [31:0]  inv_Rk1 = inv_PrevKey[31:0];
    wire [31:0]  inv_Rk2 = inv_PrevKey[63:32];

    assign oRk1    = (imode == 1'b0) ? fwd_Rk1     : inv_Rk1;
    assign oRk2    = (imode == 1'b0) ? fwd_Rk2     : inv_Rk2;
    assign oOutKey = (imode == 1'b0) ? fwd_NextKey : inv_PrevKey;

endmodule

module LiCi_Sbox(iSbox, oSbox);     
    input  wire [3:0] iSbox;
    output reg  [3:0] oSbox;
    always @(*) begin
        case (iSbox)
         4'h0: oSbox = 4'h3; 4'h1: oSbox = 4'hF; 4'h2: oSbox = 4'hE; 4'h3: oSbox = 4'h1;
         4'h4: oSbox = 4'h0; 4'h5: oSbox = 4'hA; 4'h6: oSbox = 4'h5; 4'h7: oSbox = 4'h8;
         4'h8: oSbox = 4'hC; 4'h9: oSbox = 4'h4; 4'hA: oSbox = 4'hB; 4'hB: oSbox = 4'h2;
         4'hC: oSbox = 4'h9; 4'hD: oSbox = 4'h7; 4'hE: oSbox = 4'h6; 4'hF: oSbox = 4'hD;
        endcase 
    end 
endmodule 

module LiCi_InvSbox(iSbox, oSbox);     
    input  wire [3:0] iSbox;
    output reg  [3:0] oSbox;
    always @(*) begin
        case (iSbox)
         4'h3: oSbox = 4'h0; 4'hF: oSbox = 4'h1; 4'hE: oSbox = 4'h2; 4'h1: oSbox = 4'h3;
         4'h0: oSbox = 4'h4; 4'hA: oSbox = 4'h5; 4'h5: oSbox = 4'h6; 4'h8: oSbox = 4'h7;
         4'hC: oSbox = 4'h8; 4'h4: oSbox = 4'h9; 4'hB: oSbox = 4'hA; 4'h2: oSbox = 4'hB;
         4'h9: oSbox = 4'hC; 4'h7: oSbox = 4'hD; 4'h6: oSbox = 4'hE; 4'hD: oSbox = 4'hF;
        endcase
    end 
endmodule