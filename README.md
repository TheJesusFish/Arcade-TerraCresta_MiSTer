
# Nichibutsu M68000 (Terra Cresta) FPGA Implementation

FPGA compatible core of Nichibutsu M68000 (Terra Cresta Based) arcade hardware for [**MiSTerFPGA**](https://github.com/MiSTer-devel/Main_MiSTer/wiki) written by [**Erin Olafson**].  Terra Cresta YM2203 OPN Type PCB donated by [**@atrac17**](https://twitter.com/_atrac17) / [**@djhardrich**](https://twitter.com/djhardrich). Maintenance and miscellaneous quality of life features added by TheJesusfish.

The goal for this implementation is gameplay to be 1:1 of the Nichibutsu (Terra Cresta based) 68000 hardware. This core was developed with assistance from [**atrac17**](https://github.com/atrac17).

The **MD** version (RBF `Arcade-TerraCrestaMD_YYYYMMDD.rbf`, MRAs `... [MD].mra`, `<rbf>TerraCrestaMD</rbf>`) adds save states, high-score saving, per-controller start/coin, MAME 0.288 DIP switches, a current MiSTer framework and fully clock-enabled timing. It is based on the original core by va7deo ([va7deo/TerraCresta](https://github.com/va7deo/TerraCresta)).

![Nichibutsu TC](https://user-images.githubusercontent.com/32810066/172844714-a23fce6b-2eab-4c47-ae46-e0c48f447c84.png)

## Supported Games

| Title | MAME set | MRA | Protection |
|-------|----------|-----|------------|
| [**Terra Cresta**](https://en.wikipedia.org/wiki/Terra_Cresta) (YM3526 set 1) | terracre | `releases/` | None |
| Terra Cresta (YM3526 set 2 / set 3) | terracreo, terracrea | `_alternatives/_Terra Cresta/` | None |
| [**Soldier Girl Amazon**](https://en.wikipedia.org/wiki/Soldier_Girl_Amazon) | amazon | `releases/` | NB1412M2 |
| Soldier Girl Amazon (Tecfri license), Sei Senshi Amatelass | amazont, amatelas | `_alternatives/_Soldier Girl Amazon/` | NB1412M2 |
| **Kid no Hore Hore Daisakusen** | horekid | `releases/` | NB1412M2 |
| Kid no Hore Hore Daisakusen (bootleg set 1 / set 2), Booby Kids | horekidb, horekidb2, boobhack | `_alternatives/_Kid no Hore Hore Daisakusen/` | None |

MRAs follow MAME 0.288 (ROMs, DIP switches with MAME's options, order and defaults, high-score tables).
Not supported: **Terra Cresta (YM2203)** (`terracren`) — it uses a YM2203 sound board; this core has the YM3526 only.

## Controls

Default MiSTer mapping (every MRA): **Button 1 → A, Button 2 → B, Start → Start, Coin → Select, Pause → R, Save/Load → L**.
Each controller drives its own player: controller 1 Start/Coin = 1P Start / Coin 1, controller 2 Start/Coin = 2P Start / Coin 2, and all player 2 controls come from controller 2. With the default **Upright** cabinet the games alternate players on the player 1 controls, as on the PCB; set **Cabinet = Cocktail** to play player 2 on controller 2 (the screen flips for player 2's turns).

| Game | Joystick | Button 1 | Button 2 | Source of the names |
|------|----------|----------|----------|---------------------|
| Terra Cresta | 8-way | Cannon Beam | Formation | Instruction art in `doc/` (キャノンビーム / フォーメーション) |
| Soldier Girl Amazon | 8-way | Sword Beam | Stop Bullet | Original va7deo MRAs; Japanese instruction card (ソードビーム / ストップ弾) |
| Kid no Hore Hore Daisakusen | 4-way | Dig/Bury | Open/Close Door | Original va7deo MRAs |

Button combinations: none in normal play. Kid no Hore Hore Daisakusen **Debug Mode** DIP (Cabinet = Upright): insert a coin and press P2 Button 1 + Button 2 for level select (P1 Button 1 / Button 2 change the level, P1 Start starts); P2 Button 1 + Button 2 + P1 Start gives invulnerability and infinite time. Soldier Girl Amazon **Debug Mode** DIP: invulnerability, hold 2P Start to fast forward (also OSD "Turbo (Amazon Sets)").

### Keyboard

| Function | Key | Function | Key |
|---|---|---|---|
| P1 Start / P2 Start | 1 / 2 | P1 Coin / P2 Coin | 5 / 6 |
| P1 Up/Down/Left/Right | Cursor keys | P1 Button 1 / 2 | L-Ctrl / L-Alt |
| P2 Up/Down/Left/Right | R / F / D / G | P2 Button 1 / 2 | A / S |
| Service | 9 | Test (service mode) | F2 |
| Reset | F3 | Pause | P |
| Layer toggles (FG / BG / sprites) | F7 / F8 / F9 | Restore / save state (slot 1) | F1 / Alt+F1 |

## Core Features

- **Save states**: hold **L** on controller 1, then **Down** saves, **Up** restores, **Left/Right** changes the slot (4 slots). Also in the OSD (slot, autoincrement, save/restore) and F1 / Alt+F1. States are written to `savestates/` by Main.
- **High scores**: the high-score table (MAME `hiscore.dat` entries) is saved to `config/nvram/<game>.nvm` when the OSD is opened (OSD "Autosave Hiscores", default On) or with OSD "Save Hiscores", and restored after the game has initialised its table.

## External Modules

| Name | Purpose | Author | Source |
|------|---------|--------|--------|
| [**fx68k**](https://github.com/ijor/fx68k) | Motorola 68000 CPU | Jorge Cwik | ijor/fx68k @ `0602ee4627b10f301298f2673d826cdd6baa9327` |
| [**T80**](https://github.com/MiSTer-devel/NeoGeo_MiSTer/tree/90a8350c4e7fafb64067cf777b58a93bc7511fdc/rtl/cpu/T80) | Zilog Z80 CPU | Daniel Wallner, Sorgelig, MiSTer-devel | MiSTer-devel/NeoGeo_MiSTer @ `90a8350c4e7fafb64067cf777b58a93bc7511fdc` (`rtl/cpu/T80`) |
| [**jtopl**](https://github.com/jotego/jtopl) | Yamaha YM3526 (OPL) | Jose Tejada | jotego/jtopl @ `f96ff3ef16311e677b8bccc429b1b8f9a4e53276` |
| [**Pause_MiSTer**](https://github.com/JimmyStones/Pause_MiSTer) | Pause / dim | Jim Gregory | as modified in va7deo/TerraCresta |
| dual_port_ram / math | Block RAM wrapper | Josh Bassett (nullobject), MIT | via va7deo/TerraCresta |
| [**Save states**](https://github.com/MiSTer-devel/Arcade-TaitoF2_MiSTer) | `ddram`, `memory_stream`, `savestates`, `savestate_ui` and the 68000 save/restore technique | Martin Donlon (wickerwaka); savestate_ui from FPGAzumSpass's MiSTer cores | MiSTer-devel/Arcade-TaitoF2_MiSTer @ `9438df98f1ea826c5398db43587992def0124603` |
| High-score saving | Flow modelled on MiSTer-devel/Arcade-RaizingMD_MiSTer and Arcade-IGSPGM_MiSTer; table data from MAME `hiscore.dat` | MAME hiscore.dat contributors | MAME 0.288 |
| [**Template_MiSTer**](https://github.com/MiSTer-devel/Template_MiSTer) | MiSTer framework (`sys/`) | MiSTer-devel | `e901a9fa6548f4eb024619357b89d48be94fd9f8` |

# PCB Check List

FPGA implementation is based on Terra Cresta and was verified against the YM2203 PSG Type PCB with a YM3526 swap.

### Clock Information

H-Sync      | V-Sync      | Source |
------------|-------------|--------|
15.625kHz   | 59.323592Hz | [DSLogic +](https://github.com/va7deo/TerraCresta/blob/main/doc/Terra%20Cresta%2006827/tc_csync.png) |

### Crystal Oscillators

Location | Freq (MHz) | Use          |
---------|------------|--------------|
2        | 16.000     | M68000       |
X1       | 12.000     | Z80 / YM3526 |

**Pixel clock:** 6.00 MHz

**Estimated geometry:**

    384 pixels/line
  
    263 pixels/line

### Main Components

Location | Chip | Use |
---------|------|-----|
I C (Top Board)     | [**Motorola 68000 CPU**](https://en.wikipedia.org/wiki/Motorola_68000) | Main CPU  |
17 D (Bottom Board) | [**Zilog Z80 CPU**](https://en.wikipedia.org/wiki/Zilog_Z80)           | Sound CPU |
20 D (Bottom Board) | [**Yamaha YM3526**](https://en.wikipedia.org/wiki/Yamaha_OPL#OPL)      | OPL       |

### Nichibutsu Custom Components

| Location | Chip | Use | PCB | ROM set |
|----------|-----|------|-----|---------|
15 G (Top Board) | [**NB1412M2**](https://raw.githubusercontent.com/va7deo/TerraCresta/main/doc/Sei%20Senshi%20Amatelass/Sei%20Senshi%20Amatelass%20Front.jpg) | Protection IC | <u>**Sei Senshi Amatelass <br><br> Kid no Hore Hore Daisakusen**</u> | amatelas, amazon, amazont <br><br> horekid |

# Debug Features

- The three graphics layers can be toggled in the OSD (PCB & Debug Settings) or with F7-F9.
- Sprite flip on the X / Y axis can be inverted in the OSD (PCB & Debug Settings).
