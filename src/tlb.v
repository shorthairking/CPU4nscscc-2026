module tlb
#(
    parameter TLBNUM = 8,
    parameter TLBSET = 4
)
(
    input  wire                      clk,
    input  wire                      rstn,
    // search port 0 (for fetch)
    input  wire [              18:0] s0_vppn,
    input  wire                      s0_va_odd,
    input  wire [               9:0] s0_asid,
    output wire                      s0_found,
    output wire [$clog2(TLBNUM*TLBSET)-1:0] s0_index,
    output wire [              19:0] s0_ppn,
    output wire [               5:0] s0_ps,
    output wire [               1:0] s0_plv,
    output wire [               1:0] s0_mat,
    output wire                      s0_d,
    output wire                      s0_v,

    // search port 1 (for load/store)
    input  wire [              18:0] s1_vppn,
    input  wire                      s1_va_odd,
    input  wire [               9:0] s1_asid,
    output wire                      s1_found,
    output wire [$clog2(TLBNUM*TLBSET)-1:0] s1_index,
    output wire [              19:0] s1_ppn,
    output wire [               5:0] s1_ps,
    output wire [               1:0] s1_plv,
    output wire [               1:0] s1_mat,
    output wire                      s1_d,
    output wire                      s1_v,

    // invtlb opcode
    input  wire                      invtlb_valid,
    input  wire [               4:0] invtlb_op,

    // write port
    input  wire                      we,     //w(rite) e(nable)
    input  wire                      tlbfill,
    input  wire [$clog2(TLBNUM*TLBSET)-1:0] rand_index,
    input  wire [$clog2(TLBNUM*TLBSET)-1:0] w_index,
    input  wire                      w_e,
    input  wire [              18:0] w_vppn,
    input  wire [               5:0] w_ps,
    input  wire [               9:0] w_asid,
    input  wire                      w_g,
    input  wire [              19:0] w_ppn0,
    input  wire [               1:0] w_plv0,
    input  wire [               1:0] w_mat0,
    input  wire                      w_d0,
    input  wire                      w_v0,
    input  wire [              19:0] w_ppn1,
    input  wire [               1:0] w_plv1,
    input  wire [               1:0] w_mat1,
    input  wire                      w_d1,
    input  wire                      w_v1,

    // read port
    input  wire [$clog2(TLBNUM*TLBSET)-1:0] r_index,
    output wire                      r_e,
    output wire [              18:0] r_vppn,
    output wire [               5:0] r_ps,
    output wire [               9:0] r_asid,
    output wire                      r_g,
    output wire [              19:0] r_ppn0,
    output wire [               1:0] r_plv0,
    output wire [               1:0] r_mat0,
    output wire                      r_d0,
    output wire                      r_v0,
    output wire [              19:0] r_ppn1,
    output wire [               1:0] r_plv1,
    output wire [               1:0] r_mat1,
    output wire                      r_d1,
    output wire                      r_v1
);

reg  [TLBNUM-1:0] tlb_e[TLBSET-1:0];
reg  [TLBNUM-1:0] tlb_ps4MB[TLBSET-1:0]; //pagesize 1:4MB, 0:4KB
reg  [      18:0] tlb_vppn     [TLBSET-1:0][TLBNUM-1:0];
reg  [       9:0] tlb_asid     [TLBSET-1:0][TLBNUM-1:0];
reg               tlb_g        [TLBSET-1:0][TLBNUM-1:0];
reg  [      19:0] tlb_ppn0     [TLBSET-1:0][TLBNUM-1:0];
reg  [       1:0] tlb_plv0     [TLBSET-1:0][TLBNUM-1:0];
reg  [       1:0] tlb_mat0     [TLBSET-1:0][TLBNUM-1:0];
reg               tlb_d0       [TLBSET-1:0][TLBNUM-1:0];
reg               tlb_v0       [TLBSET-1:0][TLBNUM-1:0];
reg  [      19:0] tlb_ppn1     [TLBSET-1:0][TLBNUM-1:0];
reg  [       1:0] tlb_plv1     [TLBSET-1:0][TLBNUM-1:0];
reg  [       1:0] tlb_mat1     [TLBSET-1:0][TLBNUM-1:0];
reg               tlb_d1       [TLBSET-1:0][TLBNUM-1:0];
reg               tlb_v1       [TLBSET-1:0][TLBNUM-1:0];

