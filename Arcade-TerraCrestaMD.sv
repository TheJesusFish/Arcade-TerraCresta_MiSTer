//============================================================================
//
//  This program is free software; you can redistribute it and/or modify it
//  under the terms of the GNU General Public License as published by the Free
//  Software Foundation; either version 2 of the License, or (at your option)
//  any later version.
//
//  This program is distributed in the hope that it will be useful, but WITHOUT
//  ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
//  FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for
//  more details.
//
//  You should have received a copy of the GNU General Public License along
//  with this program; if not, write to the Free Software Foundation, Inc.,
//  51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.
//

// Darren Olafson 2022
//
// Jun 2022 -- added screen flip from https://github.com/gyurco/Mist_FPGA
//============================================================================

`default_nettype none

module emu
(
	`include "sys/emu_ports.vh"
);

///////// Default values for ports not used in this core /////////

assign ADC_BUS  = 'Z;
assign USER_OUT = '1;
assign {UART_RTS, UART_TXD, UART_DTR} = 0;
assign {SD_SCK, SD_MOSI, SD_CS} = 'Z;
assign {SDRAM_DQ, SDRAM_A, SDRAM_BA, SDRAM_CLK, SDRAM_CKE, SDRAM_DQML, SDRAM_DQMH, SDRAM_nWE, SDRAM_nCAS, SDRAM_nRAS, SDRAM_nCS} = 'Z;

assign VGA_F1 = 0;
assign VGA_SCALER = 0;
assign VGA_DISABLE = 0;
assign HDMI_FREEZE = 0;
assign HDMI_BLACKOUT = 0;
assign HDMI_BOB_DEINT = 0;
assign FB_FORCE_BLANK = 0;

assign AUDIO_MIX = 0;
assign LED_USER = ss_busy_any;
assign LED_DISK = 0;
assign LED_POWER = 0;
assign BUTTONS = 0;

// Status Bit Map:
//              Upper                          Lower                
// 0         1         2         3          4         5         6   
// 01234567890123456789012345678901 23456789012345678901234567890123
// 0123456789ABCDEFGHIJKLMNOPQRSTUV 0123456789ABCDEFGHIJKLMNOPQRSTUV
// X   XXX XXXX          XXXXXXXXXX XXXXXXX                         
// status[70:64]: save-state slot/save/restore, hiscore autosave/save

wire [1:0] aspect_ratio = status[9:8];
wire orientation = status[10];
wire [2:0] scan_lines = status[6:4];
wire [3:0] hs_offset = status[27:24];
wire [3:0] vs_offset = status[31:28];

wire test_flip_x = status[32];
wire test_flip_y = status[33];
wire fg_enable   = ~(status[36] | key_fg_enable);
wire bg_enable   = ~(status[37] | key_bg_enable);
wire spr_enable  = ~(status[38] | key_spr_enable);

assign VIDEO_ARX = (!aspect_ratio) ? (orientation  ? 8'd4 : 8'd3) : (aspect_ratio - 1'd1);
assign VIDEO_ARY = (!aspect_ratio) ? (orientation  ? 8'd3 : 8'd4) : 12'd0;

`include "build_id.v" 

// save-state register chunk: board registers, OPL select, z80 irq, 68000 irq
localparam MISC_BITS = 97 + 8 + 2;

localparam CONF_STR = {
    "TerraCrestaMD;SS3E000000:400000;",
    "-;",
    "P1,Video Settings;",
    "P1-;",
    "P1O89,Aspect ratio,Original,Full Screen,[ARC1],[ARC2];",
    "P1OA,Orientation,Vert,Horz;",
    "P1-;",
    "P1O46,Scandoubler Fx,None,HQ2x,CRT 25%,CRT 50%,CRT 75%,CRT 100%;",
    "P1OB,Force Scandoubler,Off,On;",
    "P1-;",
    "P1OOR,H-sync Adjust,0,1,2,3,4,5,6,7,-8,-7,-6,-5,-4,-3,-2,-1;",
    "P1OSV,V-sync Adjust,0,1,2,3,4,5,6,7,-8,-7,-6,-5,-4,-3,-2,-1;",
    "P2,Pause Options;",
    "P2-;",
    "P2OM,Pause when OSD is open,Off,On;",
    "P2ON,Dim video after 10s,Off,On;",
    "P3,PCB & Debug Settings;",
    "P3-;",
    "h1P3o2,Turbo (Amazon Sets),Off,On;",
    "P3o3,Service Menu,Off,On;",
    "P3-;",
    "P3o5,Foreground Layer,On,Off;",
    "P3o4,Background Layer,On,Off;",
    "P3o6,Sprites,On,Off;",
    "P3-;",
    "P3o0,Invert Sprite X-Axis,Off,On;",
    "P3o1,Invert Sprite Y-Axis,Off,On;",
    "-;",
    "h2O[69],Autosave Hiscores,On,Off;",
    "h2T[70],Save Hiscores;",
    "h2-;",
    "O[66:65],Savestate Slot,1,2,3,4;",
    "O[64],Autoincrement Slot,Off,On;",
    "R[67],Save state (Alt-F1);",
    "R[68],Restore state (F1);",
    "-;",
    "DIP;",
    "-;",
    "R0,Reset;",
    "I,",
    "Hold L: Up=Load Down=Save Left/Right=Slot,",
    "Active Slot 1,",
    "Active Slot 2,",
    "Active Slot 3,",
    "Active Slot 4,",
    "Save to state 1,",
    "Restore state 1,",
    "Save to state 2,",
    "Restore state 2,",
    "Save to state 3,",
    "Restore state 3,",
    "Save to state 4,",
    "Restore state 4;",
    "v,1;",
    "V,v",`BUILD_DATE
};

wire hps_forced_scandoubler;
wire forced_scandoubler = hps_forced_scandoubler | status[11];

wire  [1:0] buttons;
wire [127:0] status;
wire [10:0] ps2_key;
wire [31:0] joy0_full, joy1_full;
wire [15:0] joy0 = joy0_full[15:0];
wire [15:0] joy1 = joy1_full[15:0];

wire        ss_status_set;
wire  [1:0] ss_slot;
wire        ss_info_req;
wire  [7:0] ss_info;
wire [127:0] status_in = {status[127:67], ss_slot, status[64:0]};

