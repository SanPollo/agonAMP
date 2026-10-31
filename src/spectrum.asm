; spectrum.asm - the agonAMP spectrum analyser: a strip of bars under the
; channel lines, one column per semitone from C1 (32.7 Hz) to F#7
; (2960 Hz), lowest on the left.
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
; There is no sound here to measure: the VDP makes it. So the bars are
; worked out from what the sound layer (lib/ayvdp.asm) sent the VDP for
; the frame just played:
;
; * each tone that is heard lights the column of its pitch, as high as
;   its level, and smaller bars for its 3rd and 5th harmonics, which an
;   AY's square wave has at a third and a fifth of its amplitude (9.5
;   and 14 dB down);
; * the envelope played as a waveform (the "buzz") does the same, with
;   the harmonics of a sawtooth (2nd and 3rd, 6 and 9.5 dB down) or of a
;   triangle (3rd and 5th, 19 and 28 dB down);
; * noise is spread over every pitch shown (the AY's noise is roughly
;   even up to well above 3 kHz), so it raises all the columns a little,
;   each by a slightly different amount.
;
; Every bar falls back by AN_DECAY each frame unless something holds it
; up. Muted channels are not heard, so they light nothing.
;
; The scale is the meters': one AY volume step (about 3 dB) is a
; fifteenth of the full height, so the harmonics above are 3, 5, 2, 3, 6
; and 9 steps lower. Heights are in eighths of a text row; a bar is
; AN_BARS rows of up to eight steps each, drawn with characters 130 to
; 137 (see ui_setup).
;
; an_frame brings the bars wanted (an_tgt) up to date each time a frame
; is played. an_step, one of the pieces of paced drawing in ui.asm, then
; redraws only the cells whose bars differ from what is on screen
; (an_shown), a few columns at a time.

AN_DECAY:	equ	4	; fall per frame, in eighths of a row
AN_NOISE:	equ	9	; noise is shown this many steps down
AN_CELLS:	equ	16	; cells drawn per step, roughly

an_on:		ds	1	; non-zero while the analyser is shown
an_want:	ds	1	; 1 if it is wanted (V; the settings)
an_bot:		ds	1	; screen row of its bottom cells
an_next:	ds	1	; an_step: the column to look at next
an_budget:	ds	1	; an_step: cells it may still draw
an_drew:	ds	1	; an_step: non-zero once it has drawn
an_rnd:		ds	1	; for the noise: never 0
an_shown:	ds	AN_COLS	; height of each bar on screen
an_tgt:		ds	AN_COLS	; and wanted (must follow an_shown)

; an_clear: no bars wanted (a new song). The bars on screen fall away
; as an_step catches up.
an_clear:
	ld	hl,an_tgt
	ld	b,AN_COLS
@clr:
	ld	(hl),0
	inc	hl
	djnz	@clr
	ret

; an_frame: work out the bars wanted after a frame has been played.
an_frame:
	ld	a,(an_on)
	or	a
	ret	z
	ld	hl,an_tgt		; everything falls a little
	ld	b,AN_COLS
@fall:
	ld	a,(hl)
	sub	AN_DECAY
	jr	nc,@f1
	xor	a
@f1:
	ld	(hl),a
	inc	hl
	djnz	@fall
	ld	ix,ay_ctx		; then the first chip's sounds hold
	call	an_chip			; their columns up
	ld	a,(ay_nchips)		; and the second chip's (TurboSound)
	cp	2
	ret	nz
	ld	ix,ay_ctx2
	; fall through

; an_chip: light the columns of the sounds of the chip whose state is at
; IX (ay_ctx or ay_ctx2).
an_chip:
	ld	c,0			; tones A, B and C
@tone:
	call	an_voice
	jr	z,@next
	push	bc
	call	an_put			; the tone (A = level, D = column)
	ld	c,19			; its 3rd harmonic, 19 semitones up
	ld	e,3
	call	an_harm
	ld	c,28			; its 5th, 28 semitones up
	ld	e,5
	call	an_harm
	pop	bc
@next:
	inc	c
	ld	a,c
	cp	3
	jr	c,@tone
	; Noise: every column, AN_NOISE steps down and up to three more.
	; (Written out rather than through an_put, as it is done for every
	; column: a step is taken as 9 eighths, near enough.)
	ld	a,(ix+ay_nw_vol-ay_ctx+AY_V_NOISE)
	or	a
	jr	z,@buzz
	call	an_lvl
	sub	AN_NOISE
	jr	c,@buzz
	jr	z,@buzz
	ld	hl,0			; D = the height of that level
	ld	l,a
	ld	de,an_hgt
	add	hl,de
	ld	d,(hl)
	ld	a,(an_rnd)		; C = an 8-bit shift register (never 0)
	ld	c,a
	ld	hl,an_tgt
	ld	b,AN_COLS