wire [TLBNUM-1:0] match0 [TLBSET-1:0];
wire [TLBNUM-1:0] match1 [TLBSET-1:0];

wire [TLBNUM-1:0] cond1[TLBSET-1:0];// G field is equal to 0
wire [TLBNUM-1:0] cond2[TLBSET-1:0];// G field is equal to 1
wire [TLBNUM-1:0] cond3[TLBSET-1:0];// s1_asid is equal to the ASID field
wire [TLBNUM-1:0] cond4[TLBSET-1:0];// s1_vppn matches the VPPN and PS fields
wire [TLBNUM-1:0] invtlb_cond[TLBSET-1:0];

wire  [1:0]real_w_row_index;
wire  [2:0]real_w_line_index;
wire  [1:0]real_r_row_index;
wire  [2:0]real_r_line_index;

//match s0
//--------------------------------------------------------------------------------------------
wire s0_row1_match;
wire s0_row2_match;
wire s0_row3_match;
wire s0_row4_match;
wire [2:0] s0_line1_match;
wire [2:0] s0_line2_match;
wire [2:0] s0_line3_match;
wire [2:0] s0_line4_match;
genvar s0_i_0;
generate
    for (s0_i_0 = 0; s0_i_0 < TLBNUM; s0_i_0 = s0_i_0 + 1) begin 
        wire row1_match0_vppn = (s0_vppn[18:9] == tlb_vppn[0][s0_i_0][18:9]);
        wire row1_match0_vppn_ps4MB = (tlb_ps4MB[0][s0_i_0] || s0_vppn[8:0] == tlb_vppn[0][s0_i_0][8:0]);
        wire row1_match0_asid = ((s0_asid == tlb_asid[0][s0_i_0]) || tlb_g[0][s0_i_0]);
        wire row1_match0_enabled = tlb_e[0][s0_i_0];

        assign match0[0][s0_i_0] = row1_match0_vppn && row1_match0_vppn_ps4MB && row1_match0_asid && row1_match0_enabled;
        //assign s0_line1_match = match0[0][s0_i_0] == 1 ?  s0_i_0 : 0;
    end
endgenerate
assign s0_line1_match = match0[0][0] == 1 ?  3'h0 : 
                        match0[0][1] == 1 ?  3'h1 : 
                        match0[0][2] == 1 ?  3'h2 : 
                        match0[0][3] == 1 ?  3'h3 : 
                        match0[0][4] == 1 ?  3'h4 : 
                        match0[0][5] == 1 ?  3'h5 : 
                        match0[0][6] == 1 ?  3'h6 : 
                        match0[0][7] == 1 ?  3'h7 : 3'h0;               

genvar s0_i_1;
generate
    for (s0_i_1 = 0; s0_i_1 < TLBNUM; s0_i_1 = s0_i_1 + 1) begin 
        wire row2_match0_vppn = (s0_vppn[18:9] == tlb_vppn[1][s0_i_1][18:9]);
        wire row2_match0_vppn_ps4MB = (tlb_ps4MB[1][s0_i_1] || s0_vppn[8:0] == tlb_vppn[1][s0_i_1][8:0]);
        wire row2_match0_asid = ((s0_asid == tlb_asid[1][s0_i_1]) || tlb_g[1][s0_i_1]);
        wire row2_match0_enabled = tlb_e[1][s0_i_1];

        assign match0[1][s0_i_1] = row2_match0_vppn && row2_match0_vppn_ps4MB && row2_match0_asid && row2_match0_enabled;
        //assign s0_line2_match = match0[1][s0_i_1] == 1 ?  s0_i_1 : 0;
    end
endgenerate
assign s0_line2_match = match0[1][0] == 1 ?  3'h0 : 
                        match0[1][1] == 1 ?  3'h1 : 
                        match0[1][2] == 1 ?  3'h2 : 
                        match0[1][3] == 1 ?  3'h3 : 
                        match0[1][4] == 1 ?  3'h4 : 
                        match0[1][5] == 1 ?  3'h5 : 
                        match0[1][6] == 1 ?  3'h6 : 
                        match0[1][7] == 1 ?  3'h7 : 3'h0;

