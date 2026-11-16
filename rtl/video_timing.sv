
module video_timing
(
    input       clk,
    input       clk_pix,
    input       reset,

    input  signed [3:0] hs_offset,
    input  signed [3:0] vs_offset,

    output [8:0] hc,
    output [8:0] vc,

    output reg  hsync,
    output reg  vsync,
    
    output reg  hbl,
    output reg  vbl 
);

// 6MHz
wire [8:0] HBL_START  = 256;
wire [8:0] HS_START   = 300;
wire [8:0] HS_END     = 332;
wire [8:0] HTOTAL     = 383;

wire [8:0] VBL_START  = 239;
wire [8:0] VBL_END    = 16;
wire [8:0] VS_START   = 251;
wire [8:0] VS_END     = 259;
wire [8:0] VTOTAL     = 263;

reg [8:0] v;
reg [8:0] h;

assign vc = v;
assign hc = h;

// sync edges moved by the sign-extended OSD offsets
wire [8:0] hs_adj   = {{5{hs_offset[3]}}, hs_offset};
wire [8:0] vs_adj   = {{5{vs_offset[3]}}, vs_offset};
wire [8:0] hs_start = HS_START + hs_adj;
wire [8:0] hs_end   = HS_END + hs_adj;
wire [8:0] vs_start = VS_START + vs_adj;
wire [8:0] vs_end_n = VS_END + vs_adj;
// a v-sync pulse that runs past the last line ends in the next frame
wire [8:0] vs_end   = (vs_end_n >= VTOTAL) ? vs_end_n - VTOTAL : vs_end_n;

always @ (posedge clk) begin
	if (reset) begin
		h <= 0;
		v <= 0;

		hbl <= 0;
		vbl <= 0;

        hsync <= 0;
        vsync <= 0;
	end else if ( clk_pix == 1 ) begin 
	// counter
    if (h == HTOTAL) begin
        h <= 0;
        hbl <= 0;

        v <= v + 1'd1;                

        if ( v == VTOTAL-1 ) begin
            v <= 0;
        end

        end else begin
            h <= h + 1'd1;
        end

        // h signals
        if ( h == HBL_START-1 ) begin
            hbl <= 1;
        end 

        // v signals
        if ( v == VBL_START ) begin
            vbl <= 1;
        end else if ( v == VBL_END-1 ) begin
            vbl <= 0;
        end
    end
   
    if ( v == vs_start ) begin
        vsync <= 1;
    end else if ( v == vs_end ) begin
        vsync <= 0;
    end

    if ( h == hs_start ) begin
        hsync <= 1;
    end else if ( h == hs_end ) begin
        hsync <= 0;
    end

end

endmodule