@noise:
	srl	c
	jr	nc,@nb
	ld	a,c
	xor	0B8h
	ld	c,a
@nb:
	ld	a,c			; 0 to 3 steps lower
	and	3
	ld	e,a
	add	a,a
	add	a,a
	add	a,a
	add	a,e
	ld	e,a
	ld	a,d
	sub	e
	jr	c,@nskip
	cp	(hl)
	jr	c,@nskip
	ld	(hl),a
@nskip:
	inc	hl
	djnz	@noise
	ld	a,c
	ld	(an_rnd),a
@buzz:
	ld	c,AY_V_BUZZ		; the envelope played as a waveform
	call	an_voice
	ret	z
	call	an_put
	ld	l,a
	ld	a,(ix+ay_env_wave-ay_ctx)
	cp	2
	ld	a,l
	jr	nz,@tri
	ld	c,12			; sawtooth: 2nd harmonic
	ld	e,2
	call	an_harm
	ld	c,19			; and 3rd
	ld	e,3
	jp	an_harm
@tri:
	ld	c,19			; triangle: 3rd harmonic
	ld	e,6
	call	an_harm
	ld	c,28			; and 5th
	ld	e,9
	jp	an_harm

; an_voice: is VDP channel C (0 to 4) of the chip at IX heard, and where?
; Out: Z if not; else NZ, A = its level (1 to 15) and D = its column.
; Preserves BC, IX.
an_voice:
	push	bc
	ld	hl,0
	ld	l,c
	ex	de,hl			; DE = channel
	lea	hl,ix+ay_nw_vol-ay_ctx	; its VDP volume
	add	hl,de
	ld	a,(hl)
	or	a
	jr	z,@silent
	call	an_lvl
	or	a
	jr	z,@silent
	push	af
	lea	hl,ix+ay_nw_fine-ay_ctx	; 1: its frequency is in quarter
	add	hl,de			; hertz, 0: in hertz
	ld	b,(hl)
	lea	hl,ix+ay_nw_freq-ay_ctx	; its frequency (two bytes)
	add	hl,de
	add	hl,de
	ld	e,(hl)
	inc	hl
	ld	d,(hl)
	ld	hl,0
	ld	l,e
	ld	h,d
	dec	b
	jr	z,@quarter
	add	hl,hl			; hertz to quarter hertz
	add	hl,hl
@quarter:
	call	an_col
	ld	d,a
	pop	af			; (1 to 15, so NZ)
	or	a
	pop	bc
	ret
@silent:
	xor	a
	pop	bc
	ret

; an_lvl: the AY level (0 to 15) that gave VDP volume A, from the table
; the sound layer is using (ay_amps): the highest level whose volume is
; no more than A. Preserves BC, DE.
an_lvl:
	push	bc
	push	de
	ld	c,a
	ld	hl,(ay_amps)
	ld	de,15
	add	hl,de
	ld	b,15
@look:
	ld	a,(hl)
	cp	c
	jr	c,@got
	jr	z,@got
	dec	hl
	djnz	@look
@got:
	ld	a,b
	pop	de
	pop	bc
	ret

; an_col: the column of frequency HL (quarter hertz): the number of
; boundaries in an_bnd that are no higher than it, found by halving.
; Out: A = 0 to AN_COLS-1. Preserves BC, DE, HL.
an_col:
	push	bc
	push	de
	ld	b,0			; B: lowest column it can be
	ld	c,AN_COLS-1		; C: highest
@halve:
	ld	a,b
	cp	c
	jr	z,@found
	add	a,c			; A = (B + C + 1) / 2, so B < A <= C
	inc	a
	srl	a
	push	hl
	push	af
	dec	a			; the boundary below column A is
	ld	hl,0			; entry A - 1
	ld	l,a
	push	hl
	pop	de
	add	hl,hl
	add	hl,de
	ld	de,an_bnd
	add	hl,de
	ld	de,(hl)
	pop	af
	pop	hl
	push	hl
	or	a
	sbc	hl,de
	pop	hl
	jr	c,@lower
	ld	b,a			; at or above it: column A or higher
	jr	@halve
@lower:
	dec	a			; below it: lower than column A
	ld	c,a
	jr	@halve
@found:
	ld	a,b
	pop	de
	pop	bc
	ret

; an_harm: light the column C semitones above column D at E levels below
; level A (a harmonic). Preserves AF, BC, DE, HL.
an_harm:
	push	af
	push	de
	sub	e
	ld	e,a
	ld	a,d
	add	a,c
	ld	d,a
	ld	a,e
	call	an_put
	pop	de
	pop	af
	ret

