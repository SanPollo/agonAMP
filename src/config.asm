; config.asm - agonAMP's settings file and screen modes.
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
; Settings. At start-up, /config/agonamp/agonamp.conf is read if it is
; there; on exit the settings in force are written to it. If the file is
; not there but the directory /config/agonamp is, the file is made on
; exit; if neither is there, nothing is saved.
;
; The file is text, one setting a line, as name=value with the value a
; whole number from 0 to 255, or for directory a path:
;
;   mode=0          screen mode (Z and X)
;   analyser=1      spectrum analyser wanted, 1, or not, 0 (V)
;   shuffle=0       shuffle on, 1, or off, 0 (R)
;   volume=127      the VDP's volume, 0 to 127 (+ and -)
;   theme=0         colour theme: 0 OCP, 1 Autumn, 2 Iceberg, 3 Emerald,
;                   4 Sand Dune, 5 Amethyst (T)
;   directory=/     the directory the file browser was showing
;
; Lines with any other name, or that do not read as above (including
; comments, which can start with '#'), are ignored, and so are settings
; out of range. Every setting is given its default (in cfg_tab) before
; the file is read, so one that is missing or ignored keeps it. The
; defaults are: analyser 1, shuffle 0, theme 0, for mode and volume
; none (0FFh), which leave the screen mode and the VDP's volume as they
; were, and for directory none (empty), which leaves the browser in the
; current directory. Line ends may be LF or CR LF, and the last line
; need not have one; the file is written with LF, and none after the
; last line.
;
; The directory is the rest of its line, taken as it is. It is used
; (cfg_usedir) only if it is an absolute path, of PATH_LIM characters
; or fewer, to a directory that can be opened; otherwise it is passed
; over without a word and the browser starts in the current directory.
; It is only where the browser starts: MOS's current directory is not
; changed, so a relative path on the command line is still taken from
; the directory agonAMP was run from.
;
; Screen modes: Z and X step through the modes in scr_modes: the
; 16-colour modes agonAMP can use in the VDP 2.16.0 source (80 columns or
; more, not double-buffered). Modes 3 and 27 can be used too (started in,
; or named in the settings), but are left out of the list: they are
; modes 4 and 28 with 64 colours, which agonAMP has no use for. Each mode
; is checked after the change and passed over if the VDP did not give
; one that will do. The screen mode in use when agonAMP was started is
; put back on exit.

CFG_MAX:	equ	1000		; most of the file that is read
CFG_SIZE:	equ	8		; bytes a setting takes in cfg_tab
THEME_N:	equ	6		; colour themes (theme_tab)

cfg_on:		ds	1	; non-zero: settings can be saved
cfg_lead:	ds	1	; cfg_dec: a digit has been written
cfg_mode:	ds	1	; settings file: screen mode (0FFh: none)
cfg_vol:	ds	1	; settings file: volume (0FFh: none)
scr_mode:	ds	1	; the screen mode in use
scr_orig:	ds	1	; the screen mode at start-up
scr_was:	ds	1	; scr_step: the mode before the change
theme:		ds	1	; the colour theme (T; the settings)

; cfg_load: give each variable in cfg_tab its default, then read the
; settings file, if there is one, into them (cfg_mode and cfg_vol are
; 0FFh if not given), and find out whether settings can be saved
; (cfg_on).
cfg_load:
	xor	a
	ld	(cfg_on),a
	ld	iy,cfg_tab		; the defaults
@def:
	ld	hl,(iy+0)
	ld	a,(hl)
	or	a
	jr	z,@read
	ld	hl,(iy+3)
	ld	a,(iy+6)
	ld	(hl),a
	lea	iy,iy+CFG_SIZE
	jr	@def
@read:
	ld	hl,txt_cfgfile
	ld	de,IOBUF
	ld	bc,CFG_MAX
	call	file_read
	jr	c,@nofile
	ld	de,IOBUF		; (HL = bytes read)
	add	hl,de
	ld	(hl),0
	ld	a,1
	ld	(cfg_on),a
	ld	hl,IOBUF
