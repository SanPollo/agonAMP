; agonamp.asm - agonAMP, a player for AY-3-8912 music files on the Agon
; Light, Agon Light 2 and Console8. It plays Pro Tracker 3 / Vortex
; Tracker II modules (.pt3), Pro Tracker 2 and 1 modules (.pt2, .pt1),
; Sound Tracker modules (.stc), Sound Tracker Pro modules (.stp), ASC
; Sound Master modules (.asc), SQ-Tracker modules (.sqt), Pro Sound
; Creator modules (.psc), AY register dumps (.psg, .ym, .vtx) and AY
; files (.ay), whose Z80 code is run on an emulated Z80.
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
; Usage:   agonamp [music file | playlist.m3u]
;
; Needs MOS 2.2.0 or later (directory calls) and a screen mode with at
; least 80 columns and 16 colours; the mode is never changed. Developed
; and tested against MOS 3.0.2 and VDP 2.16.0.
;
; Build:   ez80asm agonamp.asm ../agonamp.bin  (from the src directory;
;          on the Agon itself add the -m option)
;
; Source files:
;   src/agonamp.asm  start-up, main loop, keys, song loading (this file)
;   src/ui.asm       screen drawing and the list panel
;   src/pattern.asm  the pattern view
;   src/patother.asm the pattern view for formats other than PT3
;   src/files.asm    playlist, M3U files and the file browser
;   src/util.asm     text output helpers, number printing, strings
;   src/equs.inc     constants;  src/vk.inc  key codes
;   lib/             the sound library, usable in other programs:
;     pt3ts.asm      two-chip (TurboSound) PT3 tunes
;     pt3play.asm    the PT3 replayer: module in, AY registers out
;     psgplay.asm    the PSG (register dump) player
;     stcplay.asm    the Sound Tracker (STC) replayer
;     pt2play.asm    the Pro Tracker 2 replayer
;     pt1play.asm    the Pro Tracker 1 replayer
;     ascplay.asm    the ASC Sound Master replayer
;     stpplay.asm    the Sound Tracker Pro replayer
;     sqtplay.asm    the SQ-Tracker replayer
;     pscplay.asm    the Pro Sound Creator replayer
;     notetab.inc    note tables shared by the STC, STP, ASC and PSC ones
;     ymplay.asm     the YM and VTX (register dump) player
;     lh5.asm        LH5 unpacker, for YM and VTX files
;     ayfplay.asm    the AY file (ZXAYEMUL) player
;     z80emu.asm     Z80 emulation, for AY files
;     z80tab.inc     its decoding tables (from tools/mkz80tab.py)
;     pt3tab.inc     its tone and volume tables
;     ayvdp.asm      AY registers to Agon VDP audio commands
;     tick50.asm     50 Hz timer tick
;     libsupport.asm buffered VDU output, 16 bit fetch, division

	.assume	adl=1
	.org	040000h
	jp	start
	.align	64
	.db	"MOS",0,1		; MOS executable header, ADL mode

	include	"equs.inc"
	include	"vk.inc"

start:
	push	ix
	push	iy
	ld	(arg_ptr),hl		; MOS passes the argument string in HL
	ld	a,mos_sysvars
	rst.lil	08h
	ld	(sysvars),ix
	ld	a,(ix+sysvar_scrMode)	; the screen mode, to put back on exit
	ld	(scr_orig),a
	ld	(scr_mode),a
	ld	a,(ix+sysvar_vkeycount)
	ld	(k_count),a

	xor	a
	ld	(quit),a
	ld	(input_mode),a
	ld	(tot_min),a		; no total time until a song is loaded
	ld	(tot_sec),a
	ld	(state),a
	ld	(cur_path),a
	ld	hl,0
	ld	(t_frac),hl		; clears t_frac, t_sec and t_min
	call	pl_clear
	ld	(fmt),a
	ld	(mute_all),a
	ld	(help_prev),a
	ld	(ts_on),a
	xor	a
	ld	(pl_skip),a
	ld	(pl_fails),a
	inc	a
	ld	(pl_dir),a
	call	shuf_zero
	call	clear_song		; no song yet: the display shows zeros
	call	cfg_load		; the settings, or their defaults
					; (config.asm)
	ld	a,(cfg_mode)		; a screen mode in them is used if it
	cp	0FFh			; will do; else the one in use
	jr	z,@scr
	ld	hl,scr_orig
	cp	(hl)
	jr	z,@scr
	call	scr_setmode
	jr	nc,@scr
	ld	a,(scr_orig)
	call	scr_setmode
@scr:
	call	scr_check		; is the screen big enough?
	jp	c,toosmall

	ld	hl,br_path		; the browser starts in the current
	ld	bc,PATH_LIM+1		; directory (if its path is not too
	ld	a,ffs_getcwd		; long to keep: else the root)
	rst.lil	08h
	or	a
	jr	z,@cwd
	ld	hl,br_path
	ld	(hl),'/'
	inc	hl
	ld	(hl),0
@cwd:

	; note the volume, to put it back on exit
	call	vol_read
	call	ay_init
	ld	a,(cfg_vol)		; a volume in the settings is used
	cp	128
	jr	nc,@vol
	ld	(vol_now),a
	call	ay_volume
@vol:
	call	ui_init

	call	tick_start		; 50 Hz tick (lib/tick50.asm)

	call	get_arg			; the argument, if any: first, as a
	push	af			; relative path is taken from br_path,
	call	cfg_usedir		; which is still the current directory
	call	br_read			; (then the browser can be moved to
	ld	a,1			; the one in the settings: config.asm)
	ld	(panel),a		; with no argument, show the browser
	pop	af
	jr	z,main
	xor	a
	ld	(panel),a
	ld	hl,tmp_path
	ld	de,ext_m3u
	call	has_ext
	jr	nz,@module
	ld	hl,tmp_path
	call	pl_load_m3u
	call	c,br_noload		; (say so if it could not be read)
	jr	@play
@module:
	ld	hl,tmp_path
	call	pl_add
@play:
	ld	hl,(pl_count)
	ld	a,h
	or	l
	jr	z,main
	ld	hl,0
	call	play_index