genvar s0_i_2;
generate
    for (s0_i_2 = 0; s0_i_2 < TLBNUM; s0_i_2 = s0_i_2 + 1) begin 
        wire row3_match0_vppn = (s0_vppn[18:9] == tlb_vppn[2][s0_i_2][18:9]);
        wire row3_match0_vppn_ps4MB = (tlb_ps4MB[2][s0_i_2] || s0_vppn[8:0] == tlb_vppn[2][s0_i_2][8:0]);
        wire row3_match0_asid = ((s0_asid == tlb_asid[2][s0_i_2]) || tlb_g[2][s0_i_2]);
        wire row3_match0_enabled = tlb_e[2][s0_i_2];

        assign match0[2][s0_i_2] = row3_match0_vppn && row3_match0_vppn_ps4MB && row3_match0_asid && row3_match0_enabled;
        //assign s0_line3_match = match0[2][s0_i_2] == 1 ?  s0_i_2 : 0;
    end
endgenerate
assign s0_line3_match = match0[2][0] == 1 ?  3'h0 : 
                        match0[2][1] == 1 ?  3'h1 : 
                        match0[2][2] == 1 ?  3'h2 : 
                        match0[2][3] == 1 ?  3'h3 : 
                        match0[2][4] == 1 ?  3'h4 : 
                        match0[2][5] == 1 ?  3'h5 : 
                        match0[2][6] == 1 ?  3'h6 : 
                        match0[2][7] == 1 ?  3'h7 : 3'h0;

genvar s0_i_3;
generate
    for (s0_i_3 = 0; s0_i_3 < TLBNUM; s0_i_3 = s0_i_3 + 1) begin 
        wire row4_match0_vppn = (s0_vppn[18:9] == tlb_vppn[3][s0_i_3][18:9]);
        wire row4_match0_vppn_ps4MB = (tlb_ps4MB[3][s0_i_3] || s0_vppn[8:0] == tlb_vppn[3][s0_i_3][8:0]);
        wire row4_match0_asid = ((s0_asid == tlb_asid[3][s0_i_3]) || tlb_g[3][s0_i_3]);
        wire row4_match0_enabled = tlb_e[3][s0_i_3];

        assign match0[3][s0_i_3] = row4_match0_vppn && row4_match0_vppn_ps4MB && row4_match0_asid && row4_match0_enabled;
        //assign s0_line4_match = match0[3][s0_i_3] == 1 ?  s0_i_3 : 0;
    end
endgenerate
assign s0_line4_match = match0[3][0] == 1 ?  3'h0 : 
                        match0[3][1] == 1 ?  3'h1 : 
                        match0[3][2] == 1 ?  3'h2 : 
                        match0[3][3] == 1 ?  3'h3 : 
                        match0[3][4] == 1 ?  3'h4 : 
                        match0[3][5] == 1 ?  3'h5 : 
                        match0[3][6] == 1 ?  3'h6 : 
                        match0[3][7] == 1 ?  3'h7 : 3'h0;

assign s0_row1_match = |match0[0];
assign s0_row2_match = |match0[1];
assign s0_row3_match = |match0[2];
assign s0_row4_match = |match0[3];
assign s0_found = s0_row1_match | s0_row2_match | s0_row3_match |s0_row4_match;

reg [$clog2(TLBSET)-1:0]row1;
reg [$clog2(TLBNUM)-1:0]line1;
always@(*)begin
    row1 = s0_row1_match ? 2'h0 : 
                  s0_row2_match ? 2'h1 : 
                  s0_row3_match ? 2'h2 : 
                  s0_row4_match ? 2'h3 : 0;
    line1 = s0_row1_match ? s0_line1_match : 
                   s0_row2_match ? s0_line2_match : 
                   s0_row3_match ? s0_line3_match : 
                   s0_row4_match ? s0_line4_match : 0;
end

wire s0_select = s0_va_odd && !tlb_ps4MB[row1][line1]  || s0_vppn[8] && tlb_ps4MB[row1][line1];

assign s0_ppn = s0_select ? tlb_ppn1[row1][line1] : tlb_ppn0[row1][line1];
assign s0_ps  = tlb_ps4MB[row1][line1] ? 6'h15 : 6'hc;
assign s0_plv = s0_select ? tlb_plv1[row1][line1] : tlb_plv0[row1][line1];
assign s0_mat = s0_select ? tlb_mat1[row1][line1] : tlb_mat0[row1][line1];
assign s0_d   = s0_select ? tlb_d1[row1][line1] : tlb_d0[row1][line1];
assign s0_v   = s0_select ? tlb_v1[row1][line1] : tlb_v0[row1][line1];
assign s0_index = 8*row1 + line1 ;

