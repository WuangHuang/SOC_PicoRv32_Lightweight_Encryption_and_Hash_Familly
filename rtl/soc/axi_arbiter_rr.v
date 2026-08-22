// ============================================================
// axi_arbiter_rr.v — Parameterized AXI4-Lite N-to-1 Round-Robin Arbiter
// ============================================================
// N AXI4-Lite master ports share one AXI4-Lite slave port.
// Algorithm: Round-Robin (rotate priority)
// ============================================================

module axi_arbiter_rr #(
    parameter NUM_MASTERS = 2,
    parameter GW = (NUM_MASTERS > 1) ? $clog2(NUM_MASTERS) : 1
) (
    input  wire        clk,
    input  wire        resetn,

    // ID of the master currently granted the bus
    output reg  [GW-1:0] grant_id,

    // ---- Master Ports (packed vectors) ----
    input  wire [NUM_MASTERS-1:0]      m_awvalid,
    output wire [NUM_MASTERS-1:0]      m_awready,
    input  wire [NUM_MASTERS*32-1:0]   m_awaddr,
    input  wire [NUM_MASTERS*3-1:0]    m_awprot,

    input  wire [NUM_MASTERS-1:0]      m_wvalid,
    output wire [NUM_MASTERS-1:0]      m_wready,
    input  wire [NUM_MASTERS*32-1:0]   m_wdata,
    input  wire [NUM_MASTERS*4-1:0]    m_wstrb,

    output wire [NUM_MASTERS-1:0]      m_bvalid,
    input  wire [NUM_MASTERS-1:0]      m_bready,

    input  wire [NUM_MASTERS-1:0]      m_arvalid,
    output wire [NUM_MASTERS-1:0]      m_arready,
    input  wire [NUM_MASTERS*32-1:0]   m_araddr,
    input  wire [NUM_MASTERS*3-1:0]    m_arprot,

    output wire [NUM_MASTERS-1:0]      m_rvalid,
    input  wire [NUM_MASTERS-1:0]      m_rready,
    output wire [NUM_MASTERS*32-1:0]   m_rdata,

    // ---- Shared Slave Port (to AXI interconnect) ----
    output wire        s_awvalid,
    input  wire        s_awready,
    output wire [31:0] s_awaddr,
    output wire [ 2:0] s_awprot,

    output wire        s_wvalid,
    input  wire        s_wready,
    output wire [31:0] s_wdata,
    output wire [ 3:0] s_wstrb,

    input  wire        s_bvalid,
    output wire        s_bready,

    output wire        s_arvalid,
    input  wire        s_arready,
    output wire [31:0] s_araddr,
    output wire [ 2:0] s_arprot,

    input  wire        s_rvalid,
    output wire        s_rready,
    input  wire [31:0] s_rdata
);

    // Arbiter state machine states
    localparam STATE_IDLE  = 1'b0;
    localparam STATE_GRANT = 1'b1;

    reg state;
    reg [GW-1:0] last_grant;

    // Master requests are active if they initiate write address or read address transaction
    wire [NUM_MASTERS-1:0] m_req;
    genvar gi;
    generate
        for (gi = 0; gi < NUM_MASTERS; gi = gi + 1) begin : g_req
            assign m_req[gi] = m_awvalid[gi] | m_arvalid[gi];
        end
    endgenerate

    // Check if the current transaction has finished
    wire txn_done = (s_bvalid & s_bready) | (s_rvalid & s_rready);

    // Round-Robin selection logic
    reg [GW-1:0] next_grant;
    reg          next_grant_valid;

    // We compute next grant combinatorially
    reg [2:0] i;   // 1..NUM_MASTERS+1 : must hold the loop's exit value
    reg [31:0] idx;
    always @* begin
        next_grant = {GW{1'b0}};
        next_grant_valid = 1'b0;
        for (i = 1; i <= NUM_MASTERS; i = i + 1) begin
            idx = last_grant + i;
            if (idx >= NUM_MASTERS) begin
                idx = idx - NUM_MASTERS;
            end else begin
                idx = idx;
            end
            if (!next_grant_valid && m_req[idx]) begin
                next_grant = idx[GW-1:0];
                next_grant_valid = 1'b1;
            end else begin
                next_grant       = next_grant;
                next_grant_valid = next_grant_valid;
            end
        end
    end

    always @(posedge clk) begin
        if (!resetn) begin
            state      <= STATE_IDLE;
            last_grant <= {GW{1'b0}};
            grant_id   <= {GW{1'b0}};
        end else begin
            case (state)
                STATE_IDLE: begin
                    if (next_grant_valid) begin
                        state      <= STATE_GRANT;
                        grant_id   <= next_grant;
                        last_grant <= next_grant;
                    end else begin
                        state      <= state;
                        grant_id   <= grant_id;
                        last_grant <= last_grant;
                    end
                end
                STATE_GRANT: begin
                    if (txn_done) begin
                        state <= STATE_IDLE;
                    end else begin
                        state <= state;
                    end
                end
                default: state <= STATE_IDLE;
            endcase
        end
    end

    // Forwarding to the shared slave
    wire is_granted = (state == STATE_GRANT);

    assign s_awvalid = is_granted ? m_awvalid[grant_id] : 1'b0;
    assign s_awaddr  = m_awaddr[grant_id*32 +: 32];
    assign s_awprot  = m_awprot[grant_id*3 +: 3];

    assign s_wvalid  = is_granted ? m_wvalid[grant_id] : 1'b0;
    assign s_wdata   = m_wdata[grant_id*32 +: 32];
    assign s_wstrb   = m_wstrb[grant_id*4 +: 4];

    assign s_bready  = is_granted ? m_bready[grant_id] : 1'b0;

    assign s_arvalid = is_granted ? m_arvalid[grant_id] : 1'b0;
    assign s_araddr  = m_araddr[grant_id*32 +: 32];
    assign s_arprot  = m_arprot[grant_id*3 +: 3];

    assign s_rready  = is_granted ? m_rready[grant_id] : 1'b0;

    // Master port response assignment
    generate
        for (gi = 0; gi < NUM_MASTERS; gi = gi + 1) begin : g_master_out
            assign m_awready[gi] = is_granted && (grant_id == gi) && s_awready;
            assign m_wready[gi]  = is_granted && (grant_id == gi) && s_wready;
            assign m_bvalid[gi]  = is_granted && (grant_id == gi) && s_bvalid;

            assign m_arready[gi] = is_granted && (grant_id == gi) && s_arready;
            assign m_rvalid[gi]  = is_granted && (grant_id == gi) && s_rvalid;

            assign m_rdata[gi*32 +: 32] = s_rdata;
        end
    endgenerate

endmodule
