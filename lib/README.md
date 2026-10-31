# The agonAMP sound library

These files can be lifted out of agonAMP and used in any eZ80 ADL-mode program for the Agon, for example to give a game PT3 music. `examples/playtune.asm` is a complete program of about sixty lines which demonstrates this.

## Files

| File | What it does | Needs |
| --- | --- | --- |
| `ascplay.asm` | ASC Sound Master replayer | `ay_regs`, `notetab.inc` |
| `ayfplay.asm` | AY file (ZXAYEMUL) player: runs a file's Z80 code and catches what it writes to the AY, one frame per call | `z80emu.asm`, `ay_regs` |
| `ayvdp.asm` | Plays AY register values through the Agon VDP's audio channels, for one AY chip or two. Defines the `ay_regs` and `ay_regs2` tables | `libsupport.asm` |
| `lh5.asm` | LH5 unpacker (the method of LHA's `-lh5-` archives); needs 20 KB of working space | |
| `libsupport.asm` | Buffered VDU output, 16 bit fetch, 24 bit division | |
| `notetab.inc` | Note tables shared by the ASC, PSC, STC and STP replayers | |
| `pscplay.asm` | Pro Sound Creator replayer | `ay_regs`, `notetab.inc` |
| `psgplay.asm` | PSG player: reads an AY register dump in memory, one frame per call | `ay_regs` |
| `pt1play.asm` | Pro Tracker 1 replayer, with its own note table | `ay_regs` |
| `pt2play.asm` | Pro Tracker 2 replayer, with its own note table | `ay_regs` |
| `pt3play.asm` | PT3 replayer: turns a module in memory into AY register values, one set per 50 Hz frame | `libsupport.asm`, `pt3tab.inc` |
| `pt3tab.inc` | Tone and volume tables for the replayer | |
| `pt3ts.asm` | TurboSound PT3 tunes for two AY chips: runs the PT3 replayer twice a frame | `pt3play.asm` (included before it), `ay_regs`, `ay_regs2` |
| `sqtplay.asm` | SQ-Tracker replayer, with its own note table | `ay_regs` |
| `stcplay.asm` | Sound Tracker (STC) replayer | `ay_regs`, `notetab.inc` |
| `stpplay.asm` | Sound Tracker Pro replayer | `ay_regs`, `notetab.inc` |
| `tick50.asm` | 50 Hz tick from eZ80 timer 1 | |
| `ymplay.asm` | YM and VTX player: unpacks the file in its buffer if need be, then gives one frame's registers per call | `lh5.asm`, `libsupport.asm`, `ay_regs` |
| `z80emu.asm` | Z80 emulation: runs Z80 code in a 64 KB page of memory. Must lie, with the tables it includes, in the same 64 KB as the rest of the program's code | `z80tab.inc` (included by it) |
| `z80tab.inc` | Decoding tables for `z80emu.asm`, made by `tools/mkz80tab.py` | |

The two halves are independent. The players (`ascplay.asm`, `ayfplay.asm`, `pscplay.asm`, `psgplay.asm`, `pt1play.asm`, `pt2play.asm`, `pt3play.asm`, `sqtplay.asm`, `stcplay.asm`, `stpplay.asm`, `ymplay.asm`) know nothing about the Agon and only fill in `ay_regs`. `ayvdp.asm` plays whatever is in `ay_regs`, so it can be driven by any other source of AY register values (a replayer of your own, or sound effects written straight into the table). Include only the replayers you need. A program that uses a replayer without `ayvdp.asm` must define `ay_regs` (16 bytes) itself.

## Using it

Include the files at the end of your program. The assembler finds include files relative to the directory it is run from.

```
        include "../lib/libsupport.asm"
        include "../lib/pt3play.asm"
        include "../lib/pt3tab.inc"
        include "../lib/ayvdp.asm"
        include "../lib/tick50.asm"
```

Start-up, once:

```
        call    ay_init         ; set up VDP channels 0 to 4
        ld      hl,tune         ; address of a PT3 module, anywhere in memory
        call    pt3_init
        call    tick_start      ; 50 Hz tick
```

In the main loop, as often as possible:

```
        ld      a,(tick_count)  ; is a frame of music due?
        or      a
        jr      z,no_music
        ld      hl,tick_count
        dec     (hl)
        call    pt3_play        ; fill ay_regs for this frame
        call    ay_update       ; play them
no_music:
```

On exit:

```
        call    tick_stop
        call    ay_shutdown
```

## Routines

| Routine | In | Effect |
| --- | --- | --- |
| `asc_init`, `psc_init`, `pt1_init`, `pt2_init`, `sqt_init`, `stc_init`, `stp_init` | HL = address of the module, BC = its length | Gets ready to play an ASC Sound Master, Pro Sound Creator, Pro Tracker 1, Pro Tracker 2, SQ-Tracker, Sound Tracker or Sound Tracker Pro module. Returns with carry set if the header's pointers do not make sense (these formats have no signature to check). `sqt_init` and `stp_init` may alter the module in memory (they convert compiled-in addresses to offsets), so the module must be in RAM |
| `asc_play`, `psc_play`, `pt1_play`, `pt2_play`, `sqt_play`, `stc_play`, `stp_play` | | Advance one frame and fill `ay_regs` |
| `ay_chips` | A = 1 or 2 | Chooses how many AY chips `ay_update` plays. With 2 it enables VDP channels 5 to 9 and plays `ay_regs2` on them as a second chip, each chip at half the level; with 1 it gives those channels up. `ay_init` starts with 1 |
| `ay_clock` | HL = clock in Hz | Sets the AY clock the registers are meant for (kept between 1 and 2 MHz). `ay_init` sets 1773400, the ZX Spectrum's |
| `ay_init` | | Enables VDP channels 3 and 4 and sets the waveforms of channels 0 to 4 |
| `ay_reset` | | `ay_silence`, and forgets the envelope state. Use when changing tune |
| `ay_shutdown` | | Silences, resets channels 0 to 2 and disables channels 3 and 4 |
| `ay_silence` | | Turns all the channels down, for a pause. The next `ay_update` restores them |
| `ay_update` | | Sends the VDP whatever has changed in `ay_regs` (and `ay_regs2`, with two chips) since the last call |
| `ay_volume` | A = 0 to 127 | Sets the VDP's overall volume (VDP 2.5.0 or later). It affects all sound and stays set after the program ends, so restore the old value on exit |
| `ayf_init` | HL = address of an AY file, BC = its length, A = top address byte of a free 64 KB page for the Z80's memory | Sets up the file's first song (or, if its data is bad, the next good one) and runs its set-up code. Returns with carry set if it is not an AY file or none of its songs can be played |
| `ayf_length` | | HL = the length of all the file's songs together, in frames |
| `ayf_nextno` | A = song number | A = the number of the song after it, wrapping round to 0 |
| `ayf_play` | | Plays one frame into `ay_regs`; when a song's length has been played, the next song starts |
| `ayf_song` | A = song number | Starts that song. Returns with carry set if its data is bad, in which case nothing is changed but the Z80, which is left stopped |
| `ayf_start` | A = song number | Starts that song or, if its data is bad, the next good one after it. Returns with carry set if no song in the file can be played |
| `ayf_startb` | A = song number | As `ayf_start`, but searching backwards: the nearest good song before it |
| `lh5_unpack` | HL = packed data, BC = its length, DE = where the result goes; `lh5_size` = the result's length, `lh5_work` = address of 20 KB of working space | Unpacks LH5 data. Returns with carry set if the data is not valid |
| `psg_init` | HL = address of a PSG file, BC = its length | Gets ready to play it. Returns with carry set if it is not a PSG file |
| `psg_play` | | Advances one frame and updates `ay_regs` |
| `pt3_init` | HL = module address | Gets ready to play from the start. The module must stay in memory |
| `pt3_init_m` | HL = module address, A = number of patterns | As `pt3_init`, but pattern n is played as pattern (count - 1 - n). Used by `pt3ts.asm` for the second chip of a one-module TurboSound tune. A = 0 is the same as `pt3_init` |
| `pt3_play` | | Advances one frame and fills `ay_regs` |
| `pt3ts_detect` | HL = address of a PT3 file, BC = its length | Returns A = 0 (and Z) if it is an ordinary PT3 module, 1 if it is two modules for two chips, 2 if it is one module with mirrored patterns for the second chip |
| `pt3ts_init` | | Gets the tune that `pt3ts_detect` accepted ready to play |
| `pt3ts_play` | | Advances one frame and fills `ay_regs` for the first chip and `ay_regs2` for the second |
| `tick_start`, `tick_stop` | | Start and stop the 50 Hz timer interrupt |
| `vdu_flush` | | Sends the queued bytes. Preserves all registers |
| `vdu_put` | A = byte | Queues a byte for the VDP. Preserves everything but the flags |
| `vtx_check` | HL = address of a VTX file, BC = its length | Reads the header. Returns with carry set if it is not a VTX file; otherwise HL = the packed data, BC = its length, DE = the unpacked length |
| `vtx_init` | DE = the unpacked registers, BC = their length | After `vtx_check`: gets ready to play. Carry set if they are no use |
| `ym_init` | HL = address of an unpacked YM file, BC = its length | Gets ready to play it. Returns with carry set if it is not a YM file this can play |
| `ym_length` | | HL = the song's length in frames (1/50 s) |
| `ym_load` | HL = a YM or VTX file at the start of a buffer, BC = its length, DE = the buffer's size; `lh5_work` set | Unpacks the file within the buffer if need be and gets ready to play it. On failure carry is set, with A = 0 if it is not a YM or VTX file (buffer untouched) or 1 if it is one but damaged or too big |
| `ym_play` | | Advances 1/50 s and updates `ay_regs`, taking as many of the file's frames as are due |
| `z_int` | | Z80 emulation: takes an interrupt, if the Z80's interrupts are enabled |
| `z_run` | `z_left` = how much the Z80 may do: one is used for each jump, call and return and for every 16 instructions | Z80 emulation: runs the Z80 until HALT or until `z_left` runs out. See the top of `z80emu.asm` for the set-up |

All the `pt3_` and `ay_` routines may change any register, including IX and IY.

## Song length

Each replayer has a routine that returns the length of the song in frames in HL: `pt3_length`, `pt2_length`, `pt1_length`, `stc_length`, `asc_length`, `stp_length`, `sqt_length`, `psc_length`, `pt3ts_length`, `psg_length`, `ym_length` and `ayf_length`. For the tracker formats, call it straight after the `_init` routine and then call `_init` again, because it works by running through the song's rows. `psg_length`, `ym_length` and `ayf_length` only read the file and can be called at any time after their set-up routine. Divide by 50 for seconds.

## Two chips (TurboSound)

To play a TurboSound PT3 tune, include `pt3ts.asm` after `pt3play.asm` and, when a PT3 file has been loaded:

```
        ld      hl,tune         ; address of the file
        ld      bc,length       ; its length
        call    pt3ts_detect
        jr      z,one_chip      ; an ordinary module: pt3_init, pt3_play
        call    pt3ts_init
        ld      a,2
        call    ay_chips        ; VDP channels 5 to 9 for the second chip
```

Then call `pt3ts_play` in place of `pt3_play` each frame; `ay_update` plays both chips. Call `ay_chips` with A = 1 before going back to a one-chip tune. `pt3_loops` and the other `pt3_` variables describe the first chip. The second chip's copy of the replayer's variables is at `pt3ts_c2` (the variable `pt3_xxx` is at `pt3ts_c2 + (pt3_xxx - pt3_ctx)`), and its channels are `pt3ts_chA2`, `pt3ts_chB2` and `pt3ts_chC2`.

## Things a program can read

- `ay_regs`: 14 bytes, AY registers R0 to R13. R13 holds 0FFh on frames where the envelope shape was not written. `ay_regs2` is the same for a second chip.
- `ayf_count`, `ayf_cur`, `ayf_last`: the number of songs in an AY file (0 for 256), the one playing, and the last one's number.
- `ayf_title`, `ayf_author`, `ym_title`, `ym_author`: addresses of zero-terminated names (`ym_` ones are 0 when the file has none).
- `pt3_loops`, `psg_loops`, `stc_loops`, `pt2_loops`, `pt1_loops`, `asc_loops`, `stp_loops`, `sqt_loops`, `psc_loops`, `ym_loops`, `ayf_loops`: go up by one each time the song reaches its end and starts again. Zero it and watch it to stop or change tune.
- `pt3_pos`, `pt3_numpos`, `pt3_row`, `pt3_delay`: position in the song, for display.
- `ym_clock`: the AY clock a YM or VTX file was made for; pass it to `ay_clock`.
- `pt3_patgen`: changes whenever a new pattern starts.

## Things a program can set

- `ay_mute`: bits 0, 1 and 2 mute AY channels A, B and C; bit 3 mutes all noise; bit 4 mutes the envelope ("buzz") channel. `ay_init` clears it. `ay_mute2` does the same for a second chip. A game can use this to free a channel's worth of the volume budget for its own sound effects.
- `pt3_chA`, `pt3_chB`, `pt3_chC`: per-channel state; the `PT3C_` offsets are listed at the top of `pt3play.asm`.

## Things to know

- **Call the music from the main loop, not from an interrupt.** `ay_update` sends VDU bytes. If it ran inside an interrupt, those bytes could land in the middle of a VDU sequence the main program was sending and corrupt both.
- **The tick is 50 Hz because PT3 tunes are.** Agon screen modes refresh at 60 Hz or more, so the vertical blank is the wrong clock. If your program has no use for timer 1 otherwise, `tick50.asm` does the job. If the main loop falls behind, at most four ticks are kept, so the music resumes instead of racing.
- **VDP channels 0 to 4 belong to the music** while it plays (and 5 to 9 as well after `ay_chips` with A = 2). Sound effects should use channels 5 and up, or 10 and up (enable them with `VDU 23,0,&85,channel,8`). The VDP rescales its mix when channel volumes add up to more than 127; the music uses up to 126, so loud effects will make the music dip while they sound.
- **Global names.** The assembler has no namespaces, so everything in the library is prefixed `AC_`, `asc_`, `AY_`, `ay_`, `ayf_`, `AYF_`, `cl_`, `lh5_`, `lh_`, `LH_`, `LHW_`, `lib_`, `mt_`, `nt_`, `P1_`, `P2_`, `psc_`, `PSC_`, `PSCC_`, `psg_`, `pt1_`, `PT1_`, `PT2_`, `pt2_`, `pt3_`, `PT3_`, `PT3C_`, `pt3ts_`, `pt_`, `SC_`, `SQ_`, `sqt_`, `stc_`, `STC_`, `stp_`, `tick_`, `TICK_`, `TP_`, `vdu_`, `vtx_`, `ym_`, `z_` or `ZE_`. Avoid those prefixes for your own labels.
- **Memory.** Code, tables and variables, in bytes: `ascplay.asm` 2181, `ayfplay.asm` 1115, `ayvdp.asm` 1877, `lh5.asm` 2282, `libsupport.asm` 384, `notetab.inc` 364, `pscplay.asm` 2018, `psgplay.asm` 349, `pt1play.asm` 1275, `pt2play.asm` 1675, `pt3play.asm` 2120, `pt3tab.inc` 1856, `pt3ts.asm` 1000, `sqtplay.asm` 2204, `stcplay.asm` 1128, `stpplay.asm` 1500, `tick50.asm` 77, `ymplay.asm` 1327, `z80emu.asm` 2566 (`z80emu.asm` includes `z80tab.inc` and up to 255 bytes of alignment). `lh5.asm` also needs 20 KB of working space, and `ayfplay.asm` a 64 KB page for the Z80. The tune comes on top.