//match s1
//-----------------------------------------------------------------------------------------------------------------                
wire s1_row1_match;
wire s1_row2_match;
wire s1_row3_match;
wire s1_row4_match;
wire [2:0] s1_line1_match;
wire [2:0] s1_line2_match;
wire [2:0] s1_line3_match;
wire [2:0] s1_line4_match;
genvar s1_i_0;
generate
    for (s1_i_0 = 0; s1_i_0 < TLBNUM; s1_i_0 = s1_i_0 + 1) begin 
        wire row1_match1_vppn = (s1_vppn[18:9] == tlb_vppn[0][s1_i_0][18:9]);
        wire row1_match1_vppn_ps4MB = (tlb_ps4MB[0][s1_i_0] || s1_vppn[8:0] == tlb_vppn[0][s1_i_0][8:0]);
        wire row1_match1_asid = ((s1_asid == tlb_asid[0][s1_i_0]) || tlb_g[0][s1_i_0]);
        wire row1_match1_enabled = tlb_e[0][s1_i_0];

        assign match1[0][s1_i_0] = row1_match1_vppn && row1_match1_vppn_ps4MB && row1_match1_asid && row1_match1_enabled;
        //assign s1_line1_match = match1[0][s1_i_0] == 1 ?  s1_i_0 : 0;
    end
endgenerate
assign s1_line1_match = match1[0][0] == 1 ?  3'h0 : 
                        match1[0][1] == 1 ?  3'h1 : 
                        match1[0][2] == 1 ?  3'h2 : 
                        match1[0][3] == 1 ?  3'h3 : 
                        match1[0][4] == 1 ?  3'h4 : 
                        match1[0][5] == 1 ?  3'h5 : 
                        match1[0][6] == 1 ?  3'h6 : 
                        match1[0][7] == 1 ?  3'h7 : 3'h0; 

genvar s1_i_1;
generate
    for (s1_i_1 = 0; s1_i_1 < TLBNUM; s1_i_1 = s1_i_1 + 1) begin 
        wire row2_match1_vppn = (s1_vppn[18:9] == tlb_vppn[1][s1_i_1][18:9]);
        wire row2_match1_vppn_ps4MB = (tlb_ps4MB[1][s1_i_1] || s1_vppn[8:0] == tlb_vppn[1][s1_i_1][8:0]);
        wire row2_match1_asid = ((s1_asid == tlb_asid[1][s1_i_1]) || tlb_g[1][s1_i_1]);
        wire row2_match1_enabled = tlb_e[1][s1_i_1];

        assign match1[1][s1_i_1] = row2_match1_vppn && row2_match1_vppn_ps4MB && row2_match1_asid && row2_match1_enabled;
        //assign s1_line2_match = match1[1][s1_i_1] == 1 ?  s1_i_1 : 0;
    end
endgenerate
assign s1_line2_match = match1[1][0] == 1 ?  3'h0 : 
                        match1[1][1] == 1 ?  3'h1 : 
                        match1[1][2] == 1 ?  3'h2 : 
                        match1[1][3] == 1 ?  3'h3 : 
                        match1[1][4] == 1 ?  3'h4 : 
                        match1[1][5] == 1 ?  3'h5 : 
                        match1[1][6] == 1 ?  3'h6 : 
                        match1[1][7] == 1 ?  3'h7 : 3'h0;

genvar s1_i_2;
generate
    for (s1_i_2 = 0; s1_i_2 < TLBNUM; s1_i_2 = s1_i_2 + 1) begin 
        wire row3_match1_vppn = (s1_vppn[18:9] == tlb_vppn[2][s1_i_2][18:9]);
        wire row3_match1_vppn_ps4MB = (tlb_ps4MB[2][s1_i_2] || s1_vppn[8:0] == tlb_vppn[2][s1_i_2][8:0]);
        wire row3_match1_asid = ((s1_asid == tlb_asid[2][s1_i_2]) || tlb_g[2][s1_i_2]);
        wire row3_match1_enabled = tlb_e[2][s1_i_2];

        assign match1[2][s1_i_2] = row3_match1_vppn && row3_match1_vppn_ps4MB && row3_match1_asid && row3_match1_enabled;
        //assign s1_line3_match = match1[2][s1_i_2] == 1 ?  s1_i_2 : 0;
    end
