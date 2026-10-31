; patother.asm - the pattern view for the tracker formats other than
; PT3: Sound Tracker, Pro Tracker 1 and 2, ASC Sound Master, Sound
; Tracker Pro, SQ-Tracker and Pro Sound Creator.
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
; These formats' patterns are not unpacked by reading them here, as PT3
; patterns are (pattern.asm). Each format's own replayer reads them
; instead: its state is put aside, set to what it was when a pattern
; started, and its once-a-row routine is run row after row until the
; next pattern starts, noting after each row what it did to each
; channel. Then its state is put back. So the view always reads a
; pattern exactly as the music does, with no second copy of each
; format's rules here, and costs a small table per format.
;
; What a row did is seen by setting some of a channel's bytes to a value
; no row would leave in them (55h, or 0FFh) before the row is read, and
; looking at them afterwards:
;   * a note: the byte the format sets when a note starts (the sample
;     position, say) has changed, or so has the note;
;   * sound off: the byte that says whether the channel sounds is 0 (or,
;     for Sound Tracker, 0FFh);
;   * sample, ornament and (where the format allows) volume: the byte
;     that holds its number for display has changed;
;   * envelope: the channel's envelope switch has changed (shown as F
;     when switched off), or a shape was written to register 13 while
;     it is on (shown as the shape).
; None of the bytes changed in this way is ever read while a row is
; being read, so they do not alter how the pattern is read.
;
; Formats that do not have it show no volume. Notes are shown as the
; channel lines show them (Sound Tracker's with its position's
; transposition added).

; A format's table (pf_tab below), one per format from FMT_STC.
PF_TICK:	equ	0	; 3: the replayer's once-a-row routine
PF_SPAN:	equ	3	; 3: first byte of its state
PF_LEN:		equ	6	; 3: bytes of state
PF_POS:		equ	9	; 3: its position
PF_ROW:		equ	12	; 3: its row number
PF_CHA:		equ	15	; 3: channel A's state (B and C follow)
PF_TRANSP:	equ	18	; 3: transposition to add to notes, or 0
PF_CHSZ:	equ	21	; 1: bytes of one channel's state
PF_NOTE:	equ	22	; 1: offset of the note
PF_SAM:		equ	23	; 1: of the sample number
PF_ORN:		equ	24	; 1: of the ornament number
PF_VOL:		equ	25	; 1: of the volume (0FFh: none shown)
PF_ENV:		equ	26	; 1: of the envelope switch
PF_NIND:	equ	27	; 1: of the byte set when a note starts
PF_RIND:	equ	28	; 1: of the byte that says it sounds
PF_RVAL:	equ	29	; 1: and its value for "off"
PF_CNT:		equ	30	; 3: its frames-until-the-next-row counter
PF_CTR:		equ	33	; 1: offset of a channel's own transposition
				; (added to its notes), or 0FFh
PF_SIZE:	equ	34
PF_MAXSPAN:	equ	200		; the most state any format has (198)

po_lrow:	ds	1	; row number after the last frame
po_lpos:	ds	1	; position after the last frame
po_cell:	ds	3	; cell being filled
po_was:		ds	6	; note and envelope switch of each channel
po_regs:	ds	16	; the AY registers, put aside
po_frame:	ds	PF_MAXSPAN	; the state before this frame
po_start:	ds	PF_MAXSPAN	; the state the pattern started from
po_end:		ds	PF_MAXSPAN	; the state a decode starts or ends at
po_tmp:		ds	PF_MAXSPAN	; the state before the row being read
po_live:	ds	PF_MAXSPAN	; the replayer's own state, put aside

