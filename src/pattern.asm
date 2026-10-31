; pattern.asm - the pattern view: the notes of the PT3 pattern being
; played, scrolling past a marked current row.
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
; A PT3 pattern is three packed byte streams, one per channel, which
; cannot be read backwards or from the middle. So the pattern being
; played, and the one that will follow it, are each unpacked into a
; table of 5 byte cells (note, sample, envelope, ornament, volume;
; 0FFh = not given), one per channel and row. The streams are only read
; here, never changed, and the replayer's own state is not touched.
;
; The view keeps the current row in the middle of the panel. A real VDP
; draws text slowly, so the view is built to send it as little as
; possible:
;
; * When the music moves on a row, the VDP scrolls the panel up one line
;   (a full-width scroll, which it does by moving pointers, not pixels).
;   Then only the marker on the current row and the one new line at the
;   bottom are drawn.
; * Only what a row contains is drawn. Empty cells are left blank
;   instead of being filled with dashes and dots.
; * The rows of the following pattern are shown below the end of the
;   current one, so the display runs on through a pattern change with
;   nothing to clear or redraw.
;
; The panel is cleared and redrawn only after a jump (a different song,
; or the view having fallen a long way behind). Then the current row and
; the rows below it are drawn first, and the rows above are filled in
; whenever there is nothing more pressing to draw.
;
; Shown per channel: note, then sample (1-9, A-V), envelope type,
; ornament and volume. Effect commands, the noise period and the
; envelope period are not shown.

PC_NOTE:	equ	0	; cell: note 0-95, 0FEh = rest, 0FFh = none
PC_SAM:		equ	1	; sample number
PC_ENV:		equ	2	; envelope type, 0Fh = envelope off
PC_ORN:		equ	3	; ornament number
PC_VOL:		equ	4	; volume
PC_SIZE:	equ	5

pat_snapgen:	ds	1	; pt3_patgen when pat_skip was noted
pat_skip:	ds	3	; row spacing of A, B, C at pattern start
pat_skip2:	ds	3	; and of D, E, F (TurboSound)
pv_six:		ds	1	; non-zero if six channels are being shown
pv_gen:		ds	1	; pat_snapgen of the pattern on screen
pv_valid:	ds	1	; non-zero if the tables hold patterns
pv_ahead:	ds	1	; non-zero if the following one is not yet
pv_blank:	ds	1	; non-zero if the panel has been blanked
pv_cur:		ds	3	; table of the current pattern
pv_nxt:		ds	3	; table of the following pattern
pv_rows:	ds	1	; rows in the current pattern
pv_nrows:	ds	1	; rows in the following pattern
pv_pos:		ds	1	; song position of the current pattern
pv_npos:	ds	1	; song position expected next
pv_row:		ds	1	; row shown as current
pv_prev:	ds	1	; row that was current before the last step
pv_line:	ds	1	; next panel line to draw; pan_h = all drawn
pv_hist:	ds	1	; rows on screen above the current one
pl_row:		ds	1	; row on the line being drawn
pl_tab:		ds	3	; table that row is in
pl_parcol:	ds	1	; colour for the values on that line
pd_pos:		ds	1	; decode: song position
pd_px3:		ds	1	; decode: pattern number * 3
pd_tab:		ds	3	; decode: table being filled
pd_rows:	ds	1	; decode: rows found
pd_iskip:	ds	3	; decode: row spacing at the start
pd_oskip:	ds	3	; decode: row spacing at the end
pd_iskip2:	ds	3	; the same for the second chip's channels
pd_oskip2:	ds	3
pd_base:	ds	3	; decode: address of the module
pd_mirror:	ds	1	; decode: its pattern count if mirrored
pd_ch:		ds	1	; decode: channel number
pd_row:		ds	1	; decode: row number
pd_skip:	ds	1	; decode: rows from one entry to the next
pd_fx:		ds	1	; decode: effect parameter bytes pending
pd_bc:		ds	1	; decode: commands left in this row
pd_p:		ds	3	; decode: position in the stream
pd_ptrs:	ds	3	; decode: next stream pointer in the module
pd_cell:	ds	3	; decode: cell being filled