; an_put: hold column D up to at least the height of level A. Levels of
; 0 or less, and columns past the last, are left out. Preserves AF, BC,
; DE, HL.
an_put:
	push	af
	push	bc
	push	de
	push	hl
	or	a
	jr	z,@out
	jp	m,@out
	ld	e,a
	ld	a,d
	cp	AN_COLS
	jr	nc,@out
	ld	hl,0			; C = the height of level E
	ld	l,e
	ld	bc,an_hgt
	add	hl,bc
	ld	c,(hl)
	ld	hl,0			; HL -> the bar wanted in column D
	ld	l,d
	ld	de,an_tgt
	add	hl,de
	ld	a,(hl)
	cp	c
	jr	nc,@out
	ld	(hl),c
@out:
	pop	hl
	pop	de
	pop	bc
	pop	af
	ret

; an_step: redraw the next columns whose bars on screen are not the ones
; wanted, until about AN_CELLS cells have been drawn or every column has
; been looked at. The next call carries on from there, so all columns
; get their turn. Out: NZ if it drew something.
an_step:
	ld	a,(an_on)
	or	a
	ret	z
	ld	a,BG+COL_BLACK		; (sends nothing if it is already)
	call	vcol
	ld	a,AN_CELLS
	ld	(an_budget),a
	xor	a
	ld	(an_drew),a
	ld	a,(an_next)
	ld	d,a			; D = column
	ld	b,AN_COLS
@col:
	push	bc
	call	an_column
	pop	bc
	inc	d
	ld	a,d
	cp	AN_COLS
	jr	c,@in
	ld	d,0
@in:
	ld	a,(an_budget)		; (it can go below 0)
	dec	a
	jp	m,@stop
	djnz	@col
@stop:
	ld	a,d
	ld	(an_next),a
	ld	a,(an_drew)
	or	a
	ret	z
	jp	vdu_flush		; (keeps the flags: NZ)

; an_column: if the bar in column D on screen is not the one wanted,
; redraw the cells that differ, and take their number off an_budget.
; Preserves D.
an_column:
	push	de
	ld	hl,0
	ld	l,d
	ld	de,an_shown
	add	hl,de
	push	hl
	pop	iy			; IY -> shown; IY + AN_COLS -> wanted
	pop	de
	ld	c,(iy+AN_COLS)		; C = height wanted
	ld	a,(iy+0)		; A = height shown
	cp	c
	ret	z
	ld	(iy+0),c
	ld	b,a
	jr	c,@rise
	ld	a,c			; falling: cells C/8 to (B-1)/8
	jr	@range
@rise:
	ld	b,c			; rising: cells A/8 to (C-1)/8
@range:
	rrca				; A = the lesser height, B = the
	rrca				; greater: E = the first cell
	rrca
	and	1Fh
	ld	e,a
	ld	a,b
	dec	a
	rrca
	rrca
	rrca
	and	1Fh
	sub	e
	inc	a
	ld	b,a			; B = cells to draw
	ld	a,(an_budget)
	sub	b
	ld	(an_budget),a
	ld	a,1
	ld	(an_drew),a
@cell:
	call	an_cell
	inc	e
	djnz	@cell
	ret

; an_cell: draw cell E (0 = the bottom one) of column D for a bar of
; height C. Preserves BC, DE.
an_cell:
	push	bc
	ld	a,e			; the character: the eighths of this
	add	a,a			; cell the bar reaches, 1 to 8, or none
	add	a,a
	add	a,a
	ld	b,a
	ld	a,c
	sub	b
	jr	c,@blank
	jr	z,@blank
	cp	8
	jr	c,@part
	ld	a,8
@part:
	add	a,129			; characters 130 to 137
	ld	b,a
	ld	a,e			; its colour: the bottom six rows are
	cp	6			; the theme's light colour, the next
	ld	a,COL_LIGHT		; five its medium and the top five its
					; dark (green, light and dark blue)
	jr	c,@col
	ld	a,e
	cp	11
	ld	a,COL_MID
	jr	c,@col
	ld	a,COL_DARK
@col:
	call	vcol
	jr	@at
@blank:
	ld	b,' '
@at:
	push	de
	ld	a,(an_bot)
	sub	e
	ld	e,a
	call	vat
	pop	de
	ld	a,b
	call	vdu_put
	pop	bc
	ret

; Bar heights of levels 0 to 15 (level * 128 / 15).
an_hgt:	db	0,9,17,26,34,43,51,60,68,77,85,94,102,111,119,128

	include	"spectab.inc"