pf_tab:
	dl	stc_rowtick,stc_base,stc_loops+1-stc_base,stc_pos,stc_row
	dl	stc_chA,stc_transp
	db	SC_SIZE,SC_NOTE,SC_SAMNUM,SC_ORNNUM,0FFh,SC_ENV,SC_POS
	db	SC_TIK,0FFh
	dl	stc_delay_cnt
	db	0FFh
	dl	pt2_rowtick,pt2_base,pt2_loops+1-pt2_base,pt2_pos,pt2_row
	dl	pt2_chA,0
	db	P2_SIZE,P2_NOTE,P2_SAMNUM,P2_ORNNUM,P2_VOL,P2_ENV,P2_ENABLED
	db	P2_ENABLED,0
	dl	pt2_delay_cnt
	db	0FFh
	dl	pt1_rowtick,pt1_base,pt1_loops+1-pt1_base,pt1_pos,pt1_row
	dl	pt1_chA,0
	db	P1_SIZE,P1_NOTE,P1_SAMNUM,P1_ORNNUM,P1_VOL,P1_ENV,P1_ENABLED
	db	P1_ENABLED,0
	dl	pt1_delay_cnt
	db	0FFh
	dl	asc_rowtick,asc_base,asc_loops+1-asc_base,asc_pos,asc_row
	dl	asc_chA,0
	db	AC_SIZE,AC_NOTE,AC_SAMNUM,AC_ORNNUM,AC_VOL,AC_ENV,AC_CNOISE
	db	AC_SOUND,0
	dl	asc_delay_cnt
	db	0FFh
	dl	stp_rowtick,stp_base,stp_loops+1-stp_base,stp_pos,stp_row
	dl	stp_chA,stp_transp
	db	TP_SIZE,TP_NOTE,TP_SAMNUM,TP_ORNNUM,TP_VOL,TP_ENV,TP_ON
	db	TP_ON,0
	dl	stp_delay_cnt
	db	0FFh
	dl	sqt_rowtick,sqt_base,sqt_loops+1-sqt_base,sqt_pos,sqt_row
	dl	sqt_chA,0
	db	SQ_SIZE,SQ_NOTE,SQ_SAMNUM,SQ_ORNNUM,0FFh,SQ_ENV,SQ_STC
	db	SQ_ON,0
	dl	sqt_delay_cnt
	db	SQ_TRANSP
	dl	psc_rowtick,psc_base,psc_loops+1-psc_base,psc_pos,psc_row
	dl	psc_chA,0
	db	PSCC_SIZE,PSCC_NOTE,PSCC_SAMNUM,PSCC_ORNNUM,PSCC_VOL,PSCC_ENV
	db	PSCC_ON,PSCC_ON,0
	dl	psc_delay_cnt
	db	0FFh

; po_have: does the current format have a pattern view of this kind?
; Out: NZ if so, with IY = its table.
po_have:
	ld	a,(fmt)
	cp	FMT_STC
	jr	z,@yes
	cp	FMT_PT2
	jr	c,@no
	cp	FMT_COUNT
	jr	nc,@no
@yes:
	sub	FMT_STC
	ld	iy,pf_tab
	jr	z,@got
	ld	b,a
	ld	de,PF_SIZE
@next:
	add	iy,de
	djnz	@next
@got:
	or	1
	ret
@no:
	xor	a
	ret

; po_copy: copy the replayer's state. In: IY = its table; HL = from,
; DE = to (0 for the replayer itself in either). Preserves IY.
po_copy:
	ld	a,h
	or	l
	jr	nz,@from
	ld	hl,(iy+PF_SPAN)
@from:
	ld	a,d
	or	e
	jr	nz,@to
	ld	de,(iy+PF_SPAN)
@to:
	ld	bc,(iy+PF_LEN)
	ldir
	ret

; po_load: after a song of one of these formats is set up: note its
; state as that at the start of the first pattern.
po_load:
	call	po_have
	ret	z
	ld	hl,0
	ld	de,po_start
	call	po_copy
	ld	a,0FFh
	ld	(po_lrow),a
	ld	hl,pat_snapgen
	inc	(hl)
	ret

; po_before / po_after: around each frame the replayer plays. The state
; before a frame that reads a row is kept; if the frame started a pattern
; (the row number is 0 and was not before, or the position changed),
; that is the state the pattern started from. Every one of these
; replayers starts a frame by counting its frames-until-the-next-row
; counter down and reading a row when it reaches 0, so a frame reads a
; row only if the counter is 1 before it; on other frames the row and
; position cannot change, and nothing need be kept.
po_before:
	call	po_have
	ret	z
	ld	hl,(iy+PF_CNT)
	ld	a,(hl)
	dec	a
	ret	nz
	ld	hl,0
	ld	de,po_frame
	jr	po_copy