endgenerate
assign s1_line3_match = match1[2][0] == 1 ?  3'h0 : 
                        match1[2][1] == 1 ?  3'h1 : 
                        match1[2][2] == 1 ?  3'h2 : 
                        match1[2][3] == 1 ?  3'h3 : 
                        match1[2][4] == 1 ?  3'h4 : 
                        match1[2][5] == 1 ?  3'h5 : 
                        match1[2][6] == 1 ?  3'h6 : 
                        match1[2][7] == 1 ?  3'h7 : 3'h0;

genvar s1_i_3;
generate
    for (s1_i_3 = 0; s1_i_3 < TLBNUM; s1_i_3 = s1_i_3 + 1) begin 
        wire row4_match1_vppn = (s1_vppn[18:9] == tlb_vppn[3][s1_i_3][18:9]);
        wire row4_match1_vppn_ps4MB = (tlb_ps4MB[3][s1_i_3] || s1_vppn[8:0] == tlb_vppn[3][s1_i_3][8:0]);
        wire row4_match1_asid = ((s1_asid == tlb_asid[3][s1_i_3]) || tlb_g[3][s1_i_3]);
        wire row4_match1_enabled = tlb_e[3][s1_i_3];

        assign match1[3][s1_i_3] = row4_match1_vppn && row4_match1_vppn_ps4MB && row4_match1_asid && row4_match1_enabled;
        //assign s1_line4_match = match1[3][s1_i_3] == 1 ?  s1_i_3 : 0;
    end
endgenerate
assign s1_line4_match = match1[3][0] == 1 ?  3'h0 : 
                        match1[3][1] == 1 ?  3'h1 : 
                        match1[3][2] == 1 ?  3'h2 : 
                        match1[3][3] == 1 ?  3'h3 : 
                        match1[3][4] == 1 ?  3'h4 : 
                        match1[3][5] == 1 ?  3'h5 : 
                        match1[3][6] == 1 ?  3'h6 : 
                        match1[3][7] == 1 ?  3'h7 : 3'h0;

assign s1_row1_match = |match1[0];
assign s1_row2_match = |match1[1];
assign s1_row3_match = |match1[2];
assign s1_row4_match = |match1[3];
assign s1_found = s1_row1_match | s1_row2_match | s1_row3_match |s1_row4_match;

reg [$clog2(TLBSET)-1:0]row2;
reg [$clog2(TLBNUM)-1:0]line2;
always@(*)begin
     row2 = s1_row1_match ? 2'h0 : 
            s1_row2_match ? 2'h1 : 
            s1_row3_match ? 2'h2 : 
            s1_row4_match ? 2'h3 : 0;
            
     line2 = s1_row1_match ? s1_line1_match : 
             s1_row2_match ? s1_line2_match : 
             s1_row3_match ? s1_line3_match : 
             s1_row4_match ? s1_line4_match : 0;
end

wire s1_select = s1_va_odd && !tlb_ps4MB[row2][line2]  || s1_vppn[8] && tlb_ps4MB[row2][line2];

assign s1_ppn = s1_select ? tlb_ppn1[row2][line2] : tlb_ppn0[row2][line2];
assign s1_ps  = tlb_ps4MB[row2][line2] ? 6'h15 : 6'hc;
assign s1_plv = s1_select ? tlb_plv1[row2][line2] : tlb_plv0[row2][line2];
assign s1_mat = s1_select ? tlb_mat1[row2][line2] : tlb_mat0[row2][line2];
assign s1_d   = s1_select ? tlb_d1[row2][line2] : tlb_d0[row2][line2];
assign s1_v   = s1_select ? tlb_v1[row2][line2] : tlb_v0[row2][line2];
assign s1_index = 8*row2 + line2 ;

//write logic

