//============================================================================
//  High-score save/restore from MAME hiscore.dat entries
//
//  This program is free software; you can redistribute it and/or modify it
//  under the terms of the GNU General Public License as published by the Free
//  Software Foundation; either version 2 of the License, or (at your option)
//  any later version.
//============================================================================

// MRA rom index 3: entries {addr[4], len[2], start, end}; nvram index 4: the saved table
module hiscore #(parameter WAIT_FRAMES = 30)
(
    input             clk,
    input             reset,

    input             ioctl_download,
    input             ioctl_upload,
    input             ioctl_wr,
    input      [15:0] ioctl_index,
    input      [26:0] ioctl_addr,
    input       [7:0] ioctl_dout,
    output      [7:0] ioctl_din,
    output reg        upload_req,

    input             autosave,
    input             save_now,
    input             osd_open,
    input             frame,
    input             ram_ok,

    output reg        ram_sel,
    output reg [12:0] ram_addr,
    output reg  [7:0] ram_wdata,
    output reg        ram_we,
    input       [7:0] ram_q,

    output            has_entries
);

localparam MAXE = 4;

// entry list
reg  [7:0] ent[MAXE*8];
reg  [5:0] ent_bytes;
wire [2:0] n_ent = ent_bytes[5:3];
assign has_entries = n_ent != 0;

// saved table buffer
(* ramstyle = "MLAB" *) reg  [7:0] nvbuf[256];
reg  [7:0] buf_addr;
reg  [7:0] buf_q;
reg  [7:0] buf_wdata;
reg        buf_we;