hps_io #(.CONF_STR(CONF_STR)) hps_io
(
    .clk_sys(clk_sys),
    .HPS_BUS(HPS_BUS),

    .buttons(buttons),
    .ps2_key(ps2_key),
    .status(status),
    .status_in(status_in),
    .status_set(ss_status_set),
    .status_menumask({13'd0, hs_has_entries, pcb_amazon, direct_video}),
    .info_req(ss_info_req),
    .info(ss_info),
    .forced_scandoubler(hps_forced_scandoubler),
    .gamma_bus(gamma_bus),
    .direct_video(direct_video),
    .video_rotated(video_rotated),

    .ioctl_download(ioctl_download),
    .ioctl_upload(ioctl_upload),
    .ioctl_upload_req(ioctl_upload_req),
    .ioctl_upload_index(8'd4),
    .ioctl_wr(ioctl_wr),
    .ioctl_addr(ioctl_addr),
    .ioctl_dout(ioctl_dout),
    .ioctl_din(ioctl_din),
    .ioctl_index(ioctl_index),
    .ioctl_wait(ioctl_wait),

    .joystick_0(joy0_full),
    .joystick_1(joy1_full)
);

// INPUT

// 8 dip switches of 8 bits
reg [7:0] sw[8];
always @(posedge clk_sys) begin
    if (ioctl_wr && (ioctl_index==254) && !ioctl_addr[24:3]) begin
        sw[ioctl_addr[2:0]] <= ioctl_dout;
    end
end

wire        direct_video;

wire        ioctl_download;
wire        ioctl_upload;
wire        ioctl_upload_req;
wire        ioctl_wait = 1'b0;
wire        ioctl_wr;
wire [15:0] ioctl_index;
wire [26:0] ioctl_addr;
wire  [7:0] ioctl_dout;
wire  [7:0] ioctl_din;

wire [21:0] gamma_bus;

// ROM load holds the game in reset until the boot-time DIP push has arrived
wire rom_download = ioctl_download && (ioctl_index==0);
reg  load_hold;
always @(posedge clk_sys) begin
    reg        old_dl;
    reg [24:0] timeout;

    old_dl <= ioctl_download;
    if (rom_download) begin
        load_hold <= 1;
        timeout   <= 0;
    end else if (load_hold) begin
        if (old_dl && !ioctl_download && ioctl_index == 254) load_hold <= 0;
        else if (!ioctl_download) begin
            timeout <= timeout + 1'd1;
            if (&timeout) load_hold <= 0;
        end
    end
end

// game-visible DIP switches change only at reset
reg [15:0] dsw_latch;
reg        svc_dip;
always @(posedge clk_sys) begin
    if (reset) begin
        dsw_latch <= {sw[1], sw[0]};
        svc_dip   <= sw[3][5];
    end
end

reg [15:0] p1 ;
reg [15:0] p2 ;
reg [15:0] dsw1 ;
reg [15:0] sys ;

//localparam pcb_terra_cresta = 0;
//localparam pcb_amazon       = 1;
//localparam pcb_horekid      = 2;
//localparam pcb_amazont      = 3;
//localparam pcb_horekidb2    = 4;

wire pcb_amazon = (pcb == 1 || pcb == 3);
wire turbo      = status[34] & pcb_amazon;

always @ (posedge clk_sys) begin
    p1 <= 16'hffff;
    p1[5:0] <= ~{ p1_buttons[1:0], p1_right, p1_left ,p1_down, p1_up};
     
    p2 <= 16'hffff;
    p2[5:0] <= ~{ p2_buttons[1:0], p2_right, p2_left ,p2_down, p2_up};
    
    sys <= 16'hffff;
    if ( pcb == 0 || pcb == 2 ) begin
        // terracre and horekid
        // PORT_BIT( 0x0100, IP_ACTIVE_LOW, IPT_START1 )
        // PORT_BIT( 0x0200, IP_ACTIVE_LOW, IPT_START2 )
        sys[8] <= ~p1_start ;
        sys[9] <= ~p2_start ;
    end else begin
        // amatelas, amazon, amazont and horekidb2
        // PORT_BIT( 0x0100, IP_ACTIVE_LOW, IPT_START2 )
        // PORT_BIT( 0x0200, IP_ACTIVE_LOW, IPT_START1 )
        sys[8] <= ~p2_start ;
        sys[9] <= ~p1_start ;
    end
    sys[10] <= ~p1_coin ;
    sys[11] <= ~p2_coin ;
    sys[12] <= ~key_service;

    if ( pcb == 0 || pcb == 1 || pcb == 3 ) begin
        // terracre / amazon: Service Mode dip (MRA bit 29)
        sys[13] <= svc_dip & ~service ;
    end else begin
        // horekid: service button
        sys[13] <= ~service ;
    end
    
    dsw1 <= { dsw_latch[15:8], dsw_latch[7] & ~turbo, dsw_latch[6:0] };
end

// pad 1 is muted for the game while L (save/load) is held
wire [9:0] j0 = joy0[9] ? 10'd0 : joy0[9:0];
wire [9:0] j1 = joy1[9:0];

wire       p1_up      = j0[3] | key_p1_up;
wire       p1_down    = j0[2] | key_p1_down;
wire       p1_left    = j0[1] | key_p1_left;
wire       p1_right   = j0[0] | key_p1_right;
wire [1:0] p1_buttons = j0[5:4] | {key_p1_b, key_p1_a};

wire       p2_up      = j1[3] | key_p2_up;
wire       p2_down    = j1[2] | key_p2_down;
wire       p2_left    = j1[1] | key_p2_left;
wire       p2_right   = j1[0] | key_p2_right;
wire [1:0] p2_buttons = j1[5:4] | {key_p2_b, key_p2_a};

wire p1_start = j0[6] | key_p1_start;
wire p2_start = j1[6] | key_p2_start | turbo;
wire p1_coin  = j0[7] | key_p1_coin;
wire p2_coin  = j1[7] | key_p2_coin;
wire b_pause  = j0[8] | j1[8] | key_pause;
wire service  = key_test | status[35];

// Keyboard handler

wire key_p1_start, key_p2_start, key_p1_coin, key_p2_coin;
wire key_test, key_reset, key_service, key_pause;
wire key_fg_enable, key_bg_enable, key_spr_enable;

wire key_p1_up, key_p1_left, key_p1_down, key_p1_right, key_p1_a, key_p1_b;
wire key_p2_up, key_p2_left, key_p2_down, key_p2_right, key_p2_a, key_p2_b;

wire pressed = ps2_key[9];

always @(posedge clk_sys) begin
    reg old_state;

    old_state <= ps2_key[10];
    if(old_state ^ ps2_key[10]) begin
        casex(ps2_key[8:0])
            'h016: key_p1_start   <= pressed; // 1
            'h01e: key_p2_start   <= pressed; // 2
            'h02E: key_p1_coin    <= pressed; // 5
            'h036: key_p2_coin    <= pressed; // 6
            'h006: key_test       <= key_test ^ pressed; // f2
            'h004: key_reset      <= pressed; // f3
            'h046: key_service    <= pressed; // 9
            'h04D: key_pause      <= pressed; // p

            'hX75: key_p1_up      <= pressed; // up
            'hX72: key_p1_down    <= pressed; // down
            'hX6b: key_p1_left    <= pressed; // left
            'hX74: key_p1_right   <= pressed; // right
            'h014: key_p1_a       <= pressed; // lctrl
            'h011: key_p1_b       <= pressed; // lalt

            'h02d: key_p2_up      <= pressed; // r
            'h02b: key_p2_down    <= pressed; // f
            'h023: key_p2_left    <= pressed; // d
            'h034: key_p2_right   <= pressed; // g
            'h01c: key_p2_a       <= pressed; // a
            'h01b: key_p2_b       <= pressed; // s

            'h083: key_fg_enable  <= key_fg_enable ^ pressed; // f7
            'h00A: key_bg_enable  <= key_bg_enable ^ pressed; // f8
            'h001: key_spr_enable <= key_spr_enable ^ pressed; // f9
        endcase
    end
end

// PAUSE SYSTEM
wire    pause_cpu;
wire    hs_pause = 1'b0;


// 8 bits per colour, 72MHz sys clk
pause #(8,8,8,72) pause 
(
    .clk_sys(clk_sys),
    .reset(reset),
    .user_button(b_pause),
    .pause_request(hs_pause),
    .options(status[23:22]),
    .pause_cpu(pause_cpu),
    .dim_video(dim_video),
    .OSD_STATUS(OSD_STATUS),
    .r(rgb[23:16]),
    .g(rgb[15:8]),
    .b(rgb[7:0]),
    .rgb_out(rgb_pause_out)
);

wire [23:0] rgb_pause_out;
wire dim_video;

reg  cocktail_flip;
wire flip = cocktail_flip;

wire pll_locked;

wire clk_sys;
// clk_sys enable pulses; ce_* fire one clk_sys before the matching clk_* pulse
reg  clk_4M,clk_8M,clk_6M,clk_16M,clk_ym;
reg  ce_16m, ce_8m, ce_6m;

pll pll
(
    .refclk(CLK_50M),
    .rst(0),
    .outclk_0(clk_sys),     // 96
    .locked(pll_locked)
);

reg [5:0] clk16_count;
reg [5:0] clk8_count;
reg [5:0] clk4_count;
reg [5:0] clk6_count;
reg [15:0] clk_ym_count;

always @ (posedge clk_sys) begin

    clk_16M <= ( clk16_count == 6'd0 );
    ce_16m  <= ( clk16_count == 6'd5 );

    if ( clk16_count == 6'd5 ) begin
        clk16_count <= 6'd0;
    end else begin
        clk16_count <= clk16_count + 6'd1;
    end

    clk_8M <= ( clk8_count == 6'd0 );
    ce_8m  <= ( clk8_count == 6'd11 );

    if ( clk8_count == 6'd11 ) begin
        clk8_count <= 6'd0;
    end else begin
        clk8_count <= clk8_count + 6'd1;
    end

    clk_4M <= ( clk4_count == 6'd0 );

    if ( clk4_count == 6'd23 ) begin
        clk4_count <= 6'd0;
    end else begin
        clk4_count <= clk4_count + 6'd1;
    end

    clk_6M <= ( clk6_count == 6'd0 );
    ce_6m  <= ( clk6_count == 6'd15 );

    if ( clk6_count == 6'd15 ) begin
        clk6_count <= 6'd0;
    end else begin
        clk6_count <= clk6_count + 6'd1;
    end

    clk_ym <= ( clk_ym_count == 16'd0 ) & snd_run;

    if ( snd_run ) begin
        if ( clk_ym_count == 16'd12287 ) begin  // 4MHz / 512 = 7.8KHz
            clk_ym_count <= 16'd0;
        end else begin
            clk_ym_count <= clk_ym_count + 16'd1;
        end
    end
     
end

wire    reset;
assign  reset = RESET | status[0] | key_reset | load_hold;

//////////////////////////////////////////////////////////////////
wire rotate_ccw = 1;
wire no_rotate = orientation | direct_video;
wire video_rotated ;

reg [23:0]     rgb;

wire hbl;
wire vbl;

wire [8:0] hc;
wire [8:0] vc;

wire hsync;
wire vsync;

wire hbl_delay, vbl_delay;

delay delay_hbl( .clk(clk_sys), .ce(ce_6m), .i( hbl ), .o(hbl_delay) ) ;
delay delay_vbl( .clk(clk_sys), .ce(ce_6m), .i( vbl ), .o(vbl_delay) ) ;

video_timing video_timing (
    .clk(clk_sys),
    .clk_pix(clk_6M),
    .hc(hc),
    .vc(vc),
    .hs_offset(hs_offset),
    .vs_offset(vs_offset),
    .hbl(hbl),
    .vbl(vbl),
    .hsync(hsync),
    .vsync(vsync)
);

screen_rotate screen_rotate
(
    .*,
    .flip(1'b0),
    .DDRAM_CLK(),
    .DDRAM_BUSY(rot_busy),
    .DDRAM_BURSTCNT(rot_burstcnt),
    .DDRAM_ADDR(rot_addr),
    .DDRAM_DIN(rot_din),
    .DDRAM_BE(rot_be),
    .DDRAM_WE(rot_we),
    .DDRAM_RD(rot_rd)
);

arcade_video #(256,24) arcade_video
(
        .*,

        .clk_video(clk_sys),
        .ce_pix(clk_6M),

        .RGB_in(rgb_pause_out),

        .HBlank(hbl_delay),
        .VBlank(vbl_delay),
        .HSync(hsync),
        .VSync(vsync),

        .fx(scan_lines)
);

// sprite line buffer read, registered (used at the next pixel tick)
reg [11:0] spr_pix;
always @(posedge clk_sys) spr_pix <= sprite_line_buffer[hc_x];

// prom_s = idx 

reg   [7:0] spi, spi_r;
reg         spr_transp, spr_transp_r;


// Flipped tilemap position is (255 - pos) + scroll, as in MAME. No +256: the
// original "~hc[7:0] + scroll_x + 9'd256" widened hc before inverting, so the
// set upper bits plus 256 wrapped to zero.
wire  [9:0] hc_s = {2'b0, hc[7:0] ^ {8{flip}}} + scroll_x[9:0];
wire  [8:0] vc_s = {1'b0, vc[7:0] ^ {8{flip}}} + scroll_y[8:0];

wire  [8:0] hc_x = {hc[8], hc[7:0] ^ {8{flip}}};
wire  [8:0] vc_x = vc ^ {9{flip}};

reg  [3:0] gfx1_pix ;
reg  [7:0] gfx2_pix ;

wire [10:0] bg_tile = { hc_s[9:4], vc_s[8:4] };
wire  [9:0] fg_tile = { hc_x[7:3], vc_x[7:3] };
wire [10:0] bg_ram_addr = bg_tile;
wire [10:0] fg_ram_addr = { 1'b0, fg_tile };

reg [7:0] pal_idx;

always @ (posedge clk_sys) begin
    if (clk_6M) begin
        rgb <= { prom_r[pal_idx], 4'b0, prom_g[pal_idx], 4'b0, prom_b[pal_idx], 4'b0 };
    end
end

reg [7:0] gfxc ;

reg [15:0] fg_ram_dout_buf;
reg [15:0] bg_ram_dout_buf;

wire     [7:0] gfx1_dout;
wire     [7:0] gfx2_dout;
wire    [63:0] gfx3_dout;

reg    [13:0] gfx1_addr;
reg    [16:0] gfx2_addr;

reg [8:0] hc_r;
reg [8:0] hc_s_r;
reg [1:0] gfx2_pal_h;
reg [1:0] gfx2_pal_l;

always @ (posedge clk_sys) begin
    if (clk_6M == 1) begin
    // 0
        gfx1_addr <= { 1'b0 , fg_ram_dout[7:0],   vc_x[2:0],   hc_x[2:1] } ;  // tile #.  set of 256 tiles -- fg_ram_dout[7:0]

        gfx2_addr <= { bg_ram_dout[9:0], vc_s[3:0], hc_s[3:1] } ;
    
        gfx2_pal_h   <= bg_ram_dout[14:13];
        gfx2_pal_l   <= bg_ram_dout[12:11];

        spi <= { 2'b10, ( ( spr_pix[3] == 1'b0 ) ? spr_pix[9:8] : spr_pix[11:10] ), prom_s[ spr_pix[7:0] ][3:0] };  //p[3:0];
        spr_transp <= ( spr_pix == sprite_trans_pen );

    // 1
        gfx1_pix <= ( hc[0] ^ flip ) ? gfx1_dout[3:0] : gfx1_dout[7:4];

        gfx2_pix <= { 2'b11 , ((gfx2_pen[3] == 0 ) ? gfx2_pal_l : gfx2_pal_h ), gfx2_pen } ;

        spi_r <= spi;

        spr_transp_r <= spr_transp;
    // 2
        pal_idx <= ( gfx1_pix < 4'hf && fg_enable ) ? { 4'b0, gfx1_pix } : ( spr_enable == 0 || ( bg_enable == 1 && spr_transp_r && scroll_x[13] == 0 )) ? gfx2_pix :  spi_r;
    end
end

wire  [3:0] gfx2_pen = hc_s[0] ? gfx2_dout[3:0] : gfx2_dout[7:4];
    
   
/// 68k cpu

always @ (posedge clk_sys) begin

    if ( reset == 1 ) begin
        m68k_dtack_n <= 1;
    end else if ( clk_16M == 1 ) begin
        // tell 68k to wait for valid data. 0=ready 1=wait
        // always ack when it's not program rom
        m68k_dtack_n <= 0; 

        // select cpu data input based on what is active 
        m68k_din <=  ss_ovr_handler ? ss_irq_handler[m68k_a[4:1]] :
                     ss_ovr_reset   ? ss_reset_vector[m68k_a[2:1]] :
                     ss_ovr_vec     ? ( m68k_a[1] ? 16'h0000 : 16'h00ff ) :
                     prog_rom_cs  ? prog_rom_data :
                     m68k_ram_cs  ? ram68k_dout :
                     m68k_ram1_cs ? m68k_ram1_dout :
                     input_p1_cs ? p1 :
                     input_p2_cs ? p2 :
                     input_system_cs ? sys:
                     input_dsw_cs ? dsw1 :
                     prot_chip_data_cs ? { 8'h00, nb1412m2_decrypt_dout }:
                     16'd0;
    end
end 

// Chip select mux
// M68K selects
wire prog_rom_cs;
wire m68k_ram_cs;
wire bg_ram_cs;
wire m68k_ram1_cs;
wire fg_ram_cs;

wire input_p1_cs;
wire input_p2_cs;
wire input_system_cs;
wire input_dsw_cs;

wire flip_cs;
wire scroll_x_cs;
wire scroll_y_cs;

wire sound_latch_cs;

wire prot_chip_data_cs;
wire prot_chip_cmd_cs;

// Z80 selects
wire z80_rom_cs /* synthesis keep */;
wire z80_ram_cs /* synthesis keep */;

wire z80_sound0_cs /* synthesis keep */;
wire z80_sound1_cs /* synthesis keep */;
wire z80_dac1_cs /* synthesis keep */;
wire z80_dac2_cs /* synthesis keep */;
wire z80_latch_clr_cs /* synthesis keep */;
wire z80_latch_r_cs /* synthesis keep */;

// Select PCB Title and set chip select lines
reg [2:0] pcb = 3'd0;
reg [15:0] scroll_x;
reg [15:0] scroll_y;
reg [7:0]  sound_latch;

always @(posedge clk_sys)
    if (ioctl_wr && (ioctl_index==1))
        pcb <= ioctl_dout[2:0];

chip_select cs (
    .pcb,

    .m68k_a,
    .m68k_as_n,

    .z80_addr,
    .MREQ_n,
    .IORQ_n,
    .M1_n,

    // M68K selects
    .prog_rom_cs,
    .m68k_ram_cs,
    .bg_ram_cs,
    .m68k_ram1_cs,
    .fg_ram_cs,

    .input_p1_cs,
    .input_p2_cs,
    .input_system_cs,
    .input_dsw_cs,

    .flip_cs,
    .scroll_x_cs,
    .scroll_y_cs,

    .sound_latch_cs,

    .prot_chip_data_cs,
    .prot_chip_cmd_cs,

    // Z80 selects
    .z80_rom_cs,
    .z80_ram_cs,

    .z80_sound0_cs,
    .z80_sound1_cs,
    .z80_dac1_cs,
    .z80_dac2_cs,
    .z80_latch_clr_cs,
    .z80_latch_r_cs
);


// CPU outputs
wire m68k_rw         ;    // Read = 1, Write = 0
wire m68k_as_n       ;    // Address strobe
wire m68k_lds_n      ;    // Lower byte strobe
wire m68k_uds_n      ;    // Upper byte strobe
wire m68k_E;         
wire [2:0] m68k_fc    ;   // Processor state
wire m68k_reset_n_o  ;    // Reset output signal
wire m68k_halted_n   ;    // Halt output

// CPU busses
wire [15:0] m68k_dout       ;
wire [23:0] m68k_a          ;
reg  [15:0] m68k_din        ;   
assign m68k_a[0] = 1'b0;

// CPU inputs
reg  m68k_dtack_n ;         // Data transfer ack (always ready)
reg  m68k_ipl2_n ;


wire reset_n;
wire m68k_vpa_n = ~int_ack;//( m68k_lds_n == 0 && m68k_fc == 3'b111 ); // int ack

reg int_ack ;
reg int_ack1 ;
reg [1:0] vbl_sr;

wire [3:0] sprite_trans_pen = (pcb == 0 || pcb == 1 || pcb == 3 ) ? 4'd0 : 4'd15;

// vblank handling 
// process interrupt and sprite buffering
always @ (posedge clk_sys ) begin
    if ( reset == 1 ) begin
        m68k_ipl2_n <= 1 ;
        int_ack <= 0;
    end else begin
        vbl_sr <= { vbl_sr[0], vbl };

        if ( clk_16M == 1 ) begin
            int_ack  <= ( m68k_as_n == 0 ) && ( m68k_fc == 3'b111 ); // cpu acknowledged the interrupt
            int_ack1 <= ( m68k_as_n == 0 ) && ( m68k_fc == 3'b111 ) && ( m68k_a[3:1] == 3'b001 );
        end

        if ( vbl_sr == 2'b01 ) begin // rising edge
            // trigger sprite buffer copy
            copy_sprite_state <= 1;
            //  68k vbl interrupt
            m68k_ipl2_n <= 0;
        end else if ( int_ack1 == 1 || vbl_sr == 2'b10 ) begin
            // deassert interrupt since 68k ack'ed.
            m68k_ipl2_n <= 1 ;
        end

        if ( ss_misc_wr ) m68k_ipl2_n <= ss_misc_out[0];
        
    end

    //   copy sprite list to dedicated sprite list ram
    // start state machine for copy
    if ( copy_sprite_state == 1 ) begin
        sprite_shared_addr <= 8'd0;
        copy_sprite_state <= 4'd2;
        sprite_buffer_addr <= 6'd0;
    end else if ( copy_sprite_state == 2 ) begin
        // address now 0
        sprite_shared_addr <= sprite_shared_addr + 8'd1 ;
        copy_sprite_state <= 4'd3; 
    end else if ( copy_sprite_state == 3 ) begin        
       // address 0 result
        sprite_y_pos <= flip ? sprite_shared_ram_dout - 8'd1 : 8'd239 - sprite_shared_ram_dout;

        sprite_shared_addr <= sprite_shared_addr + 8'd1 ;
        copy_sprite_state <= 4'd4; 
    end else if ( copy_sprite_state == 4 ) begin    
        // address 1 result
        sprite_tile[7:0] <= sprite_shared_ram_dout;

        sprite_shared_addr <= sprite_shared_addr + 8'd1 ;
        copy_sprite_state <= 4'd5; 
    end else if ( copy_sprite_state == 5 ) begin        
            // add 256 to x?
        sprite_x_256 <= sprite_shared_ram_dout[0];
        // add 256 to tile?

        if ( pcb == 0 || pcb == 1 || pcb == 3 ) begin
            sprite_tile[9:8] <= { 1'b0, sprite_shared_ram_dout[1] };
        end else begin
//			if( attrs&0x10 ) tile |= 0x100;
//			if( attrs&0x02 ) tile |= 0x200;
            sprite_tile[9:8] <= { sprite_shared_ram_dout[1], sprite_shared_ram_dout[4] };
        end
        
        // flip x?
        sprite_flip_x <= sprite_shared_ram_dout[2] ^ test_flip_x ;
        // flip y?
        sprite_flip_y <= sprite_shared_ram_dout[3] ^ flip ^ test_flip_y ;
        // colour
        sprite_colour <= sprite_shared_ram_dout[7:4];

        sprite_shared_addr <= sprite_shared_addr + 8'd1 ;

        copy_sprite_state <= 4'd6; 
    end else if ( copy_sprite_state == 6 ) begin        
        sprite_x_pos <=  { sprite_x_256, sprite_shared_ram_dout } - 9'h080; 
        copy_sprite_state <= 4'd7; 
    end else if ( copy_sprite_state == 7 ) begin                
        sprite_buffer_w <= 1;
        sprite_buffer_din <= {sprite_tile,sprite_x_pos,sprite_y_pos,sprite_colour,sprite_flip_x,sprite_flip_y};
        
        copy_sprite_state <= 4'd8;
    end else if ( copy_sprite_state == 8 ) begin                

        // write is complete
        sprite_buffer_w <= 0;
        // sprite has been buffered.  are we done?
        if ( sprite_buffer_addr < 6'h3f ) begin
            // start on next sprite
            sprite_buffer_addr <= sprite_buffer_addr + 6'd1;
            copy_sprite_state <= 4'd2;
        end else begin
            // we are done, go idle.  
            copy_sprite_state <= 4'd0; 
        end
    end

    if ( draw_sprite_state == 0 && hc > 9'h0ff ) begin 
        // clear sprite buffer
        sprite_x_ofs <= 8'd0;
        draw_sprite_state <= 4'd1;
        sprite_buffer_addr <= 6'd0;
    end else if (draw_sprite_state == 1) begin
        sprite_line_buffer[sprite_x_ofs] <= sprite_trans_pen;  // 0
        if ( sprite_x_ofs < 8'd255 ) begin
            sprite_x_ofs <= sprite_x_ofs + 8'd1;
        end else begin
            // sprite buffer now blank
            draw_sprite_state <= 4'd2;
        end
    end else if (draw_sprite_state == 2) begin        
        // get current sprite attributes
        {sprite_tile,sprite_x_pos,sprite_y_pos,sprite_colour,sprite_flip_x,sprite_flip_y} <= sprite_buffer_dout[32:0];
        draw_sprite_state <= 4'd3;
        sprite_x_ofs <= 8'd0;
    end else if (draw_sprite_state == 3) begin
        draw_sprite_state <= 4'd4;
    end else if (draw_sprite_state == 4) begin
        draw_sprite_state <= 4'd3; 
        if ( vc >= sprite_y_pos && vc < ( {1'b0, sprite_y_pos} + 9'd16 ) ) begin  
            // fetch bitmap 
            if ( p[3:0] != sprite_trans_pen ) begin
                sprite_line_buffer[sprite_x_pos] <= p;
            end
            if ( sprite_x_ofs < 8'd15 ) begin
                sprite_x_pos <= sprite_x_pos + 9'd1;
                sprite_x_ofs <= sprite_x_ofs + 8'd1;
            end else begin
                draw_sprite_state <= 4'd6;
            end
        end else begin
            draw_sprite_state <= 4'd6;
        end
    end else if (draw_sprite_state == 6) begin                        
        // done. next sprite
        if ( sprite_buffer_addr < 6'd63 ) begin
            sprite_buffer_addr <= sprite_buffer_addr + 6'd1;
            draw_sprite_state <= 4'd2;
        end else begin
            // all sprites done
            draw_sprite_state <= 4'd7;
        end
    end else if (draw_sprite_state == 7) begin                        
        // we are done. wait for end of line
        if ( hc == 0 ) begin
            draw_sprite_state <= 4'd0;
        end
    end
end

wire    [3:0] sprite_y_ofs = vc[3:0] - sprite_y_pos[3:0];

wire    [3:0] flipped_x = ( sprite_flip_x == 0 ) ? sprite_x_ofs[3:0] : 4'd15 - sprite_x_ofs[3:0];
wire    [3:0] flipped_y = ( sprite_flip_y == 0 ) ? sprite_y_ofs : 4'd15 - sprite_y_ofs;

//wire    [3:0] gfx3_pix = (sprite_x_ofs[0] == 1 ) ? gfx3_dout[7:4] : gfx3_dout[3:0];
wire    [3:0] gfx3_pix = (flipped_x[0] == 1 ) ? gfx3_dout[7:4] : gfx3_dout[3:0];

// int spr_col = (u[t>>1]<<8) + (c<<4) + pen ;
// prom_u = palette bank lookup
wire   [11:0] p ;
wire   [16:0] gfx3_addr ;

always @ (*) begin
    if ( pcb == 0 || pcb == 1 || pcb == 3 ) begin
        // terra cresta / amazon
        gfx3_addr = { 1'b0, flipped_x[1], sprite_tile[8:0], flipped_y[3:0], flipped_x[3:2] };
        
        p = { prom_u[sprite_tile[8:1]][3:0], sprite_colour, gfx3_pix};
    end else begin
        // hori
        gfx3_addr = { flipped_x[1],       sprite_tile[9:0], flipped_y[3:0], flipped_x[3:2] };

        p = { prom_u[{sprite_tile[9],sprite_tile[7:2],sprite_tile[8]}][3:0], sprite_colour[3:1], 1'b0, gfx3_pix};
    end
end

reg     [7:0] sprite_x_ofs;

(* ramstyle = "MLAB" *) reg    [11:0] sprite_line_buffer [271:0];

dual_port_ram #(.LEN(64), .DATA_WIDTH(64)) sprite_buffer (
    .clock_a ( clk_sys ),
    .address_a ( sprite_buffer_addr ),
    .wren_a ( 1'b0 ),
    .data_a ( ),
    .q_a ( sprite_buffer_dout ),
    
    .clock_b ( clk_sys ),
    .address_b ( sprite_buffer_addr ),
    .wren_b ( sprite_buffer_w ),
    .data_b ( sprite_buffer_din  ),
    .q_b( )

    );

        
reg  [3:0]  copy_sprite_state;
reg  [3:0]  draw_sprite_state;

wire [7:0]  sprite_shared_ram_dout;
reg  [7:0]  sprite_shared_addr;
reg  [5:0]  sprite_buffer_addr;  // 64 sprites
reg  [63:0] sprite_buffer_din;
wire [63:0] sprite_buffer_dout;
reg  sprite_buffer_w;

reg  [9:0]  sprite_tile ;  // terra cresta has 512 tiles ,  HORE HORE Kid has 1024
reg  [7:0]  sprite_y_pos;
reg  [8:0]  sprite_x_pos;
reg  [3:0]  sprite_colour;
reg  sprite_x_256;
reg  sprite_flip_x;
reg  sprite_flip_y;

// clock generation
reg  fx68_phi1 = 0; 

// phases for 68k clock
wire m68k_ce = ce_16m & m68k_run;

always @(posedge clk_sys) begin
    if ( m68k_ce ) begin
        fx68_phi1 <= ~fx68_phi1; 
    end
end

fx68k fx68k (
    // input
    .clk( clk_sys ),
    .HALTn(1'b1),
    .enPhi1(m68k_ce & fx68_phi1),
    .enPhi2(m68k_ce & ~fx68_phi1),
    .extReset(reset | ss_reset),
    .pwrUp(reset | ss_reset),

    // output
    .eRWn(m68k_rw),
    .ASn( m68k_as_n),
    .LDSn(m68k_lds_n),
    .UDSn(m68k_uds_n),
    .E(),
    .VMAn(),
    .FC0(m68k_fc[0]),
    .FC1(m68k_fc[1]),
    .FC2(m68k_fc[2]),
    .BGn(),
    .oRESETn(m68k_reset_n_o),
    .oHALTEDn(m68k_halted_n),

    // input
    .VPAn( m68k_vpa_n ),  
    .DTACKn( m68k_dtack_n ),     
    .BERRn(1'b1), 
    .BRn(1'b1),  
    .BGACKn(1'b1),
    
    .IPL0n(m68k_ipl2_n & ~ss_irq),
    .IPL1n(~ss_irq),
    .IPL2n(~ss_irq),

    // busses
    .iEdb(m68k_din),
    .oEdb(m68k_dout),
    .eab(m68k_a[23:1])
);


// z80 bus
wire    [7:0] z80_rom_data;
wire    [7:0] z80_ram_dout;

wire   [15:0] z80_addr;
reg     [7:0] z80_din;
wire    [7:0] z80_dout;

wire z80_wr_n;
wire z80_rd_n;
reg  z80_wait_n;
reg  z80_irq_n;

wire IORQ_n;
wire MREQ_n;
wire M1_n;

//IORQ gets together with M1-pin active/low. 
always @ (posedge clk_sys) begin
    
    if ( reset == 1 ) begin
        z80_irq_n <= 1;
    end else if ( clk_ym == 1 ) begin
        z80_irq_n <= 0;
    end 
    
    // check for interrupt ack and deassert int
    if ( M1_n == 0 && z80_irq_n == 0 && IORQ_n == 0 ) begin
        z80_irq_n <= 1;
    end

    if ( ss_misc_wr ) z80_irq_n <= ss_misc_out[1];
end

T80pa u_cpu(
    .RESET_n    ( ~(reset | z80_ss_reset) ),
    .CLK        ( clk_sys ),
    .CEN_p      ( ce_8m & z80_run ),
    .CEN_n      ( ce_8m & z80_run ),
    .WAIT_n     ( z80_wait_n ), // don't wait if data is valid or rom access isn't selected
    .INT_n      ( z80_irq_n | z80_int_mask ),  // opl timer
    .NMI_n      ( 1'b1 ),
    .BUSRQ_n    ( 1'b1 ),
    .RD_n       ( z80_rd_n ),
    .WR_n       ( z80_wr_n ),
    .A          ( z80_addr ),
    .DI         ( z80_din  ),
    .DO         ( z80_dout ),
    // unused
    .R800_mode  ( 1'b0     ),
    .DIRSet     ( z80_dirset ),
    .DIR        ( z80_dir    ),
    .OUT0       ( 1'b0     ),
    .RFSH_n     (),
    .IORQ_n     ( IORQ_n ),
    .M1_n       ( M1_n ),
    .BUSAK_n    (),
    .HALT_n     ( 1'b1 ),
    .MREQ_n     ( MREQ_n ),
    .REG        ( z80_reg )
);

reg sound_addr ;
reg  [7:0] sound_data ;

// sound ic write enable
reg sound_wr;

wire [7:0] opl_dout;
wire opl_irq_n;

reg signed [15:0] sample;

assign AUDIO_S = 1'b1 ;

wire opl_sample_clk;

wire       opl_wr   = opl_rp_busy ? opl_rp_wr   : sound_wr;
wire       opl_a    = opl_rp_busy ? opl_rp_addr : sound_addr;
wire [7:0] opl_din  = opl_rp_busy ? opl_rp_data : sound_data;

jtopl #(.OPL_TYPE(1)) opl
(
    .rst(reset),
    .clk(clk_sys),
    .cen(clk_4M & (snd_run | opl_rp_busy)),
    .din(opl_din),
    .addr(opl_a),
    .cs_n(~opl_wr),
    .wr_n(~opl_wr),
    .dout(opl_dout),
    .irq_n(opl_irq_n),
    .snd(sample),
    .sample(opl_sample_clk)
);

always @ * begin
    // mix audio
    AUDIO_L <= sample + ($signed({ ~dac1[7], dac1[6:0], 8'b0 }) >>> 1) + ($signed({ ~dac2[7], dac2[6:0], 8'b0 }) >>> 1) ;
    AUDIO_R <= sample + ($signed({ ~dac1[7], dac1[6:0], 8'b0 }) >>> 1) + ($signed({ ~dac2[7], dac2[6:0], 8'b0 }) >>> 1) ;
end

reg [7:0] dac1;
reg [7:0] dac2;


always @ (posedge clk_sys) begin
     if ( clk_4M == 1 && snd_run == 1 ) begin

        z80_wait_n <= 1;
        
        if ( z80_rd_n == 0 ) begin 
            if ( z80_rom_cs ) begin
                z80_din <= z80_rom_data;
            end else if ( z80_ram_cs ) begin
                z80_din <= z80_ram_dout;
            end else if ( z80_latch_clr_cs ) begin
                // todo
                z80_din <= 0;
                      sound_latch <= 8'h0;
                     
            end else if ( z80_latch_r_cs ) begin
                z80_din <= sound_latch;
                // todo
            end else begin
                z80_din <= 8'h00;
            end
        end
        
        sound_wr <= 0 ;
        if ( z80_wr_n == 0 ) begin 
            if ( z80_sound0_cs == 1 || z80_sound1_cs == 1) begin    
                sound_data  <= z80_dout;
                sound_addr <= z80_sound1_cs ; //   opl2 is single bit address
                sound_wr <= 1;
            end else if (z80_dac1_cs == 1 ) begin
                    dac1 <= z80_dout;
                end else if (z80_dac2_cs == 1 ) begin
                    dac2 <= z80_dout;
                end
        end
    end 

    if ( snd_run == 0 ) sound_wr <= 0;
     
    if ( clk_16M == 1 ) begin
        if (!m68k_rw & !m68k_lds_n & flip_cs) begin
            cocktail_flip <= m68k_dout[2];
        end

        if (!m68k_rw & scroll_x_cs ) begin
            scroll_x <= m68k_dout[15:0];
        end

        if (!m68k_rw & scroll_y_cs ) begin
            scroll_y <= m68k_dout[15:0];
        end

        if (!m68k_rw & sound_latch_cs ) begin
            sound_latch <= {m68k_dout[6:0],1'b1};
        end

        if (!m68k_rw & prot_chip_cmd_cs ) begin
            prot_cmd <= m68k_dout[7:0] ;
        end

        if (!m68k_rw & prot_chip_data_cs ) begin
            if ( prot_cmd == 8'h33 ) begin
                if ( prot_state == 0 ) begin
                    nb1412m2_addr[15:8] <= m68k_dout[7:0] ; 
                    prot_state <= 8'h11;
                end
            end else if ( prot_cmd == 8'h34 ) begin
                if ( prot_state == 0 ) begin
                    nb1412m2_addr[7:0] <= m68k_dout[7:0] ; 
                    prot_state <= 8'h21;
                end            
            end else if ( prot_cmd == 8'h35 ) begin
                if ( prot_state == 0 ) begin
                    nb1412m2_addr[15:8] <= m68k_dout[7:0] ; 
                    prot_state <= 8'h31;
                end            
            end else if ( prot_cmd == 8'h36 ) begin
                if ( prot_state == 0 ) begin
                    nb1412m2_addr[7:0] <= m68k_dout[7:0] ; 
                    prot_state <= 8'h41;
                end            
            end
         end
    end // clk_16
    
    // writes to nb1412m2 are queued and handled here
    // each write to the nb1412m2 causes a read to the nb1412m2 rom
    // and updates the current decryted value
    if ( prot_state == 8'h11 ) begin   
        // address now vaild, wait for read
        prot_state <= 8'h12;
    end else if ( prot_state == 8'h12 ) begin
        nb1412m2_rom_dout[7:0] <= nb1412m2_dout;
        prot_state <= 0;
        
    end else if ( prot_state == 8'h21 ) begin   
        prot_state <= 8'h22;
    end else if ( prot_state == 8'h22 ) begin
        nb1412m2_rom_dout[7:0] <= nb1412m2_dout;
        prot_state <= 0;
        
    end else if ( prot_state == 8'h31 ) begin   
        prot_state <= 8'h32;
    end else if ( prot_state == 8'h32 ) begin
        nb1412m2_adj_dout[7:0] <= nb1412m2_dout;
        prot_state <= 0;
        
    end else if ( prot_state == 8'h41 ) begin   
        prot_state <= 8'h42;
    end else if ( prot_state == 8'h42 ) begin
        nb1412m2_adj_dout[7:0] <= nb1412m2_dout;
        prot_state <= 0;
    end

   if ( ss_misc_wr ) begin
        { scroll_x, scroll_y, cocktail_flip, sound_latch, dac1, dac2, prot_cmd, nb1412m2_addr, nb1412m2_rom_dout, nb1412m2_adj_dout } <= ss_misc_out[MISC_BITS-1:10];
   end

   if ( reset == 1 ) begin
        z80_wait_n <= 0;
        sound_wr <= 0 ;
          sound_latch <= 8'h00;
   end


end

reg [7:0]  prot_dout;
reg [15:0] prot_rom_addr;
reg [15:0] prot_adj_addr;
reg [7:0]  prot_cmd;
reg [7:0]  prot_state;

reg [15:0] nb1412m2_addr;
wire [7:0] nb1412m2_dout;

reg  [7:0] nb1412m2_adj_dout;
reg  [7:0] nb1412m2_rom_dout;
wire [7:0] nb1412m2_decrypt_dout = nb1412m2_rom_dout - ( 8'h43 - nb1412m2_adj_dout ) ;

//	prot_adj = (0x43 - m_data[m_adj_address]) & 0xff;
//	return m_data[m_rom_address & 0x1fff] - prot_adj;

dual_port_ram #(.LEN(8192)) nb1412m2_adj (
    .clock_a ( clk_sys ),
    .address_a ( nb1412m2_addr[12:0] ),
    .wren_a ( 1'b0 ),
    .data_a ( ),
    .q_a ( nb1412m2_dout ),
    
    .clock_b ( clk_sys ),
    .address_b ( ioctl_addr[12:0] ),
    .wren_b ( nb1412m2_ioctl_wr ),
    .data_b ( ioctl_dout  ),
    .q_b( )
    );
    

wire [15:0] ram68k_dout;
wire [15:0] prog_rom_data;

// ioctl download addressing    

wire m68k_rom_h_ioctl_wr = rom_download & ioctl_wr & (ioctl_addr  <  24'h020000) & (ioctl_addr[0] == 1);
wire m68k_rom_l_ioctl_wr = rom_download & ioctl_wr & (ioctl_addr  <  24'h020000) & (ioctl_addr[0] == 0);

wire gfx2_ioctl_wr       = rom_download & ioctl_wr & (ioctl_addr >=  24'h020000) & (ioctl_addr <  24'h040000) ;
wire gfx3_ioctl_wr       = rom_download & ioctl_wr & (ioctl_addr >=  24'h040000) & (ioctl_addr <  24'h060000) ;
wire gfx1_ioctl_wr       = rom_download & ioctl_wr & (ioctl_addr >=  24'h060000) & (ioctl_addr <  24'h064000) ;

wire z80_rom_ioctl_wr    = rom_download & ioctl_wr & (ioctl_addr >=  24'h070000) & (ioctl_addr <  24'h07c000) ;

wire nb1412m2_ioctl_wr   = rom_download & ioctl_wr & (ioctl_addr >=  24'h07c000) & (ioctl_addr <  24'h07e000) ;

wire prom_r_wr           = rom_download & ioctl_wr & (ioctl_addr >=  24'h07E000) & (ioctl_addr <  24'h07E100) ;
wire prom_g_wr           = rom_download & ioctl_wr & (ioctl_addr >=  24'h07E100) & (ioctl_addr <  24'h07E200) ;
wire prom_b_wr           = rom_download & ioctl_wr & (ioctl_addr >=  24'h07E200) & (ioctl_addr <  24'h07E300) ;
wire prom_s_wr           = rom_download & ioctl_wr & (ioctl_addr >=  24'h07E300) & (ioctl_addr <  24'h07E400) ;
wire prom_u_wr           = rom_download & ioctl_wr & (ioctl_addr >=  24'h07E400) & (ioctl_addr <  24'h07E500) ;

(* ramstyle = "MLAB" *) reg [3:0] prom_r [255:0] ;
(* ramstyle = "MLAB" *) reg [3:0] prom_g [255:0] ;
(* ramstyle = "MLAB" *) reg [3:0] prom_b [255:0] ;
(* ramstyle = "MLAB" *) reg [3:0] prom_s [255:0] ;
reg [3:0] prom_u [255:0] ;

always @ (posedge clk_sys) begin

    if ( prom_r_wr == 1 ) begin
        prom_r[ioctl_addr[7:0]] <= ioctl_dout[3:0];
    end
     
    if ( prom_g_wr == 1 ) begin
        prom_g[ioctl_addr[7:0]] <= ioctl_dout[3:0];
    end
     
    if ( prom_b_wr == 1 ) begin
        prom_b[ioctl_addr[7:0]] <= ioctl_dout[3:0];
    end
     
    if ( prom_s_wr == 1 ) begin
        prom_s[ioctl_addr[7:0]] <= ioctl_dout[3:0];
    end

    if ( prom_u_wr == 1 ) begin
        prom_u[ioctl_addr[7:0]] <= ioctl_dout[3:0];
    end
     
end

// main 68k ROM low     
// 3.4d & 4.6d
dual_port_ram #(.LEN(65536)) rom64kx8_H (
    .clock_a ( clk_sys ),
    .address_a ( m68k_a[16:1] ),
    .wren_a ( 1'b0 ),
    .data_a ( ),
    .q_a ( prog_rom_data[15:8] ),
    
    .clock_b ( clk_sys ),
    .address_b ( ioctl_addr[16:1] ),
    .wren_b ( m68k_rom_h_ioctl_wr ),
    .data_b ( ioctl_dout  ),
    .q_b( )

    );

// main 68k ROM high 
// // rom 1.4b & 2.6b  
dual_port_ram #(.LEN(65536)) rom64kx8_L (
    .clock_a ( clk_sys ),
    .address_a ( m68k_a[16:1] ),
    .wren_a ( 1'b0 ),
    .data_a ( ),
    .q_a ( prog_rom_data[7:0] ),
    
    .clock_b ( clk_sys ),
    .address_b ( ioctl_addr[16:1] ),
    .wren_b ( m68k_rom_l_ioctl_wr ),
    .data_b ( ioctl_dout  ),
    .q_b( )
    );

// main 68k ram high    
dual_port_ram #(.LEN(4096)) ram4kx8_H (
    .clock_a ( clk_sys ),
    .address_a ( ss_main_sel ? ss_main_addr : m68k_a[12:1] ),
    .wren_a ( ss_main_sel ? ss_main_we : (!m68k_rw & m68k_ram_cs & !m68k_uds_n) ),
    .data_a ( ss_main_sel ? ss_main_wdata[15:8] : m68k_dout[15:8] ),
    .q_a (  ram68k_dout[15:8] ),

    .clock_b ( clk_sys ),
    .address_b ( hs_ram_addr[12:1] ),
    .wren_b ( hs_ram_sel & hs_ram_we & ~hs_ram_addr[0] ),
    .data_b ( hs_ram_wdata ),
    .q_b( hs_q_h )
    );

// main 68k ram low     
// 0x200 shared with sound cpu            
dual_port_ram #(.LEN(4096)) ram4kx8_L (
    .clock_a ( clk_sys ),
    .address_a ( ss_main_sel ? ss_main_addr : m68k_a[12:1] ),
    .wren_a ( ss_main_sel ? ss_main_we : (!m68k_rw & m68k_ram_cs & !m68k_lds_n) ),
    .data_a ( ss_main_sel ? ss_main_wdata[7:0] : m68k_dout[7:0] ),
    .q_a ( ram68k_dout[7:0] ),
     
     .clock_b ( clk_sys ),
    .address_b ( hs_ram_sel ? hs_ram_addr[12:1] : {4'b0, sprite_shared_addr[7:0]} ),  // 64 sprites * 4 bytes for each == 256
    .wren_b ( hs_ram_sel & hs_ram_we & hs_ram_addr[0] ),
    .data_b ( hs_ram_wdata ),
    .q_b( sprite_shared_ram_dout )
    );

wire [7:0] hs_q_h;
wire [7:0] hs_ram_q = hs_ram_addr[0] ? sprite_shared_ram_dout : hs_q_h;
    
// z80 address to the sound ROM/RAM, registered (read data is used a T-state later)
reg [15:0] z80_addr_r;
always @(posedge clk_sys) z80_addr_r <= z80_addr;

// z80 rom (48k)
dual_port_ram #(.LEN(16'hc000)) rom_z80 (
    .clock_a ( clk_sys ),
    .address_a ( z80_addr_r[15:0] ),
    .wren_a ( 1'b0 ),
    .data_a (  ),
    .q_a ( z80_rom_data ),
    
    .clock_b ( clk_sys ),
    .address_b ( ioctl_addr[15:0] ),
    .wren_b ( z80_rom_ioctl_wr ),
    .data_b ( ioctl_dout  ),
    .q_b( )
    );
    
// z80 ram    
dual_port_ram #(.LEN(4096)) z80_ram (
    .clock_b ( clk_sys ),
    .address_b ( ss_z80_sel ? ss_z80_addr : z80_addr_r[11:0] ),
    .data_b ( ss_z80_sel ? ss_z80_wdata : z80_dout ),
    .wren_b ( ss_z80_sel ? ss_z80_we : (z80_ram_cs & ~z80_wr_n) ),
    .q_b ( z80_ram_dout )
    );

    
//  <!-- gfx1   ioctl    0x060000-0x063fff 16K -->
dual_port_ram #(.LEN(16384)) gfx1 (
    .clock_a ( clk_sys ),
    .address_a ( gfx1_addr[13:0] ),
    .wren_a ( 1'b0 ),
    .data_a ( ),
    .q_a ( gfx1_dout[7:0] ),
    
    .clock_b ( clk_sys ),
    .address_b ( ioctl_addr[13:0] ),
    .wren_b ( gfx1_ioctl_wr ),
    .data_b ( ioctl_dout  ),
    .q_b( )
    );
    
//  <!-- gfx2   ioctl    0x020000-0x03FFFF 128K -->
dual_port_ram #(.LEN(131072)) gfx2 (
    .clock_a ( clk_sys ),
    .address_a ( gfx2_addr[16:0] ),
    .wren_a ( 1'b0 ),
    .data_a ( ),
    .q_a ( gfx2_dout[7:0] ),
    
    .clock_b ( clk_sys ),
    .address_b ( ioctl_addr[16:0] ),
    .wren_b ( gfx2_ioctl_wr ),
    .data_b ( ioctl_dout  ),
    .q_b( )
    );

//  <!-- gfx3   ioctl   0x40000-0x5fffff  128K -->     
dual_port_ram #(.LEN(131072)) gfx3 (
    .clock_a ( clk_sys ),
    .address_a ( gfx3_addr[16:0] ),
    .wren_a ( 1'b0 ),
    .data_a ( ),
    .q_a ( gfx3_dout[7:0] ),
    
    .clock_b ( clk_sys ),
    .address_b ( ioctl_addr[16:0] ),
    .wren_b ( gfx3_ioctl_wr ),
    .data_b ( ioctl_dout  ),
    .q_b( )
    );

wire [15:0] fg_ram_dout;
wire  [7:0] fg_ram_q;

// 2 x 1k
dual_port_ram #(.LEN(2048)) fg_ram_l (
    .clock_a ( clk_sys ),
    .address_a ( ss_fg_sel ? ss_fg_addr : m68k_a[11:1] ),
    .wren_a ( ss_fg_sel ? ss_fg_we : (!m68k_rw & fg_ram_cs & !m68k_lds_n) ),
    .data_a ( ss_fg_sel ? ss_fg_wdata[7:0] : m68k_dout[7:0] ),
    .q_a ( fg_ram_q[7:0] ),

    .clock_b ( clk_sys ),
    .address_b ( fg_ram_addr  ),
    .wren_b ( 1'b0 ),
    .data_b (  ),
    .q_b( fg_ram_dout[7:0]  )

    );

dual_port_ram #(.LEN(2048)) fg_ram_h (
    .clock_a ( clk_sys ),
    .address_a ( ss_fg_sel ? ss_fg_addr : m68k_a[11:1] ),
    .wren_a ( ss_fg_sel ? ss_fg_we : (!m68k_rw & fg_ram_cs & !m68k_lds_n) ),
    .data_a ( ss_fg_sel ? ss_fg_wdata[15:8] : m68k_dout[15:8] ),
    .q_a ( ),
    
    .clock_b ( clk_sys ),
    .address_b ( fg_ram_addr  ),
    .wren_b ( 1'b0 ),
    .data_b (  ),
    .q_b( fg_ram_dout[15:8]  )
    );
    
    
wire [15:0] bg_ram_dout;
wire [15:0] bg_ram_q;

dual_port_ram #(.LEN(2048)) bg_ram_l (
    .clock_a ( clk_sys ),
    .address_a ( ss_bg_sel ? ss_bg_addr : m68k_a[11:1] ),
    .wren_a ( ss_bg_sel ? ss_bg_we : (!m68k_rw & bg_ram_cs & !m68k_lds_n) ),
    .data_a ( ss_bg_sel ? ss_bg_wdata[7:0] : m68k_dout[7:0] ),
    .q_a ( bg_ram_q[7:0] ),

    .clock_b ( clk_sys ),
    .address_b ( bg_ram_addr  ),
    .wren_b ( 1'b0 ),
    .data_b (  ),
    .q_b( bg_ram_dout[7:0]  )

    );

dual_port_ram #(.LEN(2048)) bg_ram_h (
    .clock_a ( clk_sys ),
    .address_a ( ss_bg_sel ? ss_bg_addr : m68k_a[11:1] ),
    .wren_a ( ss_bg_sel ? ss_bg_we : (!m68k_rw & bg_ram_cs & !m68k_lds_n) ),
    .data_a ( ss_bg_sel ? ss_bg_wdata[15:8] : m68k_dout[15:8] ),
    .q_a ( bg_ram_q[15:8] ),
    
    .clock_b ( clk_sys ), 
    .address_b ( bg_ram_addr  ),
    .wren_b ( 1'b0 ),
    .data_b (  ),
    .q_b( bg_ram_dout[15:8]  )
    );    

reg  [11:0] m68k_ram1_addr;
wire [15:0] m68k_ram1_dout;

dual_port_ram #(.LEN(2048)) m68k_ram1_l (
    .clock_a ( clk_sys ),
    .address_a ( ss_ram1_sel ? ss_ram1_addr : m68k_a[11:1] ),
    .wren_a ( ss_ram1_sel ? ss_ram1_we : (!m68k_rw & m68k_ram1_cs & !m68k_lds_n) ),
    .data_a ( ss_ram1_sel ? ss_ram1_wdata[7:0] : m68k_dout[7:0] ),
    .q_a ( m68k_ram1_dout[7:0] )
    );

dual_port_ram #(.LEN(2048)) m68k_ram1_h (
    .clock_a ( clk_sys ),
    .address_a ( ss_ram1_sel ? ss_ram1_addr : m68k_a[11:1] ),
    .wren_a ( ss_ram1_sel ? ss_ram1_we : (!m68k_rw & m68k_ram1_cs & !m68k_lds_n) ),
    .data_a ( ss_ram1_sel ? ss_ram1_wdata[15:8] : m68k_dout[15:8] ),
    .q_a ( m68k_ram1_dout[15:8] )
    );

//////////////////////////////////////////////////////////////////
// High scores

wire        hs_ram_sel, hs_ram_we;
wire [12:0] hs_ram_addr;
wire  [7:0] hs_ram_wdata;
wire        hs_has_entries;

hiscore hiscore
(
    .clk(clk_sys),
    .reset(reset),

    .ioctl_download(ioctl_download),
    .ioctl_upload(ioctl_upload),
    .ioctl_wr(ioctl_wr),
    .ioctl_index(ioctl_index),
    .ioctl_addr(ioctl_addr),
    .ioctl_dout(ioctl_dout),
    .ioctl_din(ioctl_din),
    .upload_req(ioctl_upload_req),

    .autosave(~status[69]),
    .save_now(status[70]),
    .osd_open(OSD_STATUS),
    .frame(vbl),
    .ram_ok(vc >= 9'd32 && vc < 9'd200),

    .ram_sel(hs_ram_sel),
    .ram_addr(hs_ram_addr),
    .ram_wdata(hs_ram_wdata),
    .ram_we(hs_ram_we),
    .ram_q(hs_ram_q),

    .has_entries(hs_has_entries)
);

//////////////////////////////////////////////////////////////////
// Save states

// 68000 code served at $ff0000: push registers, store SSP at $ff0000, pop and return
logic [15:0] ss_irq_handler[16] = '{
    16'h48e7, 16'hfffe,            // movem.l d0-d7/a0-a6,-(a7)
    16'h4e6e,                      // move.l usp,a6
    16'h2f0e,                      // move.l a6,-(a7)
    16'h4df9, 16'h00ff, 16'h0000,  // lea $ff0000,a6 (restore entry)
    16'h2c8f,                      // move.l a7,(a6)
    16'h2c5f,                      // move.l (a7)+,a6
    16'h4e66,                      // move.l a6,usp
    16'h4cdf, 16'h7fff,            // movem.l (a7)+,d0-d7/a0-a6
    16'h4e73,                      // rte
    16'h0000,
    16'h0000,
    16'h0000
};

typedef enum logic [3:0] {
    SST_IDLE,
    SST_SAVE_Z80,
    SST_SAVE_IRQ,
    SST_SAVE_SSP,
    SST_SAVE_WRITE,
    SST_SAVE_EXIT,
    SST_LOAD_READ,
    SST_LOAD_OPL,
    SST_LOAD_Z80,
    SST_LOAD_RESET,
    SST_LOAD_EXIT
} sst_t;
sst_t ss_state = SST_IDLE;

wire        ss_save, ss_load;
reg         ss_write, ss_read;
wire        ss_busy;
reg         ss_busy_seen;
reg  [31:0] ss_saved_ssp;
wire [31:0] ss_restore_ssp;
reg  [15:0] ss_reset_vector[4];
reg   [5:0] ss_reset_count;
reg  [23:0] ss_timeout;
reg         z80_at_m1;
reg         z80_ss_reset;
reg         z80_dirset;
reg         opl_rp_start;
wire        opl_rp_busy;

wire ss_idle        = ss_state == SST_IDLE;
wire ss_busy_any    = ~ss_idle;
wire ss_irq         = ss_state == SST_SAVE_IRQ;
wire ss_ovr         = ss_state == SST_SAVE_SSP || ss_state == SST_SAVE_EXIT || ss_state == SST_LOAD_RESET || ss_state == SST_LOAD_EXIT;
wire ss_restoring   = ss_state == SST_LOAD_RESET || ss_state == SST_LOAD_EXIT;
wire ss_reset       = ss_state == SST_LOAD_RESET;
wire ss_cpu_execute = ss_state == SST_SAVE_IRQ || ss_state == SST_SAVE_SSP || ss_state == SST_SAVE_EXIT || ss_restoring;

// 68000 address decode while the core serves the save-state code
wire ss_in_handler  = m68k_a[23:5] == 19'h7f800;
wire ss_in_reset    = m68k_a[23:3] == 21'd0;
wire ss_ovr_handler = ss_ovr & ss_in_handler;
wire ss_ovr_reset   = ss_ovr & ss_restoring & ss_in_reset;
wire ss_ovr_vec     = ss_ovr & (m68k_a[23:2] == 22'h1f);

wire ss_iack7       = !m68k_as_n && m68k_fc == 3'b111 && m68k_a[3:1] == 3'b111;
wire ss_wr_ssp_hi   = !m68k_as_n && !m68k_rw && !m68k_uds_n && !m68k_lds_n && m68k_a[23:1] == 23'h7f8000;
wire ss_wr_ssp_lo   = !m68k_as_n && !m68k_rw && !m68k_uds_n && !m68k_lds_n && m68k_a[23:1] == 23'h7f8001;
wire ss_prog_fetch  = !m68k_as_n && m68k_rw && m68k_fc[1:0] == 2'b10 && !ss_in_handler && !(ss_restoring && ss_in_reset);

// 68000 and sound side run unless paused or held by a save-state sequence
wire m68k_run     = ss_idle ? ~pause_cpu : ss_cpu_execute;
wire z80_run      = ss_idle ? ~pause_cpu : (ss_state == SST_SAVE_Z80 && !z80_at_m1);
wire snd_run      = z80_run;
wire z80_int_mask = ~ss_idle;

always @(posedge clk_sys) begin
    reg m1_d;

    m1_d         <= M1_n;
    ss_write     <= 0;
    ss_read      <= 0;
    z80_dirset   <= 0;
    opl_rp_start <= 0;
    ss_timeout   <= ss_timeout + 1'd1;

    if (ss_busy) ss_busy_seen <= 1;

    case (ss_state)
        SST_IDLE: begin
            ss_timeout   <= 0;
            ss_busy_seen <= 0;
            z80_at_m1    <= 0;
            z80_ss_reset <= 0;
            if (!reset && ss_save) ss_state <= SST_SAVE_Z80;
            if (!reset && ss_load) begin
                z80_ss_reset <= 1;
                ss_read      <= 1;
                ss_state     <= SST_LOAD_READ;
            end
        end

        // sound cpu runs to the start of its next instruction fetch
        SST_SAVE_Z80: begin
            if (m1_d && !M1_n) z80_at_m1 <= 1;
            if (z80_at_m1) begin
                ss_timeout <= 0;
                ss_state   <= SST_SAVE_IRQ;
            end else if (&ss_timeout) ss_state <= SST_IDLE;
        end

        SST_SAVE_IRQ: begin
            if (ss_iack7) ss_state <= SST_SAVE_SSP;
            else if (&ss_timeout) ss_state <= SST_IDLE;
        end

        SST_SAVE_SSP: begin
            if (ss_wr_ssp_hi) ss_saved_ssp[31:16] <= m68k_dout;
            if (ss_wr_ssp_lo) begin
                ss_saved_ssp[15:0] <= m68k_dout;
                ss_write <= 1;
                ss_state <= SST_SAVE_WRITE;
            end
        end

        SST_SAVE_WRITE: if (ss_busy_seen && !ss_busy && !ss_write) ss_state <= SST_SAVE_EXIT;

        SST_SAVE_EXIT: if (ss_prog_fetch) ss_state <= SST_IDLE;

        SST_LOAD_READ: if (ss_busy_seen && !ss_busy && !ss_read) begin
            opl_rp_start <= 1;
            ss_state     <= SST_LOAD_OPL;
        end

        SST_LOAD_OPL: if (!opl_rp_start && !opl_rp_busy) begin
            z80_ss_reset <= 0;
            ss_state     <= SST_LOAD_Z80;
        end

        // registers loaded with the cpu out of reset and its clock enable stopped
        SST_LOAD_Z80: begin
            z80_dirset <= 1;
            ss_reset_vector[0] <= ss_restore_ssp[31:16];
            ss_reset_vector[1] <= ss_restore_ssp[15:0];
            ss_reset_vector[2] <= 16'h00ff;
            ss_reset_vector[3] <= 16'h0008;
            ss_reset_count     <= 0;
            ss_state           <= SST_LOAD_RESET;
        end

        SST_LOAD_RESET: if (m68k_ce) begin
            ss_reset_count <= ss_reset_count + 1'd1;
            if (&ss_reset_count) ss_state <= SST_LOAD_EXIT;
        end

        SST_LOAD_EXIT: if (ss_prog_fetch) ss_state <= SST_IDLE;

        default: ss_state <= SST_IDLE;
    endcase
end

// OPL register shadow (z80 writes) and replay after a restore
reg  [7:0] opl_sel;
(* ramstyle = "MLAB" *) reg  [7:0] opl_shadow[256];
reg  [7:0] opl_sh_q;
reg  [8:0] opl_clr;
wire       ss_opl_sel, ss_opl_we;
wire [7:0] ss_opl_addr, ss_opl_wdata;
reg  [7:0] opl_rp_idx;
reg  [2:0] opl_rp_step;
reg [11:0] opl_rp_wait;
reg        opl_rp_run;
reg        opl_rp_wr, opl_rp_addr;
reg  [7:0] opl_rp_data;
assign     opl_rp_busy = opl_rp_run;

wire       sh_z80_wr = sound_wr & sound_addr & snd_run;
wire [7:0] sh_addr   = ss_opl_sel ? ss_opl_addr : opl_rp_run ? opl_rp_idx : ~opl_clr[8] ? opl_clr[7:0] : opl_sel;
wire [7:0] sh_wdata  = ss_opl_sel ? ss_opl_wdata : ~opl_clr[8] ? 8'd0 : sound_data;
wire       sh_we     = ss_opl_sel ? ss_opl_we : opl_rp_run ? 1'b0 : ~opl_clr[8] ? 1'b1 : sh_z80_wr;

always @(posedge clk_sys) begin
    if (sh_we) opl_shadow[sh_addr] <= sh_wdata;
    opl_sh_q <= opl_shadow[sh_addr];
end

always @(posedge clk_sys) begin
    reg old_reset;

    old_reset <= reset;
    if (reset & ~old_reset) opl_clr <= 0;
    else if (~opl_clr[8]) opl_clr <= opl_clr + 1'd1;

    if (sound_wr & ~sound_addr & snd_run) opl_sel <= sound_data;
    if (ss_misc_wr) opl_sel <= ss_misc_out[9:2];

    opl_rp_wr <= 0;
    if (opl_rp_start) begin
        opl_rp_run  <= 1;
        opl_rp_idx  <= 0;
        opl_rp_step <= 0;
    end else if (opl_rp_run) begin
        case (opl_rp_step)
            0: begin
                opl_rp_wait <= 0;
                opl_rp_step <= 1;
            end
            1: begin
                opl_rp_wr   <= 1;
                opl_rp_addr <= 0;
                opl_rp_data <= opl_rp_idx;
                opl_rp_step <= 2;
            end
            2: begin
                opl_rp_wait <= opl_rp_wait + 1'd1;
                if (opl_rp_wait == 12'd16) begin
                    opl_rp_wr   <= 1;
                    opl_rp_addr <= 1;
                    opl_rp_data <= opl_sh_q;
                    opl_rp_wait <= 0;
                    opl_rp_step <= 3;
                end
            end
            3: begin
                opl_rp_wait <= opl_rp_wait + 1'd1;
                if (opl_rp_wait == 12'd2400) begin
                    opl_rp_idx  <= opl_rp_idx + 1'd1;
                    opl_rp_step <= (opl_rp_idx == 8'hff) ? 3'd4 : 3'd0;
                end
            end
            4: begin
                opl_rp_wr   <= 1;
                opl_rp_addr <= 0;
                opl_rp_data <= opl_sel;
                opl_rp_step <= 5;
            end
            default: opl_rp_run <= 0;
        endcase
    end
end

// save-state chunks
wire        ss_main_sel, ss_main_we;
wire [11:0] ss_main_addr;
wire [15:0] ss_main_wdata;
wire        ss_fg_sel, ss_fg_we, ss_bg_sel, ss_bg_we, ss_ram1_sel, ss_ram1_we;
wire [10:0] ss_fg_addr, ss_bg_addr, ss_ram1_addr;
wire [15:0] ss_fg_wdata, ss_bg_wdata, ss_ram1_wdata;
wire        ss_z80_sel, ss_z80_we;
wire [11:0] ss_z80_addr;
wire  [7:0] ss_z80_wdata;
wire [211:0] z80_reg, z80_dir;
wire [MISC_BITS-1:0] ss_misc_out;
wire        ss_misc_wr;
wire [MISC_BITS-1:0] ss_misc_in = { scroll_x, scroll_y, cocktail_flip, sound_latch, dac1, dac2, prot_cmd, nb1412m2_addr, nb1412m2_rom_dout, nb1412m2_adj_dout, opl_sel, z80_irq_n, m68k_ipl2_n };

ssbus_if ssbus();
ssbus_if ssb[SSIDX_COUNT]();

ssbus_mux #(.COUNT(SSIDX_COUNT)) ssmux
(
    .clk(clk_sys),
    .slave(ssbus),
    .masters(ssb)
);

ss_reg32 #(.SS_IDX(SSIDX_GLOBAL)) ss_ssp
(
    .clk(clk_sys), .ssbus(ssb[SSIDX_GLOBAL]),
    .value_in(ss_saved_ssp), .value_out(ss_restore_ssp)
);

ss_ram_port #(.AW(12), .DW(16), .SS_IDX(SSIDX_MAIN_RAM)) ss_main
(
    .clk(clk_sys), .ssbus(ssb[SSIDX_MAIN_RAM]),
    .sel(ss_main_sel), .addr(ss_main_addr), .wdata(ss_main_wdata), .we(ss_main_we), .q(ram68k_dout)
);

ss_ram_port #(.AW(11), .DW(16), .SS_IDX(SSIDX_FG_RAM)) ss_fg
(
    .clk(clk_sys), .ssbus(ssb[SSIDX_FG_RAM]),
    .sel(ss_fg_sel), .addr(ss_fg_addr), .wdata(ss_fg_wdata), .we(ss_fg_we), .q({8'h00, fg_ram_q[7:0]})
);

ss_ram_port #(.AW(11), .DW(16), .SS_IDX(SSIDX_BG_RAM)) ss_bg
(
    .clk(clk_sys), .ssbus(ssb[SSIDX_BG_RAM]),
    .sel(ss_bg_sel), .addr(ss_bg_addr), .wdata(ss_bg_wdata), .we(ss_bg_we), .q(bg_ram_q)
);

ss_ram_port #(.AW(11), .DW(16), .SS_IDX(SSIDX_RAM1)) ss_ram1
(
    .clk(clk_sys), .ssbus(ssb[SSIDX_RAM1]),
    .sel(ss_ram1_sel), .addr(ss_ram1_addr), .wdata(ss_ram1_wdata), .we(ss_ram1_we), .q(m68k_ram1_dout)
);

ss_ram_port #(.AW(12), .DW(8), .SS_IDX(SSIDX_Z80_RAM)) ss_z80
(
    .clk(clk_sys), .ssbus(ssb[SSIDX_Z80_RAM]),
    .sel(ss_z80_sel), .addr(ss_z80_addr), .wdata(ss_z80_wdata), .we(ss_z80_we), .q(z80_ram_dout)
);

auto_save_adaptor #(.N_BITS(212), .SS_IDX(SSIDX_Z80_REG)) ss_z80reg
(
    .clk(clk_sys), .ssbus(ssb[SSIDX_Z80_REG]),
    .bits_in(z80_reg), .bits_out(z80_dir), .bits_wr()
);

ss_ram_port #(.AW(8), .DW(8), .SS_IDX(SSIDX_OPL)) ss_opl
(
    .clk(clk_sys), .ssbus(ssb[SSIDX_OPL]),
    .sel(ss_opl_sel), .addr(ss_opl_addr), .wdata(ss_opl_wdata), .we(ss_opl_we), .q(opl_sh_q)
);

auto_save_adaptor #(.N_BITS(MISC_BITS), .SS_IDX(SSIDX_MISC)) ss_misc
(
    .clk(clk_sys), .ssbus(ssb[SSIDX_MISC]),
    .bits_in(ss_misc_in), .bits_out(ss_misc_out), .bits_wr(ss_misc_wr)
);

// keyboard: only F1 and Alt reach the save-state UI (F2/F3 are core keys)
reg [10:0] ss_ps2_key;
always @(posedge clk_sys) if (ps2_key[7:0] == 8'h05 || ps2_key[7:0] == 8'h11) ss_ps2_key <= ps2_key;

savestate_ui #(.INFO_TIMEOUT_BITS(26)) savestate_ui
(
    .clk            (clk_sys),
    .ps2_key        (ss_ps2_key),
    .allow_ss       (1'b1),
    .joySS          (joy0[9]),
    .joyRight       (joy0[0]),
    .joyLeft        (joy0[1]),
    .joyDown        (joy0[2]),
    .joyUp          (joy0[3]),
    .joyStart       (1'b0),
    .joyRewind      (1'b0),
    .rewindEnable   (1'b0),
    .status_slot    (status[66:65]),
    .autoincslot    (status[64]),
    .OSD_saveload   (status[68:67]),
    .ss_save        (ss_save),
    .ss_load        (ss_load),
    .ss_info_req    (ss_info_req),
    .ss_info        (ss_info),
    .statusUpdate   (ss_status_set),
    .selected_slot  (ss_slot)
);

// DDR3: save states and the rotation framebuffer
ddr_if ddr_host();
ddr_if ddr_ss();
ddr_if ddr_rot();

save_state_data save_state_data
(
    .clk(clk_sys),
    .reset(reset),
    .ddr(ddr_ss),
    .read_start(ss_read),
    .write_start(ss_write),
    .index(ss_slot),
    .busy(ss_busy),
    .ssbus(ssbus)
);

ddr_mux ddr_mux
(
    .clk(clk_sys),
    .x(ddr_host),
    .a(ddr_ss),
    .b(ddr_rot)
);

wire        rot_busy, rot_we, rot_rd;
wire  [7:0] rot_burstcnt, rot_be;
wire [28:0] rot_addr;
wire [63:0] rot_din;

assign ddr_rot.acquire    = ~ddr_ss.acquire;
assign ddr_rot.addr       = {rot_addr, 3'b000};
assign ddr_rot.wdata      = rot_din;
assign ddr_rot.read       = rot_rd;
assign ddr_rot.write      = rot_we;
assign ddr_rot.burstcnt   = rot_burstcnt;
assign ddr_rot.byteenable = rot_be;
assign rot_busy           = ddr_rot.busy;

assign DDRAM_CLK      = clk_sys;
assign DDRAM_ADDR     = ddr_host.addr[31:3];
assign DDRAM_DIN      = ddr_host.wdata;
assign DDRAM_RD       = ddr_host.read;
assign DDRAM_WE       = ddr_host.write;
assign DDRAM_BURSTCNT = ddr_host.burstcnt;
assign DDRAM_BE       = ddr_host.byteenable;
assign ddr_host.rdata       = DDRAM_DOUT;
assign ddr_host.rdata_ready = DDRAM_DOUT_READY;
assign ddr_host.busy        = DDRAM_BUSY;
    
endmodule


module delay
(
    input clk,  
    input ce,
    input i,
    output o
);

// Include the registered clk_6M phase so blanking matches the RGB pipeline.
reg [4:0] r;

assign o = r[4];

always @(posedge clk) begin
    if (ce) r <= { r[3:0], i };
end

endmodule
