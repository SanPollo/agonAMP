; stcplay.asm - Sound Tracker (.stc) module replayer.
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
; Part of the reusable agonAMP sound library in lib/. It turns a
; compiled Sound Tracker 1.x module held in memory into AY-3-8912
; register values, one set per 50 Hz frame, in the table ay_regs (which
; ayvdp.asm defines and plays). It needs only
; notetab.inc (its note table, nt_st) from the rest of the library.
;
; Written for the eZ80 in ADL mode from the published description of the
; format ("STC File Format (Sound Tracker)", www.avray.ru, 2015), which
; also gives the note table used here. Where that description is silent
; (how a sample's 32 steps are counted and repeated, and the order of
; the two bytes of a position) the behaviour was matched to an existing
; player, STCPlay.h of the ESP32AY project, whose source was read for
; the purpose. No code was copied from it.
;
; The module: a 27 byte header (speed; pointers to the position list,
; the ornaments and the pattern table; an 18 character identifier),
; then the samples, 99 bytes each: a number, 32 steps of 3 bytes, and a
; repeat position and length. Ornaments are 33 bytes: a number and 32
; note offsets. Each pattern table entry is a pattern number and three
; pointers, one per channel, to streams of:
;   00h-5Fh  note; ends the row
;   60h-6Fh  select sample
;   70h-7Fh  select ornament, envelope off
;   80h      rest; ends the row
;   81h      nothing; ends the row
;   82h      ornament 0, envelope off
;   83h-8Eh  envelope shape (low 4 bits), then its period (1 byte)
;   A1h-FEh  rows to leave empty after each row from now on
;   FFh      end of the pattern
;
; Entry points:
;   stc_init   HL = address of the module, BC = its length. Returns with
;              carry set if it cannot be a Sound Tracker module. (The
;              format has no signature, so this only checks that the
;              header's pointers make sense.)
;   stc_play   advance one frame and fill ay_regs
;   stc_length frames the song lasts (see the routine for how to use it)
;
; Results:
;   ay_regs    R13 is 0FFh on frames where the shape was not written.
;   stc_loops  goes up by one each time the song ends and starts again.
;   stc_pos, stc_numpos, stc_pat, stc_row, stc_delay, stc_transp and the
;   SC_ fields of stc_chA/B/C can be read for display.
;
; All registers are used.

; Per-channel state, addressed through IX.
SC_ADDR:	equ	0	; 3: address of next byte of pattern data
SC_SAMPTR:	equ	3	; 3: address of the sample's 32 steps
SC_ORNPTR:	equ	6	; 3: address of the ornament's 32 offsets
SC_TON:		equ	9	; 3: tone period sent to the AY
SC_AMP:		equ	12	; 1: amplitude sent to the AY
SC_NOTE:	equ	13	; 1: note number
SC_POS:		equ	14	; 1: step in the sample, 0 to 31
SC_SKIPN:	equ	15	; 1: empty rows after each row
SC_TIK:		equ	16	; 1: sample steps left; negative = silent
SC_SKIPCNT:	equ	17	; 1: rows left before the next one (signed)
SC_ENV:		equ	18	; 1: non-zero if the envelope is in use
SC_SAMNUM:	equ	19	; 1: sample number (for display)
SC_ORNNUM:	equ	20	; 1: ornament number (for display)
SC_SIZE:	equ	21

STC_SAMPLES:	equ	27	; offset of the first sample in the module
STC_SAMSIZE:	equ	99
STC_ORNSIZE:	equ	33

stc_base:	ds	3	; address of the module
stc_len:	ds	3	; its length
stc_posptr:	ds	3	; address of the position list
stc_ornptr:	ds	3	; address of the ornaments
stc_patptr:	ds	3	; address of the pattern table
stc_delay:	ds	1	; frames per row
; Everything from here to stc_vars_end is cleared by stc_init.
stc_vars:
stc_chA:	ds	SC_SIZE
stc_chB:	ds	SC_SIZE
stc_chC:	ds	SC_SIZE
		ds	2	; spill room for 24 bit loads
stc_delay_cnt:	ds	1	; frames until the next row
stc_pos:	ds	1	; current position
stc_numpos:	ds	1	; number of positions
stc_pat:	ds	1	; current pattern number
stc_row:	ds	1	; row within the pattern (for display)
stc_transp:	ds	1	; note offset of the current position
stc_mixer:	ds	1	; mixer value being assembled
stc_b1:		ds	1	; sample step: masks and noise
stc_b2:		ds	1	; sample step: low byte of tone offset
stc_frames:	ds	3	; stc_length: frames counted
stc_loops:	ds	1	; times the end of the song was reached
stc_vars_end:
stc_rows:	ds	3	; length: rows counted
stc_rowlim:	ds	3	; bytes left in this pattern row

; stc_word: fetch a pointer from the module.
; In: HL = address of a 16 bit offset. Out: HL = module address + offset,
; carry set if the offset lies beyond the end of the module.
stc_word:
	ld	e,(hl)
	inc	hl
	ld	d,(hl)
	ld	hl,0
	ld	l,e
	ld	h,d
	push	hl
	ld	de,(stc_len)
	or	a
	sbc	hl,de
	pop	hl
	ccf
	ld	de,(stc_base)
	push	af
	add	hl,de
	pop	af
	ret

stc_init:
	ld	(stc_base),hl
	ld	(stc_len),bc
	push	hl
	ld	hl,STC_SAMPLES+STC_SAMSIZE	; too short to hold a sample?
	or	a
	sbc	hl,bc
	pop	hl
	ccf
	ret	c
	ld	a,(hl)			; a speed of 0 is impossible
	or	a
	scf
	ret	z
	ld	(stc_delay),a
	inc	hl
	push	hl
	call	stc_word
	ld	(stc_posptr),hl
	pop	hl
	ret	c
	inc	hl
	inc	hl
	push	hl
	call	stc_word
	ld	(stc_ornptr),hl
	pop	hl
	ret	c
	inc	hl
	inc	hl
	call	stc_word
	ld	(stc_patptr),hl
	ret	c
	ld	hl,stc_vars		; clear the playing state
	ld	de,stc_vars+1
	ld	bc,stc_vars_end-stc_vars-1
	ld	(hl),0
	ldir
	ld	hl,ay_regs		; and the AY registers
	ld	b,13
@regs:
	ld	(hl),0
	inc	hl
	djnz	@regs
	ld	(hl),0FFh
	ld	a,1
	ld	(stc_delay_cnt),a
	ld	hl,(stc_posptr)
	ld	a,(hl)
	inc	a
	ld	(stc_numpos),a
	ld	ix,stc_chA
	call	@chinit
	ld	ix,stc_chB
	call	@chinit
	ld	ix,stc_chC
	call	@chinit
	xor	a
	call	stc_setpos
	ld	a,0FFh			; becomes row 0 on the first frame
	ld	(stc_row),a
	or	a			; carry clear: accepted
	ret
@chinit:
	ld	hl,(stc_base)
	ld	(ix+SC_SAMPTR),hl
	ld	hl,(stc_ornptr)
	inc	hl
	ld	(ix+SC_ORNPTR),hl
	ld	(ix+SC_TIK),0FFh
	ret

; stc_setpos: point the channels at the pattern for position A.
; Corrupts IX.
stc_setpos:
	ld	(stc_pos),a
	ld	hl,0
	ld	l,a
	add	hl,hl
	ld	de,(stc_posptr)
	add	hl,de
	inc	hl
	ld	a,(hl)			; pattern number
	ld	(stc_pat),a
	inc	hl
	ld	c,a
	ld	a,(hl)			; note offset for the whole position
	ld	(stc_transp),a
	ld	hl,(stc_patptr)		; look the pattern up in the table
	ld	b,64
	ld	de,7
@find:
	ld	a,(hl)
	cp	c
	jr	z,@found
	add	hl,de
	djnz	@find
	ld	hl,(stc_patptr)		; not there: fall back on the first
@found:
	inc	hl
	ld	ix,stc_chA
	call	@addr
	ld	ix,stc_chB
	call	@addr
	ld	ix,stc_chC
@addr:
	push	hl
	ld	e,(hl)
	inc	hl
	ld	d,(hl)
	ld	hl,0
	ld	l,e
	ld	h,d
	ld	de,(stc_base)
	add	hl,de
	ld	(ix+SC_ADDR),hl
	pop	hl
	inc	hl
	inc	hl
	ret

; stc_findsam / stc_findorn: select sample or ornament number A for the
; channel at IX. Samples and ornaments carry their numbers and may be
; stored in any order. Preserves HL.
stc_findsam:
	push	hl
	ld	c,a
	ld	hl,(stc_base)
	ld	de,STC_SAMPLES
	add	hl,de
	ld	b,16
	ld	de,STC_SAMSIZE
@find:
	ld	a,(hl)
	cp	c
	jr	z,@found
	add	hl,de
	djnz	@find
	pop	hl			; no such sample: keep the old one
	ret
@found:
	inc	hl
	ld	(ix+SC_SAMPTR),hl
	ld	(ix+SC_SAMNUM),c
	pop	hl
	ret
stc_findorn:
	push	hl
	ld	c,a
	ld	hl,(stc_ornptr)
	ld	b,16
	ld	de,STC_ORNSIZE
@find:
	ld	a,(hl)
	cp	c
	jr	z,@found
	add	hl,de
	djnz	@find
	pop	hl
	ret
@found:
	inc	hl
	ld	(ix+SC_ORNPTR),hl
	ld	(ix+SC_ORNNUM),c
	pop	hl
	ret

; stc_interp: read one row of pattern data for the channel at IX.
stc_interp:
	ld	hl,(ix+SC_ADDR)
	push	hl			; (bytes read in this row: see @loop)
	ld	hl,0
	ld	(stc_rowlim),hl
	pop	hl
@loop:
	push	hl			; a damaged pattern: give up on the
	ld	hl,(stc_rowlim)	; row after 65536 bytes
	dec	hl
	ld	(stc_rowlim),hl
	ld	a,h
	or	l
	pop	hl
	jp	z,@end
	ld	a,(hl)
	cp	060h
	jr	c,@note
	cp	070h
	jr	c,@sample
	cp	080h
	jr	c,@ornament
	jr	z,@rest
	cp	081h
	jr	z,@end
	cp	082h
	jr	z,@plain
	cp	08Fh
	jr	c,@envelope
	sub	0A1h			; anything else sets the row spacing
	ld	(ix+SC_SKIPN),a
@next:
	inc	hl
	jr	@loop
@note:
	ld	(ix+SC_NOTE),a
	ld	(ix+SC_TIK),32		; start the sample from its first step
	ld	(ix+SC_POS),0
	jr	@end
@sample:
	sub	060h
	call	stc_findsam
	jr	@next
@ornament:
	sub	070h
	call	stc_findorn
	ld	(ix+SC_ENV),0
	jr	@next
@rest:
	ld	(ix+SC_TIK),0FFh
	jr	@end
@plain:
	xor	a
	call	stc_findorn
	ld	(ix+SC_ENV),0
	jr	@next
@envelope:
	sub	080h
	ld	(ay_regs+13),a
	inc	hl
	ld	a,(hl)
	ld	(ay_regs+11),a
	ld	(ix+SC_ENV),1
	xor	a
	call	stc_findorn
	jr	@next
@end:
	inc	hl
	ld	(ix+SC_ADDR),hl
	ld	a,(ix+SC_SKIPN)
	ld	(ix+SC_SKIPCNT),a
	ret

; stc_chreg: work out this frame's tone and amplitude for the channel at
; IX and add its bits to the mixer.
;
; A note plays its sample's 32 steps once. Then, if the sample has a
; repeat position, the steps from there are played again and again for
; the repeat length; if not, the channel falls silent.
stc_chreg:
	bit	7,(ix+SC_TIK)
	jp	nz,@silent
	dec	(ix+SC_TIK)
	ld	a,(ix+SC_POS)
	inc	a
	and	31
	ld	(ix+SC_POS),a
	ld	a,(ix+SC_TIK)
	or	a
	jr	nz,@sound
	ld	hl,(ix+SC_SAMPTR)	; end of the pass: repeat or stop
	ld	de,96
	add	hl,de
	ld	a,(hl)
	or	a
	jr	z,@stop
	and	31
	ld	(ix+SC_POS),a
	inc	hl
	ld	a,(hl)
	inc	a
	ld	(ix+SC_TIK),a
	jr	@sound
@stop:
	ld	(ix+SC_TIK),0FFh
@sound:
	bit	7,(ix+SC_TIK)
	jp	nz,@silent
	ld	a,(ix+SC_POS)		; the step just reached
	dec	a
	and	31
	ld	c,a
	ld	hl,0
	ld	l,a
	push	hl
	pop	de
	add	hl,hl
	add	hl,de
	ld	de,(ix+SC_SAMPTR)
	add	hl,de
	ld	b,(hl)			; B = volume, top 4 bits of tone offset
	inc	hl
	ld	a,(hl)			; masks, direction, noise period
	ld	(stc_b1),a
	inc	hl
	ld	a,(hl)			; low 8 bits of the tone offset
	ld	(stc_b2),a
	ld	a,(stc_b1)
	ld	hl,stc_mixer
	bit	7,a
	jr	z,@noise
	set	6,(hl)			; noise off for this channel
	jr	@tonemask
@noise:
	and	31
	ld	(ay_regs+6),a
@tonemask:
	ld	a,(stc_b1)
	bit	6,a
	jr	z,@amp
	set	3,(hl)			; tone off for this channel
@amp:
	ld	a,b
	and	15
	bit	0,(ix+SC_ENV)
	jr	z,@noenv
	or	16
@noenv:
	ld	(ix+SC_AMP),a
	ld	hl,0			; note + ornament + position offset
	ld	l,c
	ld	de,(ix+SC_ORNPTR)
	add	hl,de
	ld	a,(ix+SC_NOTE)
	add	a,(hl)
	ld	hl,stc_transp
	add	a,(hl)
	cp	96
	jr	c,@inrange
	ld	a,95
@inrange:
	ld	hl,0
	ld	l,a
	add	hl,hl
	ld	de,nt_st
	add	hl,de
	ld	e,(hl)
	inc	hl
	ld	d,(hl)
	ld	hl,0
	ld	l,e
	ld	h,d			; HL = the note's period
	ld	a,b			; DE = the sample's 12 bit tone offset
	rrca
	rrca
	rrca
	rrca
	and	0Fh
	ld	de,0
	ld	d,a
	ld	a,(stc_b2)
	ld	e,a
	ld	a,(stc_b1)
	bit	5,a
	jr	z,@minus
	add	hl,de
	jr	@ton
@minus:
	or	a
	sbc	hl,de
@ton:
	ld	(ix+SC_TON),l
	ld	a,h
	and	0Fh
	ld	(ix+SC_TON+1),a
	jr	@done
@silent:
	ld	(ix+SC_AMP),0
@done:
	ld	hl,stc_mixer		; make room for the next channel
	srl	(hl)
	ret

; stc_play: advance the song by one frame and fill ay_regs.
stc_play:
	ld	a,0FFh
	ld	(ay_regs+13),a
	ld	hl,stc_delay_cnt
	dec	(hl)
	call	z,stc_rowtick
	xor	a
	ld	(stc_mixer),a
	ld	ix,stc_chA
	call	stc_chreg
	ld	ix,stc_chB
	call	stc_chreg
	ld	ix,stc_chC
	call	stc_chreg
	ld	a,(stc_mixer)
	ld	(ay_regs+7),a
	ld	hl,(stc_chA+SC_TON)
	ld	(ay_regs+0),hl
	ld	hl,(stc_chB+SC_TON)
	ld	(ay_regs+2),hl
	ld	hl,(stc_chC+SC_TON)
	ld	a,l
	ld	(ay_regs+4),a
	ld	a,h
	ld	(ay_regs+5),a
	ld	a,(stc_chA+SC_AMP)
	ld	(ay_regs+8),a
	ld	a,(stc_chB+SC_AMP)
	ld	(ay_regs+9),a
	ld	a,(stc_chC+SC_AMP)
	ld	(ay_regs+10),a
	ret

; stc_rowtick: the work done once per row: read the next row for each
; channel whose turn it is, moving to the next pattern when one ends.
stc_rowtick:
	ld	a,(stc_delay)
	ld	(stc_delay_cnt),a
	ld	hl,stc_row
	inc	(hl)
	ld	ix,stc_chA
	dec	(ix+SC_SKIPCNT)
	jp	p,@chb
	ld	hl,(ix+SC_ADDR)
	ld	a,(hl)
	inc	a			; 0FFh in channel A ends the pattern
	jr	nz,@cha
	ld	a,(stc_pos)
	ld	hl,(stc_posptr)		; (first byte: the last position)
	cp	(hl)
	jr	nz,@nextpos
	ld	hl,stc_loops		; end of song: note it, start again
	inc	(hl)
	ld	a,0FFh
@nextpos:
	inc	a
	call	stc_setpos
	xor	a
	ld	(stc_row),a
	ld	ix,stc_chA
@cha:
	call	stc_interp
@chb:
	ld	ix,stc_chB
	dec	(ix+SC_SKIPCNT)
	call	m,stc_interp
	ld	ix,stc_chC
	dec	(ix+SC_SKIPCNT)
	call	m,stc_interp
	ret

; stc_length: how many frames the song lasts before it ends. Call it
; straight after stc_init, and call stc_init again afterwards, because
; it works by running through all the song's rows (without the per-frame
; work, so it is quick). Out: HL = frames.
stc_length:
	ld	hl,0
	ld	(stc_frames),hl
	ld	(stc_rows),hl	; (rows counted)
@row:
	call	stc_rowtick
	ld	hl,(stc_rows)		; give up after 65536 rows, which no
	inc	hl			; real song needs (a damaged one that
	ld	(stc_rows),hl		; never ends)
	ld	a,(stc_rows+2)
	or	a
	jp	nz,@done
	ld	a,(stc_loops)
	or	a
	jr	nz,@done
	ld	de,0
	ld	a,(stc_delay)
	ld	e,a
	or	a
	jr	nz,@add
	inc	d			; a speed of 0 lasts 256 frames
@add:
	ld	hl,(stc_frames)
	add	hl,de
	ld	(stc_frames),hl
	ld	a,(stc_frames+2)	; give up on a song that never ends
	cp	10h			; (about 5 hours)
	jr	c,@row
@done:
	ld	hl,(stc_frames)
	ret