// Save-state constants for TerraCrestaMD: DDR base and chunk indices
package system_consts;
    parameter bit [31:0] SS_DDR_BASE = 32'h3E00_0000;

    parameter int SSIDX_GLOBAL   = 0;
    parameter int SSIDX_MAIN_RAM = 1;
    parameter int SSIDX_FG_RAM   = 2;
    parameter int SSIDX_BG_RAM   = 3;
    parameter int SSIDX_RAM1     = 4;
    parameter int SSIDX_Z80_RAM  = 5;
    parameter int SSIDX_Z80_REG  = 6;
    parameter int SSIDX_OPL      = 7;
    parameter int SSIDX_MISC     = 8;
    parameter int SSIDX_COUNT    = 9;
endpackage

// makes the constants visible to the save-state files compiled after this one
import system_consts::*;