; pat_decode: unpack one pattern: three channels, or all six of a
; TurboSound tune while its two chips are in step (pv_six).
; In:  (pd_pos) = its position in the song, (pd_tab) = table to fill,
;      pd_iskip = row spacing of channels A, B, C when it starts (and
;      pd_iskip2 that of D, E, F).
; Out: (pd_rows) = number of rows, pd_oskip = row spacing when it ends
;      (and pd_oskip2).
pat_decode:
	ld	a,(fmt)			; (the other formats: patother.asm)
	or	a
	jp	nz,po_decode
	ld	hl,(pt3_base)
	ld	(pd_base),hl
	xor	a
	ld	(pd_mirror),a
	call	pat_dec3
	ld	a,(pv_six)
	or	a
	ret	z
	; The second chip's three channels go in the second half of the
	; table. They are taken from the same position of its module (or,
	; in a one-module tune, from the mirrored pattern of the same one).
	ld	a,(pd_rows)		; the first chip's results are kept
	push	af
	ld	hl,(pd_tab)
	push	hl
	ld	de,3*PAT_CH
	add	hl,de
	ld	(pd_tab),hl
	ld	hl,(pd_iskip)
	push	hl
	ld	hl,(pd_oskip)
	push	hl
	ld	hl,(pd_iskip2)
	ld	(pd_iskip),hl
	ld	hl,(pt3ts_base2)
	ld	(pd_base),hl
	ld	a,(pt3ts_count)
	ld	(pd_mirror),a
	ld	ix,(pt3ts_base2)	; no such position in its module:
	ld	a,(pd_pos)		; leave its cells empty
	cp	(ix+PT3_NUMPOS)
	jr	c,@decode
	ld	hl,(pd_tab)
	push	hl
	pop	de
	inc	de
	ld	bc,3*PAT_CH-1
	ld	(hl),0FFh
	ldir
	jr	@done
@decode:
	call	pat_dec3
	ld	hl,(pd_oskip)
	ld	(pd_oskip2),hl
@done:
	pop	hl
	ld	(pd_oskip),hl
	pop	hl
	ld	(pd_iskip),hl
	pop	hl
	ld	(pd_tab),hl
	pop	af
	ld	(pd_rows),a
	ret

; pat_dec3: unpack the three channels of one pattern of the module at
; (pd_base). If (pd_mirror) is not zero the module is being played with
; its patterns mirrored and that is the number of patterns.
pat_dec3:
	ld	hl,(pd_base)		; which pattern is at that position?
	ld	de,PT3_POSLIST
	add	hl,de
	ld	de,0
	ld	a,(pd_pos)
	ld	e,a
	add	hl,de
	ld	c,(hl)			; (pattern number * 3)
	ld	a,(pd_mirror)
	or	a
	jr	z,@plain
	ld	b,a			; mirrored: pattern (count - 1 - n)
	add	a,a
	add	a,b
	sub	3
	sub	c
	ld	c,a
@plain:
	ld	a,c
	ld	(pd_px3),a
	ld	hl,(pd_base)		; find its three stream pointers
	ld	de,PT3_PATPTR
	add	hl,de
	call	lib_getw
	ld	de,0
	ld	a,(pd_px3)
	ld	e,a
	add	hl,de
	add	hl,de
	ld	de,(pd_base)
	add	hl,de
	ld	(pd_ptrs),hl
	ld	hl,(pd_tab)		; every cell starts as "nothing"
	push	hl
	pop	de
	inc	de
	ld	bc,3*PAT_CH-1
	ld	(hl),0FFh
	ldir
	ld	a,255			; until channel A's end is found
	ld	(pd_rows),a
	xor	a
	ld	(pd_ch),a