@line:
	ld	a,(hl)
	or	a
	ret	z
	ld	iy,cfg_tab
@key:
	ld	de,(iy+0)		; the next name (0: none left)
	ld	a,(de)
	or	a
	jr	z,@skip
	push	hl
@cmp:
	ld	a,(de)
	or	a
	jr	z,@match
	cp	(hl)
	jr	nz,@differ
	inc	de
	inc	hl
	jr	@cmp
@differ:
	pop	hl
	lea	iy,iy+CFG_SIZE
	jr	@key
@match:
	pop	de			; (the start of the line)
	ld	a,(iy+7)		; a text setting (most 0): the rest of
	or	a			; the line
	jr	z,@text
	call	cfg_num			; C = the value; carry if none
	jr	c,@skip
	ld	a,(iy+7)		; out of range: ignored
	cp	c
	jr	c,@skip
	ld	de,(iy+3)
	ld	a,c
	ld	(de),a
	jr	@skip
@text:
	ld	de,(iy+3)
	call	cfg_text
@skip:
	ld	a,(hl)			; on to the next line
	or	a
	ret	z
	inc	hl
	cp	10
	jr	nz,@skip
	jr	@line
@nofile:
	ld	hl,dirobj		; no file: is the directory there?
	ld	de,txt_cfgdir
	ld	a,ffs_dopen
	rst.lil	08h
	or	a
	ret	nz
	ld	hl,dirobj
	ld	a,ffs_dclose
	rst.lil	08h
	ld	a,1
	ld	(cfg_on),a
	ret

; cfg_num: read a whole number from 0 to 255 at HL, which must be the
; rest of the line (spaces and a CR may follow it). Out: C = the value,
; HL past the digits; carry if there is no such number.
cfg_num:
	ld	bc,0			; B = digits, C = value
@digit:
	ld	a,(hl)
	sub	'0'
	cp	10
	jr	nc,@end
	ld	e,a
	ld	a,c			; C = C * 10 + digit, at most 255
	cp	26
	ccf
	ret	c
	add	a,a
	ld	d,a
	add	a,a
	add	a,a
	add	a,d
	add	a,e
	ret	c
	ld	c,a
	inc	b
	inc	hl
	jr	@digit
@end:
	ld	a,b			; no digits: not a number
	or	a
	scf
	ret	z
@tail:
	ld	a,(hl)			; nothing but spaces may follow
	or	a
	ret	z
	cp	10
	ret	z
	cp	13
	jr	z,@sp
	cp	' '
	scf
	ret	nz
@sp:
	inc	hl
	jr	@tail

; cfg_text: copy the rest of the line at HL (up to a CR, an LF or the
; end of the text) to DE, as a string. A value of more than PATH_LIM
; characters is not kept: DE is left empty. Out: HL at or before the
; end of the line.
cfg_text:
	push	de
	ld	bc,PATH_LIM+1		; (one more than may be kept)
@copy:
	ld	a,(hl)
	or	a
	jr	z,@end
	cp	13
	jr	z,@end
	cp	10
	jr	z,@end
	ld	(de),a
	inc	de
	inc	hl
	dec	bc
	ld	a,b
	or	c
	jr	nz,@copy
	pop	de			; too long
	xor	a
	ld	(de),a
	ret
@end:
	xor	a
	ld	(de),a
	pop	de
	ret

; cfg_usedir: if the settings named a directory for the browser, and it
; is an absolute path to a directory that can be opened, make it the
; browser's (br_path), without any '/' at its end (but the root's).
; Otherwise leave br_path as it is, and say nothing.
cfg_usedir:
	ld	a,(cfg_dir)
	cp	'/'
	ret	nz			; none, or not an absolute path
@trim:
	ld	hl,cfg_dir
	call	strlen
	dec	bc			; BC = 0 for "/" alone
	ld	a,b
	or	c
	jr	z,@open
	add	hl,bc			; HL -> the last character
	ld	a,(hl)
	cp	'/'
	jr	nz,@open
	ld	(hl),0
	jr	@trim