assign real_w_row_index = tlbfill ? rand_index[4:3] : w_index[4:3];
assign real_w_line_index = tlbfill ? rand_index[2:0] : w_index[2:0];
always @(posedge clk or negedge rstn) begin
    if (~rstn) begin:ini
        // initial tlb_e
        integer i, j;
        for (i = 0; i < TLBSET; i = i + 1) begin
            for (j = 0; j < TLBNUM; j = j + 1) begin
                tlb_e[i][j]      <= 0;
                tlb_ps4MB[i][j]  <= 0;
                tlb_vppn[i][j]   <= 0;
                tlb_asid[i][j]   <= 0;
                tlb_g[i][j]      <= 0;
                tlb_ppn0[i][j]   <= 0;
                tlb_plv0[i][j]   <= 0;
                tlb_mat0[i][j]   <= 0;
                tlb_d0[i][j]     <= 0;
                tlb_v0[i][j]     <= 0;
                tlb_ppn1[i][j]   <= 0;
                tlb_plv1[i][j]   <= 0;
                tlb_mat1[i][j]   <= 0;
                tlb_d1[i][j]     <= 0;
                tlb_v1[i][j]     <= 0;
            end
        end
    end
    else if(we) begin
        tlb_e[real_w_row_index][real_w_line_index]     <= w_e;
        tlb_ps4MB[real_w_row_index][real_w_line_index] <= w_ps == 6'h15 ? 1 : 0;
        tlb_vppn[real_w_row_index][real_w_line_index]  <= w_vppn;
        tlb_asid[real_w_row_index][real_w_line_index]  <= w_asid;
        tlb_g[real_w_row_index][real_w_line_index]     <= w_g;
        tlb_ppn0[real_w_row_index][real_w_line_index]  <= w_ppn0;
        tlb_plv0[real_w_row_index][real_w_line_index]  <= w_plv0;
        tlb_mat0[real_w_row_index][real_w_line_index]  <= w_mat0;
        tlb_d0[real_w_row_index][real_w_line_index]    <= w_d0;
        tlb_v0[real_w_row_index][real_w_line_index]    <= w_v0;
        tlb_ppn1[real_w_row_index][real_w_line_index]  <= w_ppn1;
        tlb_plv1[real_w_row_index][real_w_line_index]  <= w_plv1;
        tlb_mat1[real_w_row_index][real_w_line_index]  <= w_mat1;
        tlb_d1[real_w_row_index][real_w_line_index]    <= w_d1;
        tlb_v1[real_w_row_index][real_w_line_index]    <= w_v1;
    end
    else if(invtlb_valid)begin
        if(invtlb_cond[0][0]) tlb_e[0][0] <= 0;
        if(invtlb_cond[0][1]) tlb_e[0][1] <= 0;
        if(invtlb_cond[0][2]) tlb_e[0][2] <= 0;
        if(invtlb_cond[0][3]) tlb_e[0][3] <= 0;
        if(invtlb_cond[0][4]) tlb_e[0][4] <= 0;
        if(invtlb_cond[0][5]) tlb_e[0][5] <= 0;
        if(invtlb_cond[0][6]) tlb_e[0][6] <= 0;
        if(invtlb_cond[0][7]) tlb_e[0][7] <= 0;
        if(invtlb_cond[1][0]) tlb_e[1][0] <= 0;
        if(invtlb_cond[1][1]) tlb_e[1][1] <= 0;
        if(invtlb_cond[1][2]) tlb_e[1][2] <= 0;
        if(invtlb_cond[1][3]) tlb_e[1][3] <= 0;
        if(invtlb_cond[1][4]) tlb_e[1][4] <= 0;
        if(invtlb_cond[1][5]) tlb_e[1][5] <= 0;
        if(invtlb_cond[1][6]) tlb_e[1][6] <= 0;
        if(invtlb_cond[1][7]) tlb_e[1][7] <= 0;
        if(invtlb_cond[2][0]) tlb_e[2][0] <= 0;
        if(invtlb_cond[2][1]) tlb_e[2][1] <= 0;
        if(invtlb_cond[2][2]) tlb_e[2][2] <= 0;
        if(invtlb_cond[2][3]) tlb_e[2][3] <= 0;
        if(invtlb_cond[2][4]) tlb_e[2][4] <= 0;
        if(invtlb_cond[2][5]) tlb_e[2][5] <= 0;
        if(invtlb_cond[2][6]) tlb_e[2][6] <= 0;
        if(invtlb_cond[2][7]) tlb_e[2][7] <= 0;
        if(invtlb_cond[3][0]) tlb_e[3][0] <= 0;
        if(invtlb_cond[3][1]) tlb_e[3][1] <= 0;
        if(invtlb_cond[3][2]) tlb_e[3][2] <= 0;
        if(invtlb_cond[3][3]) tlb_e[3][3] <= 0;
        if(invtlb_cond[3][4]) tlb_e[3][4] <= 0;
        if(invtlb_cond[3][5]) tlb_e[3][5] <= 0;
        if(invtlb_cond[3][6]) tlb_e[3][6] <= 0;
        if(invtlb_cond[3][7]) tlb_e[3][7] <= 0;
    end