@chan:
	ld	hl,(pd_ptrs)
	push	hl
	call	lib_getw
	ld	de,(pd_base)
	add	hl,de
	ld	(pd_p),hl
	pop	hl
	inc	hl
	inc	hl
	ld	(pd_ptrs),hl
	ld	a,(pd_ch)		; row spacing in force at the start
	ld	de,0
	ld	e,a
	ld	hl,pd_iskip
	add	hl,de
	ld	a,(hl)
	ld	(pd_skip),a
	ld	hl,(pd_tab)		; this channel's part of the table
	ld	a,(pd_ch)
	or	a
	jr	z,@base
	ld	de,PAT_CH
	add	hl,de
	dec	a
	jr	z,@base
	add	hl,de
@base:
	ld	(pd_cell),hl
	xor	a
	ld	(pd_row),a
@row:
	ld	a,(pd_row)
	ld	hl,pd_rows
	cp	(hl)
	jp	nc,@chdone
	ld	hl,(pd_p)
	ld	a,(hl)
	or	a
	jr	nz,@cmds
	ld	a,(pd_ch)		; a zero where a row should start ends
	or	a			; the pattern; channel A's sets the
	jp	nz,@chdone		; length
	ld	a,(pd_row)
	ld	(pd_rows),a
	jp	@chdone
@cmds:
	xor	a
	ld	(pd_fx),a		; effect parameter bytes to step over
	ld	(pd_bc),a
	ld	ix,(pd_cell)
@byte:
	ld	a,(pd_bc)		; more than 255 commands in one row:
	dec	a			; damaged data, so the channel's rows
	ld	(pd_bc),a		; end here
	jp	z,@chdone
	ld	a,(hl)
	cp	0F0h
	jp	nc,@ornsam
	cp	0D1h
	jp	nc,@sam
	cp	0D0h
	jp	z,@endrow
	cp	0C1h
	jp	nc,@vol
	cp	0C0h
	jp	z,@rest
	cp	0B2h
	jp	nc,@env
	cp	0B1h
	jp	z,@skip
	cp	0B0h
	jp	z,@envoff
	cp	050h
	jp	nc,@note
	cp	040h
	jp	nc,@orn
	cp	020h
	jr	nc,@next		; noise period: not shown
	cp	010h
	jp	nc,@envsam
	push	hl			; an effect: remember how many
	ld	hl,pd_fxlen		; parameter bytes follow the row
	ld	de,0
	ld	e,a
	add	hl,de
	ld	a,(pd_fx)
	add	a,(hl)
	ld	(pd_fx),a
	pop	hl
@next:
	inc	hl
	jr	@byte
@ornsam:
	sub	0F0h
	ld	(ix+PC_ORN),a
	inc	hl
	ld	a,(hl)
	srl	a
	ld	(ix+PC_SAM),a
	ld	(ix+PC_ENV),0Fh
	jr	@next
@sam:
	sub	0D0h
	ld	(ix+PC_SAM),a
	jr	@next
@vol:
	sub	0C0h
	ld	(ix+PC_VOL),a
	jr	@next
@rest:
	ld	(ix+PC_NOTE),0FEh
	jr	@endrow
@env:
	sub	0B1h
	ld	(ix+PC_ENV),a
	inc	hl
	inc	hl
	jr	@next
@skip:
	inc	hl
	ld	a,(hl)
	ld	(pd_skip),a
	jr	@next
@envoff:
	ld	(ix+PC_ENV),0Fh
	jr	@next
@note:
	sub	050h
	ld	(ix+PC_NOTE),a
	jr	@endrow
@orn:
	sub	040h
	ld	(ix+PC_ORN),a
	jr	@next
@envsam:
	cp	010h
	jr	nz,@es1
	ld	(ix+PC_ENV),0Fh
	jr	@es2
@es1:
	sub	010h
	ld	(ix+PC_ENV),a
	inc	hl
	inc	hl