@open:
	ld	hl,dirobj
	ld	de,cfg_dir
	ld	a,ffs_dopen
	rst.lil	08h
	or	a
	ret	nz			; it cannot be opened: passed over
	ld	hl,dirobj
	ld	a,ffs_dclose
	rst.lil	08h
	ld	hl,cfg_dir
	ld	de,br_path
	jp	strcpy

; cfg_save: write the settings in force to the settings file, if
; settings can be saved. A failure is passed over: the program is ending.
cfg_save:
	ld	a,(cfg_on)
	or	a
	ret	z
	ld	a,(scr_mode)		; the values to save
	ld	(cfg_mode),a
	ld	a,(vol_now)
	ld	(cfg_vol),a
	ld	hl,br_path
	ld	de,cfg_dir
	call	strcpy
	ld	hl,txt_cfghead		; the text: a heading, then a line
	ld	de,IOBUF		; per setting, each line end coming
	call	strcpy			; before the line it ends, so that
	ld	iy,cfg_tab		; there is none after the last
@set:
	ld	hl,(iy+0)
	ld	a,(hl)
	or	a
	jr	z,@write
	ld	a,10
	ld	(de),a
	inc	de
	call	strcpy
	ld	hl,(iy+3)
	ld	a,(iy+7)		; a text setting (most 0) or a number
	or	a
	jr	nz,@num
	call	strcpy
	jr	@next
@num:
	ld	a,(hl)
	call	cfg_dec
@next:
	lea	iy,iy+CFG_SIZE
	jr	@set
@write:
	ex	de,hl			; BC = length
	ld	de,IOBUF
	or	a
	sbc	hl,de
	push	hl
	pop	bc
	ld	hl,txt_cfgfile
	jp	file_write

; cfg_dec: write A in decimal at DE, without leading zeros. Out: DE ->
; after it.
cfg_dec:
	push	af
	xor	a			; no digit written yet
	ld	(cfg_lead),a
	pop	af
	ld	b,100
	call	@digit
	ld	b,10
	call	@digit
	add	a,'0'			; (the last digit always)
	ld	(de),a
	inc	de
	ret
@digit:
	ld	c,'0'-1
@sub:
	inc	c
	sub	b
	jr	nc,@sub
	add	a,b
	push	af
	ld	a,c
	cp	'0'
	jr	nz,@put
	ld	a,(cfg_lead)		; a zero before any other digit is
	or	a			; left out
	jr	z,@none
	ld	a,c
@put:
	ld	(de),a
	inc	de
	ld	a,1
	ld	(cfg_lead),a
@none:
	pop	af
	ret

; The settings: the name (with its '='), the variable it sets, its
; default and the most it may be. (A mode or volume of 0FFh is none.)
; A most of 0 marks a text setting, a string whose default (0) is
; empty.
cfg_tab:
	dl	cfg_kmode, cfg_mode
	db	0FFh, 0FEh
	dl	cfg_kan, an_want
	db	1, 1
	dl	cfg_kshuf, shuffle
	db	0, 1
	dl	cfg_kvol, cfg_vol
	db	0FFh, 127
	dl	cfg_ktheme, theme
	db	0, THEME_N-1
	dl	cfg_kdir, cfg_dir
	db	0, 0
	dl	cfg_end
cfg_end:	db	0
cfg_kmode:	db	"mode=",0
cfg_kan:	db	"analyser=",0
cfg_kshuf:	db	"shuffle=",0
cfg_kvol:	db	"volume=",0
cfg_ktheme:	db	"theme=",0
cfg_kdir:	db	"directory=",0
txt_cfghead:	db	"# agonAMP settings (see the README)",0
txt_cfgfile:	db	"/config/agonamp/agonamp.conf",0
txt_cfgdir:	db	"/config/agonamp",0

; ---------------------------------------------------------------------
; Screen modes.
; ---------------------------------------------------------------------

; The modes Z and X step through.
scr_modes:	db	0,4,24,28
SCR_NMODES:	equ	4