po_after:
	call	po_have
	ret	z
	ld	hl,(iy+PF_ROW)
	ld	a,(hl)
	ld	hl,po_lrow
	ld	b,(hl)
	ld	(hl),a
	or	a
	ret	nz
	ld	hl,(iy+PF_POS)
	ld	a,(hl)
	ld	hl,po_lpos
	ld	c,(hl)
	ld	(hl),a
	cp	c
	jr	nz,@new
	ld	a,b
	or	a
	ret	z
@new:
	ld	hl,po_frame
	ld	de,po_start
	call	po_copy
	ld	hl,pat_snapgen
	inc	(hl)
	ret

; po_decode: fill the table at (pd_tab) with the pattern that starts
; from the state in po_end, and leave in po_end the state it ends with.
; Out: (pd_rows) = its rows, (pd_pos) = its position.
po_decode:
	call	po_have
	ld	hl,0			; put the replayer's state aside
	ld	de,po_live
	call	po_copy
	ld	hl,ay_regs		; (rows write to the AY registers)
	ld	de,po_regs
	ld	bc,16
	ldir
	ld	hl,po_end		; start where the last pattern ended
	ld	de,0
	call	po_copy
	ld	hl,(pd_tab)		; every cell starts as "nothing"
	push	hl
	pop	de
	inc	de
	ld	bc,3*PAT_CH-1
	ld	(hl),0FFh
	ldir
	xor	a
	ld	(pd_rows),a
@row:
	ld	hl,0			; keep the state before this row
	ld	de,po_tmp
	call	po_copy
	ld	a,0FFh
	ld	(ay_regs+13),a
	ld	ix,(iy+PF_CHA)		; mark each channel's bytes
	ld	b,3
	ld	hl,po_was
@mark:
	call	po_field		; (A = offset, from the table)
	db	PF_NOTE
	ld	a,(de)
	ld	(hl),a
	inc	hl
	call	po_field
	db	PF_ENV
	ld	a,(de)
	ld	(hl),a
	inc	hl
	call	po_field
	db	PF_NIND
	ld	a,55h
	ld	(de),a
	call	po_field
	db	PF_RIND
	ld	a,55h
	ld	(de),a
	call	po_field
	db	PF_SAM
	ld	a,0FFh
	ld	(de),a
	call	po_field
	db	PF_ORN
	ld	a,0FFh
	ld	(de),a
	ld	a,(iy+PF_VOL)
	cp	0FFh
	jr	z,@novol
	call	po_field
	db	PF_VOL
	ld	a,0FFh
	ld	(de),a
@novol:
	call	po_nextch
	djnz	@mark
	ld	hl,(iy+PF_TICK)		; read the row
	call	po_call
	ld	a,(pd_rows)		; the first row of the next pattern?
	or	a
	jr	z,@first
	ld	hl,(iy+PF_ROW)
	ld	a,(hl)
	or	a
	jp	z,@end
	jr	@cells
@first:
	ld	hl,(iy+PF_POS)
	ld	a,(hl)
	ld	(pd_pos),a
@cells:
	ld	ix,(iy+PF_CHA)		; what the row did to each channel
	ld	hl,(pd_tab)
	ld	de,0
	ld	a,(pd_rows)
	ld	e,a
	add	hl,de
	add	hl,de
	add	hl,de
	add	hl,de
	add	hl,de
	ld	(po_cell),hl
	ld	hl,po_was
	ld	b,3
@chan:
	push	bc
	push	hl
	call	po_cell1
	pop	hl
	inc	hl
	inc	hl
	ld	de,PAT_CH
	push	hl
	ld	hl,(po_cell)
	add	hl,de
	ld	(po_cell),hl
	pop	hl
	call	po_nextch
	pop	bc
	djnz	@chan
	ld	hl,pd_rows		; up to 256 rows
	inc	(hl)
	jp	nz,@row
	dec	(hl)
	ld	hl,0			; (the next decode carries on from
	ld	de,po_end		; here)
	call	po_copy
	jr	@done
@end:
	ld	hl,po_tmp		; the state before that row: where the
	ld	de,po_end		; next pattern starts
	call	po_copy
@done:
	ld	hl,po_live		; put the replayer's state back
	ld	de,0
	call	po_copy
	ld	hl,po_regs
	ld	de,ay_regs
	ld	bc,16
	ldir
	ret