wire dl_ent   = ioctl_download & (ioctl_index == 16'd3);
wire dl_nv    = ioctl_download & (ioctl_index == 16'd4);
wire up_nv    = ioctl_upload   & (ioctl_index == 16'd4);
wire dl_rom   = ioctl_download & (ioctl_index == 16'd0);

// buffer port: host download/upload, otherwise the copy engine
wire [7:0] b_addr = (dl_nv | up_nv) ? ioctl_addr[7:0] : buf_addr;
wire [7:0] b_data = dl_nv ? ioctl_dout : buf_wdata;
wire       b_we   = dl_nv ? (ioctl_wr & ~|ioctl_addr[26:8]) : buf_we;

always @(posedge clk) begin
    if (b_we) nvbuf[b_addr] <= b_data;
    buf_q <= nvbuf[b_addr];
end

assign ioctl_din = buf_q;

// entry download and saved-table presence
reg have_nv;
always @(posedge clk) begin
    if (dl_rom) begin
        ent_bytes <= 0;
        have_nv   <= 0;
    end
    if (dl_ent & ioctl_wr & (ioctl_addr < MAXE*8)) begin
        ent[ioctl_addr[4:0]] <= ioctl_dout;
        ent_bytes <= ioctl_addr[5:0] + 6'd1;
    end
    if (dl_nv & ioctl_wr & ~|ioctl_addr[26:8]) have_nv <= 1;
end

// current entry fields
reg  [1:0] ei;
wire [4:0] eb = {ei, 3'b000};
wire [12:0] e_addr  = {ent[eb + 5'd2][4:0], ent[eb + 5'd3]};
wire [15:0] e_len   = {ent[eb + 5'd4], ent[eb + 5'd5]};
wire  [7:0] e_start = ent[eb + 5'd6];
wire  [7:0] e_end   = ent[eb + 5'd7];

typedef enum logic [3:0] {
    ST_WAIT, ST_FRAME, ST_CHK_S, ST_CHK_E, ST_RESTORE, ST_READY, ST_SAVE, ST_REQ
} state_t;
state_t state;

reg  [8:0] frames;
reg  [2:0] step;
reg [15:0] off;
reg  [7:0] pos;
reg        ok;
reg        pass1;
reg        old_frame, old_osd, old_save;

wire frame_rise = frame & ~old_frame;

always @(posedge clk) begin
    old_frame  <= frame;
    old_osd    <= osd_open;
    old_save   <= save_now;
    upload_req <= 0;
    ram_we     <= 0;
    buf_we     <= 0;

    if (reset | dl_rom) begin
        state   <= ST_WAIT;
        frames  <= 0;
        ram_sel <= 0;
        step    <= 0;
        pass1   <= 0;
    end else begin
        case (state)
            // let the game initialise its table first
            ST_WAIT: if (frame_rise && n_ent != 0) begin
                frames <= frames + 1'd1;
                if (frames == WAIT_FRAMES) state <= ST_FRAME;
            end

            // one check of every entry's start/end bytes per frame
            ST_FRAME: if (frame_rise) begin
                ei    <= 0;
                ok    <= 1;
                step  <= 0;
                state <= ST_CHK_S;
            end

            ST_CHK_S, ST_CHK_E: begin
                case (step)
                    0: if (ram_ok) begin
                        ram_sel  <= 1;
                        ram_addr <= (state == ST_CHK_S) ? e_addr : e_addr + e_len[12:0] - 1'd1;
                        step     <= 1;
                    end
                    1: step <= 2;
                    2: step <= 3;
                    3: begin
                        ram_sel <= 0;
                        step    <= 0;
                        if (ram_q != ((state == ST_CHK_S) ? e_start : e_end)) ok <= 0;
                        if (state == ST_CHK_S) state <= ST_CHK_E;
                        else if (ei + 1'd1 < n_ent) begin
                            ei    <= ei + 1'd1;
                            state <= ST_CHK_S;
                        // the table is ready once every check passes on two consecutive frames
                        end else if (ok && ram_q == e_end && pass1) begin
                            ei    <= 0;
                            off   <= 0;
                            pos   <= 0;
                            state <= have_nv ? ST_RESTORE : ST_READY;
                        end else begin
                            pass1 <= ok && ram_q == e_end;
                            state <= ST_FRAME;
                        end
                    end
                    default: step <= 0;
                endcase
            end

            // buffer -> RAM
            ST_RESTORE: begin
                case (step)
                    0: begin
                        buf_addr <= pos;
                        step     <= 1;
                    end
                    1: step <= 2;
                    2: if (ram_ok) begin
                        ram_sel   <= 1;
                        ram_addr  <= e_addr + off[12:0];
                        ram_wdata <= buf_q;
                        ram_we    <= 1;
                        step      <= 3;
                    end
                    3: begin
                        ram_sel <= 0;
                        step    <= 0;
                        pos     <= pos + 1'd1;
                        if (off + 1'd1 < e_len) off <= off + 1'd1;
                        else begin
                            off <= 0;
                            if (ei + 1'd1 < n_ent) ei <= ei + 1'd1;
                            else state <= ST_READY;
                        end
                    end
                    default: step <= 0;
                endcase
            end

            ST_READY: if ((autosave & osd_open & ~old_osd) | (save_now & ~old_save)) begin
                ei    <= 0;
                off   <= 0;
                pos   <= 0;
                step  <= 0;
                state <= ST_SAVE;
            end

            // RAM -> buffer, then ask the HPS to fetch it
            ST_SAVE: begin
                case (step)
                    0: if (ram_ok) begin
                        ram_sel  <= 1;
                        ram_addr <= e_addr + off[12:0];
                        step     <= 1;
                    end
                    1: step <= 2;
                    2: step <= 3;
                    3: begin
                        ram_sel   <= 0;
                        buf_addr  <= pos;
                        buf_wdata <= ram_q;
                        buf_we    <= 1;
                        step      <= 0;
                        pos       <= pos + 1'd1;
                        if (off + 1'd1 < e_len) off <= off + 1'd1;
                        else begin
                            off <= 0;
                            if (ei + 1'd1 < n_ent) ei <= ei + 1'd1;
                            else state <= ST_REQ;
                        end
                    end
                    default: step <= 0;
                endcase
            end

            ST_REQ: begin
                upload_req <= 1;
                state      <= ST_READY;
            end

            default: state <= ST_WAIT;
        endcase
    end
end

endmodule