@es2:
	inc	hl
	ld	a,(hl)
	srl	a
	ld	(ix+PC_SAM),a
	jr	@next
@endrow:
	inc	hl			; past the byte that ended the row
	ld	de,0
	ld	a,(pd_fx)
	ld	e,a
	add	hl,de			; and past the effect parameters
	ld	(pd_p),hl
	ld	a,(pd_skip)		; the next row with data is this many
	or	a			; rows further on
	jr	z,@chdone
	ld	b,a
	ld	a,(pd_row)
	add	a,b
	jr	c,@chdone
	ld	(pd_row),a
	ld	hl,(pd_cell)
	ld	de,PC_SIZE
@adv:
	add	hl,de
	djnz	@adv
	ld	(pd_cell),hl
	jp	@row
@chdone:
	ld	a,(pd_ch)		; remember the spacing it ended with
	ld	de,0
	ld	e,a
	ld	hl,pd_oskip
	add	hl,de
	ld	a,(pd_skip)
	ld	(hl),a
	ld	hl,pd_ch
	inc	(hl)
	ld	a,(hl)
	cp	3
	jp	nz,@chan
	ret
; Parameter bytes that follow a row for each effect command 00h-0Fh.
pd_fxlen:	db	0,3,5,1,1,2,0,0,3,1,0,0,0,0,0,0

; pat_ahead: unpack the pattern that will follow the current one.
pat_ahead:
	ld	hl,(pd_oskip)		; it starts with the spacing the
	ld	(pd_iskip),hl		; current one ends with
	ld	hl,(pd_oskip2)
	ld	(pd_iskip2),hl
	ld	a,(pt3_numpos)
	ld	b,a
	ld	a,(pv_pos)
	inc	a
	cp	b
	jr	c,@pos
	ld	a,(pt3_looppos)		; after the last position: the loop
@pos:
	ld	(pv_npos),a
	ld	(pd_pos),a
	ld	hl,(pv_nxt)
	ld	(pd_tab),hl
	call	pat_decode
	ld	a,(pd_rows)
	ld	(pv_nrows),a
	ld	a,(fmt)			; the other formats find out its
	or	a			; position as they read it
	ret	z
	ld	a,(pd_pos)
	ld	(pv_npos),a
	ret

; pat_insync: Z if a TurboSound tune's second chip is at the same
; position and row as the first.
pat_insync:
	ld	a,(pt3ts_pos2)
	ld	hl,pt3_pos
	cp	(hl)
	ret	nz
	ld	a,(pt3ts_row2)
	ld	hl,pt3_row
	cp	(hl)
	ret

; pat_rebuild: start the view afresh from where the music is now.
pat_rebuild:
	ld	a,(pat_snapgen)
	ld	(pv_gen),a
	ld	a,(pt3_pos)
	ld	(pv_pos),a
	ld	(pd_pos),a
	ld	hl,PAT_TAB
	ld	(pv_cur),hl
	ld	(pd_tab),hl
	ld	hl,(pat_skip)
	ld	(pd_iskip),hl
	ld	hl,(pat_skip2)
	ld	(pd_iskip2),hl
	ld	a,(fmt)			; the other formats start from the
	or	a			; state their replayer had when the
	jr	z,@pt3			; pattern started
	call	po_have
	ld	hl,po_start
	ld	de,po_end
	call	po_copy
@pt3:
	; Six channels are shown for a TurboSound tune, as long as its
	; second chip is at the same place in the song as the first. (In
	; a tune of two separate modules nothing obliges it to be.)
	ld	a,(ts_on)
	or	a
	jr	z,@three
	call	pat_insync
	ld	a,0
	jr	nz,@three
	inc	a
