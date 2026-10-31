; pt2play.asm - Pro Tracker 2 (.pt2) module replayer.
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
; Part of the reusable agonAMP sound library in lib/. It turns a Pro
; Tracker 2.x module held in memory into AY-3-8912 register values, one
; set per 50 Hz frame, in the table ay_regs (which ayvdp.asm defines and
; plays). It needs nothing else from the library.
;
; Written for the eZ80 in ADL mode. I found no written description of
; this format to work from: the behaviour was taken from reading the
; source of an existing player, PT2Play.h of the ESP32AY project, and
; this code was then written to do the same. No code was copied. The
; note table is the one PT3 modules know as "ST". Two details follow
; zxtune instead, where its register logs show it differs: the tone
; slide is kept to 16 bits, and each channel starts with sample 1 (so a
; note played before a sample is chosen sounds as it does there).
;
; The module: speed, number of positions, loop position; 32 sample
; pointers, 16 ornament pointers, the pattern table pointer, a 30
; character name, then the position list (pattern numbers). A sample is
; a length, a loop position and 3 byte steps; an ornament is a length, a
; loop position and note offsets. Pattern streams hold:
;   E1h-FFh  select sample              80h-DFh  note; ends the row
;   E0h      sound off; ends the row    7Fh      envelope off
;   71h-7Eh  envelope shape, then its period (2 bytes)
;   70h      nothing; ends the row      60h-6Fh  select ornament
;   20h-5Fh  rows to leave empty        10h-1Fh  volume
;   0Fh n    speed                      0Eh n    slide by n per frame
;   0Dh n,x,x  slide to the next note   0Ch      slide off
;   00h-0Bh n  noise offset             00h at a row start: pattern end
;
; Entry points:
;   pt2_init   HL = address of the module, BC = its length. Returns with
;              carry set if it cannot be a PT2 module (the format has no
;              signature; only the header is checked for sense).
;   pt2_play   advance one frame and fill ay_regs
;   pt2_length frames the song lasts (see the routine for how to use it)
;
; Results:
;   ay_regs    R13 is 0FFh on frames where the shape was not written.
;   pt2_loops  goes up by one each time the song ends and loops.
;   pt2_pos, pt2_numpos, pt2_pat, pt2_row, pt2_delay (in that order in
;   memory) and the first four bytes of pt2_chA/B/C (note, sample,
;   ornament, sounding) can be read for display.
;
; All registers are used.

; Per-channel state, addressed through IX.
P2_NOTE:	equ	0	; 1: note number
P2_SAMNUM:	equ	1	; 1: sample number (for display)
P2_ORNNUM:	equ	2	; 1: ornament number (for display)
P2_ENABLED:	equ	3	; 1: non-zero if the channel is sounding
P2_ADDR:	equ	4	; 3: address of next byte of pattern data
P2_ORNPTR:	equ	7	; 3: address of the ornament's offsets
P2_SAMPTR:	equ	10	; 3: address of the sample's steps
P2_TON:		equ	13	; 3: tone period sent to the AY
P2_ORNLOOP:	equ	16	; 1
P2_ORNLEN:	equ	17	; 1
P2_ORNPOS:	equ	18	; 1
P2_SAMLOOP:	equ	19	; 1
P2_SAMLEN:	equ	20	; 1
P2_SAMPOS:	equ	21	; 1
P2_VOL:		equ	22	; 1: channel volume, 0 to 15
P2_SKIPN:	equ	23	; 1: empty rows after each row
P2_SLIDETO:	equ	24	; 1: note being slid to
P2_AMP:		equ	25	; 1: amplitude sent to the AY
P2_TSLIDE:	equ	26	; 2: tone slide so far (signed)
P2_TDELTA:	equ	28	; 2: distance left to slide (signed)
P2_GLTYPE:	equ	30	; 1: 0 no slide, 1 plain, 2 to a note
P2_ENV:		equ	31	; 1: non-zero if the envelope is in use
P2_GLISS:	equ	32	; 1: slide per frame (signed)
P2_NOISEADD:	equ	33	; 1: noise offset
P2_SKIPCNT:	equ	34	; 1: rows left before the next one (signed)
P2_SIZE:	equ	35

