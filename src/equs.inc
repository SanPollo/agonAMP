; equs.inc - constants for agonAMP: MOS API numbers, system variable
; offsets and the program's memory map.
;
; Copyright (c) 2026 Nick J. Date
;
; This software is provided 'as-is', without any express or implied
; warranty. In no event will the authors be held liable for any damages
; arising from the use of this software.
;
; Permission is granted to anyone to use this software for any purpose,
; including commercial applications, and to alter it and redistribute it
; freely, subject to the following restrictions:
;
; 1. The origin of this software must not be misrepresented; you must not
;    claim that you wrote the original software. If you use this software
;    in a product, an acknowledgment in the product documentation would be
;    appreciated but is not required.
; 2. Altered source versions must be plainly marked as such, and must not
;    be misrepresented as being the original software.
; 3. This notice may not be removed or altered from any source
;    distribution.
;
; The MOS values were checked against agon-docs (docs/mos/API.md) and
; agon-mos v3.0.2 (src/mos_api.inc).

; MOS API functions (number in A, then RST.LIL 08h).
mos_sysvars:		equ	08h
mos_fopen:		equ	0Ah
mos_fclose:		equ	0Bh
mos_fread:		equ	1Ah
mos_fwrite:		equ	1Bh
ffs_dopen:		equ	91h
ffs_dclose:		equ	92h
ffs_dread:		equ	93h
ffs_getcwd:		equ	9Eh

; MOS system variables (offsets from the pointer mos_sysvars returns).
sysvar_time:		equ	00h	; centiseconds
sysvar_vpd_pflags:	equ	04h
sysvar_keyascii:	equ	05h
sysvar_audioChannel:	equ	0Dh
sysvar_audioSuccess:	equ	0Eh
sysvar_scrCols:		equ	13h
sysvar_scrRows:		equ	14h
sysvar_scrColours:	equ	15h
sysvar_vkeycode:	equ	17h
sysvar_vkeydown:	equ	18h
sysvar_vkeycount:	equ	19h
sysvar_scrMode:		equ	27h

; FatFS FILINFO layout (agon-mos src/mos_api.inc).
FI_ATTRIB:		equ	8
FI_NAME:		equ	22
FI_SIZE:		equ	278
AM_HID:			equ	02h
AM_DIR:			equ	10h

; Memory map. The program loads at 040000h and may take up to 64 KB;
; these areas lie above it. 0B0000h and up is left to MOS.
PAT_CH:			equ	1280	; bytes of PAT_TAB per channel
MODULE:			equ	050000h	; the music file being played
MODULE_MAX:		equ	040000h	; largest music file (256K)
PL_POOL:		equ	090000h	; playlist path strings
PL_POOL_END:		equ	097F00h
IOBUF:			equ	098000h	; playlist file text
IOBUF_MAX:		equ	007FF0h	; largest playlist file (32K)
BR_POOL:		equ	0A0000h	; file browser entries
BR_POOL_END:		equ	0ABE00h
; pattern decoded for display: six channels' worth (7680 bytes), of
; which only a TurboSound tune uses the second three
PAT_TAB:		equ	0AC000h
PAT_TAB2:		equ	0AE000h	; the same for the pattern that follows
PL_MAX:			equ	255	; most entries in the playlist
; directory path buffers (br_path, m3u_dir, sv_path) are PATH_SIZE
; bytes; a directory path may be up to PATH_LIM characters, leaving room
; for a '/' and the terminator
PATH_SIZE:		equ	300
PATH_LIM:		equ	298
TMP_SIZE:		equ	600	; tmp_path and cur_path
BR_MAX:			equ	500	; most entries shown in a directory

; Screen layout (rows). The panel fills what is left above the key bar.
ROW_TITLE:		equ	0
ROW_FILE:		equ	1
ROW_SONG:		equ	2
ROW_STATUS:		equ	3
ROW_CHBAR:		equ	4
ROW_CHA:		equ	5
ROW_NE:			equ	8
ROW_PANBAR:		equ	9
ROW_PANEL:		equ	10
; While a TurboSound tune is loaded the second chip's three channel
; lines and its noise and envelope line come next, and the panel bar and
; the panel are that much lower.
ROW_CHD:		equ	9
ROW_NE2:		equ	12
TS_ROWS:		equ	4
; The spectrum analyser (spectrum.asm), while it is shown, comes next: a
; blank row, then AN_BARS rows of bars. It is shown when it is wanted (V,
; and the settings) on screens of AN_MIN rows or more, which leave the
; panel at least eight rows even with a TurboSound tune.
AN_COLS:		equ	79	; one per semitone, C1 to F#7
AN_BARS:		equ	16
AN_ROWS:		equ	AN_BARS+1
AN_MIN:			equ	ROW_PANEL+1+TS_ROWS+AN_ROWS+8

; Colours of the default 16 colour palette. Three of them are the colour
; theme's (config.asm: theme_apply), and are named for their part in it:
; dark (for bars and the dark third of the meters), medium and light.
; In the OCP theme they are as in the default palette: blue, bright blue
; and bright green.
COL_BLACK:		equ	0
COL_RED:		equ	1
COL_GREEN:		equ	2
COL_YELLOW:		equ	3
COL_DARK:		equ	4	; theme's dark colour (blue)
COL_CYAN:		equ	6
COL_GREY:		equ	7
COL_DGREY:		equ	8
COL_BRED:		equ	9
COL_LIGHT:		equ	10	; theme's light colour (bright green)
COL_BYELLOW:		equ	11
COL_MID:		equ	12	; theme's medium colour (bright blue)
COL_BCYAN:		equ	14
COL_WHITE:		equ	15
BG:			equ	128	; add to a colour to set the background

; Song formats.
FMT_PT3:		equ	0
FMT_PSG:		equ	1
FMT_STC:		equ	2
FMT_PT2:		equ	3
FMT_PT1:		equ	4
FMT_ASC:		equ	5
FMT_STP:		equ	6
FMT_SQT:		equ	7
FMT_PSC:		equ	8
FMT_COUNT:		equ	9	; (the end of those in fmt_tab)
FMT_YM:			equ	9	; YM and VTX files
FMT_AY:			equ	10	; AY files

; Formats from FMT_PT2 on are handled through a table (fmt_tab in
; agonamp.asm), one entry of these fields per format.
; replayer: set up (HL = module, BC = length)
F_INIT:			equ	0
F_PLAY:			equ	3	; replayer: play one frame
; replayer: length of the song in frames
F_LENGTH:		equ	6
F_STATUS:		equ	9	; its five status bytes for the screen
F_CHAN:			equ	12	; its channel A state
F_CHSIZE:		equ	15	; size of one channel's state
F_NAME:			equ	18	; offset of a name in the module, or 0
F_NLEN:			equ	21	; its length (up to 32)
F_AUTH:			equ	24	; offset of an author's name, or 0
F_ALEN:			equ	27	; its length (up to 27)
; the file name extension (4 characters)
F_EXT:			equ	30
F_SIZE:			equ	33

; Player states.
ST_STOPPED:		equ	0
ST_PLAYING:		equ	1
ST_PAUSED:		equ	2
ST_LOADERR:		equ	3
ST_BADFILE:		equ	4