@three:
	ld	(pv_six),a
	call	pat_decode
	ld	a,(pd_rows)
	ld	(pv_rows),a
	ld	hl,PAT_TAB2		; the following pattern is unpacked
	ld	(pv_nxt),hl		; on the next call (pat_step), to
	xor	a			; spread the work; until then it has
	ld	(pv_nrows),a		; no rows
	dec	a
	ld	(pv_npos),a
	ld	a,1
	ld	(pv_ahead),a
	ld	a,(pt3_row)
	ld	(pv_row),a
	ld	a,1
	ld	(pv_valid),a
	xor	a
	ld	(pv_hist),a
	ld	(pv_blank),a
	ld	a,(pan_h)		; drawing starts at the current row;
	srl	a			; the rows above it come later
	ld	(pv_line),a
	; fall through to clear the panel

; pat_clear: clear the panel. Out: NZ, as it drew.
pat_clear:
	ld	a,1
	ld	(ui_drew),a
	ld	a,BG+COL_BLACK
	call	vcol
	call	pat_viewport
	ld	a,12			; clear the text viewport
	call	vdu_put
	ld	a,26			; and give the whole screen back
	call	vdu_put
	jp	st_done

; pat_viewport: make the panel the text viewport (VDU 28).
pat_viewport:
	ld	a,28
	call	vdu_put
	xor	a
	call	vdu_put
	ld	a,(scr_rows)
	sub	2
	call	vdu_put
	ld	a,79
	call	vdu_put
	xor	a
	call	pan_row
	jp	vdu_put

; pat_at: go to column D of panel line (dpl_r), black background.
pat_at:
	ld	a,(dpl_r)
	call	pan_row
	ld	e,a
	call	vat
	ld	a,BG+COL_BLACK
	jp	vcol

; pat_mark: mark panel line (dpl_r) as the current row: an arrow, and
; the row number in white on the dark colour.
pat_mark:
	ld	d,0
	call	pat_at
	ld	a,COL_WHITE
	call	vcol
	ld	a,'>'
	call	vdu_put
	ld	a,BG+COL_DARK
	call	vcol
	ld	a,(pv_row)
	jp	vdec3

; pat_unmark: take the marking off panel line (dpl_r). In: A = the row
; number shown on it.
pat_unmark:
	push	af
	ld	d,0
	call	pat_at
	ld	a,' '
	call	vdu_put
	ld	a,COL_CYAN
	call	vcol
	pop	af
	jp	vdec3

; pat_step: keep the pattern view up to date; called from ui_step while
; the view is showing. Out: NZ if it drew something.
pat_step:
	call	pat_kind		; only tracker formats have them
	jr	z,@nopat
	ld	a,(state)
	cp	ST_PLAYING
	jr	z,@have
	cp	ST_PAUSED
	jr	z,@have
@nopat:
	xor	a
	ld	(pv_valid),a
	ld	a,(pv_blank)		; blank the panel, once
	or	a
	jr	z,@blank
	xor	a
	ret
@blank:
	ld	a,1
	ld	(pv_blank),a
	jp	pat_clear
@have:
	ld	a,(pv_valid)
	or	a
	jp	z,pat_rebuild
	ld	a,(pv_ahead)		; the following pattern still to be
	or	a			; unpacked (pat_rebuild)?
	jr	z,@ahead
	xor	a
	ld	(pv_ahead),a
	call	pat_ahead
	or	1
	ret
@ahead:
	ld	a,(pat_snapgen)		; has a new pattern started?
	ld	hl,pv_gen
	cp	(hl)
	jp	z,@valid
	; Yes. If it is the one already unpacked as "next" and the view
	; had reached the last row of the old one, simply carry on into
	; it. Otherwise start afresh.
	ld	(hl),a
	ld	a,(pt3_pos)
	ld	hl,pv_npos
	cp	(hl)
	jp	nz,pat_rebuild
	ld	a,(pv_six)		; six columns: the second chip must
	or	a			; still be in step with the first
	jr	z,@insync
	call	pat_insync
	jp	nz,pat_rebuild