PT2_SAMPTRS:	equ	3	; header: 32 sample pointers
PT2_ORNPTRS:	equ	67	; header: 16 ornament pointers
PT2_PATPTR:	equ	99	; header: pattern table pointer
PT2_NAME:	equ	101	; header: 30 character name
PT2_POSLIST:	equ	131	; header: position list

pt2_base:	ds	3	; address of the module
pt2_patptr:	ds	3	; address of the pattern table
; Everything from here to pt2_vars_end is cleared by pt2_init.
pt2_vars:
pt2_chA:	ds	P2_SIZE
pt2_chB:	ds	P2_SIZE
pt2_chC:	ds	P2_SIZE
		ds	2	; spill room for 24 bit loads
pt2_pos:	ds	1	; current position       (these five are
pt2_numpos:	ds	1	; number of positions     kept together,
pt2_pat:	ds	1	; current pattern number  in this order,
pt2_row:	ds	1	; row within the pattern  for display)
pt2_delay:	ds	1	; frames per row
pt2_delay_cnt:	ds	1	; frames until the next row
pt2_mixer:	ds	1	; mixer value being assembled
pt2_gl:		ds	1	; non-zero if the row being read slides
pt2_frames:	ds	3	; pt2_length: frames counted
pt2_loops:	ds	1	; times the end of the song was reached
pt2_vars_end:
pt2_rows:	ds	3	; length: rows counted
pt2_rowlim:	ds	3	; bytes left in this pattern row

; pt2_ptr: HL = address of a 16 bit offset. Out: HL = module address +
; that offset. Preserves BC.
pt2_ptr:
	ld	e,(hl)
	inc	hl
	ld	d,(hl)
	ld	hl,0
	ld	l,e
	ld	h,d
	ld	de,(pt2_base)
	add	hl,de
	ret

pt2_init:
	ld	(pt2_base),hl
	push	hl
	ld	hl,PT2_POSLIST		; too short for a header?
	or	a
	sbc	hl,bc
	pop	hl
	ccf
	ret	c
	inc	hl
	ld	a,(hl)			; no positions?
	or	a
	scf
	ret	z
	push	bc
	ld	de,PT2_PATPTR-1
	add	hl,de
	ld	e,(hl)
	inc	hl
	ld	d,(hl)
	ld	hl,0
	ld	l,e
	ld	h,d
	pop	bc
	or	a
	sbc	hl,bc			; pattern table beyond the end?
	ccf
	ret	c
	ld	hl,pt2_vars
	ld	de,pt2_vars+1
	ld	bc,pt2_vars_end-pt2_vars-1
	ld	(hl),0
	ldir
	ld	hl,ay_regs
	ld	b,13
@regs:
	ld	(hl),0
	inc	hl
	djnz	@regs
	ld	(hl),0FFh
	ld	hl,(pt2_base)
	ld	a,(hl)
	ld	(pt2_delay),a
	inc	hl
	ld	a,(hl)
	ld	(pt2_numpos),a
	ld	de,PT2_PATPTR-1
	add	hl,de
	call	pt2_ptr
	ld	(pt2_patptr),hl
	ld	a,1
	ld	(pt2_delay_cnt),a
	ld	ix,pt2_chA
	call	@chinit
	ld	ix,pt2_chB
	call	@chinit
	ld	ix,pt2_chC
	call	@chinit
	xor	a
	call	pt2_setpos
	ld	a,0FFh			; becomes row 0 on the first frame
	ld	(pt2_row),a
	or	a
	ret
@chinit:
	xor	a			; ornament 0 and sample 1, as zxtune
	call	pt2_setorn		; starts a channel: a note played
	ld	a,1			; before a sample is chosen then
	call	pt2_setsam		; sounds as it does there
	ld	(ix+P2_VOL),15
	ret

; pt2_setpos: point the channels at the pattern for position A.
pt2_setpos:
	ld	(pt2_pos),a
	ld	hl,0
	ld	l,a
	ld	de,PT2_POSLIST
	add	hl,de
	ld	de,(pt2_base)
	add	hl,de
	ld	a,(hl)
	ld	(pt2_pat),a
	ld	hl,0
	ld	l,a
	push	hl
	pop	de
	add	hl,hl
	add	hl,de
	add	hl,hl			; pattern * 6
	ld	de,(pt2_patptr)
	add	hl,de
	ld	ix,pt2_chA
	call	@addr
	ld	ix,pt2_chB
	call	@addr
	ld	ix,pt2_chC