; po_cell1: fill the cell at (po_cell) for the channel at IX, whose note
; and envelope switch before the row are at HL.
po_cell1:
	push	hl
	pop	bc			; BC -> note and envelope before
	lea	hl,ix+0			; HL = the channel, for po_get
	push	ix
	ld	ix,(po_cell)
	call	po_get			; sound off?
	db	PF_RIND
	cp	(iy+PF_RVAL)
	jr	nz,@notoff
	ld	(ix+PC_NOTE),0FEh
	jr	@sam
@notoff:
	call	po_get			; a note: its marker byte was set,
	db	PF_NIND			; or the note changed
	cp	55h
	jr	nz,@note
	call	po_get
	db	PF_NOTE
	ld	e,a
	ld	a,(bc)
	cp	e
	jr	z,@sam
@note:
	call	po_get
	db	PF_NOTE
	ld	e,a
	push	hl
	ld	a,(iy+PF_CTR)		; plus the channel's own transposition
	cp	0FFh
	jr	z,@nctr
	push	de
	ld	de,0
	ld	e,a
	add	hl,de
	pop	de
	ld	a,(hl)
	add	a,e
	ld	e,a
@nctr:
	ld	hl,(iy+PF_TRANSP)	; and the position's
	ld	a,h
	or	l
	ld	a,e
	jr	z,@nt
	add	a,(hl)
@nt:
	cp	96			; (as the replayers limit it)
	jr	c,@nt2
	ld	a,95
@nt2:
	pop	hl
	ld	(ix+PC_NOTE),a
@sam:
	call	po_get
	db	PF_SAM
	ld	(ix+PC_SAM),a
	call	po_get
	db	PF_ORN
	ld	(ix+PC_ORN),a
	ld	a,(iy+PF_VOL)
	cp	0FFh
	jr	z,@env
	call	po_get
	db	PF_VOL
	ld	(ix+PC_VOL),a
@env:
	call	po_get			; the envelope switched?
	db	PF_ENV
	ld	e,a
	inc	bc
	ld	a,(bc)
	cp	e
	jr	z,@same
	ld	a,e
	or	a
	ld	a,0Fh			; off
	jr	z,@setenv
	jr	@shape			; on: show the shape written
@same:
	ld	a,e			; still on: a shape written in this
	or	a			; row belongs to a channel whose row
	jr	z,@fin			; did something (a note, or sound off)
	ld	a,(ix+PC_NOTE)
	cp	0FFh
	jr	z,@fin
@shape:
	ld	a,(ay_regs+13)
	cp	0FFh
	jr	z,@fin
	and	0Fh
@setenv:
	ld	(ix+PC_ENV),a
@fin:
	pop	ix
	ret

; po_get: A = the byte, at the offset the format's table gives in the
; field named by the byte after the call, of the channel state at HL.
; Preserves BC, DE, HL.
po_get:
	ex	(sp),hl			; HL -> the field's name
	ld	a,(hl)
	inc	hl
	ex	(sp),hl			; (return past it)
	push	de
	push	hl
	ld	hl,0
	ld	l,a
	lea	de,iy+0
	add	hl,de
	ld	de,0
	ld	e,(hl)			; the offset
	pop	hl
	push	hl
	add	hl,de
	ld	a,(hl)
	pop	hl
	pop	de
	ret

; po_field: DE = address of the field named as for po_get, of the
; channel state at IX. Preserves BC, HL.
po_field:
	ex	(sp),hl
	ld	a,(hl)
	inc	hl
	ex	(sp),hl
	push	hl
	ld	hl,0
	ld	l,a
	lea	de,iy+0
	add	hl,de
	ld	de,0
	ld	e,(hl)
	lea	hl,ix+0
	add	hl,de
	ex	de,hl
	pop	hl
	ret

; po_nextch: IX = the next channel's state. Preserves BC, HL.
po_nextch:
	push	de
	ld	de,0
	ld	e,(iy+PF_CHSZ)
	add	ix,de
	pop	de
	ret

; po_call: call the routine at HL, keeping IY.
po_call:
	push	iy
	call	@go
	pop	iy
	ret
@go:
	jp	(hl)