; scr_check: is the screen mode in use one agonAMP can use? Out: carry
; if not; else NC, with its number in scr_mode and its rows in scr_rows.
scr_check:
	ld	ix,(sysvars)
	ld	a,(ix+sysvar_scrMode)
	ld	(scr_mode),a
	ld	a,(ix+sysvar_scrCols)
	cp	80
	ret	c
	ld	a,(ix+sysvar_scrColours)
	cp	16
	ret	c
	ld	a,(ix+sysvar_scrRows)
	cp	24
	ret	c
	ld	(scr_rows),a
	ld	a,(scr_mode)		; modes 128 and up are double-buffered:
	cp	128			; nothing drawn would ever be shown
	ccf
	ret

; scr_setmode: change to screen mode A, wait (a second at most) for the
; VDP to report the new mode, and check it (scr_check). Out: as
; scr_check.
scr_setmode:
	ld	ix,(sysvars)
	res	4,(ix+sysvar_vpd_pflags)
	push	af
	ld	a,22
	call	vdu_put
	pop	af
	call	vdu_put
	call	vdu_flush
	ld	b,(ix+sysvar_time)	; (centiseconds)
@wait:
	bit	4,(ix+sysvar_vpd_pflags)
	jr	nz,scr_check
	ld	a,(ix+sysvar_time)
	sub	b
	cp	100
	jr	c,@wait
	jr	scr_check

; scr_next, scr_prev: X and Z: change to the next or the previous mode in
; scr_modes, passing over any that will not do.
scr_next:
	ld	c,1
	jr	scr_step
scr_prev:
	ld	c,0FFh
scr_step:
	ld	a,(scr_mode)		; where it is in the list (if it is
	ld	(scr_was),a		; not there, as if just before the
	ld	hl,scr_modes		; first, or just after the last)
	ld	b,SCR_NMODES
	ld	e,0
@find:
	cp	(hl)
	jr	z,@found
	inc	hl
	inc	e
	djnz	@find
	ld	e,0FFh
	bit	7,c
	jr	z,@found
	ld	e,SCR_NMODES
@found:
	ld	b,SCR_NMODES
@try:
	ld	a,e			; the next one along, going round
	add	a,c
	jp	p,@pos
	ld	a,SCR_NMODES-1
@pos:
	cp	SCR_NMODES
	jr	c,@in
	xor	a
@in:
	ld	e,a
	push	bc
	push	de
	ld	hl,0
	ld	l,a
	ld	de,scr_modes
	add	hl,de
	ld	a,(hl)
	call	scr_setmode
	pop	de
	pop	bc
	jr	nc,@ok
	djnz	@try
	ld	a,(scr_was)		; none would do: back to where it was
	call	scr_setmode
@ok:
	call	ui_redo			; set the screen up again for the
					; new size
	ld	hl,txt_scrmode		; and say which mode it is
	ld	de,pb_buf
	call	strcpy
	ld	a,(scr_mode)
	call	cfg_dec
	xor	a
	ld	(de),a
	ld	hl,pb_buf
	jp	ui_msg
txt_scrmode:	db	" Screen mode ",0

; scr_restore: on exit, go back to the screen mode agonAMP was started
; in, if it is in another.
scr_restore:
	ld	a,(scr_orig)
	ld	hl,scr_mode
	cp	(hl)
	ret	z
	jp	scr_setmode

; ui_redo: clear the screen and draw it all again, from ui_init on,
; including a TurboSound layout if one is needed.
ui_redo:
	call	ui_init
	ld	a,0FFh
	ld	(lay_ts),a
	jp	ui_layout

; ---------------------------------------------------------------------
; Colour themes.
; ---------------------------------------------------------------------

; A theme gives new colours to the three logical colours COL_DARK,
; COL_MID and COL_LIGHT (VDU 19), which the bars, the selected entry,
; the entry being played, the meters and the analyser are drawn in. In
; the 16-colour modes this changes what is on the screen at once; in
; the 64-colour modes (3 and 27) it changes only what is drawn after it
; (and nothing at all before Console8 VDP 2.6.0), so there the screen
; is drawn again. The VDP turns each 0 to 255 value into one of its
; four levels (0, 85, 170 and 255), so these are given as those levels.