@addr:
	push	hl
	call	pt2_ptr
	ld	(ix+P2_ADDR),hl
	pop	hl
	inc	hl
	inc	hl
	ret

; pt2_setorn / pt2_setsam: select ornament or sample A for the channel
; at IX. Preserves HL and BC.
pt2_setorn:
	push	hl
	ld	(ix+P2_ORNNUM),a
	ld	hl,0
	ld	l,a
	add	hl,hl
	ld	de,PT2_ORNPTRS
	add	hl,de
	ld	de,(pt2_base)
	add	hl,de
	call	pt2_ptr
	ld	a,(hl)
	ld	(ix+P2_ORNLEN),a
	inc	hl
	ld	a,(hl)
	ld	(ix+P2_ORNLOOP),a
	inc	hl
	ld	(ix+P2_ORNPTR),hl
	pop	hl
	ret
pt2_setsam:
	push	hl
	ld	(ix+P2_SAMNUM),a
	ld	hl,0
	ld	l,a
	add	hl,hl
	ld	de,PT2_SAMPTRS
	add	hl,de
	ld	de,(pt2_base)
	add	hl,de
	call	pt2_ptr
	ld	a,(hl)
	ld	(ix+P2_SAMLEN),a
	inc	hl
	ld	a,(hl)
	ld	(ix+P2_SAMLOOP),a
	inc	hl
	ld	(ix+P2_SAMPTR),hl
	pop	hl
	ret

; pt2_freq: HL = tone period of note A. Preserves BC, DE.
pt2_freq:
	push	de
	ld	hl,0
	ld	l,a
	add	hl,hl
	ld	de,pt2_notes
	add	hl,de
	ld	e,(hl)
	inc	hl
	ld	d,(hl)
	ld	hl,0
	ld	l,e
	ld	h,d
	pop	de
	ret

; pt2_interp: read one row of pattern data for the channel at IX.
pt2_interp:
	xor	a
	ld	(pt2_gl),a		; set if this row starts a slide
	ld	hl,(ix+P2_ADDR)
	push	hl			; (bytes read in this row: see @loop)
	ld	hl,0
	ld	(pt2_rowlim),hl
	pop	hl
@loop:
	push	hl			; a damaged pattern: give up on the
	ld	hl,(pt2_rowlim)	; row after 65536 bytes
	dec	hl
	ld	(pt2_rowlim),hl
	ld	a,h
	or	l
	pop	hl
	jp	z,@quit
	ld	a,(hl)
	cp	0E1h
	jp	nc,@sample
	cp	0E0h
	jp	z,@off
	cp	080h
	jp	nc,@note
	cp	07Fh
	jp	z,@envoff
	cp	071h
	jp	nc,@env
	cp	070h
	jp	z,@quit
	cp	060h
	jp	nc,@orn
	cp	020h
	jp	nc,@skip
	cp	010h
	jp	nc,@vol
	cp	00Fh
	jp	z,@speed
	cp	00Eh
	jp	z,@slide
	cp	00Dh
	jp	z,@porta
	cp	00Ch
	jp	z,@slideoff
	inc	hl			; 00h-0Bh: noise offset
	ld	a,(hl)
	ld	(ix+P2_NOISEADD),a
@next:
	inc	hl
	jr	@loop
@sample:
	sub	0E0h
	call	pt2_setsam
	jr	@next
@off:
	xor	a
	ld	(ix+P2_SAMPOS),a
	ld	(ix+P2_ORNPOS),a
	ld	(ix+P2_TSLIDE),a
	ld	(ix+P2_TSLIDE+1),a
	ld	(ix+P2_GLTYPE),a
	ld	(ix+P2_ENABLED),a
	jp	@quit
@note:
	sub	080h
	ld	c,a
	xor	a
	ld	(ix+P2_SAMPOS),a
	ld	(ix+P2_ORNPOS),a
	ld	(ix+P2_TSLIDE),a
	ld	(ix+P2_TSLIDE+1),a
	ld	a,(pt2_gl)
	or	a
	jr	z,@plain
	ld	(ix+P2_SLIDETO),c	; a slide: this note is where it ends
	ld	a,(ix+P2_GLTYPE)
	cp	1
	jr	nz,@sounding
	ld	(ix+P2_NOTE),c
	jr	@sounding
