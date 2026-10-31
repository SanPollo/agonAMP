; ui.asm - the agonAMP screen: title, song details, channel meters and
; the list panel shared by the playlist and the file browser.
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
; The layout follows the general look of Open Cubic Player's text mode:
; coloured title bars, a block of song details, one line per channel
; with a level meter, and a list below. Nothing is taken from OCP itself.
;
; The screen is only ever written from the main loop, and ui_step does
; one small piece of drawing per call so that the 50 Hz music tick is
; never kept waiting for long.

MSG_TICKS:	equ	150	; how long a message stays up (3 s)
msg_timer:	ds	1	; ticks until the message is removed
scr_rows:	ds	1	; text rows on screen
lay_ts:		ds	1	; non-zero: laid out for a TurboSound tune
lay_x:		ds	1	; rows the panel is moved down for that
ui_ntasks:	ds	1	; lines ui_lines looks after: 5 or 9
ne_chip:	ds	1	; ne_check: which chip's line
ne_ctx:		ds	3	; ne_check: that chip's state
ne_lastp:	ds	3	; ne_check: what that line shows
pan_h:		ds	1	; lines in the list panel
help_top:	ds	1	; help line shown at the top of the panel
pan_line:	ds	1	; next panel line to draw; pan_h = none
panel:		ds	1	; 0 playlist, 1 files, 2 pattern, 3 help
flash_t:	ds	1	; counts ticks; bit 4 times the flashing
ui_wait:	ds	1	; non-zero: waiting for the VDP to catch up
ui_wait_t:	ds	1	; ticks left before giving up waiting
ui_drew:	ds	1	; set whenever the cursor is moved to draw
ui_turn:	ds	1	; whose turn: panel or the lines above it
ui_rot:		ds	1	; which line was looked at last
dirty_frame:	ds	1	; non-zero: redraw the fixed parts
dirty_info:	ds	1	; non-zero: redraw the song details
dirty_panbar:	ds	1	; non-zero: redraw the bar above the list
dirty_keys:	ds	1	; non-zero: put the key summary back
dc_i:		ds	1	; channel being drawn
dpl_r:		ds	1	; panel line being drawn
dpl_idx:	ds	3	; list entry on that line
old_sel:	ds	3	; selection before a cursor move
ch_sig:		ds	10	; what a line should show now
ch_last:	ds	48	; what the channel lines show (up to six)
ne_last:	ds	6	; what the noise/envelope line shows
ne_last2:	ds	6	; and the second chip's
st_last:	ds	17	; what the status lines, "mute" and the
				; AY song number show
st_last_end:
pb_buf:		ds	96	; text of the panel bar

; ui_init: prepare the screen.
ui_init:
	ld	hl,ui_setup
	call	vseq
	call	theme_apply		; the colour theme (config.asm)
	ld	a,0FFh			; that set colours behind vcol's back
	ld	(col_fg),a
	ld	(col_bg),a
	xor	a
	ld	(msg_timer),a
	ld	(ui_wait),a		; (not waiting for the VDP yet)
	ld	(ui_wait_t),a
	ld	(dirty_keys),a
	ld	(lay_ts),a
	ld	(an_next),a
	ld	hl,an_shown		; no bars on the screen just cleared,
	ld	b,AN_COLS*2		; and none wanted
@nobars:
	ld	(hl),a
	inc	hl
	djnz	@nobars
	inc	a
	ld	(an_rnd),a
	call	lay_set
	ld	a,1
	ld	(dirty_frame),a
	jp	vdu_flush

; ui_layout: a TurboSound tune has six channels, so while one is loaded
; there are six channel lines and two noise and envelope lines, and the
; panel starts lower and is shorter. This is called after every load;
; when the kind of tune has changed it clears the screen and has it all
; drawn again in the other arrangement.
ui_layout:
	ld	a,(ts_on)
	ld	hl,lay_ts
	cp	(hl)
	ret	z
	ld	(hl),a