; ---------------------------------------------------------------------
; Main loop. Music ticks come first; keys and drawing use the time left.
; ---------------------------------------------------------------------
main:
	ld	a,(tick_count)
	or	a
	jr	z,@idle
	ld	hl,tick_count
	dec	(hl)
	call	msg_tick
	ld	a,(state)
	cp	ST_PLAYING
	jr	nz,main
	call	song_play
	call	ay_update
	call	an_frame		; (the analyser's bars: spectrum.asm)
	ld	hl,t_frac		; elapsed time
	inc	(hl)
	ld	a,(hl)
	cp	50
	jr	c,@ended
	ld	(hl),0
	ld	hl,t_sec
	inc	(hl)
	ld	a,(hl)
	cp	60
	jr	c,@ended
	ld	(hl),0
	ld	hl,t_min
	ld	a,(hl)
	cp	99			; the display stops at 99:59
	jr	nc,@maxed
	inc	(hl)
	jr	@ended
@maxed:
	ld	a,59
	ld	(t_sec),a
@ended:
	ld	a,(fmt)			; has the song reached its end?
	ld	c,a
	add	a,a
	add	a,c
	ld	de,0
	ld	e,a
	ld	hl,loops_tab
	add	hl,de
	ld	hl,(hl)
@loops:
	ld	a,(hl)
	or	a
	jp	z,main
	ld	(hl),0
	ld	hl,(pl_count)		; with one song or none, just loop it
	ld	de,2
	or	a
	sbc	hl,de
	jr	c,main
	call	next_track
	jr	main
@idle:
	ld	a,(pl_skip)		; an entry that could not be played:
	or	a			; on to the next (see play_index)
	jr	z,@key
	ld	b,a
	xor	a
	ld	(pl_skip),a
	ld	a,b
	inc	a
	call	z,prev_track
	ld	a,b
	dec	a
	call	z,next_track
@key:
	call	kbd_poll
	call	nz,handle_key
	ld	a,(quit)
	or	a
	jr	nz,exit
	call	ui_paced
	jp	main

exit:
	call	tick_stop
	call	cfg_save		; the settings in force (config.asm)
	ld	a,(vol_saved)		; the volume as it was found
	call	ay_volume
	call	ay_shutdown
	call	ui_restore
	call	scr_restore		; and the screen mode
	pop	iy
	pop	ix
	ld	hl,0
	ret

toosmall:
	call	scr_restore		; (if the settings changed the mode)
	ld	hl,txt_small
	ld	bc,0
	xor	a
	rst.lil	18h
	pop	iy
	pop	ix
	ld	hl,0
	ret
txt_small:
	db	"agonAMP needs a screen mode with at least 80 columns,",13,10
	db	"24 rows and 16 colours that is not double-buffered",13,10
	db	"(for example MODE 0).",13,10,0

; ---------------------------------------------------------------------
; Volume. The VDP has one overall volume for all sound, 0 to 127. It
; belongs to the VDP, not to this program, so the value found at the
; start is put back on exit.
; ---------------------------------------------------------------------
VOL_STEP:	equ	8

; vol_read: ask the VDP for its volume. Asking to set the volume to 255
; changes nothing and returns the current value; MOS puts the reply in
; its system variables and sets a flag. If no reply for the right
; "channel" comes (a VDP before 2.5.0), full volume is assumed.
vol_read:
	ld	ix,(sysvars)
	res	3,(ix+sysvar_vpd_pflags)
	ld	c,255			; VDU 23,0,&85,255,2,255
	ld	b,2
	call	ay_cmd
	ld	a,255
	call	vdu_put
	call	vdu_flush
	ld	ix,(sysvars)
	ld	hl,300000		; wait a fraction of a second at most
	ld	de,0FFFFFFh
@wait:
	bit	3,(ix+sysvar_vpd_pflags)
	jr	z,@count
	ld	a,(ix+sysvar_audioChannel)
	cp	255
	jr	z,@reply
	res	3,(ix+sysvar_vpd_pflags)	; a reply to something else
@count:
	add	hl,de
	jr	c,@wait
	ld	a,127
	jr	@store
@reply:
	ld	a,(ix+sysvar_audioSuccess)
	cp	128
	jr	c,@store
	ld	a,127
@store:
	ld	(vol_saved),a
	ld	(vol_now),a
	ret

; vol_up / vol_down: change the volume by one step and show the level
; on the bottom row for a few seconds.
vol_up:
	ld	a,(vol_now)
	add	a,VOL_STEP
	cp	128
	jr	c,vol_set
	ld	a,127
	jr	vol_set
vol_down:
	ld	a,(vol_now)
	sub	VOL_STEP
	jr	nc,vol_set
	xor	a
vol_set:
	ld	(vol_now),a
	push	af			; changing the volume ends a mute
	xor	a
	ld	(mute_all),a
	pop	af
	call	ay_volume
	ld	hl,txt_volume
	ld	de,pb_buf
	call	strcpy
	ld	a,(vol_now)		; a bar of 16 cells
	add	a,7
	srl	a
	srl	a
	srl	a
	ld	c,a
	ld	b,16
@cell:
	ld	a,c
	or	a
	jr	z,@dark
	dec	c
	ld	a,128
	jr	@put
@dark:
	ld	a,129
@put:
	ld	(de),a
	inc	de
	djnz	@cell
	ld	a,' '
	ld	(de),a
	inc	de
	ld	(de),a
	inc	de
	push	de			; and the level as a percentage
	ld	de,0
	ld	a,(vol_now)
	ld	e,a
	ld	hl,0
	ld	b,100
@times:
	add	hl,de
	djnz	@times
	ld	de,127
	call	lib_div24
	ld	a,l
	pop	de
	call	mdec3
	push	de			; blank out leading zeros
	pop	hl
	dec	hl
	dec	hl
	dec	hl
	ld	a,(hl)
	cp	'0'
	jr	nz,@pct
	ld	(hl),' '
	inc	hl
	ld	a,(hl)
	cp	'0'
	jr	nz,@pct
	ld	(hl),' '
@pct:
	ld	a,'%'
	ld	(de),a
	inc	de
	xor	a
	ld	(de),a
	ld	hl,pb_buf
	jp	ui_msg
txt_volume:	db	" Volume ",0

; get_arg: copy the first command line argument to tmp_path as an
; absolute path. Out: Z if there was no argument.
get_arg:
	ld	hl,(arg_ptr)
@sp:
	ld	a,(hl)
	cp	' '
	jr	nz,@first
	inc	hl
	jr	@sp
@first:
	cp	33
	jr	nc,@have
	xor	a
	ret
@have:
	ld	de,tmp_path
	cp	'/'
	jr	z,@copy
	; relative: put the current directory first
	push	hl
	ld	hl,br_path
	call	strcpy
	dec	de
	ld	a,(de)
	inc	de
	cp	'/'
	jr	z,@joined
	ld	a,'/'
	ld	(de),a
	inc	de
@joined:
	pop	hl
@copy:
	ld	a,(hl)
	cp	33
	jr	c,@end
	ld	(de),a
	inc	hl
	push	hl			; (stop at the end of tmp_path)
	ld	hl,tmp_path+TMP_SIZE-2
	or	a
	sbc	hl,de
	pop	hl
	jr	c,@copy
	inc	de
	jr	@copy
@end:
	xor	a
	ld	(de),a
	inc	a
	ret

; load_song: load and start the music file whose path is at HL. The
; format is recognised from the file's contents, not its name.
load_song:
	call	load_song1
	ld	a,(ts_on)		; one AY chip, or two for a TurboSound
	inc	a			; tune
	call	ay_chips
	jp	ui_layout		; and three channel lines, or six
load_song1:
	xor	a
	ld	(ts_on),a
	ld	(pv_valid),a		; (the pattern view starts afresh)
	ld	de,cur_path
	call	strcpy
	call	ay_reset
	call	clear_song
	ld	hl,1773400		; most formats are for the Spectrum's
	call	ay_clock		; AY clock
	ld	hl,0			; the clock starts again
	ld	(t_frac),hl
	xor	a			; no total time until it is worked out
	ld	(tot_min),a
	ld	(tot_sec),a
	ld	a,0FEh			; (have the time drawn again)
	ld	(st_last+6),a
	ld	a,ST_LOADERR
	ld	(state),a
	ld	a,1
	ld	(dirty_info),a
	ld	hl,cur_path
	ld	de,MODULE
	ld	bc,MODULE_MAX
	call	file_read
	ret	c
	ld	(mod_len),hl
	ld	a,ST_BADFILE
	ld	(state),a
	ld	de,16			; too short to be a music file (and
	or	a			; what is left of the last one in the
	sbc	hl,de			; buffer must not be taken for it)
	jp	c,@reject
	ld	hl,MODULE		; PT3: both trackers' signatures
	ld	de,sig_pt3
	ld	b,13
	call	memcmp
	jp	z,@pt3
	ld	hl,MODULE
	ld	de,sig_vt2
	ld	b,14
	call	memcmp
	jp	z,@pt3
	ld	hl,txt_none		; (only PT3 modules name their author)
	ld	(info_title),hl
	ld	(info_author),hl
	ld	hl,MODULE		; PSG register dump?
	ld	bc,(mod_len)
	call	psg_init
	ld	a,FMT_PSG
	jp	nc,@go
	ld	hl,MODULE		; an AY file?
	ld	de,ayf_sig
	ld	b,8
	call	memcmp
	jp	z,@ay
	ld	hl,IOBUF		; YM or VTX (unpacked within MODULE,
	ld	(lh5_work),hl		; with IOBUF as working space)?
	ld	hl,MODULE
	ld	bc,(mod_len)
	ld	de,MODULE_MAX
	call	ym_load
	jp	nc,@ym
	or	a
	jp	nz,@reject		; one, but damaged or too big
	; Sound Tracker modules have no signature, so go by the file
	; name; stc_init then checks that the contents are plausible.
	ld	hl,cur_path
	ld	de,ext_stc
	call	has_ext
	jp	z,@stc
	ld	iy,fmt_tab		; the formats described by fmt_tab
	ld	a,FMT_PT2
@try:
	ld	(fmt),a
	ld	hl,cur_path
	ld	de,(iy+F_EXT)
	push	iy
	call	has_ext
	pop	iy
	jr	z,@std
	ld	de,F_SIZE
	add	iy,de
	ld	a,(fmt)
	inc	a
	cp	FMT_COUNT
	jr	c,@try
@reject:
	xor	a
	ld	(fmt),a
	ret
@std:
	call	fmt_init
	jr	c,@reject
	ld	hl,(iy+F_NAME)		; a name in the module is its title
	ld	a,h
	or	l
	jr	z,@noname
	ld	de,MODULE
	add	hl,de
	ld	bc,(iy+F_NLEN)
	call	@title
@noname:
	ld	hl,(iy+F_AUTH)		; and some name their author too
	ld	a,h
	or	l
	jr	z,@noauthor
	ld	de,MODULE
	add	hl,de
	ld	bc,(iy+F_ALEN)
	ld	de,alt_author
	ldir
	xor	a
	ld	(de),a
	ld	hl,alt_author
	ld	(info_author),hl
@noauthor:
	ld	a,(fmt)
	jp	@go
@ym:
	ld	hl,(ym_clock)		; made for any of several machines
	call	ay_clock
	ld	hl,(ym_title)
	ld	de,alt_title
	ld	bc,32
	call	@name
	jr	z,@noyt
	ld	hl,alt_title
	ld	(info_title),hl
@noyt:
	ld	hl,(ym_author)
	ld	de,alt_author
	ld	bc,27
	call	@name
	jr	z,@noya
	ld	hl,alt_author
	ld	(info_author),hl
@noya:
	ld	a,FMT_YM
	jp	@go
@ay:
	; The Z80's 64 KB go at MODULE, so the file is moved above them.
	ld	hl,(mod_len)
	ld	de,MODULE_MAX-10000h+1
	or	a
	sbc	hl,de
	jp	nc,@reject		; (too big to be moved)
	ld	hl,MODULE-1		; from its end down
	ld	de,(mod_len)
	add	hl,de
	push	hl
	ld	hl,MODULE+10000h-1
	add	hl,de
	ex	de,hl
	pop	hl
	ld	bc,(mod_len)
	lddr
	ld	hl,MODULE+10000h
	ld	bc,(mod_len)
	ld	a,MODULE >> 16
	call	ayf_init
	jp	c,@reject
	call	ay_names
	ld	a,FMT_AY
	jp	@go
@name:					; BC bytes from HL to DE and a zero
	push	de			; after them; Z if there is no name
	ld	de,0			; (HL = 0, tested in all 24 bits)
	ex	de,hl
	or	a
	sbc	hl,de
	ex	de,hl
	pop	de
	ret	z
	ldir
	xor	a
	ld	(de),a
	inc	a
	ret
@stc:
	ld	hl,MODULE
	ld	bc,(mod_len)
	call	stc_init
	jp	c,@reject
	ld	hl,MODULE+7		; its 18 character identifier is shown
	ld	bc,18			; as the title
	call	@title
	ld	a,FMT_STC
	jp	@go
@pt3:
	ld	hl,MODULE+30
	ld	(info_title),hl
	ld	hl,MODULE+66
	ld	(info_author),hl
	ld	hl,MODULE		; a TurboSound tune (two chips)?
	ld	bc,(mod_len)
	call	pt3ts_detect
	jr	z,@onechip
	ld	a,1
	ld	(ts_on),a
	call	pt3ts_init
	jr	@pt3go
@onechip:
	ld	hl,MODULE
	call	pt3_init
@pt3go:
	ld	a,(pt3_patgen)		; (so that the pattern view notes the
	dec	a			; first pattern's row spacing)
	ld	(pat_snapgen),a
	xor	a			; FMT_PT3
@go:
	ld	(fmt),a
	call	song_total
	call	po_load			; (pattern view: patother.asm)
	ld	hl,0
	ld	(t_frac),hl
	xor	a
	ld	(tick_count),a
	ld	a,ST_PLAYING
	ld	(state),a
	ret
@title:					; use BC characters at HL as the title
	ld	de,alt_title
	ldir
	xor	a
	ld	(de),a
	ld	hl,alt_title
	ld	(info_title),hl
	ret

; ay_names: show the AY file's song name and author, and note which
; song they belong to (ayf_play moves on from song to song).
ay_names:
	ld	a,(ayf_cur)
	ld	(ay_shown),a
	ld	hl,(ayf_title)
	ld	de,alt_title
	ld	bc,32
	ldir
	xor	a
	ld	(de),a
	ld	hl,alt_title
	ld	(info_title),hl
	ld	hl,(ayf_author)
	ld	de,alt_author
	ld	bc,27
	ldir
	xor	a
	ld	(de),a
	ld	hl,alt_author
	ld	(info_author),hl
	ld	a,1
	ld	(dirty_info),a
	ret

; ay_next, ay_prev: the N and P keys. In an AY file, move to the next
; song, or to the previous one, wrapping round; as with Left, "previous"
; starts the song again instead if it has played for 3 seconds or more.
; With any other kind of song they do nothing.
ay_next:
	call	ay_can
	ret	nz
	ld	a,(ayf_cur)
	call	ayf_nextno
	jr	ay_goto
ay_prev:
	call	ay_can
	ret	nz
	ld	a,(t_min)
	or	a
	jr	nz,@again
	ld	a,(t_sec)
	cp	RESTART_SECS
	jr	c,@back
@again:
	ld	a,(ayf_cur)
	jr	ay_goto
@back:
	ld	a,(ayf_cur)		; the song before (passing back over
	call	ayf_prevno		; any with bad data)
	push	af
	call	ay_reset
	pop	af
	call	ayf_startb
	jr	ay_newsong

; ay_goto: start song A of the AY file (or the next good one), from
; silence. (ayf_song clears ay_regs.)
ay_goto:
	push	af
	call	ay_reset
	pop	af
	call	ayf_start
	; fall through

; ay_newsong: a new song in the AY file has started: show its name and
; start the clock and the total time again.
ay_newsong:
	call	ay_names
	ld	hl,0
	ld	(t_frac),hl		; (and t_sec, t_min)
	call	song_total
	ld	a,0FEh			; (have the time drawn again)
	ld	(st_last+6),a
	ret

; ay_can: Z if an AY file is loaded and playing or paused.
ay_can:
	ld	a,(fmt)
	cp	FMT_AY
	ret	nz
	ld	a,(state)
	cp	ST_PLAYING
	ret	z
	cp	ST_PAUSED
	ret

; clear_song: zero the AY registers and the PT3 replayer's state, so
; that the display shows nothing left over from the last song.
clear_song:
	xor	a
	ld	(disp_pat),a
	ld	hl,ay_regs
	ld	b,16
@regs:
	ld	(hl),0
	inc	hl
	djnz	@regs
	ld	hl,pt3_vars
	ld	de,pt3_vars+1
	ld	bc,pt3_vars_end-pt3_vars-1
	ld	(hl),0
	ldir
	ld	hl,ay_regs2		; and the same for a second chip
	ld	b,16
@regs2:
	ld	(hl),0
	inc	hl
	djnz	@regs2
	ld	hl,pt3ts_c2
	ld	de,pt3ts_c2+1
	ld	bc,pt3_ctx_end-pt3_ctx-1
	ld	(hl),0
	ldir
	jp	an_clear		; and the analyser's bars

; song_total: work out how long the song just loaded lasts, for the
; status line. The replayers find this by running through the song's
; rows, so each is set up again afterwards.
song_total:
	ld	a,(fmt)
	cp	FMT_YM
	jr	nz,@notym
	call	ym_length
	jr	@got
@notym:
	cp	FMT_AY
	jr	nz,@notay
	ld	hl,(ayf_len)		; (the song playing, not all the file)
	jr	@got
@notay:
	or	a
	jr	nz,@psg
	ld	a,(ts_on)
	or	a
	jr	nz,@ts
	call	pt3_length
	push	hl
	ld	hl,MODULE
	call	pt3_init
	pop	hl
	jr	@got
@ts:
	call	pt3ts_length
	push	hl
	call	pt3ts_init
	pop	hl
	jr	@got
@psg:
	dec	a
	jr	nz,@stc
	call	psg_length
	jr	@got
@stc:
	dec	a
	jr	nz,@pt2
	call	stc_length
	push	hl
	ld	hl,MODULE
	ld	bc,(mod_len)
	call	stc_init
	pop	hl
	jr	@got
@pt2:					; the formats described by fmt_tab
	call	fmt_entry
	ld	hl,(iy+F_LENGTH)
	push	iy
	call	jp_hl
	pop	iy
	push	hl
	call	fmt_init
	pop	hl
@got:
	ld	de,50			; frames to seconds
	call	lib_div24
	ld	(tot_work),hl
	ld	de,60			; and to minutes
	call	lib_div24
	ld	de,100
	or	a
	sbc	hl,de
	add	hl,de
	jr	c,@fits
	ld	a,99			; more than the field can show
	ld	(tot_min),a
	ld	a,59
	ld	(tot_sec),a
	ret
@fits:
	ld	a,l
	ld	(tot_min),a
	ld	hl,0			; seconds left over
	or	a
	jr	z,@rem
	ld	b,a
	ld	de,60
@mins:
	add	hl,de
	djnz	@mins
@rem:
	ex	de,hl
	ld	hl,(tot_work)
	or	a
	sbc	hl,de
	ld	a,l
	ld	(tot_sec),a
	ret

; pat_avail: can the pattern view be shown? Only a tracker module (of
; any of the formats with patterns) that is loaded has one. Out: NZ if
; it can.
pat_avail:
	call	pat_kind
	jr	z,@no
	ld	a,(state)
	cp	ST_PLAYING
	jr	z,@yes
	cp	ST_PAUSED
	jr	z,@yes
@no:
	xor	a
	ret
@yes:
	or	1
	ret

; after_load: once a playlist entry has been loaded or has failed to
; load: mark the entry (a failed one is shown in red), say what went
; wrong on the bottom row, and leave the pattern view if this song does
; not have one.
after_load:
	ld	hl,(pl_cur)
	ld	de,pl_bad
	add	hl,de
	ld	a,(state)
	cp	ST_LOADERR
	jr	z,@bad
	cp	ST_BADFILE
	jr	z,@bad
	ld	(hl),0
	jr	@panel
@bad:
	ld	(hl),1
	ld	hl,txt_noopen
	cp	ST_LOADERR
	jr	z,@msg
	ld	hl,txt_noplay
@msg:
	ld	de,pb_buf
	call	strcpy
	push	de
	ld	hl,cur_path
	ld	b,48
	call	vtail			; (corrupts DE)
	pop	de
	call	strcpy
	ld	hl,pb_buf
	call	ui_err
@panel:
	ld	a,(panel)
	cp	2
	ret	nz
	call	pat_avail
	ret	nz
	xor	a			; back to the playlist
	ld	(panel),a
	inc	a
	ld	(dirty_panbar),a
	ret
txt_noopen:	db	" Cannot open ",0
txt_noplay:	db	" Not a file agonAMP can play: ",0

; song_play: play one frame of the current song, whatever its format.
song_play:
	ld	a,(fmt)
	or	a
	jr	nz,@psg
	ld	a,(ts_on)
	or	a
	jr	nz,@ts
	call	pt3_play
	jr	@snap
@ts:
	call	pt3ts_play
@snap:
	; When a pattern starts, note each channel's row spacing as it
	; stands, for the pattern view (see pattern.asm).
	ld	a,(pt3_patgen)
	ld	hl,pat_snapgen
	cp	(hl)
	ret	z
	ld	(hl),a
	ld	a,(pt3_chA+PT3C_SKIPN)
	ld	(pat_skip),a
	ld	a,(pt3_chB+PT3C_SKIPN)
	ld	(pat_skip+1),a
	ld	a,(pt3_chC+PT3C_SKIPN)
	ld	(pat_skip+2),a
	ld	a,(pt3ts_chA2+PT3C_SKIPN)
	ld	(pat_skip2),a
	ld	a,(pt3ts_chB2+PT3C_SKIPN)
	ld	(pat_skip2+1),a
	ld	a,(pt3ts_chC2+PT3C_SKIPN)
	ld	(pat_skip2+2),a
	ret
@psg:
	cp	FMT_STC
	jp	z,@stc
	cp	FMT_YM
	jr	nz,@notym
	call	ym_play
	jp	@mirror
@notym:
	cp	FMT_AY
	jr	nz,@notay
	call	ayf_play
	ld	a,(ayf_cur)		; a new song in the file?
	ld	hl,ay_shown
	cp	(hl)
	call	nz,ay_newsong
	jp	@mirror
@notay:
	cp	FMT_PT2
	jr	nc,@table
	call	psg_play
	jp	@mirror
@table:
	call	po_before
	call	fmt_entry
	ld	hl,(iy+F_PLAY)
	push	iy
	call	jp_hl
	pop	iy
	ld	hl,(iy+F_STATUS)
	ld	de,(iy+F_CHSIZE)
	ld	bc,(iy+F_CHAN)
	push	bc
	pop	iy
@std:
	; These replayers keep what the screen shows in the same
	; layout: five status bytes at HL, and the first four bytes of
	; each channel's state (IY, DE apart).
	ld	a,(hl)
	ld	(pt3_pos),a
	inc	hl
	ld	a,(hl)
	ld	(pt3_numpos),a
	inc	hl
	ld	a,(hl)
	ld	(disp_pat),a
	inc	hl
	ld	a,(hl)
	ld	(pt3_row),a
	inc	hl
	ld	a,(hl)
	ld	(pt3_delay),a
	; The notes are shown with any transposition the music adds: for
	; STP the position's, for SQT each channel's.
	xor	a
	ld	(disp_tr),a
	dec	a
	ld	(disp_ctr),a
	ld	a,(fmt)
	cp	FMT_STP
	jr	nz,@nstp
	ld	a,(stp_transp)
	ld	(disp_tr),a
	jr	@nsqt
@nstp:
	cp	FMT_SQT
	jr	nz,@nsqt
	ld	a,SQ_TRANSP
	ld	(disp_ctr),a
@nsqt:
	ld	ix,pt3_chA
	call	@std1
	add	iy,de
	ld	ix,pt3_chB
	call	@std1
	add	iy,de
	ld	ix,pt3_chC
	call	@std1
	jp	@mirror
@std1:
	push	de
	ld	c,0			; C = the channel's transposition
	ld	a,(disp_ctr)
	cp	0FFh
	jr	z,@nct
	ld	de,0
	ld	e,a
	lea	hl,iy+0
	add	hl,de
	ld	c,(hl)
@nct:
	pop	de
	ld	a,(disp_tr)
	add	a,c
	add	a,(iy+0)
	cp	96			; (as the replayers limit it)
	jr	c,@ntok
	ld	a,95
@ntok:
	ld	(ix+PT3C_NOTE),a
	ld	a,(iy+1)
	ld	(ix+PT3C_SAMNUM),a
	ld	a,(iy+2)
	ld	(ix+PT3C_ORNNUM),a
	ld	a,(iy+3)
	ld	(ix+PT3C_ENABLED),a
	ret
@stc:
	call	po_before
	call	stc_play
	; The screen takes what it shows from the PT3 replayer's variables,
	; so copy the Sound Tracker replayer's equivalents there.
	ld	a,(stc_pos)
	ld	(pt3_pos),a
	ld	a,(stc_numpos)
	ld	(pt3_numpos),a
	ld	a,(stc_pat)
	ld	(disp_pat),a
	ld	a,(stc_row)
	ld	(pt3_row),a
	ld	a,(stc_delay)
	ld	(pt3_delay),a
	ld	ix,pt3_chA
	ld	iy,stc_chA
	call	@notes
	ld	ix,pt3_chB
	ld	iy,stc_chB
	call	@notes
	ld	ix,pt3_chC
	ld	iy,stc_chC
	call	@notes
@mirror:
	call	po_after		; (the pattern view, other formats)
	; The channel lines on screen read the PT3 replayer's per-channel
	; state. A register dump has no notes, samples or ornaments, so
	; just copy its tone periods and amplitudes there.
	ld	hl,ay_regs
	ld	de,ay_regs+8
	ld	ix,pt3_chA
	call	@copy
	ld	ix,pt3_chB
	call	@copy
	ld	ix,pt3_chC
@copy:
	ld	a,(hl)
	ld	(ix+PT3C_TON),a
	inc	hl
	ld	a,(hl)
	and	0Fh
	ld	(ix+PT3C_TON+1),a
	inc	hl
	ld	a,(de)
	ld	(ix+PT3C_AMP),a
	inc	de
	ret
	; note, sample and ornament of one channel
@notes:
	ld	a,(iy+SC_NOTE)
	ld	hl,stc_transp
	add	a,(hl)
	cp	96
	jr	c,@inrange
	ld	a,95
@inrange:
	ld	(ix+PT3C_NOTE),a
	ld	a,(iy+SC_TIK)		; sounding unless the count is negative
	rlca
	and	1
	xor	1
	ld	(ix+PT3C_ENABLED),a
	ld	a,(iy+SC_SAMNUM)
	ld	(ix+PT3C_SAMNUM),a
	ld	a,(iy+SC_ORNNUM)
	ld	(ix+PT3C_ORNNUM),a
	ret

sig_pt3:	db	"ProTracker 3."
sig_vt2:	db	"Vortex Tracker"

; play_index: play playlist entry HL.
play_index:
	ld	(pl_cur),hl
	push	hl
	ld	hl,0FFFFFFh
	ld	(pl_resume),hl
	pop	hl
	; for shuffle: this one has had its turn
	push	hl
	ld	a,l
	call	map_set
	pop	hl
	call	pl_get
	call	load_song
	call	after_load
	xor	a
	ld	(pan_line),a
	; An entry that cannot be played is passed over: the one after it
	; (or before it, going back with Left) is tried next, from the main
	; loop. Once as many have failed in a row as there are entries,
	; none can be played, and playback stops.
	ld	a,(state)
	cp	ST_LOADERR
	jr	z,@fail
	cp	ST_BADFILE
	jr	z,@fail
	xor	a			; it plays
	ld	(pl_fails),a
	inc	a
	ld	(pl_dir),a
	ret
@fail:
	ld	hl,pl_fails
	inc	(hl)
	ld	a,(pl_count)		; (at most 255 entries)
	cp	(hl)
	ret	z
	ret	c
	ld	a,(pl_dir)
	ld	(pl_skip),a
	ret

RESTART_SECS:	equ	3

; pl_none: In: HL = pl_cur. If no entry is playing because the one that
; was has been removed from the playlist, HL = the place it was (now
; holding the entry after it), with carry set. Otherwise HL is kept and
; carry is clear. Corrupts DE.
pl_none:
	push	hl
	ld	de,(pl_count)
	or	a
	sbc	hl,de			; (carry: a real entry)
	pop	hl
	ccf
	ret	nc
	push	hl
	ld	hl,(pl_resume)
	or	a
	sbc	hl,de
	add	hl,de
	jr	nc,@no
	pop	de
	scf
	ret
@no:
	pop	hl
	or	a
	ret

; next_track / prev_track: move through the playlist, wrapping round.
; prev_track goes back to the start of the current song first.
next_track:
	ld	a,1			; (a bad entry is passed over forwards)
	ld	(pl_dir),a
	ld	hl,(pl_count)
	ld	a,h
	or	l
	ret	z
	ld	a,(shuffle)
	or	a
	jp	nz,shuffle_next
	ld	hl,(pl_cur)
	call	pl_none			; (the playing entry was removed: the
	jp	c,play_index		; one now in its place is next)
	inc	hl
	ld	de,(pl_count)
	or	a
	sbc	hl,de
	jr	c,@ok
	ld	hl,0
	jp	play_index
@ok:
	add	hl,de
	jp	play_index
prev_track:
	ld	a,0FFh			; (and backwards)
	ld	(pl_dir),a
	ld	hl,(pl_count)
	ld	a,h
	or	l
	ret	z
	ld	a,(t_min)		; more than 3 seconds into a song,
	or	a			; "previous" starts it again instead
	jr	nz,@again
	ld	a,(t_sec)
	cp	RESTART_SECS
	jr	c,@prev
@again:
	ld	hl,(pl_cur)
	ld	de,(pl_count)
	or	a
	sbc	hl,de
	jr	nc,@prev
	add	hl,de
	jp	play_index
@prev:
	ld	hl,(pl_cur)
	call	pl_none			; (as if the removed one were playing)
	ld	a,h
	or	l
	jr	z,@last
	ld	de,(pl_count)
	or	a
	sbc	hl,de
	jr	nc,@last
	add	hl,de
	dec	hl
	jp	play_index
@last:
	ld	hl,(pl_count)
	dec	hl
	jp	play_index

; ---------------------------------------------------------------------
; Shuffle. With shuffle on, "next" picks an entry at random from those
; that have not had a turn yet; when all have, a new round starts. One
; bit per playlist entry in shuf_map records who has had a turn.
; ---------------------------------------------------------------------

; map_addr: A = entry number. Out: HL -> its byte of the map, A = its bit.
map_addr:
	ld	c,a
	srl	a
	srl	a
	srl	a
	ld	de,0
	ld	e,a
	ld	hl,shuf_map
	add	hl,de
	ld	a,c
	and	7
	ld	b,a
	inc	b
	ld	a,80h
@bit:
	rlca
	djnz	@bit
	ret
; map_test: NZ if entry A has had its turn. map_set: note that it has.
map_test:
	call	map_addr
	and	(hl)
	ret
map_set:
	call	map_addr
	or	(hl)
	ld	(hl),a
	ret
; shuf_zero: nobody has had a turn. shuf_clear: nobody but the entry
; being played.
shuf_zero:
	ld	hl,shuf_map
	ld	b,32
@clr:
	ld	(hl),0
	inc	hl
	djnz	@clr
	ret
shuf_clear:
	call	shuf_zero
	ld	hl,(pl_cur)
	ld	de,(pl_count)
	or	a
	sbc	hl,de
	ret	nc
	ld	a,(pl_cur)
	jp	map_set

; rnd: A = a fairly random byte. It mixes a running value with the
; CPU's refresh register and the tick counter, which depend on when
; keys were pressed.
rnd:
	ld	a,(rnd_seed)
	ld	b,a
	add	a,a
	add	a,a
	add	a,b
	inc	a
	ld	b,a
	ld	a,r
	add	a,b
	ld	hl,flash_t
	add	a,(hl)
	ld	(rnd_seed),a
	ret

; shuffle_next: play a random entry that has not had its turn.
shuffle_next:
	ld	a,(pl_count)
	cp	2
	jr	nc,@pick
	ld	hl,0			; a single entry: just play it again
	jp	play_index
@pick:
	call	rnd
	ld	hl,pl_count
@mod:
	cp	(hl)
	jr	c,@start
	sub	(hl)
	jr	@mod
@start:
	ld	(shuf_try),a		; look from a random place onwards
	ld	a,2
	ld	(shuf_pass),a
@pass:
	ld	a,(pl_count)
	ld	b,a
	ld	a,(shuf_try)
	ld	c,a
@scan:
	ld	a,(pl_cur)		; never the one playing now
	cp	c
	jr	z,@skip
	push	bc
	ld	a,c
	call	map_test
	pop	bc
	jr	z,@found
@skip:
	inc	c
	ld	a,(pl_count)
	cp	c
	jr	nz,@wrapped
	ld	c,0
@wrapped:
	djnz	@scan
	call	shuf_clear		; everyone has had a turn: new round
	ld	hl,shuf_pass
	dec	(hl)
	jr	nz,@pass
	ld	c,0
@found:
	ld	hl,0
	ld	l,c
	jp	play_index

; Where each format counts the times its song has ended (by FMT_).
loops_tab:	dl	pt3_loops,psg_loops,stc_loops,pt2_loops,pt1_loops
		dl	asc_loops,stp_loops,sqt_loops,psc_loops,ym_loops
		dl	ayf_loops

; The formats from FMT_PT2 on: for each, the replayer's routines, where
; it keeps what the screen shows, and how its files are recognised (see
; the F_ offsets in equs.inc). Adding a format of this kind takes an
; entry here, one in loops_tab, an extension below and an include.
fmt_tab:
	dl	pt2_init,pt2_play,pt2_length,pt2_pos,pt2_chA,P2_SIZE
	dl	PT2_NAME,30,0,0,ext_pt2
	dl	pt1_init,pt1_play,pt1_length,pt1_pos,pt1_chA,P1_SIZE
	dl	PT1_NAME,30,0,0,ext_pt1
	dl	asc_init,asc_play,asc_length,asc_pos,asc_chA,AC_SIZE
	dl	0,0,0,0,ext_asc
	dl	stp_init,stp_play,stp_length,stp_pos,stp_chA,TP_SIZE
	dl	0,0,0,0,ext_stp
	dl	sqt_init,sqt_play,sqt_length,sqt_pos,sqt_chA,SQ_SIZE
	dl	0,0,0,0,ext_sqt
	dl	psc_init,psc_play,psc_length,psc_pos,psc_chA,PSCC_SIZE
	dl	PSC_NAME,20,PSC_AUTHOR,20,ext_psc

; fmt_entry: IY = the fmt_tab entry of the current format.
fmt_entry:
	ld	iy,fmt_tab
	ld	a,(fmt)
	sub	FMT_PT2
	ret	z
	ld	b,a
	ld	de,F_SIZE
@next:
	add	iy,de
	djnz	@next
	ret

; fmt_init: set the replayer of the entry at IY up for the module in
; memory. Out: carry set if it rejects the module. Preserves IY.
fmt_init:
	push	iy
	ld	hl,(iy+F_INIT)
	ld	(fmt_call+1),hl
	ld	hl,MODULE
	ld	bc,(mod_len)
fmt_call:
	call	0			; (address filled in above)
	pop	iy
	ret

; jp_hl: call the routine whose address is in HL.
jp_hl:
	jp	(hl)

; kbd_poll: has a key gone down since the last call?
; Out: NZ if so, with A = ASCII code and B = FabGL virtual key number.
kbd_poll:
	ld	ix,(sysvars)
	ld	a,(ix+sysvar_vkeycount)
	ld	hl,k_count
	cp	(hl)
	jr	z,@none
	ld	(hl),a
	ld	a,(ix+sysvar_vkeydown)
	or	a
	jr	z,@none
	ld	b,(ix+sysvar_vkeycode)
	ld	c,(ix+sysvar_keyascii)
	or	1
	ld	a,c
	ret
@none:
	xor	a
	ret

; handle_key: act on a key. In: A = ASCII, B = virtual key.
handle_key:
	ld	c,a
	xor	a			; (a key pressed starts the count of
	ld	(pl_fails),a		; entries that failed afresh)
	ld	a,(input_mode)
	or	a
	jp	nz,input_key
	ld	a,(panel)		; the help: the cursor keys scroll
	cp	3			; it, any other key closes it
	jr	nz,@nothelp
	ld	a,b
	call	help_key
	ret	nz
	ld	a,(help_prev)
	jp	@panel
@nothelp:
	ld	a,(panel)		; the pattern view has no cursor
	cp	2
	jr	nz,@keys
	ld	a,b
	cp	VK_UP
	ret	z
	cp	VK_DOWN
	ret	z
	cp	VK_PAGEUP
	ret	z
	cp	VK_PAGEDOWN
	ret	z
	cp	VK_HOME
	ret	z
	cp	VK_END
	ret	z
@keys:
	ld	a,b
	cp	VK_UP
	jp	z,key_up
	cp	VK_DOWN
	jp	z,key_down
	cp	VK_PAGEUP
	jp	z,key_pgup
	cp	VK_PAGEDOWN
	jp	z,key_pgdn
	cp	VK_HOME
	jp	z,key_home
	cp	VK_END
	jp	z,key_end
	cp	VK_RETURN
	jp	z,@enter
	cp	VK_KP_ENTER
	jp	z,@enter
	cp	VK_TAB
	jp	z,@tab
	cp	VK_ESCAPE
	jp	z,@quit
	cp	VK_BACKSPACE
	jp	z,@back
	cp	VK_DELETE
	jp	z,@del
	cp	VK_INSERT
	jp	z,@add
	cp	VK_LEFT
	jp	z,prev_track
	cp	VK_RIGHT
	jp	z,next_track
	ld	a,c
	; 6 to 0 do the same for the second chip
	ld	hl,ay_mute2
	cp	'0'			; of a TurboSound tune: D, E, F, its
	jr	nz,@not0		; noise, its envelope
	ld	a,'5'
	jr	@chip2
@not0:
	cp	'6'
	jr	c,@chip1
	cp	'9'+1
	jr	nc,@notmute
	sub	5
@chip2:
	ld	c,a
	ld	a,(ts_on)		; (with one chip they do nothing)
	or	a
	ret	z
	ld	a,c
	jr	@toggle
@chip1:
	ld	hl,ay_mute
	cp	'1'			; 1 to 5 mute and unmute: A, B, C,
	jr	c,@notmute		; noise, envelope
@toggle:
	sub	'0'
	ld	b,a
	ld	a,80h
@bit:
	rlca
	djnz	@bit
	xor	(hl)
	ld	(hl),a
	; the pattern view greys muted channels,
	xor	a
	ld	(pv_valid),a		; so have it drawn again
	ret
@notmute:
	cp	'+'			; volume ('=' is '+' without Shift)
	jp	z,vol_up
	cp	'='
	jp	z,vol_up
	cp	'-'
	jp	z,vol_down
	cp	'_'
	jp	z,vol_down
	cp	'?'
	jp	z,@help
	cp	'['
	jp	z,pl_moveup
	cp	']'
	jp	z,pl_movedown
	call	upcase
	cp	'Q'
	jr	z,@quit
	cp	' '
	jp	z,@pause
	cp	'M'
	jp	z,@mute
	cp	'H'
	jp	z,@help
	cp	'R'
	jp	z,@shuffle
	cp	'C'
	jp	z,@clear
	cp	'S'
	jp	z,@save
	cp	'N'
	jp	z,ay_next
	cp	'P'
	jp	z,ay_prev
	cp	'V'
	jp	z,an_toggle
	cp	'X'			; screen modes (config.asm)
	jp	z,scr_next
	cp	'Z'
	jp	z,scr_prev
	cp	'T'			; colour themes (config.asm)
	jp	z,theme_next
	ret
@quit:
	ld	a,1
	ld	(quit),a
	ret
	; M: silence everything, or stop doing so
@mute:
	ld	a,(mute_all)
	xor	1
	ld	(mute_all),a
	ld	a,0
	jp	nz,ay_volume
	ld	a,(vol_now)
	jp	ay_volume
@shuffle:				; R: random order on and off
	ld	a,(shuffle)
	xor	1
	ld	(shuffle),a
	ret	z
	jp	shuf_clear		; a new round starts with this song
@help:					; H or ?: show the keys in the panel
	ld	a,(panel)
	ld	(help_prev),a
	xor	a
	ld	(help_top),a
	ld	a,3
	jp	@panel
@tab:
	ld	a,(panel)		; playlist, then the pattern view if
	or	a			; this song has one, then files, then
					; the playlist again if it has entries
	jr	nz,@tab1
	call	pat_avail
	ld	a,2
	jr	nz,@panel
	ld	a,1
	jr	@panel
@tab1:
	cp	2
	ld	a,1
	jr	z,@panel
	ld	hl,(pl_count)		; files: on to the playlist, unless it
	ld	a,h			; is empty
	or	l
	ret	z
	xor	a
@panel:
	ld	(panel),a
	ld	a,1
	ld	(dirty_panbar),a
	xor	a
	ld	(pan_line),a
	ld	(pv_valid),a
	ld	(pv_blank),a
	ret
@enter:
	ld	a,(panel)
	cp	2
	ret	z
	or	a
	jp	nz,br_activate
	ld	hl,(pl_count)
	ld	a,h
	or	l
	ret	z
	ld	hl,(pl_sel)
	jp	play_index
@back:
	ld	a,(panel)
	cp	1
	ret	nz
	jp	br_parent
@add:
	ld	a,(panel)		; unless the file browser is showing,
	cp	1			; Insert opens it
	jp	z,br_addsel
	ld	a,1
	jr	@panel
@del:
	ld	a,(panel)
	or	a
	ret	nz
	jp	pl_del
@clear:
	ld	a,(panel)
	or	a
	ret	nz
	jp	pl_clear
@pause:
	ld	a,(state)
	cp	ST_PLAYING
	jr	nz,@resume
	ld	a,ST_PAUSED
	ld	(state),a
	jp	ay_silence
@resume:
	cp	ST_PAUSED
	ret	nz
	ld	a,ST_PLAYING
	ld	(state),a
	ret
@save:
	ld	hl,(pl_count)
	ld	a,h
	or	l
	ret	z
	ld	a,1
	ld	(input_mode),a
	ld	hl,pl_name		; a playlist with a name offers it,
	ld	de,in_buf		; selected, so that typing replaces it
	call	strcpy
	ld	hl,in_buf
	call	strlen
	ld	a,c
	ld	(in_len),a
	or	a
	jr	z,@nosel
	ld	a,1
@nosel:
	ld	(in_sel),a
	jp	draw_prompt

; input_key: keys while the file name for "save playlist" is typed.
; In: C = ASCII, B = virtual key. While the name offered is selected,
; a character typed replaces it, Backspace or Delete removes it, and the
; cursor keys, Home and End keep it for editing.
input_key:
	ld	a,b
	cp	VK_RETURN
	jp	z,@done
	cp	VK_KP_ENTER
	jp	z,@done
	cp	VK_ESCAPE
	jp	z,@cancel
	ld	hl,in_sel
	cp	VK_BACKSPACE
	jr	z,@del
	cp	VK_DELETE
	jr	z,@del
	cp	VK_LEFT
	jr	z,@keep
	cp	VK_RIGHT
	jr	z,@keep
	cp	VK_HOME
	jr	z,@keep
	cp	VK_END
	jr	z,@keep
	ld	a,c
	cp	33			; no spaces or control codes, and
	ret	c			; nothing FAT would refuse
	cp	127
	ret	nc
	ld	hl,txt_badchars
@bad:
	ld	a,(hl)
	or	a
	jr	z,@good
	cp	c
	ret	z
	inc	hl
	jr	@bad
@good:
	ld	a,(in_sel)		; typing over the name offered
	or	a
	call	nz,@clear
	ld	a,(in_len)
	cp	40
	ret	nc
	ld	de,0
	ld	e,a
	ld	hl,in_buf
	add	hl,de
	ld	(hl),c
	inc	hl
	ld	(hl),0
	inc	a
	ld	(in_len),a
	jr	draw_prompt
@keep:
	ld	a,(hl)
	or	a
	ret	z
	ld	(hl),0
	jr	draw_prompt
@del:
	ld	a,(hl)
	or	a
	jr	z,@rubout
	call	@clear
	jr	draw_prompt
@clear:
	xor	a
	ld	(in_sel),a
	ld	(in_len),a
	ld	(in_buf),a
	ret
@rubout:
	ld	a,(in_len)
	or	a
	ret	z
	dec	a
	ld	(in_len),a
	ld	de,0
	ld	e,a
	ld	hl,in_buf
	add	hl,de
	ld	(hl),0
	jr	draw_prompt
@done:
	xor	a
	ld	(input_mode),a
	ld	a,(in_len)
	or	a
	jp	z,ui_helpbar
	jp	pl_save			; ends by showing a message
@cancel:
	xor	a
	ld	(input_mode),a
	jp	ui_helpbar
txt_badchars:	db	"/\\:*?\"<>|",0

; draw_prompt: show the file name being typed on the bottom row: the
; prompt, the name (dark on white while selected) and a cursor.
draw_prompt:
	ld	hl,txt_saveas
	ld	a,(scr_rows)
	dec	a
	ld	e,a
	ld	b,DP_TEXT
	call	ui_bar			; (white on dark)
	ld	a,(in_sel)
	or	a
	jr	z,@plain
	ld	a,COL_DARK
	call	vcol
	ld	a,BG+COL_WHITE
	call	vcol
@plain:
	ld	hl,in_buf
	call	vstr
	ld	a,COL_WHITE
	call	vcol
	ld	a,BG+COL_DARK
	call	vcol
	ld	a,'_'
	call	vdu_put
	ld	a,(in_len)		; and spaces to the end of the bar
	ld	b,a
	ld	a,79-DP_TEXT-1
	sub	b
	ld	b,a
	call	vspaces
	jp	vdu_flush
txt_saveas:	db	" Save as (Enter saves, Esc cancels): ",0
DP_TEXT:	equ	37		; columns the prompt takes

	include	"../lib/libsupport.asm"
	include	"../lib/pt3play.asm"
	include	"../lib/pt3tab.inc"
	include	"../lib/pt3ts.asm"
	include	"../lib/psgplay.asm"
	include	"../lib/stcplay.asm"
	include	"../lib/pt2play.asm"
	include	"../lib/pt1play.asm"
	include	"../lib/ascplay.asm"
	include	"../lib/stpplay.asm"
	include	"../lib/sqtplay.asm"
	include	"../lib/pscplay.asm"
	include	"../lib/notetab.inc"
	include	"../lib/ymplay.asm"
	include	"../lib/lh5.asm"
	include	"../lib/ayfplay.asm"
	include	"../lib/z80emu.asm"
	include	"../lib/ayvdp.asm"
	include	"../lib/tick50.asm"
	include	"util.asm"
	include	"ui.asm"
	include	"spectrum.asm"
	include	"config.asm"
	include	"pattern.asm"
	include	"patother.asm"
	include	"files.asm"

arg_ptr:	ds	3	; command line from MOS
sysvars:	ds	3	; address of the MOS system variables
old_vector:	ds	3	; timer 1 vector as MOS had it
k_count:	ds	1	; last key packet count seen
state:		ds	1	; ST_ value
quit:		ds	1	; non-zero to leave the main loop
input_mode:	ds	1	; non-zero while a file name is being typed
tot_min:	ds	1	; total length of the song
tot_sec:	ds	1
tot_work:	ds	3	; (its length in seconds)
vol_saved:	ds	1	; VDP volume when the program started
vol_now:	ds	1	; VDP volume now
mute_all:	ds	1	; non-zero while everything is muted (M)
help_prev:	ds	1	; panel to go back to when help closes
info_title:	ds	3	; address of the song's title text
info_author:	ds	3	; address of its author text
alt_author:	ds	28	; author copied out of a module likewise
alt_title:	ds	33	; title copied out of a module that has
				; no zero after it
shuffle:	ds	1	; non-zero while shuffle is on (R)
pl_skip:	ds	1	; 1 or 0FFh: pass over a bad entry, forwards
			; or backwards; 0: no
pl_dir:		ds	1	; 1 or 0FFh: the way the playlist last moved
pl_fails:	ds	1	; entries that failed to play, in a row
shuf_map:	ds	32	; one bit per entry: has had its turn
shuf_try:	ds	1	; shuffle: where the search starts
shuf_pass:	ds	1	; shuffle: search passes left
rnd_seed:	ds	1	; running value for rnd
ts_on:		ds	1	; non-zero if the song is a TurboSound tune
fmt:		ds	1	; format of the current song (FMT_ value)
disp_pat:	ds	1	; pattern number shown, formats other than PT3
disp_tr:	ds	1	; transposition added to the notes shown
disp_ctr:	ds	1	; offset of a channel's own one, or 0FFh
ay_shown:	ds	1	; AY file: the song whose name is shown
mod_len:	ds	3	; length of the music file in memory
t_frac:		ds	1	; frames into the current second
t_sec:		ds	1	; elapsed time
t_min:		ds	1