@plain:
	ld	(ix+P2_NOTE),c
	ld	(ix+P2_GLTYPE),0
@sounding:
	ld	(ix+P2_ENABLED),1
	jr	@quit
@envoff:
	ld	(ix+P2_ENV),0
	jr	@next
@env:
	sub	070h
	ld	(ay_regs+13),a
	ld	(ix+P2_ENV),1
	inc	hl
	ld	a,(hl)
	ld	(ay_regs+11),a
	inc	hl
	ld	a,(hl)
	ld	(ay_regs+12),a
	jr	@next
@orn:
	sub	060h
	call	pt2_setorn
	ld	(ix+P2_ORNPOS),0
	jr	@next
@skip:
	sub	020h
	ld	(ix+P2_SKIPN),a
	jp	@next
@vol:
	sub	010h
	ld	(ix+P2_VOL),a
	jp	@next
@speed:
	inc	hl
	ld	a,(hl)
	ld	(pt2_delay),a
	jp	@next
@slide:
	inc	hl
	ld	a,(hl)
	ld	(ix+P2_GLISS),a
	ld	(ix+P2_GLTYPE),1
	ld	a,1
	ld	(pt2_gl),a
	jp	@next
@porta:
	inc	hl
	ld	a,(hl)			; the step, used as a magnitude
	or	a
	jp	p,@ppos
	neg
@ppos:
	ld	(ix+P2_GLISS),a
	inc	hl			; two bytes that are not used
	inc	hl
	ld	(ix+P2_GLTYPE),2
	ld	a,1
	ld	(pt2_gl),a
	jp	@next
@slideoff:
	ld	(ix+P2_GLTYPE),0
	jp	@next
@quit:
	inc	hl
	ld	(ix+P2_ADDR),hl
	; a slide to a note: how far, which way?
	ld	a,(pt2_gl)
	or	a
	jr	z,@fin
	ld	a,(ix+P2_GLTYPE)
	cp	2
	jr	nz,@fin
	ld	a,(ix+P2_NOTE)
	call	pt2_freq
	ex	de,hl
	ld	a,(ix+P2_SLIDETO)
	call	pt2_freq
	or	a
	sbc	hl,de
	jp	p,@dpos
	ex	de,hl
	ld	hl,0
	or	a
	sbc	hl,de
@dpos:
	ld	(ix+P2_TDELTA),l
	ld	(ix+P2_TDELTA+1),h
	ld	a,(ix+P2_NOTE)
	cp	(ix+P2_SLIDETO)
	jr	nc,@fin
	xor	a			; sliding up in pitch: the period falls
	sub	(ix+P2_GLISS)
	ld	(ix+P2_GLISS),a
@fin:
	ld	a,(ix+P2_SKIPN)
	ld	(ix+P2_SKIPCNT),a
	ret

; pt2_chreg: work out this frame's tone and amplitude for the channel at
; IX and add its bits to the mixer.
pt2_chreg:
	ld	a,(ix+P2_ENABLED)
	or	a
	jp	z,@silent
	ld	hl,0			; the 3 byte sample step
	ld	l,(ix+P2_SAMPOS)
	push	hl
	pop	de
	add	hl,hl
	add	hl,de
	ld	de,(ix+P2_SAMPTR)
	add	hl,de
	ld	b,(hl)			; B = noise period, tone sign, masks
	inc	hl
	ld	c,(hl)			; C = amplitude, top of tone offset
	inc	hl
	ld	e,(hl)
	ld	a,c
	and	15
	ld	d,a
	ld	hl,0
	ld	l,e
	ld	h,d			; HL = tone offset
	bit	2,b
	jr	nz,@plus
	ex	de,hl
	ld	hl,0
	or	a
	sbc	hl,de
@plus:
	push	hl
	ld	hl,0			; note + ornament
	ld	l,(ix+P2_ORNPOS)
	ld	de,(ix+P2_ORNPTR)
	add	hl,de
	ld	a,(ix+P2_NOTE)
	add	a,(hl)
	cp	96
	jr	c,@inrange
	ld	a,95