@insync:
	ld	a,(pv_line)
	ld	hl,pan_h
	cp	(hl)
	jp	c,pat_rebuild
	ld	a,(pv_row)
	inc	a
	ld	hl,pv_rows
	cp	(hl)
	jp	nz,pat_rebuild
	ld	a,(pan_h)		; a following pattern too short to
	srl	a			; reach the bottom of the panel would
	ld	b,a			; leave lines blank below it: start
	ld	a,(pan_h)		; afresh then
	sub	b
	ld	b,a
	ld	a,(pv_nrows)
	cp	b
	jp	c,pat_rebuild
	ld	a,(pv_row)
	ld	(pv_prev),a
	ld	hl,(pv_cur)		; "next" becomes "current"
	ld	de,(pv_nxt)
	ld	(pv_cur),de
	ld	(pv_nxt),hl
	ld	a,(pv_nrows)
	ld	(pv_rows),a
	ld	a,(pv_npos)
	ld	(pv_pos),a
	call	pat_ahead
	xor	a
	ld	(pv_row),a
	jr	@scroll
@valid:
	ld	a,(pv_line)		; still drawing the whole panel?
	ld	hl,pan_h
	cp	(hl)
	jp	c,@page
	ld	a,(pt3_row)
	ld	hl,pv_row
	sub	(hl)
	jr	nz,@moved
	; Nothing has moved. Use the time to draw one of the rows above
	; the current one that are not on screen yet (after a jump only
	; the current row and those below it are drawn at first).
	ld	a,(pan_h)
	srl	a
	ld	hl,pv_hist
	sub	(hl)
	jr	nz,@history
	xor	a
	ret
@history:
	inc	(hl)
	dec	a
	call	draw_pat_line
	jp	st_done
@moved:
	cp	33			; a long way behind, or gone backwards:
	jp	nc,pat_rebuild		; start afresh
	ld	a,(hl)			; otherwise move on one row
	ld	(pv_prev),a
	inc	(hl)
@scroll:
	ld	a,(pan_h)		; one more row of history is on screen
	srl	a
	ld	hl,pv_hist
	cp	(hl)
	jr	z,@full
	inc	(hl)
@full:
	ld	a,1
	ld	(ui_drew),a
	ld	a,BG+COL_BLACK
	call	vcol
	call	pat_viewport
	ld	hl,@seq
	call	vseq
	ld	a,(pan_h)		; the row that was current
	srl	a
	dec	a
	ld	(dpl_r),a
	ld	a,(pv_prev)
	call	pat_unmark
	ld	a,(pan_h)		; the row that is current now
	srl	a
	ld	(dpl_r),a
	call	pat_mark
	ld	a,(pan_h)		; the new row at the bottom
	dec	a
	call	draw_pat_line
	jp	st_done
@page:
	ld	b,4			; a few lines of the panel at a time
@line:
	push	bc
	ld	a,(pv_line)
	call	draw_pat_line
	ld	a,(pan_h)
	srl	a
	ld	hl,pv_line
	cp	(hl)
	jr	nz,@notmid
	ld	(dpl_r),a
	call	pat_mark
@notmid:
	ld	hl,pv_line
	inc	(hl)
	ld	a,(hl)
	ld	hl,pan_h
	cp	(hl)
	pop	bc
	jr	nc,@pagedone
	djnz	@line
@pagedone:
	jp	st_done
; Scroll the text viewport up one line, then reset the viewports.
@seq:	db	23,7,0,3,0,26,0FFh

; draw_pat_line: draw panel line A of the pattern view, on a line that
; is already blank. The current row belongs on the middle line; rows
; past the end of the pattern come from the following pattern.
draw_pat_line:
	ld	(dpl_r),a
	ld	hl,0			; which row belongs on this line?
	ld	a,(pv_row)
	ld	l,a
	ld	de,0
	ld	a,(dpl_r)
	ld	e,a
	add	hl,de
	ld	a,(pan_h)
	srl	a
	ld	e,a
	or	a
	sbc	hl,de
	ret	m			; before the pattern's first row
	ld	de,0
	ld	a,(pv_rows)
	ld	e,a
	or	a
	sbc	hl,de
	jr	nc,@following
	add	hl,de
	ld	de,(pv_cur)
	jr	@got