; ui_relayout: lay the screen out again (after the analyser is turned on
; or off as well).
ui_relayout:
	call	lay_set
	ld	ix,pl_count		; keep both lists' selections in view
	call	@fit
	ld	ix,br_count
	call	@fit
	ld	hl,@clear
	call	vseq
	ld	a,0FFh			; (that set colours behind vcol's back)
	ld	(col_fg),a
	ld	(col_bg),a
	xor	a			; a message that was up has gone with
	ld	(msg_timer),a		; the screen: draw_frame shows the keys
	inc	a
	ld	(dirty_frame),a
	jp	vdu_flush
@fit:
	ld	hl,(ix+L_SEL)
	ld	de,(ix+L_TOP)
	or	a
	sbc	hl,de
	ret	c
	ld	de,0
	ld	a,(pan_h)
	ld	e,a
	or	a
	sbc	hl,de
	ret	c
	ld	de,(ix+L_TOP)
	add	hl,de
	inc	hl
	ld	(ix+L_TOP),hl
	ret
@clear:	db	17,COL_GREY,17,BG+COL_BLACK,12,0FFh

; lay_set: work out whether the analyser is shown (an_on, from an_show),
; where the panel starts (lay_x rows lower than with three channels and
; no analyser), how many lines it has, where the analyser's bars end and
; how many lines ui_lines looks after, from lay_ts and an_on.
lay_set:
	call	an_show
	ld	(an_on),a
	ld	a,(lay_ts)
	or	a
	ld	b,0
	ld	c,5
	jr	z,@an
	ld	b,TS_ROWS
	ld	c,9
@an:
	ld	a,c
	ld	(ui_ntasks),a
	ld	a,b			; the analyser's bottom row, if shown
	add	a,ROW_PANBAR+AN_BARS
	ld	(an_bot),a
	ld	a,(an_on)
	or	a
	jr	z,@set
	ld	a,b
	add	a,AN_ROWS
	ld	b,a
@set:
	ld	a,b
	ld	(lay_x),a
	ld	a,(scr_rows)
	sub	ROW_PANEL+1
	sub	b
	ld	(pan_h),a
	ret

; an_show: should the analyser be shown? Only if it is wanted (an_want),
; the screen has room for it, and a song is loaded (playing or paused),
; so that the panel has all the room there is while nothing is. Out: A
; = 1 if so, else 0. Preserves BC, DE.
an_show:
	ld	a,(state)
	cp	ST_PLAYING
	jr	z,@loaded
	cp	ST_PAUSED
	jr	nz,@no
@loaded:
	ld	a,(scr_rows)
	cp	AN_MIN
	jr	c,@no
	ld	a,(an_want)
	ret
@no:
	xor	a
	ret

; an_toggle: the V key: show or hide the analyser, if the screen has room
; for it.
an_toggle:
	ld	a,(scr_rows)
	cp	AN_MIN
	ld	hl,txt_anroom
	jp	c,ui_msg
	ld	a,(an_want)
	xor	1
	ld	(an_want),a
	jp	ui_relayout

; pan_row: A = the screen row of panel line A. Preserves all else.
pan_row:
	push	hl
	ld	hl,lay_x
	add	a,(hl)
	pop	hl
	add	a,ROW_PANEL
	ret
; The screen mode's own colours (VDU 20, undoing any palette changes made
; before agonAMP was run); cursor off; character 128 = meter block, 129 =
; meter dot, 130 to 137 the analyser's bars, 138 an apostrophe; clear.
ui_setup:
	db	20
	db	23,1,0
	db	23,128,0,7Eh,7Eh,7Eh,7Eh,7Eh,7Eh,0
	db	23,129,0,0,0,18h,18h,0,0,0
	; character 138: a straight apostrophe (the font's own is slanted)
	db	23,138,18h,18h,18h,0,0,0,0,0
	; characters 130 to 137: a bar 1 to 8 eighths of a cell high, one
	; pixel narrower than the cell so that bars side by side stay apart
	db	23,130,0,0,0,0,0,0,0,0FEh
	db	23,131,0,0,0,0,0,0,0FEh,0FEh
	db	23,132,0,0,0,0,0,0FEh,0FEh,0FEh
	db	23,133,0,0,0,0,0FEh,0FEh,0FEh,0FEh
	db	23,134,0,0,0,0FEh,0FEh,0FEh,0FEh,0FEh
	db	23,135,0,0,0FEh,0FEh,0FEh,0FEh,0FEh,0FEh
	db	23,136,0,0FEh,0FEh,0FEh,0FEh,0FEh,0FEh,0FEh
	db	23,137,0FEh,0FEh,0FEh,0FEh,0FEh,0FEh,0FEh,0FEh
	db	17,COL_GREY,17,BG+COL_BLACK,12,0FFh

; ui_restore: put the screen back to normal on exit: VDU 20 puts the
; colours back to the screen mode's own (undoing the colour theme), and
; VDU 23,0,&91 the characters (undoing 128 to 138).
ui_restore:
	ld	hl,@seq
	call	vseq
	jp	vdu_flush
@seq:	db	20,23,0,91h,17,COL_WHITE,17,BG+COL_BLACK,12,23,1,1,0FFh

; ui_bar: draw a white bar on the theme's dark colour. In: HL -> text,
; E = row, B = width.
ui_bar:
	push	hl
	ld	d,0
	call	vat
	ld	a,COL_WHITE
	call	vcol
	ld	a,BG+COL_DARK
	call	vcol
	pop	hl
	call	vtext
	jp	vdu_flush

; vstr: queue a zero terminated string as it is.
vstr:
	ld	a,(hl)
	or	a
	ret	z
	call	vdu_put
	inc	hl
	jr	vstr

; vlabel: queue a caption in cyan, leaving white selected for the value.
vlabel:
	ld	a,COL_CYAN
	call	vcol
	call	vstr
	ld	a,COL_WHITE
	jp	vcol

; vtail: if a string is longer than a field, skip to its last part.
; In: HL -> string, B = width. Out: HL -> where to start. Preserves BC.
vtail:
	push	bc
	call	strlen
	pop	de
	push	de
	ld	a,d
	ld	de,0
	ld	e,a
	push	hl
	push	bc
	pop	hl
	or	a
	sbc	hl,de
	jr	c,@fits
	jr	z,@fits
	pop	de
	add	hl,de
	pop	bc
	ret
@fits:
	pop	hl
	pop	bc
	ret

; ui_helpbar: draw the key summary (the legend) on the bottom row, with
; the key names in yellow and what they do in white. It is one column
; short so that the screen does not scroll. While a file name is being
; typed, the save prompt is drawn there instead.
ui_helpbar:
	ld	a,(input_mode)
	or	a
	jp	nz,draw_prompt
	ld	a,(scr_rows)
	dec	a
	ld	e,a
	ld	d,0
	call	vat
	ld	a,BG+COL_DARK
	call	vcol
	ld	hl,txt_help
	ld	b,79
@char:
	ld	a,(hl)
	or	a
	jr	z,@pad
	inc	hl
	ld	c,a
	cp	' '
	jr	nz,@notspace
	ld	a,COL_BYELLOW		; a key name follows a space
	call	vcol
@notspace:
	ld	a,c
	cp	':'
	jr	nz,@put
	ld	a,COL_WHITE		; and its description follows a colon
	call	vcol
@put:
	ld	a,c
	cp	32
	jr	nc,@plain
	ld	a,27			; VDU 27 prints a character below 32
	call	vdu_put			; (the two arrow heads)
	ld	a,c
@plain:
	call	vdu_put
	djnz	@char
	jp	vdu_flush
@pad:
	ld	a,' '
	call	vdu_put
	djnz	@pad
	jp	vdu_flush

; ui_msg: show a message on the bottom row for a few seconds, in black
; on yellow so that it stands out from the key summary. In: HL -> text.
ui_msg:
	xor	a			; (a message replaces the key summary)
	ld	(dirty_keys),a
	ld	a,MSG_TICKS
	ld	(msg_timer),a
	push	hl
	ld	a,(scr_rows)
	dec	a
	ld	e,a
	ld	d,0
	call	vat
	ld	a,COL_BLACK
	call	vcol
	ld	a,BG+COL_BYELLOW
	call	vcol
	pop	hl
	ld	b,79
	call	vtext
	jp	vdu_flush

; ui_err: like ui_msg, but for something that went wrong: white on red.
ui_err:
	xor	a
	ld	(dirty_keys),a
	ld	a,MSG_TICKS
	ld	(msg_timer),a
	push	hl
	ld	a,(scr_rows)
	dec	a
	ld	e,a
	ld	d,0
	call	vat
	ld	a,COL_WHITE
	call	vcol
	ld	a,BG+COL_RED
	call	vcol
	pop	hl
	ld	b,79
	call	vtext
	jp	vdu_flush

; msg_tick: called 50 times a second; puts the key summary back when a
; message has been up for long enough.
msg_tick:
	ld	hl,flash_t		; the clock for flashing signs
	inc	(hl)
	ld	a,(ui_wait_t)		; also the time-out for ui_paced
	or	a
	jr	z,@msg
	dec	a
	ld	(ui_wait_t),a
@msg:
	ld	a,(msg_timer)
	or	a
	ret	z
	dec	a
	ld	(msg_timer),a
	ret	nz
	ld	a,1			; the key summary goes back, drawn with
	ld	(dirty_keys),a		; the rest of the screen (ui_step)
	ret

; draw_frame: draw everything that does not change, and mark the rest
; to be drawn again.
draw_frame:
	ld	d,0			; the title, yellow on dark
	ld	e,ROW_TITLE
	call	vat
	ld	a,COL_BYELLOW
	call	vcol
	ld	a,BG+COL_DARK
	call	vcol
	ld	hl,txt_title		; name and version at the left,
	ld	b,58
	call	vtext
	ld	hl,txt_copy		; copyright at the right
	ld	b,22
	call	vtext
	ld	hl,txt_chbar
	ld	e,ROW_CHBAR
	ld	b,80
	call	ui_bar
	ld	a,(msg_timer)		; (leave a message that is up alone)
	or	a
	call	z,ui_helpbar
	ld	d,0			; the captions of the status line
	ld	e,ROW_STATUS
	call	vat
	ld	a,BG+COL_BLACK
	call	vcol
	ld	hl,lbl_pos
	ld	b,7
	call	@cap
	ld	hl,lbl_pat
	ld	b,3
	call	@cap
	ld	hl,lbl_row
	ld	b,3
	call	@cap
	ld	hl,lbl_speed
	ld	b,3
	call	@cap
	ld	hl,lbl_time
	ld	b,11
	call	@cap
	ld	hl,lbl_track
	ld	b,18
	call	@cap
	call	vdu_flush
	ld	hl,ch_last
	ld	b,st_last_end-ch_last
@inv:
	ld	(hl),0FEh
	inc	hl
	djnz	@inv
	ld	hl,an_shown		; (the screen has just been cleared)
	ld	b,AN_COLS
@nobar:
	ld	(hl),0
	inc	hl
	djnz	@nobar
	ld	a,1
	ld	(dirty_info),a
	ld	(dirty_panbar),a
	xor	a
	ld	(pan_line),a
	ld	(pv_valid),a
	ld	(pv_blank),a
	ret
@cap:					; a caption and room for its value
	push	bc
	call	vlabel
	pop	bc
	jp	vspaces

; draw_info: the file name, and the title and author from the module.
draw_info:
	ld	d,0
	ld	e,ROW_FILE
	call	vat
	ld	a,BG+COL_BLACK
	call	vcol
	ld	hl,lbl_file
	call	vlabel
	ld	hl,cur_path
	ld	b,67			; (the "mute" sign is to its right)
	call	vtail
	call	vtext
	ld	d,0
	ld	e,ROW_SONG
	call	vat
	ld	hl,lbl_title
	call	vlabel
	ld	hl,(info_title)
	ld	c,32
	call	@field
	ld	hl,lbl_by
	call	vlabel
	ld	hl,(info_author)
	ld	c,27			; (the "shuffle" sign is to its right)
	call	@field
	jp	vdu_flush
@field:					; C characters, blank if no song
	ld	a,(state)
	cp	ST_PLAYING
	jr	z,@show
	cp	ST_PAUSED
	jr	z,@show
	ld	hl,txt_none
@show:
	ld	b,c
	jp	vtext

; draw_panbar: the bar above the list says which list is showing.
draw_panbar:
	ld	hl,txt_playlist
	ld	a,(panel)
	or	a
	jr	z,@go
	cp	2
	jr	nz,@notpat
	ld	hl,txt_pattern
	ld	a,(lay_ts)
	or	a
	jr	z,@go
	ld	hl,txt_pattern6
	jr	@go
@notpat:
	ld	hl,txt_helpbar
	cp	3
	jr	z,@go
	ld	hl,txt_files
	ld	de,pb_buf
	call	strcpy
	push	de
	ld	hl,br_path
	ld	b,68
	call	vtail			; (corrupts DE)
	pop	de
	call	strcpy
	ld	hl,pb_buf
@go:
	ld	a,(lay_x)
	add	a,ROW_PANBAR
	ld	e,a
	ld	b,80
	jp	ui_bar

; status_check: bring the status line up to date. Each value has its
; own place on the line and only a value that has changed is redrawn,
; one per call, because the VDP takes time over every character.
; Out: NZ if it drew something.
status_check:
	ld	a,(pt3_pos)		; position / positions
	ld	hl,st_last
	cp	(hl)
	jr	nz,@pos
	ld	a,(pt3_numpos)
	ld	hl,st_last+1
	cp	(hl)
	jr	z,@fpat
@pos:
	ld	a,(pt3_pos)
	ld	(st_last),a
	ld	a,(pt3_numpos)
	ld	(st_last+1),a
	ld	d,5
	call	st_at
	ld	a,(pt3_pos)
	call	vdec3
	call	st_slash
	ld	a,(pt3_numpos)
	call	vdec3
	jp	st_done
@fpat:
	ld	a,(disp_pat)		; pattern (the PT3 replayer keeps it
	ld	c,a			; as pattern * 3)
	ld	a,(fmt)
	or	a
	jr	nz,@patc
	ld	a,(pt3_patx3)
	ld	c,0FFh
@div3:
	inc	c
	sub	3
	jr	nc,@div3
@patc:
	ld	a,c
	ld	hl,st_last+2
	cp	(hl)
	jr	z,@frow
	ld	(hl),a
	ld	d,17
	call	st_at
	ld	a,(st_last+2)
	call	vdec3
	jp	st_done
@frow:
	ld	a,(pt3_row)
	ld	hl,st_last+3
	cp	(hl)
	jr	z,@fspeed
	ld	(hl),a
	ld	d,25
	call	st_at
	ld	a,(pt3_row)
	call	vdec3
	jp	st_done
@fspeed:
	ld	a,(pt3_delay)
	ld	hl,st_last+4
	cp	(hl)
	jr	z,@ftime
	ld	(hl),a
	ld	d,35
	call	st_at
	ld	a,(pt3_delay)
	call	vdec3
	jp	st_done
@ftime:
	ld	a,(t_min)		; time so far: the minutes changed?
	ld	hl,st_last+6
	cp	(hl)
	jr	nz,@time
	ld	a,(t_sec)		; just the seconds?
	ld	hl,st_last+5
	cp	(hl)
	jr	z,@ftot
	ld	(hl),a
	ld	d,47
	call	st_at
	ld	a,(t_sec)
	call	vdec2
	jp	st_done
@time:
	ld	(hl),a
	ld	a,(t_sec)
	ld	(st_last+5),a
	ld	d,44
	call	st_at
	ld	a,(t_min)
	call	vdec2
	ld	a,':'
	call	vdu_put
	ld	a,(t_sec)
	call	vdec2
	call	st_slash
	jp	st_done
@ftot:
	ld	a,(tot_min)		; length of the song
	ld	hl,st_last+12
	cp	(hl)
	jr	nz,@tot
	ld	a,(tot_sec)
	ld	hl,st_last+13
	cp	(hl)
	jr	z,@ftrack
@tot:
	ld	a,(tot_min)
	ld	(st_last+12),a
	ld	a,(tot_sec)
	ld	(st_last+13),a
	ld	d,50
	call	st_at
	ld	a,(tot_min)
	call	vdec2
	ld	a,':'
	call	vdu_put
	ld	a,(tot_sec)
	call	vdec2
	jp	st_done
@ftrack:
	ld	a,(pl_cur)
	ld	hl,st_last+7
	cp	(hl)
	jr	nz,@track
	ld	a,(pl_count)
	ld	hl,st_last+8
	cp	(hl)
	jr	z,@fstate
@track:
	ld	a,(pl_cur)
	ld	(st_last+7),a
	ld	a,(pl_count)
	ld	(st_last+8),a
	ld	d,62
	call	st_at
	ld	a,(pl_cur)
	inc	a
	call	vdec3
	call	st_slash
	ld	a,(pl_count)
	call	vdec3
	jp	st_done
@fstate:
	ld	a,(state)		; "pause" flashes: bit 7 = hidden now
	cp	ST_PAUSED
	jr	nz,@scode
	ld	a,(flash_t)
	bit	4,a
	ld	a,ST_PAUSED
	jr	z,@scode
	or	80h
@scode:
	ld	hl,st_last+9
	cp	(hl)
	jr	z,@fmute
	ld	(hl),a
	ld	d,70
	call	st_at
	ld	a,COL_BYELLOW
	call	vcol
	ld	a,(st_last+9)
	bit	7,a
	jr	z,@name
	ld	b,10
	call	vspaces
	jp	st_done
@name:
	ld	c,a			; state name, 10 characters each
	add	a,a
	add	a,a
	add	a,c
	add	a,a
	ld	de,0
	ld	e,a
	ld	hl,txt_states
	add	hl,de
	ld	b,10
@st:
	ld	a,(hl)
	call	vdu_put
	inc	hl
	djnz	@st
	jp	st_done
@fmute:
	ld	a,(mute_all)		; "mute" flashes two rows higher:
	or	a			; 0 = off, 1 = showing, 2 = hidden now
	jr	z,@mcode
	ld	a,(flash_t)
	bit	4,a
	ld	a,1
	jr	z,@mcode
	ld	a,2
@mcode:
	ld	hl,st_last+10
	cp	(hl)
	jp	z,@fshuf
	ld	(hl),a
	ld	d,75
	ld	e,ROW_FILE
	call	vat
	ld	a,BG+COL_BLACK
	call	vcol
	ld	a,COL_BYELLOW
	call	vcol
	ld	hl,txt_mute
	ld	a,(st_last+10)
	cp	1
	jr	z,@mshow
	ld	hl,txt_nomute
@mshow:
	call	vstr
	jp	st_done
@fshuf:
	ld	a,(shuffle)		; "shuffle", at the right of the third
					; channel line
	ld	hl,st_last+11
	cp	(hl)
	jr	z,@fsong
	ld	(hl),a
	ld	d,80-7			; (ends in column 79, two lines below
	ld	e,ROW_CHA+2		; an AY file's song number)
	call	vat
	ld	a,BG+COL_BLACK
	call	vcol
	ld	a,COL_BYELLOW
	call	vcol
	ld	hl,txt_shuffle
	ld	a,(st_last+11)
	or	a
	jr	nz,@shshow
	ld	hl,txt_noshuffle
@shshow:
	call	vstr
	jp	st_done
@fsong:
	; An AY file's song number and number of songs, at the right of
	; the first channel line (blank for anything else).
	call	ay_can
	jr	nz,@nosong
	ld	a,(ayf_cur)
	ld	hl,st_last+14
	cp	(hl)
	jr	nz,@song
	ld	a,(ayf_count)
	ld	hl,st_last+15
	cp	(hl)
	jr	nz,@song
	ld	a,(st_last+16)
	dec	a
	jr	z,@same			; (already shown)
@song:
	ld	a,(ayf_cur)
	ld	(st_last+14),a
	ld	a,(ayf_count)
	ld	(st_last+15),a
	ld	a,1
	ld	(st_last+16),a
	call	@songat
	ld	hl,lbl_song
	call	vlabel
	ld	a,(ayf_cur)
	inc	a
	call	vsongno
	call	st_slash
	ld	a,(ayf_count)
	call	vsongno
	jp	st_done
@nosong:
	ld	a,(st_last+16)		; take it away if it is showing
	or	a
	jr	z,@same
	xor	a
	ld	(st_last+16),a
	call	@songat
	ld	b,SONG_W
	call	vspaces
	jp	st_done
@songat:
	ld	d,SONG_COL
	ld	e,ROW_CHA
	call	vat
	ld	a,BG+COL_BLACK
	jp	vcol
@same:
	xor	a
	ret

; vsongno: queue an AY song number, A = 1 to 255 or 0 for 256, as three
; digits.
vsongno:
	or	a
	jp	nz,vdec3
	ld	a,'2'
	call	vdu_put
	ld	a,'5'
	call	vdu_put
	ld	a,'6'
	jp	vdu_put
SONG_W:		equ	13	; " song 001/007"
SONG_COL:	equ	80-SONG_W	; ends in column 79, as the state does

; st_at: go to column D of the status line, white on black.
st_at:
	ld	e,ROW_STATUS
	call	vat
	ld	a,BG+COL_BLACK
	call	vcol
	ld	a,COL_WHITE
	jp	vcol

; st_slash: a grey '/' between two white numbers.
st_slash:
	ld	a,COL_GREY
	call	vcol
	ld	a,'/'
	call	vdu_put
	ld	a,COL_WHITE
	jp	vcol

; st_done: common ending for a routine that drew something.
st_done:
	call	vdu_flush
	or	1
	ret

; vnote: queue a note name such as "C#4". In: A = note number 0 to 95.
vnote:
	ld	b,'1'
@oct:
	cp	12
	jr	c,@name
	sub	12
	inc	b
	jr	@oct
@name:
	add	a,a
	ld	de,0
	ld	e,a
	ld	hl,txt_notes
	add	hl,de
	ld	a,(hl)
	call	vdu_put
	inc	hl
	ld	a,(hl)
	call	vdu_put
	ld	a,b
	jp	vdu_put

; ch_ix: IX = state of channel number (dc_i). Channels 3 to 5 are the
; second chip's (D, E and F), which only a TurboSound tune has.
ch_ix:
	ld	a,(dc_i)
	ld	ix,pt3_chA
	or	a
	ret	z
	ld	ix,pt3_chB
	dec	a
	ret	z
	ld	ix,pt3_chC
	dec	a
	ret	z
	ld	ix,pt3ts_chA2
	dec	a
	ret	z
	ld	ix,pt3ts_chB2
	dec	a
	ret	z
	ld	ix,pt3ts_chC2
	ret

; ch_chip: for channel number (dc_i): HL = the sound layer's state for
; its chip (see ayvdp.asm), A = its number within the chip (0 to 2).
; Preserves BC, DE.
ch_chip:
	ld	hl,ay_ctx
	ld	a,(dc_i)
	cp	3
	ret	c
	ld	hl,ay_ctx2
	sub	3
	ret

; ch_get: A = the byte at offset DE in the state at HL. Preserves BC.
ch_get:
	add	hl,de
	ld	a,(hl)
	ret

; ch_level: A = meter level (0-15) of the channel at IX. A channel under
; envelope control shows the envelope level.
ch_level:
	ld	a,(ix+PT3C_AMP)
	bit	4,a
	jr	nz,@env
	and	0Fh
	ret
@env:
	push	de
	call	ch_chip
	push	hl
	ld	de,ay_env_buzz-ay_ctx
	call	ch_get
	pop	hl
	or	a
	ld	a,15
	jr	nz,@got
	ld	de,ay_env_level-ay_ctx
	call	ch_get
@got:
	pop	de
	ret

; ch_muted: is channel (dc_i) muted? Out: A = 80h and NZ if so, else
; A = 0 and Z. Corrupts C, DE, HL.
ch_muted:
	call	ch_chip
	push	af
	ld	de,ay_mute-ay_ctx
	call	ch_get
	ld	c,a
	pop	af
	ld	hl,ay_chbits
	ld	de,0
	ld	e,a
	add	hl,de
	ld	a,c
	and	(hl)
	ret	z
	ld	a,80h
	or	a
	ret

; vlabel_m: like vlabel, but if A is not zero the caption and the value
; after it are both greyed out.
vlabel_m:
	or	a
	jp	z,vlabel
	ld	a,COL_DGREY
	call	vcol
	jp	vstr

; chan_check: bring channel line A (0-5) up to date. As with the status
; line, each part of the line is compared with what is on screen and
; only one changed part is redrawn per call. The level meter is altered
; by just the cells that differ. Out: NZ if it drew something.
;
; ch_last holds 8 bytes per channel describing what is on screen:
; tone period (2), note (0FFh = none), sample, ornament, mixer flags,
; meter level, and 80h if drawn as muted.
chan_check:
	ld	(dc_i),a
	call	ch_ix
	ld	a,(dc_i)
	add	a,a
	add	a,a
	add	a,a
	ld	de,0
	ld	e,a
	ld	iy,ch_last
	add	iy,de
	call	ch_muted		; a change of muting changes every
	cp	(iy+7)			; colour, so draw the whole line
	jr	z,@fields
	ld	(iy+7),a
	ld	d,1
	call	ch_at
	ld	a,(dc_i)
	add	a,'A'
	call	vdu_put
	call	ch_dper
	call	ch_dnote
	call	ch_dsam
	call	ch_dorn
	call	ch_dmix
	ld	d,32			; an empty meter; the level follows
	call	ch_at
	ld	a,COL_DGREY
	call	vcol
	ld	b,15
@empty:
	ld	a,129
	call	vdu_put
	djnz	@empty
	ld	(iy+6),0
	jp	st_done
@fields:
	ld	a,(ix+PT3C_TON)
	cp	(iy+0)
	jr	nz,@per
	ld	a,(ix+PT3C_TON+1)
	cp	(iy+1)
	jr	z,@fnote
@per:
	call	ch_dper
	jp	st_done
@fnote:
	call	ch_notecode
	cp	(iy+2)
	jr	z,@fsam
	call	ch_dnote
	jp	st_done
@fsam:
	ld	a,(ix+PT3C_SAMNUM)
	cp	(iy+3)
	jr	z,@forn
	call	ch_dsam
	jp	st_done
@forn:
	ld	a,(ix+PT3C_ORNNUM)
	cp	(iy+4)
	jr	z,@fmix
	call	ch_dorn
	jp	st_done
@fmix:
	call	ch_mixbits
	cp	(iy+5)
	jr	z,@flevel
	call	ch_dmix
	jp	st_done
@flevel:
	call	ch_level
	cp	(iy+6)
	jr	z,@same
	call	ch_dbar
	jp	st_done
@same:
	xor	a
	ret

; ch_at: go to column D of the line of channel (dc_i) and select its
; text colour: white, or dark grey if it is drawn as muted.
ch_at:
	ld	a,(dc_i)
	add	a,ROW_CHA
	cp	ROW_NE			; D, E and F come after the first
	jr	c,@row			; chip's noise and envelope line
	inc	a
@row:
	ld	e,a
	call	vat
	ld	a,BG+COL_BLACK
	call	vcol
	ld	a,COL_WHITE
	bit	7,(iy+7)
	jr	z,@col
	ld	a,COL_DGREY
@col:
	jp	vcol

; ch_notecode: A = the note to show for the channel at IX, 0FFh = none.
ch_notecode:
	ld	a,(ix+PT3C_ENABLED)
	or	a
	ld	a,0FFh
	ret	z
	ld	a,(ix+PT3C_NOTE)
	ret

; ch_dper, ch_dnote, ch_dsam, ch_dorn, ch_dmix, ch_dbar: draw one part
; of a channel line and record what was drawn.
ch_dper:
	ld	a,(ix+PT3C_TON)
	ld	(iy+0),a
	ld	a,(ix+PT3C_TON+1)
	ld	(iy+1),a
	ld	d,11
	call	ch_at
	ld	a,(iy+1)
	call	vhex1
	ld	a,(iy+0)
	jp	vhex2
ch_dnote:
	call	ch_notecode
	ld	(iy+2),a
	ld	d,5
	call	ch_at
	ld	a,(iy+2)
	cp	0FFh
	jp	nz,vnote
	ld	hl,txt_dash
	jp	vstr
ch_dsam:
	ld	a,(ix+PT3C_SAMNUM)
	ld	(iy+3),a
	ld	d,17
	call	ch_at
	ld	a,(iy+3)
	jp	vdec2
ch_dorn:
	ld	a,(ix+PT3C_ORNNUM)
	ld	(iy+4),a
	ld	d,22
	call	ch_at
	ld	a,(iy+4)
	jp	vhex1

; ch_mixbits: A = bit 0 tone on, bit 1 noise on, bit 2 envelope in use,
; for channel (dc_i) whose state is at IX.
ch_mixbits:
	call	ch_chip
	ld	b,a
	ld	de,ay_regs-ay_ctx+7
	call	ch_get
	inc	b
@shift:
	dec	b
	jr	z,@shifted
	rrca
	jr	@shift
@shifted:
	cpl				; the AY's mixer bits are 0 for "on"
	ld	c,a
	and	1
	ld	b,a
	bit	3,c
	jr	z,@nonoise
	set	1,b
@nonoise:
	bit	4,(ix+PT3C_AMP)
	jr	z,@noenv
	set	2,b
@noenv:
	ld	a,b
	ret
ch_dmix:
	call	ch_mixbits
	ld	(iy+5),a
	ld	d,26
	call	ch_at
	ld	c,(iy+5)
	ld	a,'T'
	bit	0,c
	call	@flag
	ld	a,'N'
	bit	1,c
	call	@flag
	ld	a,'E'
	bit	2,c
@flag:
	jr	nz,@put
	ld	a,'-'
@put:
	jp	vdu_put
ch_dbar:
	call	ch_level
	ld	c,a			; C = level wanted
	ld	b,(iy+6)		; B = level shown
	ld	(iy+6),c
	cp	b
	jr	c,@less
	ld	a,b			; higher: light the cells in between
	add	a,32
	ld	d,a
	push	bc
	call	ch_at
	pop	bc
	ld	a,c
	sub	b
	ld	e,a			; E = cells to light
	ld	d,b			; D = the first one (0 to 14)
@fill:
	; As in OCP, the meter is in the theme's dark colour for its
	; first third, its medium for the second and its light for the
	; last (blue, bright blue and bright green in the OCP theme;
	; grey if muted).
	ld	a,COL_DGREY
	bit	7,(iy+7)
	jr	nz,@col
	ld	a,d
	cp	5
	ld	a,COL_DARK
	jr	c,@col
	ld	a,d
	cp	10
	ld	a,COL_MID
	jr	c,@col
	ld	a,COL_LIGHT
@col:
	call	vcol
	ld	a,128
	call	vdu_put
	inc	d
	dec	e
	jr	nz,@fill
	ret
@less:
	ld	a,c			; lower: put the cells in between out
	add	a,32
	ld	d,a
	push	bc
	call	ch_at
	pop	bc
	ld	a,COL_DGREY
	call	vcol
	ld	a,b
	sub	c
	ld	b,a
@dots:
	ld	a,129
	call	vdu_put
	djnz	@dots
	ret

; ne_check: redraw a noise and envelope line if it has changed.
; In: A = 0 for the first chip's line, 1 for the second's.
; ch_sig is filled with what the line should show: noise period,
; envelope period (2), envelope shape, whether the envelope is played
; as a waveform, and what is muted.
ne_check:
	ld	(ne_chip),a
	or	a
	ld	hl,ay_ctx
	ld	bc,ne_last
	jr	z,@chip
	ld	hl,ay_ctx2
	ld	bc,ne_last2
@chip:
	ld	(ne_ctx),hl
	ld	(ne_lastp),bc
	ld	ix,ch_sig
	ld	de,ay_regs-ay_ctx+6
	call	@get
	ld	de,ay_regs-ay_ctx+11
	call	@get
	ld	de,ay_regs-ay_ctx+12
	call	@get
	ld	de,ay_env_shape-ay_ctx
	call	@get
	ld	de,ay_env_buzz-ay_ctx
	call	@get
	ld	de,ay_mute-ay_ctx
	call	@get
	ld	hl,ch_sig
	ld	de,(ne_lastp)
	ld	b,6
	call	memcmp
	ret	z
	ld	ix,(ne_lastp)		; only the values that changed are
	ld	a,(ch_sig+5)		; redrawn, unless what is muted changed
	cp	(ix+5)			; (that changes the colours)
	jp	z,@part
	ld	hl,ch_sig
	ld	de,(ne_lastp)
	ld	bc,6
	ldir
	ld	d,0
	ld	e,ROW_NE
	ld	a,(ne_chip)
	or	a
	jr	z,@row
	ld	e,ROW_NE2
@row:
	call	vat
	ld	a,BG+COL_BLACK
	call	vcol
	ld	a,(ch_sig+5)
	and	8
	ld	hl,lbl_noise
	call	vlabel_m
	ld	a,(ch_sig)
	call	vhex2
	ld	a,(ch_sig+5)
	and	10h
	ld	hl,lbl_env
	call	vlabel_m
	ld	a,(ch_sig+2)
	call	vhex2
	ld	a,(ch_sig+1)
	call	vhex2
	ld	a,(ch_sig+5)
	and	10h
	ld	hl,lbl_shape
	call	vlabel_m
	ld	a,(ch_sig+3)
	call	vhex1
	ld	b,2
	call	vspaces
	ld	hl,txt_soft
	ld	a,(ch_sig+4)
	or	a
	jr	z,@s
	ld	hl,txt_buzz
@s:
	call	vstr
	call	vdu_flush
	or	1
	ret
@part:
	ld	a,(ch_sig)		; noise period
	cp	(ix+0)
	jr	z,@nenv
	ld	(ix+0),a
	ld	d,7
	ld	c,8
	call	@at
	ld	a,(ch_sig)
	call	vhex2
@nenv:
	ld	a,(ch_sig+1)		; envelope period
	cp	(ix+1)
	jr	nz,@env
	ld	a,(ch_sig+2)
	cp	(ix+2)
	jr	z,@nshape
@env:
	ld	a,(ch_sig+1)
	ld	(ix+1),a
	ld	a,(ch_sig+2)
	ld	(ix+2),a
	ld	d,21
	ld	c,10h
	call	@at
	ld	a,(ch_sig+2)
	call	vhex2
	ld	a,(ch_sig+1)
	call	vhex2
@nshape:
	ld	a,(ch_sig+3)		; envelope shape
	cp	(ix+3)
	jr	z,@nbuzz
	ld	(ix+3),a
	ld	d,33
	ld	c,10h
	call	@at
	ld	a,(ch_sig+3)
	call	vhex1
@nbuzz:
	ld	a,(ch_sig+4)		; envelope as a waveform or not
	cp	(ix+4)
	jr	z,@pdone
	ld	(ix+4),a
	ld	d,36
	ld	c,10h
	call	@at
	ld	hl,txt_soft
	ld	a,(ch_sig+4)
	or	a
	jr	z,@ps
	ld	hl,txt_buzz
@ps:
	call	vstr
@pdone:
	call	vdu_flush
	or	1
	ret
@at:					; go to column D of the line, in the
	ld	e,ROW_NE		; value's colour: grey if the mute
	ld	a,(ne_chip)		; bits in C are set, else white
	or	a
	jr	z,@atrow
	ld	e,ROW_NE2
@atrow:
	call	vat
	ld	a,BG+COL_BLACK
	call	vcol
	ld	a,(ch_sig+5)
	and	c
	ld	a,COL_WHITE
	jr	z,@atcol
	ld	a,COL_DGREY
@atcol:
	jp	vcol
@get:					; next byte of ch_sig = offset DE of
	ld	hl,(ne_ctx)		; the chip's state
	add	hl,de
	ld	a,(hl)
	ld	(ix+0),a
	inc	ix
	ret

; ---------------------------------------------------------------------
; The list panel. Each list has a count, a selected entry and the entry
; shown on the top line, 3 bytes each, in that order.
; ---------------------------------------------------------------------
L_COUNT:	equ	0
L_SEL:		equ	3
L_TOP:		equ	6

; The panel can also show the pattern view (panel = 2), which is not a
; list; see pattern.asm.

; lst_ix: IX = the list now showing.
lst_ix:
	ld	ix,pl_count
	ld	a,(panel)
	or	a
	ret	z
	ld	ix,br_count
	ret

; draw_pan_line: draw line A (0 = top) of the panel.
draw_pan_line:
	ld	(dpl_r),a
	ld	a,(panel)
	cp	3
	jp	z,draw_help_line
	call	lst_ix
	ld	a,(dpl_r)
	call	pan_row
	ld	e,a
	ld	d,0
	call	vat
	ld	hl,(ix+L_TOP)
	ld	de,0
	ld	a,(dpl_r)
	ld	e,a
	add	hl,de
	ld	(dpl_idx),hl
	ld	de,(ix+L_COUNT)
	or	a
	sbc	hl,de
	jr	c,@have
	ld	a,BG+COL_BLACK		; past the end: blank line
	call	vcol
	ld	b,80
	jp	vspaces
@have:
	ld	hl,(dpl_idx)
	ld	de,(ix+L_SEL)
	or	a
	sbc	hl,de
	ld	a,BG+COL_BLACK
	jr	nz,@bg
	ld	a,BG+COL_DARK		; the selected entry
@bg:
	call	vcol
	ld	a,(panel)
	or	a
	jr	nz,@file
	ld	hl,(dpl_idx)		; playlist entry
	ld	de,(pl_cur)
	or	a
	sbc	hl,de
	ld	c,' '
	ld	a,COL_GREY
	jr	nz,@pc
	ld	c,'>'			; the one being played
	ld	a,COL_LIGHT
@pc:
	ld	b,a			; an entry that would not play is red
	ld	hl,(dpl_idx)
	ld	de,pl_bad
	add	hl,de
	ld	a,(hl)
	or	a
	ld	a,b
	jr	z,@pcol
	ld	a,COL_BRED
@pcol:
	call	vcol
	ld	a,' '
	call	vdu_put
	ld	a,c
	call	vdu_put
	ld	a,' '
	call	vdu_put
	ld	a,(dpl_idx)
	inc	a
	call	vdec3
	ld	a,' '
	call	vdu_put
	call	vdu_put
	ld	hl,(dpl_idx)
	call	pl_get
	ld	b,72
	call	vtail
	jp	vtext
@file:
	ld	hl,(dpl_idx)		; file browser entry
	call	mul3
	ld	de,br_ptr
	add	hl,de
	ld	hl,(hl)
	ld	a,(hl)
	inc	hl
	push	hl
	or	a
	jr	nz,@f1
	ld	a,COL_BCYAN
	call	vcol
	ld	hl,txt_dir
	jr	@pfx
@f1:
	cp	2
	ld	a,COL_WHITE
	jr	nz,@f2
	ld	a,COL_BYELLOW
@f2:
	call	vcol
	ld	hl,txt_nodir
@pfx:
	call	vstr
	pop	hl
	ld	b,73
	jp	vtext

; draw_help_line: draw line (dpl_r) of the help. Each line of the text
; has the key in its first 16 columns, shown in yellow.
HELP_LINES:	equ	23

; help_key: keys while the help is showing. Up, Down, PgUp, PgDn, Home
; and End scroll it (on screens too short to show it all). In: A =
; virtual key. Out: NZ if it was one of those; Z for any other key,
; which closes the help.
help_key:
	ld	c,a
	ld	a,(pan_h)		; B = the last top line there can be
	ld	b,a
	ld	a,HELP_LINES
	sub	b
	jr	nc,@max
	xor	a
@max:
	ld	b,a
	ld	hl,help_top
	ld	a,c
	cp	VK_UP
	jr	z,@up
	cp	VK_DOWN
	jr	z,@down
	cp	VK_PAGEUP
	jr	z,@pgup
	cp	VK_PAGEDOWN
	jr	z,@pgdn
	cp	VK_HOME
	jr	z,@home
	cp	VK_END
	jr	z,@end
	xor	a
	ret
@up:
	ld	a,(hl)
	or	a
	jr	z,@set
	dec	a
	jr	@set
@down:
	ld	a,(hl)
	inc	a
	jr	@clamp
@pgup:
	ld	a,(pan_h)
	ld	c,a
	ld	a,(hl)
	sub	c
	jr	nc,@set
@home:
	xor	a
	jr	@set
@pgdn:
	ld	a,(pan_h)
	add	a,(hl)
	jr	@clamp
@end:
	ld	a,b
@clamp:
	cp	b
	jr	c,@set
	ld	a,b
@set:
	ld	(hl),a
	xor	a			; draw the panel again
	ld	(pan_line),a
	or	1
	ret
draw_help_line:
	ld	a,(dpl_r)
	call	pan_row
	ld	e,a
	ld	d,0
	call	vat
	ld	a,BG+COL_BLACK
	call	vcol
	ld	a,(help_top)		; the line of the help shown there
	ld	hl,dpl_r
	add	a,(hl)
	cp	HELP_LINES
	jr	nc,@blank
	ld	hl,txt_helptext		; step along to the line wanted
	ld	b,a
	inc	b
@find:
	dec	b
	jr	z,@found
@skip:
	ld	a,(hl)
	inc	hl
	or	a
	jr	nz,@skip
	jr	@find
@found:
	ld	a,COL_BYELLOW
	call	vcol
	ld	b,16
	call	vtext
	ld	a,COL_WHITE
	call	vcol
	ld	b,64
	jp	vtext
@blank:
	ld	b,80
	jp	vspaces
txt_helptext:
	db	"  Keys          (Up and Down scroll this list; other keys close it)",0
	db	"  TAB           switch between playlist, pattern view and files",0
	db	"  Up Down       move through the list (also PgUp, PgDn, Home, End)",0
	db	"  ENTER         play the entry, open the directory or load the playlist",0
	db	"  Backspace     files: go up one directory",0
	db	"  INS           files: add the file to the playlist; elsewhere: show files",0
	db	"  DEL, C        playlist: remove the entry, or clear the list",0
	db	"  [ ]           playlist: move the entry up or down",0
	db	"  S             save the playlist",0
	db	"  SPACE         pause and resume",0
	db	"  Left          back to the start of the song, or to the previous song",0
	db	"  Right         next song",0
	db	"  P N           AY files: previous or next song in the file, as Left and Right",0
	db	"  + -           volume",0
	db	"  M             mute everything",0
	db	"  R             shuffle (random order) on and off",0
	db	"  1 2 3         mute channel A, B or C (6 7 8: D, E or F)",0
	db	"  4 5           mute the noise or the envelope sound (9 0: second chip",138,"s)",0
	db	"  V             spectrum analyser on and off (screens of 40 rows or more)",0
	db	"  Z X           previous or next screen mode",0
	db	"  T             colour theme: OCP, Autumn, Iceberg, Emerald, Sand Dune, Amethyst",0
	db	"  H or ?        this help",0
	db	"  Q or Esc      quit",0

; lst_setsel: select entry HL of the list at IX, scrolling if needed.
lst_setsel:
	ld	de,(ix+L_SEL)
	ld	(old_sel),de
	ld	(ix+L_SEL),hl
	ld	de,(ix+L_TOP)
	or	a
	sbc	hl,de
	jr	c,@above
	ld	de,0
	ld	a,(pan_h)
	ld	e,a
	or	a
	sbc	hl,de
	jr	nc,@below
@lines:
	ld	hl,(old_sel)		; in view: redraw two lines
	call	@line
	ld	hl,(ix+L_SEL)
	call	@line
	jp	vdu_flush
@above:
	ld	hl,(ix+L_TOP)		; the list moves down
	ld	de,(ix+L_SEL)
	ld	(ix+L_TOP),de
	or	a
	sbc	hl,de			; HL = lines it moves
	ld	b,2			; (VDU 23,7 direction: down)
	jr	@moved
@below:
	ld	de,(ix+L_TOP)		; the list moves up
	add	hl,de
	inc	hl
	ld	(ix+L_TOP),hl
	or	a
	sbc	hl,de			; HL = lines it moves
	ld	b,3			; (up)
@moved:
	; By one line, with no drawing of the whole panel under way: scroll
	; the panel and draw just the lines that change. Otherwise the whole
	; panel is drawn again, a line at a time (ui_panel).
	ld	de,1
	or	a
	sbc	hl,de
	jr	nz,@all
	ld	a,(pan_line)
	ld	hl,pan_h
	cp	(hl)
	jr	c,@all
	ld	a,BG+COL_BLACK		; (the line left empty is black)
	call	vcol
	call	pat_viewport		; VDU 23,7,0,B,0: scroll the panel
	ld	a,23
	call	vdu_put
	ld	a,7
	call	vdu_put
	xor	a
	call	vdu_put
	ld	a,b
	call	vdu_put
	xor	a
	call	vdu_put
	ld	a,26			; and give the whole screen back
	call	vdu_put
	jr	@lines
@all:
	xor	a
	ld	(pan_line),a
	ret
@line:					; draw the line of entry HL, if shown
	ld	de,(ix+L_TOP)
	or	a
	sbc	hl,de
	ret	c
	ld	de,0
	ld	a,(pan_h)
	ld	e,a
	push	hl
	or	a
	sbc	hl,de
	pop	hl
	ret	nc
	ld	a,l
	call	draw_pan_line
	jp	lst_ix			; (draw_pan_line may change IX)

; Cursor keys for the list.
key_up:
	call	lst_ix
	ld	hl,(ix+L_SEL)
	ld	a,h
	or	l
	ret	z
	dec	hl
	jp	lst_setsel
key_down:
	call	lst_ix
	ld	hl,(ix+L_SEL)
	inc	hl
	ld	de,(ix+L_COUNT)
	or	a
	sbc	hl,de
	ret	nc
	add	hl,de
	jp	lst_setsel
key_pgup:
	call	lst_ix
	ld	hl,(ix+L_SEL)
	ld	de,0
	ld	a,(pan_h)
	ld	e,a
	or	a
	sbc	hl,de
	jp	nc,lst_setsel
	; fewer than a page from the top: fall through to the first entry
key_home:
	call	lst_ix
	ld	hl,0
	jp	lst_setsel
key_pgdn:
	call	lst_ix
	ld	hl,(ix+L_SEL)
	ld	de,0
	ld	a,(pan_h)
	ld	e,a
	add	hl,de
	ld	de,(ix+L_COUNT)
	or	a
	sbc	hl,de
	jr	nc,key_end
	add	hl,de
	jp	lst_setsel
key_end:
	call	lst_ix
	ld	hl,(ix+L_COUNT)
	ld	a,h
	or	l
	ret	z
	dec	hl
	jp	lst_setsel

; ui_paced: do one piece of pending drawing, but only when the VDP has
; finished the last piece.
;
; The eZ80 can send text far faster than a real VDP draws it. If the
; program simply kept sending, the VDP's input would fill up, MOS would
; make the program wait, and the music would slow down. So after each
; piece of drawing the VDP is asked to read back a screen pixel, which
; it only does once everything before it has been drawn; MOS sets a flag
; when the answer arrives, and nothing more is drawn until then. The
; music, which is sent every tick regardless, then never has more than
; one small piece of drawing in front of it. A time-out covers a VDP
; that does not answer.
ui_paced:
	ld	a,(ui_wait)
	or	a
	jr	z,@go
	ld	ix,(sysvars)
	bit	2,(ix+sysvar_vpd_pflags)
	jr	nz,@go
	ld	a,(ui_wait_t)
	or	a
	ret	nz			; still drawing
@go:
	xor	a
	ld	(ui_wait),a
	ld	(ui_drew),a
	call	ui_step
	ld	a,(ui_drew)
	or	a
	ret	z
	ld	ix,(sysvars)
	res	2,(ix+sysvar_vpd_pflags)
	ld	hl,@ask
	call	vseq
	call	vdu_flush
	ld	a,1
	ld	(ui_wait),a
	ld	a,50			; give up waiting after a second
	ld	(ui_wait_t),a
	ret
; VDU 23,0,&84,0;0; - read the colour of the pixel at 0,0.
@ask:	db	23,0,084h,0,0,0,0,0FFh

; ui_step: do one piece of pending drawing. A change of layout (the
; analyser shown or hidden as a song starts or stops) comes first, then
; anything else that changes the whole screen. After that the panel,
; the lines above it and the analyser take turns at going first (two
; turns in four for the panel), so that none of them can keep the
; others waiting.
ui_step:
	call	an_show			; the analyser comes or goes with a
	ld	hl,an_on		; song: lay the screen out again
	cp	(hl)
	jp	nz,ui_relayout
	ld	a,(dirty_frame)
	or	a
	jr	z,@1
	xor	a
	ld	(dirty_frame),a
	jp	draw_frame
@1:
	ld	a,(dirty_info)
	or	a
	jr	z,@2
	xor	a
	ld	(dirty_info),a
	jp	draw_info
@2:
	ld	a,(dirty_panbar)
	or	a
	jr	z,@2k
	xor	a
	ld	(dirty_panbar),a
	jp	draw_panbar
@2k:
	ld	a,(dirty_keys)
	or	a
	jr	z,@3
	xor	a
	ld	(dirty_keys),a
	jp	ui_helpbar
@3:
	ld	a,(ui_turn)
	inc	a
	and	3
	ld	(ui_turn),a
	jr	z,@lines1st
	cp	2
	jr	z,@an1st
	call	ui_panel		; turns 1 and 3
	ret	nz
	call	an_step
	ret	nz
	jr	ui_lines
@lines1st:
	call	ui_lines
	ret	nz
	call	ui_panel
	ret	nz
	jp	an_step
@an1st:
	call	an_step			; (without the analyser, the panel
	ret	nz			; goes first: three turns in four)
	call	ui_panel
	ret	nz
	; fall through

; ui_lines: update one of the status, channel or noise/envelope lines,
; starting with the one after the one updated last. There are five of
; them, or nine while a TurboSound tune is loaded. Out: NZ if it drew.
ui_lines:
	ld	a,(ui_ntasks)
	ld	b,a
@try:
	push	bc
	ld	hl,ui_ntasks
	ld	a,(ui_rot)
	inc	a
	cp	(hl)
	jr	c,@ok
	xor	a
@ok:
	ld	(ui_rot),a
	call	@task
	pop	bc
	ret	nz
	djnz	@try
	xor	a
	ret
@task:
	or	a
	jp	z,status_check
	cp	4			; 1-3 channels A-C, 4 their noise line
	jr	z,@ne1
	jr	c,@ch
	cp	8			; 5-7 channels D-F, 8 their noise line
	jr	z,@ne2
	dec	a
@ch:
	dec	a
	jp	chan_check
@ne1:
	xor	a
	jp	ne_check
@ne2:
	ld	a,1
	jp	ne_check

; ui_panel: draw the next pending line of the list, or let the pattern
; view update itself. Out: NZ if it drew.
ui_panel:
	ld	a,(panel)
	cp	2
	jp	z,pat_step
	ld	a,(pan_line)
	ld	hl,pan_h
	cp	(hl)
	jr	c,@draw
	xor	a
	ret
@draw:
	call	draw_pan_line
	call	vdu_flush
	ld	hl,pan_line
	inc	(hl)
	or	1
	ret

txt_title:	db	" agonAMP 1.1",0
txt_copy:	db	"(c) 2026 Nick J. Date",0
txt_chbar:	db	" ch  note  per   sam orn  mix   level",0
txt_help:	db	" TAB:panel ENT:play INS/DEL:add/remove S:save SPC:pause ",15,"/",14
		db	":skip H:help Q:quit",0
txt_playlist:	db	" PLAYLIST",0
txt_pattern:	db	" row  A          B          C            PATTERN",0
txt_pattern6:	db	" row  A          B          C          D          E"
		db	"          F        PATTERN",0
txt_rest:	db	"R--",0
txt_files:	db	" FILES  ",0
txt_dir:	db	" <DIR> ",0
txt_nodir:	db	"       ",0
txt_dash:	db	"---",0
txt_none:	db	0
txt_soft:	db	"    ",0
txt_buzz:	db	"buzz",0
txt_notes:	db	"C-C#D-D#E-F-F#G-G#A-A#B-"
txt_states:	db	"   stopped   playing     pauseload error"
		db	"  bad file"
txt_shuffle:	db	"shuffle",0
txt_noshuffle:	db	"       ",0
txt_mute:	db	"mute",0
txt_nomute:	db	"    ",0
txt_helpbar:	db	" HELP",0
txt_anroom:	db	"The spectrum analyser needs a screen of 40 rows or more",0
lbl_file:	db	" file ",0
lbl_title:	db	" title ",0
lbl_by:		db	"  by ",0
lbl_pos:	db	" pos ",0
lbl_pat:	db	" pat ",0
lbl_row:	db	" row ",0
lbl_speed:	db	" speed ",0
lbl_time:	db	" time ",0
lbl_track:	db	" track ",0
lbl_song:	db	" song ",0
lbl_noise:	db	" noise ",0
lbl_env:	db	"   envelope ",0
lbl_shape:	db	"  shape ",0