@inrange:
	call	pt2_freq
	pop	de
	add	hl,de
	ld	e,(ix+P2_TSLIDE)	; + the slide (only the low 16 bits
	ld	d,(ix+P2_TSLIDE+1)	; of the sum count)
	add	hl,de
	ld	(ix+P2_TON),l
	ld	a,h
	and	0Fh
	ld	(ix+P2_TON+1),a

	ld	a,(ix+P2_GLTYPE)	; a slide to a note stops on arrival
	cp	2
	jr	nz,@slide
	ld	a,(ix+P2_GLISS)
	or	a
	jp	p,@gpos
	neg
@gpos:
	ld	de,0
	ld	e,a
	ld	l,(ix+P2_TDELTA)
	ld	h,(ix+P2_TDELTA+1)
	or	a
	sbc	hl,de
	ld	(ix+P2_TDELTA),l
	ld	(ix+P2_TDELTA+1),h
	bit	7,h			; (16 bit sign)
	jr	z,@slide
	ld	a,(ix+P2_SLIDETO)
	ld	(ix+P2_NOTE),a
	ld	(ix+P2_GLTYPE),0
	ld	(ix+P2_TSLIDE),0
	ld	(ix+P2_TSLIDE+1),0
@slide:
	ld	a,(ix+P2_GLTYPE)
	or	a
	jr	z,@amp
	ld	a,(ix+P2_GLISS)		; 16 bit slide += step, sign extended
	ld	e,a
	rla
	sbc	a,a
	ld	d,a
	ld	l,(ix+P2_TSLIDE)
	ld	h,(ix+P2_TSLIDE+1)
	add	hl,de
	ld	(ix+P2_TSLIDE),l
	ld	(ix+P2_TSLIDE+1),h
@amp:
	; amplitude = (volume * 17 + (1 if volume > 7)) * level / 256
	ld	a,(ix+P2_VOL)
	ld	e,a
	add	a,a
	add	a,a
	add	a,a
	add	a,a
	add	a,e
	ld	hl,0
	ld	l,a
	ld	a,e
	cp	8
	jr	c,@nocarry
	inc	hl
@nocarry:
	ex	de,hl
	ld	hl,0
	ld	a,c
	rrca
	rrca
	rrca
	rrca
	and	15
	jr	z,@mulled
@mul:
	add	hl,de
	dec	a
	jr	nz,@mul
@mulled:
	ld	a,h
	bit	0,(ix+P2_ENV)
	jr	z,@noenv
	or	16
@noenv:
	ld	(ix+P2_AMP),a
	ld	hl,pt2_mixer
	bit	0,b
	jr	z,@noise
	set	6,(hl)			; noise off for this channel
	jr	@tone
@noise:
	ld	a,b
	rrca
	rrca
	rrca
	and	1Fh
	add	a,(ix+P2_NOISEADD)
	and	31
	ld	(ay_regs+6),a
@tone:
	bit	1,b
	jr	z,@step
	set	3,(hl)			; tone off for this channel
@step:
	ld	a,(ix+P2_SAMPOS)	; step through sample and ornament
	inc	a
	cp	(ix+P2_SAMLEN)
	jr	nz,@samok
	ld	a,(ix+P2_SAMLOOP)
@samok:
	ld	(ix+P2_SAMPOS),a
	ld	a,(ix+P2_ORNPOS)
	inc	a
	cp	(ix+P2_ORNLEN)
	jr	nz,@ornok
	ld	a,(ix+P2_ORNLOOP)
@ornok:
	ld	(ix+P2_ORNPOS),a
	jr	@done
@silent:
	ld	(ix+P2_AMP),0
@done:
	ld	hl,pt2_mixer
	srl	(hl)
	ret

; pt2_play: advance the song by one frame and fill ay_regs.
pt2_play:
	ld	a,0FFh
	ld	(ay_regs+13),a
	ld	hl,pt2_delay_cnt
	dec	(hl)
	call	z,pt2_rowtick
	xor	a
	ld	(pt2_mixer),a
	ld	ix,pt2_chA
	call	pt2_chreg
	ld	ix,pt2_chB
	call	pt2_chreg
	ld	ix,pt2_chC
	call	pt2_chreg
	ld	a,(pt2_mixer)
	ld	(ay_regs+7),a
	ld	hl,(pt2_chA+P2_TON)
	ld	(ay_regs+0),hl
	ld	hl,(pt2_chB+P2_TON)
	ld	(ay_regs+2),hl
	ld	hl,(pt2_chC+P2_TON)
	ld	a,l
	ld	(ay_regs+4),a
	ld	a,h
	ld	(ay_regs+5),a
	ld	a,(pt2_chA+P2_AMP)
	ld	(ay_regs+8),a
	ld	a,(pt2_chB+P2_AMP)
	ld	(ay_regs+9),a
	ld	a,(pt2_chC+P2_AMP)
	ld	(ay_regs+10),a
	ret