end

//read logic
assign real_r_row_index = r_index[4:3];
assign real_r_line_index = r_index[2:0];
assign r_e   = tlb_e[real_r_row_index][real_r_line_index];
assign r_vppn= tlb_vppn[real_r_row_index][real_r_line_index];
assign r_ps  = tlb_ps4MB[real_r_row_index][real_r_line_index] ? 6'h15 : 6'hc;
assign r_asid= tlb_asid[real_r_row_index][real_r_line_index];
assign r_g   = tlb_g[real_r_row_index][real_r_line_index];
assign r_ppn0= tlb_ppn0[real_r_row_index][real_r_line_index];
assign r_plv0= tlb_plv0[real_r_row_index][real_r_line_index];
assign r_mat0= tlb_mat0[real_r_row_index][real_r_line_index];
assign r_d0  = tlb_d0[real_r_row_index][real_r_line_index];
assign r_v0  = tlb_v0[real_r_row_index][real_r_line_index];
assign r_ppn1= tlb_ppn1[real_r_row_index][real_r_line_index];
assign r_plv1= tlb_plv1[real_r_row_index][real_r_line_index];
assign r_mat1= tlb_mat1[real_r_row_index][real_r_line_index];
assign r_d1  = tlb_d1[real_r_row_index][real_r_line_index];
assign r_v1  = tlb_v1[real_r_row_index][real_r_line_index];

//invtlb logic
//cond1
genvar i_1;
genvar j_1;
generate
    for(i_1=0; i_1 < TLBSET; i_1 = i_1 + 1)begin
        for(j_1 = 0; j_1 < TLBNUM; j_1 = j_1 + 1)begin
            assign cond1[i_1][j_1] = ~tlb_g[i_1][j_1];
        end
    end
endgenerate


//cond2
genvar i_2;
genvar j_2;
generate
    for(i_2=0; i_2 < TLBSET; i_2 = i_2 + 1)begin
        for(j_2 = 0; j_2 < TLBNUM; j_2 = j_2 + 1)begin
            assign cond2[i_2][j_2] = tlb_g[i_2][j_2];
        end
    end
endgenerate

//cond3 
genvar i_3;
genvar j_3;
generate
    for(i_3=0; i_3 < TLBSET; i_3 = i_3 + 1)begin
        for(j_3 = 0; j_3 < TLBNUM; j_3 = j_3 + 1)begin
            assign cond3[i_3][j_3] = s1_asid==tlb_asid[i_3][j_3];
        end
    end
endgenerate

//cond4
genvar i_4;
genvar j_4;
generate
    for (i_4 = 0; i_4 < TLBSET; i_4 = i_4 + 1)begin  
        for(j_4 = 0; j_4 < TLBNUM; j_4 = j_4 +1)begin
            assign cond4[i_4][j_4] = (s1_vppn[18: 9] == tlb_vppn[i_4][j_4][18: 9]) &&(tlb_ps4MB[i_4][j_4] || s1_vppn[8:0] == tlb_vppn[i_4][j_4][8:0]);
        end
    end
endgenerate

//invtlb_cond
genvar i;
generate
    for(i = 0; i < TLBSET; i = i + 1)begin
    assign invtlb_cond[i] = invtlb_op == 5'b0 ? cond1[i] | cond2[i] :
                     invtlb_op == 5'b1 ? cond1[i] | cond2[i] :
                     invtlb_op == 5'h2 ? cond2[i]         :
                     invtlb_op == 5'h3 ? cond1[i]         :
                     invtlb_op == 5'h4 ? cond1[i] & cond3[i] :
                     invtlb_op == 5'h5 ? cond1[i] & cond3[i] & cond4[i]:
                     invtlb_op == 5'h6 ? (cond2[i] | cond3[i]) & cond4[i] :
                     16'h0;
    end
endgenerate
endmodule
