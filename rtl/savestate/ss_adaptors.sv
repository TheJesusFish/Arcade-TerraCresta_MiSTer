// Save-state bus (ssbus) adaptors for TerraCrestaMD

// lends a RAM port to the save-state stream while it accesses this chunk
module ss_ram_port #(parameter AW = 12, DW = 16, SS_IDX = 0)
(
    input               clk,
    ssbus_if.slave      ssbus,

    output              sel,
    output     [AW-1:0] addr,
    output     [DW-1:0] wdata,
    output              we,
    input      [DW-1:0] q
);

assign sel   = ssbus.access(SS_IDX);
assign addr  = ssbus.addr[AW-1:0];
assign wdata = ssbus.data[DW-1:0];
assign we    = sel & ssbus.write;

reg rd_dly;
always @(posedge clk) begin
    ssbus.setup(SS_IDX, 2**AW, (DW == 8) ? 0 : 1);

    if (sel) begin
        if (ssbus.write) begin
            ssbus.write_ack(SS_IDX);
        end else if (ssbus.read) begin
            if (rd_dly) ssbus.read_response(SS_IDX, {{(64-DW){1'b0}}, q});
            rd_dly <= 1;
        end
    end else begin
        rd_dly <= 0;
    end
end

endmodule

// one 32-bit register chunk (68000 supervisor stack pointer)
module ss_reg32 #(parameter SS_IDX = 0)
(
    input               clk,
    ssbus_if.slave      ssbus,
    input        [31:0] value_in,
    output reg   [31:0] value_out
);

always @(posedge clk) begin
    ssbus.setup(SS_IDX, 1, 2);
    if (ssbus.access(SS_IDX)) begin
        if (ssbus.read) begin
            ssbus.read_response(SS_IDX, {32'd0, value_in});
        end else if (ssbus.write) begin
            value_out <= ssbus.data[31:0];
            ssbus.write_ack(SS_IDX);
        end
    end
end

endmodule