@following:
	ld	de,0
	ld	a,(pv_nrows)
	ld	e,a
	or	a
	sbc	hl,de
	ret	nc			; beyond the following pattern too
	add	hl,de
	ld	de,(pv_nxt)
@got:
	ld	a,l
	ld	(pl_row),a
	ld	(pl_tab),de
	ld	d,1
	call	pat_at
	ld	a,COL_CYAN
	call	vcol
	ld	a,(pl_row)
	call	vdec3
	xor	a
	ld	(dc_i),a
@chan:
	ld	hl,0			; find the cell
	ld	a,(pl_row)
	ld	l,a
	push	hl
	pop	de
	add	hl,hl
	add	hl,hl
	add	hl,de
	ld	de,(pl_tab)
	add	hl,de
	ld	a,(dc_i)
	or	a
	jr	z,@cell
	ld	b,a
	ld	de,PAT_CH
@chtab:
	add	hl,de
	djnz	@chtab
@cell:
	push	hl
	pop	ix
	ld	a,(ix+PC_NOTE)		; nothing in it: draw nothing
	and	(ix+PC_SAM)
	and	(ix+PC_ENV)
	and	(ix+PC_ORN)
	and	(ix+PC_VOL)
	inc	a
	jp	z,@nextch
	ld	a,(dc_i)		; column 6, 17, 28 (39, 50, 61)
	ld	b,a
	add	a,a
	add	a,a
	add	a,b
	add	a,a
	add	a,b
	add	a,6
	ld	d,a
	call	pat_at
	call	ch_muted		; muted channels are greyed out
	ld	b,COL_WHITE
	ld	c,COL_GREY
	jr	z,@cols
	ld	b,COL_DGREY
	ld	c,b
@cols:
	ld	a,c
	ld	(pl_parcol),a
	ld	a,b
	call	vcol
	ld	a,(ix+PC_NOTE)
	cp	0FFh
	jr	z,@none
	cp	0FEh
	jr	z,@rest
	call	vnote
	jr	@params
@none:
	ld	hl,txt_dash
	call	vstr
	jr	@params
@rest:
	ld	hl,txt_rest
	call	vstr
@params:
	ld	a,(ix+PC_SAM)		; no values: stop after the note
	and	(ix+PC_ENV)
	and	(ix+PC_ORN)
	and	(ix+PC_VOL)
	inc	a
	jr	z,@nextch
	ld	a,(pl_parcol)
	call	vcol
	ld	a,' '
	call	vdu_put
	ld	a,(ix+PC_SAM)
	call	pat_digit
	ld	a,(ix+PC_ENV)
	call	pat_digit
	ld	a,(ix+PC_ORN)
	call	pat_digit
	ld	a,(ix+PC_VOL)
	call	pat_digit
@nextch:
	ld	hl,dc_i
	inc	(hl)
	ld	a,(pv_six)		; three channels, or six
	or	a
	ld	a,3
	jr	z,@count
	ld	a,6
@count:
	cp	(hl)
	jp	nz,@chan
	ret

; pat_digit: show a cell value as one character: '.' if not given, else
; 0-9 then A-V (so that sample numbers up to 31 fit).
pat_digit:
	cp	0FFh
	jr	nz,@given
	ld	a,'.'
	jp	vdu_put
@given:
	cp	10
	jr	nc,@letter
	add	a,'0'
	jp	vdu_put
@letter:
	add	a,'A'-10
	jp	vdu_put

; pat_kind: has the current format got patterns to show? Out: NZ if so.
pat_kind:
	ld	a,(fmt)
	or	a
	jr	z,@yes
	jp	po_have
@yes:
	or	1
	ret