; pt2_rowtick: the work done once per row: read the next row for each
; channel whose turn it is, moving to the next pattern when one ends.
pt2_rowtick:
	ld	hl,pt2_row
	inc	(hl)
	ld	ix,pt2_chA
	dec	(ix+P2_SKIPCNT)
	jp	p,@chb
	ld	hl,(ix+P2_ADDR)
	ld	a,(hl)
	or	a			; 0 in channel A ends the pattern
	jr	nz,@cha
	ld	a,(pt2_numpos)
	ld	b,a
	ld	a,(pt2_pos)
	inc	a
	cp	b
	jr	nz,@newpos
	ld	hl,pt2_loops		; end of song: note it and loop
	inc	(hl)
	ld	hl,(pt2_base)
	inc	hl
	inc	hl
	ld	a,(hl)
@newpos:
	call	pt2_setpos
	xor	a
	ld	(pt2_row),a
	ld	ix,pt2_chA
@cha:
	call	pt2_interp
@chb:
	ld	ix,pt2_chB
	dec	(ix+P2_SKIPCNT)
	call	m,pt2_interp
	ld	ix,pt2_chC
	dec	(ix+P2_SKIPCNT)
	call	m,pt2_interp
	ld	a,(pt2_delay)
	ld	(pt2_delay_cnt),a
	ret

; pt2_length: how many frames the song lasts before it ends. Call it
; straight after pt2_init, and call pt2_init again afterwards, because
; it works by running through all the song's rows (without the per-frame
; work, so it is quick). Out: HL = frames.
pt2_length:
	ld	hl,0
	ld	(pt2_frames),hl
	ld	(pt2_rows),hl	; (rows counted)
@row:
	call	pt2_rowtick
	ld	hl,(pt2_rows)		; give up after 65536 rows, which no
	inc	hl			; real song needs (a damaged one that
	ld	(pt2_rows),hl		; never ends)
	ld	a,(pt2_rows+2)
	or	a
	jp	nz,@done
	ld	a,(pt2_loops)
	or	a
	jr	nz,@done
	ld	de,0
	ld	a,(pt2_delay)
	ld	e,a
	or	a
	jr	nz,@add
	inc	d			; a speed of 0 lasts 256 frames
@add:
	ld	hl,(pt2_frames)
	add	hl,de
	ld	(pt2_frames),hl
	ld	a,(pt2_frames+2)	; give up on a song that never ends
	cp	10h			; (about 5 hours)
	jr	c,@row
@done:
	ld	hl,(pt2_frames)
	ret

; The note table: 96 AY tone periods.
pt2_notes:
	dw	00EF8h,00E10h,00D60h,00C80h,00BD8h,00B28h,00A88h,009F0h,00960h,008E0h,00858h,007E0h
	dw	0077Ch,00708h,006B0h,00640h,005ECh,00594h,00544h,004F8h,004B0h,00470h,0042Ch,003FDh
	dw	003BEh,00384h,00358h,00320h,002F6h,002CAh,002A2h,0027Ch,00258h,00238h,00216h,001F8h
	dw	001DFh,001C2h,001ACh,00190h,0017Bh,00165h,00151h,0013Eh,0012Ch,0011Ch,0010Ah,000FCh
	dw	000EFh,000E1h,000D6h,000C8h,000BDh,000B2h,000A8h,0009Fh,00096h,0008Eh,00085h,0007Eh
	dw	00077h,00070h,0006Bh,00064h,0005Eh,00059h,00054h,0004Fh,0004Bh,00047h,00042h,0003Fh
	dw	0003Bh,00038h,00035h,00032h,0002Fh,0002Ch,0002Ah,00027h,00025h,00023h,00021h,0001Fh
	dw	0001Dh,0001Ch,0001Ah,00019h,00017h,00016h,00015h,00013h,00012h,00011h,00010h,0000Fh