; theme_apply: send the colours of the theme in use (theme) to the VDP,
; without sending them on (the caller calls vdu_flush).
theme_apply:
	ld	a,(theme)		; HL -> its colours: theme * 9 along
	ld	b,a
	add	a,a
	add	a,a
	add	a,a
	add	a,b
	ld	hl,0
	ld	l,a
	ld	de,theme_tab
	add	hl,de
	ld	de,theme_slots
	ld	c,3
@slot:
	ld	a,19			; VDU 19,l,255,r,g,b (sent byte by
	call	vdu_put			; byte, as 255 would end a vseq
	ld	a,(de)			; sequence)
	inc	de
	call	vdu_put
	ld	a,255
	call	vdu_put
	ld	b,3
@rgb:
	ld	a,(hl)
	inc	hl
	call	vdu_put
	djnz	@rgb
	dec	c
	jr	nz,@slot
	ret

; theme_next: the T key: on to the next theme, going round, and say
; which it is.
theme_next:
	ld	a,(theme)
	inc	a
	cp	THEME_N
	jr	c,@set
	xor	a
@set:
	ld	(theme),a
	ld	ix,(sysvars)		; a 64-colour mode: draw it all again
	ld	a,(ix+sysvar_scrColours)
	cp	17
	jr	c,@pal
	call	ui_redo
	jr	@say
@pal:
	call	theme_apply		; else the palette alone will do
	call	vdu_flush
@say:
	ld	hl,txt_theme		; " Theme: " and its name
	ld	de,pb_buf
	call	strcpy
	ld	a,(theme)		; HL -> its name, from theme_names
	ld	b,a			; (theme * 3 along)
	add	a,a
	add	a,b
	ld	hl,0
	ld	l,a
	ld	bc,theme_names
	add	hl,bc
	ld	hl,(hl)
	call	strcpy
	ld	hl,pb_buf
	jp	ui_msg
txt_theme:	db	" Theme: ",0

; The logical colours a theme sets, in the order of its colours below.
theme_slots:	db	COL_DARK, COL_MID, COL_LIGHT

; Each theme's dark, medium and light colours, as red, green and blue.
; None of them may be the same as one of the other thirteen colours of
; the palette (or as each other): the VDP draws in the logical colour
; that has the colour asked for, so a theme colour that is also, say,
; COL_RED would have things drawn in COL_RED, which would keep its
; colour when the theme changed. (So Autumn's dark red is a darker one
; than COL_RED's, and its yellow a paler one than COL_BYELLOW's; and
; Sand Dune's dark colour is olive, as the palette's own dark yellow is
; COL_YELLOW's.)
; T steps through them in this order, going round.
theme_tab:
	db	0,0,170, 0,0,255, 0,255,0	; 0 OCP: as the default palette
	db	85,0,0, 255,85,0, 255,255,85	; 1 Autumn: maroon, orange,
						; pale yellow
	db	0,85,170, 85,170,255, 170,255,255 ; 2 Iceberg: steel blue, sky
						; blue, ice
	db	0,85,0, 85,170,0, 170,255,85	; 3 Emerald: forest green, leaf
						; green, pale lime
	db	85,85,0, 255,170,0, 255,255,170	; 4 Sand Dune: olive, gold,
						; cream
	db	85,0,170, 170,0,255, 255,170,255 ; 5 Amethyst: violet, purple,
						; lilac

; Their names.
theme_names:
	dl	txt_th0, txt_th1, txt_th2, txt_th3, txt_th4, txt_th5
txt_th0:	db	"OCP",0
txt_th1:	db	"Autumn",0
txt_th2:	db	"Iceberg",0
txt_th3:	db	"Emerald",0
txt_th4:	db	"Sand Dune",0
txt_th5:	db	"Amethyst",0