module Klein_Core (iclk, rst_n, istart, imode, iData, iKey, oData, odone);


    input   wire          iclk;
    input   wire          rst_n;
    input   wire          istart;
    input   wire          imode;
    input   wire  [63:0]  iData;   
    input   wire  [63:0]  iKey;  
      
    output  wire          odone;   
    output  wire  [63:0]  oData;  

    localparam S_IDLE  = 2'd0; 
    localparam S_SETUP = 2'd1; 
    localparam S_RUN   = 2'd2; 

    reg [1:0]   fsm_state;
    reg         ready_reg;
    reg [63:0]  result_reg;
    reg [3:0]   round;
    reg [63:0]  state, kstate;

    reg [63:0]  cached_k0;
    reg [63:0]  cached_k12;
    reg         k12_valid;

    wire [63:0] nstate, nkstate;

    assign odone = ready_reg;
    assign oData = result_reg;

    Klein_Datapath datapath (
        .state  (state),
        .kstate (kstate),
        .imode   (imode),     
        .nstate (nstate)    
    );


    wire is_fwd_key = imode | (fsm_state == S_SETUP);
    Klein_KeySchedule keyschedule (.kstate(kstate), .round(round), .is_fwd_key(is_fwd_key), .nkstate(nkstate));

    always @(posedge iclk or negedge rst_n) begin
        if (!rst_n) begin
            fsm_state   <= S_IDLE;
            ready_reg   <= 1'b0; 
            result_reg  <= 64'd0;
            round       <= 4'd0;
            state       <= 64'd0;
            kstate      <= 64'd0;
            cached_k0   <= 64'd0;
            cached_k12  <= 64'd0;
            k12_valid   <= 1'b0;
        end 
        else begin
            case (fsm_state)
                S_IDLE: begin
                    ready_reg <= 1'b0;
                    if (istart) begin
                        state <= iData;
                        if (iKey != cached_k0 || !k12_valid) begin
                            cached_k0 <= iKey;
                            k12_valid <= 1'b0;
                            if (!imode) begin
                                fsm_state <= S_SETUP;
                                round     <= 4'd0;
                                kstate    <= iKey;
                            end else begin
                                fsm_state <= S_RUN;
                                round     <= 4'd0;
                                kstate    <= iKey;
                            end
                        end 
                        else begin
                            fsm_state <= S_RUN;
                            if (imode) begin
                                round  <= 4'd0;
                                kstate <= iKey;
                            end else begin
                                round  <= 4'd11;
                                kstate <= cached_k12; 
                            end
                        end
                    end
                end

                S_SETUP: begin
                    if (round < 4'd11) begin
                        round  <= round + 4'd1;
                        kstate <= nkstate; 
                    end 
                    else begin
                        cached_k12 <= nkstate; 
                        k12_valid  <= 1'b1;   
                        fsm_state  <= S_RUN;
                        round      <= 4'd11;    
                        kstate     <= nkstate;
                    end
                end

                S_RUN: begin
                    state  <= nstate;
                    kstate <= nkstate; 
                    
                    if (imode) begin
                        if (round < 4'd11) round <= round + 4'd1;
                        else begin
                            result_reg <= nstate ^ nkstate;
                            cached_k12 <= nkstate; 
                            k12_valid  <= 1'b1;   
                            ready_reg  <= 1'b1;
                            fsm_state  <= S_IDLE;
                        end
                    end 
                    else begin
                        if (round > 4'd0) round <= round - 4'd1;
                        else begin
                            result_reg <= nstate ^ nkstate;
                            ready_reg  <= 1'b1;
                            fsm_state  <= S_IDLE;
                        end
                    end
                end
            endcase
        end
    end
endmodule

module Klein_Datapath (
    input  wire [63:0] state,
    input  wire [63:0] kstate,
    input  wire        imode,   
    output wire [63:0] nstate
);

    wire [63:0] ssum = state ^ kstate;

 
    wire [63:0] srot_dec; 

    wire [63:0] sbox_in = imode ? ssum : srot_dec; 
    wire [63:0] sbox_out;

    Klein_Sbox s1  (.in(sbox_in[63:60]), .out(sbox_out[63:60]));
    Klein_Sbox s2  (.in(sbox_in[59:56]), .out(sbox_out[59:56]));
    Klein_Sbox s3  (.in(sbox_in[55:52]), .out(sbox_out[55:52]));
    Klein_Sbox s4  (.in(sbox_in[51:48]), .out(sbox_out[51:48]));
    Klein_Sbox s5  (.in(sbox_in[47:44]), .out(sbox_out[47:44]));
    Klein_Sbox s6  (.in(sbox_in[43:40]), .out(sbox_out[43:40]));
    Klein_Sbox s7  (.in(sbox_in[39:36]), .out(sbox_out[39:36]));
    Klein_Sbox s8  (.in(sbox_in[35:32]), .out(sbox_out[35:32]));
    Klein_Sbox s9  (.in(sbox_in[31:28]), .out(sbox_out[31:28]));
    Klein_Sbox s10 (.in(sbox_in[27:24]), .out(sbox_out[27:24]));
    Klein_Sbox s11 (.in(sbox_in[23:20]), .out(sbox_out[23:20]));
    Klein_Sbox s12 (.in(sbox_in[19:16]), .out(sbox_out[19:16]));
    Klein_Sbox s13 (.in(sbox_in[15:12]), .out(sbox_out[15:12]));
    Klein_Sbox s14 (.in(sbox_in[11:08]), .out(sbox_out[11:08]));
    Klein_Sbox s15 (.in(sbox_in[07:04]), .out(sbox_out[07:04]));
    Klein_Sbox s16 (.in(sbox_in[03:00]), .out(sbox_out[03:00]));

    
    wire [63:0] srot_enc = {sbox_out[47:0], sbox_out[63:48]};

    wire [63:0] mix_in = imode ? srot_enc : ssum;
    wire [63:0] mix_out;

    Klein_Mixnibbles mix1(.idata(mix_in[63:32]), .iinv(!imode), .odata(mix_out[63:32]));
    Klein_Mixnibbles mix2(.idata(mix_in[31:00]), .iinv(!imode), .odata(mix_out[31:00]));

    assign srot_dec = {mix_out[15:0], mix_out[63:16]};

    assign nstate = imode ? mix_out : sbox_out;

endmodule

module Klein_KeySchedule (kstate, nkstate, round, is_fwd_key);
    input  wire [63:0] kstate;
    input  wire [3:0]  round;
    input  wire        is_fwd_key;
    
    output wire [63:0] nkstate;
    
    //STATE 1: Divide 2 tuples and Cycle left shift 1 byte (ENCRYPTION)
    wire [63:0] krot_enc = {kstate[55:32], kstate[63:56], kstate[23:0], kstate[31:24]};
    wire [63:0] kfei_enc;

    //STATE 2: Feistel-like structure (ENCRYPTION)
    assign kfei_enc[63:32] = krot_enc[31:00];
    assign kfei_enc[31:00] = krot_enc[63:32] ^ krot_enc[31:00];
    
    //STATE 3: S-box sk 5th and sk 6th (ENCRYPTION-DECRYPTION)
    wire [15:0] ks_sbox_in = is_fwd_key ? kfei_enc[23:8] : kstate[23:8];
    wire [15:0] ks_sbox_out;
    /////////////////////////////////////////////////////////////////
    Klein_Sbox sk0 (.in(ks_sbox_in[15:12]), .out(ks_sbox_out[15:12]));
    Klein_Sbox sk1 (.in(ks_sbox_in[11:08]), .out(ks_sbox_out[11:08]));
    /////////////////////////////////////////////////////////////////
    Klein_Sbox sk2 (.in(ks_sbox_in[7:4]),   .out(ks_sbox_out[7:4]));
    Klein_Sbox sk3 (.in(ks_sbox_in[3:0]),   .out(ks_sbox_out[3:0]));
   
     //STATE 3: (ENCRYPTION)
    wire [63:0] nkstate_enc;
    assign nkstate_enc[63:48] = kfei_enc[63:48];
    assign nkstate_enc[47:40] = kfei_enc[47:40] ^ {4'd0, round + 4'd1}; //sk 2th xor round counter i 

    assign nkstate_enc[39:24] = kfei_enc[39:24];
    assign nkstate_enc[23:8]  = ks_sbox_out; //S-box sk 5th and sk 6th 
    assign nkstate_enc[7:0]   = kfei_enc[7:0];
   
   //STATE 1: (DECRYPTION)
    wire [63:0] kfei_dec_pre;
    assign kfei_dec_pre[63:48] = kstate[63:48];
    assign kfei_dec_pre[47:40] = kstate[47:40] ^ {4'd0, round + 4'd1}; //sk 2th xor round counter i 
    assign kfei_dec_pre[39:24] = kstate[39:24];
    assign kfei_dec_pre[23:8]  = ks_sbox_out; //S-box sk 5th and sk 6th 
    assign kfei_dec_pre[7:0]   = kstate[7:0];
   
   //STATE 2: Feistel-like structure (DECRYPTION)
    wire [63:0] krot_dec;
    assign krot_dec[31:0]  = kfei_dec_pre[63:32];
    assign krot_dec[63:32] = kfei_dec_pre[63:32] ^ kfei_dec_pre[31:0];
   
    //STATE 3: Rotate (DECRYPTION)
    wire [63:0] nkstate_dec = {krot_dec[39:32], krot_dec[63:40], krot_dec[7:0], krot_dec[31:8]};
    
    //MUX : ENCRYPTION AND DECRYPTION 
    assign nkstate = is_fwd_key ? nkstate_enc : nkstate_dec;
endmodule

module Klein_Mixnibbles(idata, iinv, odata);
    input       wire    [31:0]   idata;
    input       wire             iinv;
    output      wire    [31:0]   odata;


////////////////////////////////////////////////////////////////////////
function [7 : 0] gm2(input [7 : 0] op);
  begin
    gm2 = {op[6:4], op[3]^op[7], op[2]^op[7], op[1], op[0]^op[7], op[7]}; //
  end
endfunction // gm2
////////////////////////////////////////////////////////////////////////


function [7 : 0] gm4(input [7 : 0] op);
  begin
    gm4 = gm2(gm2(op));
  end
endfunction // gm4

wire [7:0] w0, w1, w2, w3;    // data in
wire [7:0] a0, a1, a2, a3;    // mix data
wire [7:0] b0, b1, b2, b3;    // inv mix data

assign w0 = idata[31:24];
assign w1 = idata[23:16];
assign w2 = idata[15:08];
assign w3 = idata[07:00];

///////////////////////////////////////
wire [7:0] sum = w0 ^ w1 ^ w2 ^ w3;

assign a0 = gm2(w0 ^ w1) ^ sum ^ w0;
assign a1 = gm2(w1 ^ w2) ^ sum ^ w1;
assign a2 = gm2(w2 ^ w3) ^ sum ^ w2;
assign a3 = gm2(w3 ^ w0) ^ sum ^ w3;
/////////////////////////////////////


assign b0 = gm4(a0 ^ a2) ^ a0;
assign b1 = gm4(a1 ^ a3) ^ a1;
assign b2 = gm4(a0 ^ a2) ^ a2;
assign b3 = gm4(a1 ^ a3) ^ a3;

assign odata = (iinv) ? {b0, b1, b2, b3} : {a0, a1, a2, a3};

endmodule

module Klein_Sbox(in, out);
  input wire [3:0] in;
  output wire [3:0] out;
  
  reg [3:0] reg_out;
  
  assign out = reg_out;
  
  always @(*) begin
   case (in)
    4'h0: reg_out = 4'h7;
    4'h1: reg_out = 4'h4;
    4'h2: reg_out = 4'hA;
    4'h3: reg_out = 4'h9;
    4'h4: reg_out = 4'h1;
    4'h5: reg_out = 4'hF;
    4'h6: reg_out = 4'hB;
    4'h7: reg_out = 4'h0;
    4'h8: reg_out = 4'hC;
    4'h9: reg_out = 4'h3;
    4'hA: reg_out = 4'h2;
    4'hB: reg_out = 4'h6;
    4'hC: reg_out = 4'h8;
    4'hD: reg_out = 4'hE;
    4'hE: reg_out = 4'hD;
    4'hF: reg_out = 4'h5;
   default: reg_out = 4'h7;
  endcase 
 end 
  
endmodule 

