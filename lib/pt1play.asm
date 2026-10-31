; pt1play.asm - Pro Tracker 1 (.pt1) module replayer.
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
; Tracker 1.x module held in memory into AY-3-8912 register values, one
; set per 50 Hz frame, in the table ay_regs (which ayvdp.asm defines and
; plays). It needs nothing else from the library.
;
; Written for the eZ80 in ADL mode. I found no written description of
; this format to work from: the behaviour was taken from reading the
; source of an existing player, PT1Play.h of the ESP32AY project, and
; this code was then written to do the same. No code was copied.
;
; The module: speed, number of positions, loop position; 16 sample
; pointers, 16 ornament pointers, the pattern table pointer, a 30
; character name, then the position list (pattern numbers). A sample is
; a length, a loop position and 3 byte steps; an ornament is a run of
; note offsets, stepped through together with the sample. Pattern
; streams hold:
;   00h-5Fh  note; ends the row         60h-6Fh  select sample
;   70h-7Fh  select ornament            80h      sound off; ends the row
;   81h      envelope off
;   82h-8Fh  envelope shape, then its period (2 bytes)
;   90h      nothing; ends the row      91h-A0h  speed
;   A1h-B0h  volume                     B1h-FEh  rows to leave empty
;   FFh at a row start: end of the pattern
;
; Entry points:
;   pt1_init   HL = address of the module, BC = its length. Returns with
;              carry set if it cannot be a PT1 module (the format has no
;              signature; only the header is checked for sense).
;   pt1_play   advance one frame and fill ay_regs
;   pt1_length frames the song lasts (see the routine for how to use it)
;
; Results:
;   ay_regs    R13 is 0FFh on frames where the shape was not written.
;   pt1_loops  goes up by one each time the song ends and loops.
;   pt1_pos, pt1_numpos, pt1_pat, pt1_row, pt1_delay (in that order in
;   memory) and the first four bytes of pt1_chA/B/C (note, sample,
;   ornament, sounding) can be read for display.
;
; All registers are used.

; Per-channel state, addressed through IX.
P1_NOTE:	equ	0	; 1: note number
P1_SAMNUM:	equ	1	; 1: sample number (for display)
P1_ORNNUM:	equ	2	; 1: ornament number (for display)
P1_ENABLED:	equ	3	; 1: non-zero if the channel is sounding
P1_ADDR:	equ	4	; 3: address of next byte of pattern data
P1_ORNPTR:	equ	7	; 3: address of the ornament's offsets
P1_SAMPTR:	equ	10	; 3: address of the sample's steps
P1_TON:		equ	13	; 3: tone period sent to the AY
P1_SKIPN:	equ	16	; 1: empty rows after each row
P1_VOL:		equ	17	; 1: channel volume, 0 to 15
P1_SAMLOOP:	equ	18	; 1
P1_SAMPOS:	equ	19	; 1
P1_SAMLEN:	equ	20	; 1
P1_AMP:		equ	21	; 1: amplitude sent to the AY
P1_SKIPCNT:	equ	22	; 1: rows left before the next one (signed)
P1_ENV:		equ	23	; 1: non-zero if the envelope is in use
P1_SIZE:	equ	24

PT1_SAMPTRS:	equ	3	; header: 16 sample pointers
PT1_ORNPTRS:	equ	35	; header: 16 ornament pointers
PT1_PATPTR:	equ	67	; header: pattern table pointer
PT1_NAME:	equ	69	; header: 30 character name
PT1_POSLIST:	equ	99	; header: position list

pt1_base:	ds	3	; address of the module
pt1_patptr:	ds	3	; address of the pattern table
; Everything from here to pt1_vars_end is cleared by pt1_init.
pt1_vars:
pt1_chA:	ds	P1_SIZE
pt1_chB:	ds	P1_SIZE
pt1_chC:	ds	P1_SIZE
		ds	2	; spill room for 24 bit loads
pt1_pos:	ds	1	; current position       (these five are
pt1_numpos:	ds	1	; number of positions     kept together,
pt1_pat:	ds	1	; current pattern number  in this order,
pt1_row:	ds	1	; row within the pattern  for display)
pt1_delay:	ds	1	; frames per row
pt1_delay_cnt:	ds	1	; frames until the next row
pt1_mixer:	ds	1	; mixer value being assembled
pt1_j:		ds	1	; note being played, with its ornament
pt1_frames:	ds	3	; pt1_length: frames counted
pt1_loops:	ds	1	; times the end of the song was reached
pt1_vars_end:
pt1_rows:	ds	3	; length: rows counted
pt1_rowlim:	ds	3	; bytes left in this pattern row

; pt1_ptr: HL = address of a 16 bit offset. Out: HL = module address +
; that offset. Preserves BC.
pt1_ptr:
	ld	e,(hl)
	inc	hl
	ld	d,(hl)
	ld	hl,0
	ld	l,e
	ld	h,d
	ld	de,(pt1_base)
	add	hl,de
	ret

pt1_init:
	ld	(pt1_base),hl
	push	hl
	ld	hl,PT1_POSLIST		; too short for a header?
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
	ld	de,PT1_PATPTR-1
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
	ld	hl,pt1_vars
	ld	de,pt1_vars+1
	ld	bc,pt1_vars_end-pt1_vars-1
	ld	(hl),0
	ldir
	ld	hl,ay_regs
	ld	b,13
@regs:
	ld	(hl),0
	inc	hl
	djnz	@regs
	ld	(hl),0FFh
	ld	hl,(pt1_base)
	ld	a,(hl)
	ld	(pt1_delay),a
	inc	hl
	ld	a,(hl)
	ld	(pt1_numpos),a
	ld	de,PT1_PATPTR-1
	add	hl,de
	call	pt1_ptr
	ld	(pt1_patptr),hl
	ld	a,1
	ld	(pt1_delay_cnt),a
	ld	ix,pt1_chA
	call	@chinit
	ld	ix,pt1_chB
	call	@chinit
	ld	ix,pt1_chC
	call	@chinit
	xor	a
	call	pt1_setpos
	ld	a,0FFh			; becomes row 0 on the first frame
	ld	(pt1_row),a
	or	a
	ret
@chinit:
	xor	a
	call	pt1_setorn
	ld	hl,(pt1_base)
	ld	(ix+P1_SAMPTR),hl
	ld	(ix+P1_VOL),15
	ret

; pt1_setpos: point the channels at the pattern for position A.
pt1_setpos:
	ld	(pt1_pos),a
	ld	hl,0
	ld	l,a
	ld	de,PT1_POSLIST
	add	hl,de
	ld	de,(pt1_base)
	add	hl,de
	ld	a,(hl)
	ld	(pt1_pat),a
	ld	hl,0
	ld	l,a
	push	hl
	pop	de
	add	hl,hl
	add	hl,de
	add	hl,hl			; pattern * 6
	ld	de,(pt1_patptr)
	add	hl,de
	ld	ix,pt1_chA
	call	@addr
	ld	ix,pt1_chB
	call	@addr
	ld	ix,pt1_chC
@addr:
	push	hl
	call	pt1_ptr
	ld	(ix+P1_ADDR),hl
	pop	hl
	inc	hl
	inc	hl
	ret

; pt1_setorn / pt1_setsam: select ornament or sample A for the channel
; at IX. Preserves HL and BC.
pt1_setorn:
	push	hl
	ld	(ix+P1_ORNNUM),a
	ld	hl,0
	ld	l,a
	add	hl,hl
	ld	de,PT1_ORNPTRS
	add	hl,de
	ld	de,(pt1_base)
	add	hl,de
	call	pt1_ptr
	ld	(ix+P1_ORNPTR),hl
	pop	hl
	ret
pt1_setsam:
	push	hl
	ld	(ix+P1_SAMNUM),a
	ld	hl,0
	ld	l,a
	add	hl,hl
	ld	de,PT1_SAMPTRS
	add	hl,de
	ld	de,(pt1_base)
	add	hl,de
	call	pt1_ptr
	ld	a,(hl)
	ld	(ix+P1_SAMLEN),a
	inc	hl
	ld	a,(hl)
	ld	(ix+P1_SAMLOOP),a
	inc	hl
	ld	(ix+P1_SAMPTR),hl
	pop	hl
	ret

; pt1_interp: read one row of pattern data for the channel at IX.
pt1_interp:
	ld	hl,(ix+P1_ADDR)
	push	hl			; (bytes read in this row: see @loop)
	ld	hl,0
	ld	(pt1_rowlim),hl
	pop	hl
@loop:
	push	hl			; a damaged pattern: give up on the
	ld	hl,(pt1_rowlim)	; row after 65536 bytes
	dec	hl
	ld	(pt1_rowlim),hl
	ld	a,h
	or	l
	pop	hl
	jp	z,@quit
	ld	a,(hl)
	cp	060h
	jr	c,@note
	cp	070h
	jr	c,@sample
	cp	080h
	jr	c,@orn
	jr	z,@off
	cp	081h
	jr	z,@envoff
	cp	090h
	jr	c,@env
	jr	z,@quit
	cp	0A1h
	jr	c,@speed
	cp	0B1h
	jr	c,@vol
	sub	0B1h
	ld	(ix+P1_SKIPN),a
@next:
	inc	hl
	jr	@loop
@note:
	ld	(ix+P1_NOTE),a
	ld	(ix+P1_ENABLED),1
	ld	(ix+P1_SAMPOS),0
	jr	@quit
@sample:
	sub	060h
	call	pt1_setsam
	jr	@next
@orn:
	sub	070h
	call	pt1_setorn
	jr	@next
@off:
	ld	(ix+P1_ENABLED),0
	jr	@quit
@envoff:
	ld	(ix+P1_ENV),0
	jr	@next
@env:
	sub	081h
	ld	(ay_regs+13),a
	ld	(ix+P1_ENV),1
	inc	hl
	ld	a,(hl)
	ld	(ay_regs+11),a
	inc	hl
	ld	a,(hl)
	ld	(ay_regs+12),a
	jr	@next
@speed:
	sub	091h
	ld	(pt1_delay),a
	jr	@next
@vol:
	sub	0A1h
	ld	(ix+P1_VOL),a
	jr	@next
@quit:
	inc	hl
	ld	(ix+P1_ADDR),hl
	ld	a,(ix+P1_SKIPN)
	ld	(ix+P1_SKIPCNT),a
	ret

; pt1_chreg: work out this frame's tone and amplitude for the channel at
; IX and add its bits to the mixer.
pt1_chreg:
	ld	a,(ix+P1_ENABLED)
	or	a
	jp	z,@silent
	ld	hl,0			; note + ornament
	ld	l,(ix+P1_SAMPOS)
	ld	de,(ix+P1_ORNPTR)
	add	hl,de
	ld	a,(ix+P1_NOTE)
	add	a,(hl)
	cp	96
	jr	c,@inrange
	ld	a,95
@inrange:
	ld	(pt1_j),a
	ld	hl,0			; the 3 byte sample step
	ld	l,(ix+P1_SAMPOS)
	push	hl
	pop	de
	add	hl,hl
	add	hl,de
	ld	de,(ix+P1_SAMPTR)
	add	hl,de
	ld	b,(hl)			; B = top of tone offset, amplitude
	inc	hl
	ld	c,(hl)			; C = masks, tone sign, noise period
	inc	hl
	ld	e,(hl)
	ld	a,b
	rrca
	rrca
	rrca
	rrca
	and	0Fh
	ld	d,a
	ld	hl,0
	ld	l,e
	ld	h,d			; HL = tone offset
	bit	5,c
	jr	nz,@plus
	ex	de,hl
	ld	hl,0
	or	a
	sbc	hl,de
@plus:
	push	hl
	ld	a,(pt1_j)
	ld	hl,0
	ld	l,a
	add	hl,hl
	ld	de,pt1_notes
	add	hl,de
	ld	e,(hl)
	inc	hl
	ld	d,(hl)
	ld	hl,0
	ld	l,e
	ld	h,d
	pop	de
	add	hl,de
	ld	(ix+P1_TON),l
	ld	a,h
	and	0Fh
	ld	(ix+P1_TON+1),a
	; amplitude = (volume * 17 + (1 if volume > 7)) * level / 256
	ld	a,(ix+P1_VOL)
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
	ld	a,b
	and	15
	jr	z,@mulled
@mul:
	add	hl,de
	dec	a
	jr	nz,@mul
@mulled:
	ld	a,h
	bit	0,(ix+P1_ENV)
	jr	z,@noenv
	or	16
@noenv:
	ld	(ix+P1_AMP),a
	ld	hl,pt1_mixer
	bit	7,c
	jr	z,@noise
	set	6,(hl)			; noise off for this channel
	jr	@tone
@noise:
	ld	a,c
	and	31
	ld	(ay_regs+6),a
@tone:
	bit	6,c
	jr	z,@step
	set	3,(hl)			; tone off for this channel
@step:
	ld	a,(ix+P1_SAMPOS)
	inc	a
	cp	(ix+P1_SAMLEN)
	jr	nz,@samok
	ld	a,(ix+P1_SAMLOOP)
@samok:
	ld	(ix+P1_SAMPOS),a
	jr	@done
@silent:
	ld	(ix+P1_AMP),0
@done:
	ld	hl,pt1_mixer
	srl	(hl)
	ret

; pt1_play: advance the song by one frame and fill ay_regs.
pt1_play:
	ld	a,0FFh
	ld	(ay_regs+13),a
	ld	hl,pt1_delay_cnt
	dec	(hl)
	call	z,pt1_rowtick
	xor	a
	ld	(pt1_mixer),a
	ld	ix,pt1_chA
	call	pt1_chreg
	ld	ix,pt1_chB
	call	pt1_chreg
	ld	ix,pt1_chC
	call	pt1_chreg
	ld	a,(pt1_mixer)
	ld	(ay_regs+7),a
	ld	hl,(pt1_chA+P1_TON)
	ld	(ay_regs+0),hl
	ld	hl,(pt1_chB+P1_TON)
	ld	(ay_regs+2),hl
	ld	hl,(pt1_chC+P1_TON)
	ld	a,l
	ld	(ay_regs+4),a
	ld	a,h
	ld	(ay_regs+5),a
	ld	a,(pt1_chA+P1_AMP)
	ld	(ay_regs+8),a
	ld	a,(pt1_chB+P1_AMP)
	ld	(ay_regs+9),a
	ld	a,(pt1_chC+P1_AMP)
	ld	(ay_regs+10),a
	ret

; pt1_rowtick: the work done once per row: read the next row for each
; channel whose turn it is, moving to the next pattern when one ends.
pt1_rowtick:
	ld	hl,pt1_row
	inc	(hl)
	ld	ix,pt1_chA
	dec	(ix+P1_SKIPCNT)
	jp	p,@chb
	ld	hl,(ix+P1_ADDR)
	ld	a,(hl)
	inc	a			; 0FFh in channel A ends the pattern
	jr	nz,@cha
	ld	a,(pt1_numpos)
	ld	b,a
	ld	a,(pt1_pos)
	inc	a
	cp	b
	jr	nz,@newpos
	ld	hl,pt1_loops		; end of song: note it and loop
	inc	(hl)
	ld	hl,(pt1_base)
	inc	hl
	inc	hl
	ld	a,(hl)
@newpos:
	call	pt1_setpos
	xor	a
	ld	(pt1_row),a
	ld	ix,pt1_chA
@cha:
	call	pt1_interp
@chb:
	ld	ix,pt1_chB
	dec	(ix+P1_SKIPCNT)
	call	m,pt1_interp
	ld	ix,pt1_chC
	dec	(ix+P1_SKIPCNT)
	call	m,pt1_interp
	ld	a,(pt1_delay)
	ld	(pt1_delay_cnt),a
	ret

; pt1_length: how many frames the song lasts before it ends. Call it
; straight after pt1_init, and call pt1_init again afterwards, because
; it works by running through all the song's rows (without the per-frame
; work, so it is quick). Out: HL = frames.
pt1_length:
	ld	hl,0
	ld	(pt1_frames),hl
	ld	(pt1_rows),hl	; (rows counted)
@row:
	call	pt1_rowtick
	ld	hl,(pt1_rows)		; give up after 65536 rows, which no
	inc	hl			; real song needs (a damaged one that
	ld	(pt1_rows),hl		; never ends)
	ld	a,(pt1_rows+2)
	or	a
	jp	nz,@done
	ld	a,(pt1_loops)
	or	a
	jr	nz,@done
	ld	de,0
	ld	a,(pt1_delay)
	ld	e,a
	or	a
	jr	nz,@add
	inc	d			; a speed of 0 lasts 256 frames
@add:
	ld	hl,(pt1_frames)
	add	hl,de
	ld	(pt1_frames),hl
	ld	a,(pt1_frames+2)	; give up on a song that never ends
	cp	10h			; (about 5 hours)
	jr	c,@row
@done:
	ld	hl,(pt1_frames)
	ret

; The note table: 96 AY tone periods. It is the PT2 table except that
; entry 46 is one higher, as Pro Tracker 1 played that note.
pt1_notes:
	dw	00EF8h,00E10h,00D60h,00C80h,00BD8h,00B28h,00A88h,009F0h,00960h,008E0h,00858h,007E0h
	dw	0077Ch,00708h,006B0h,00640h,005ECh,00594h,00544h,004F8h,004B0h,00470h,0042Ch,003FDh
	dw	003BEh,00384h,00358h,00320h,002F6h,002CAh,002A2h,0027Ch,00258h,00238h,00216h,001F8h
	dw	001DFh,001C2h,001ACh,00190h,0017Bh,00165h,00151h,0013Eh,0012Ch,0011Ch,0010Bh,000FCh
	dw	000EFh,000E1h,000D6h,000C8h,000BDh,000B2h,000A8h,0009Fh,00096h,0008Eh,00085h,0007Eh
	dw	00077h,00070h,0006Bh,00064h,0005Eh,00059h,00054h,0004Fh,0004Bh,00047h,00042h,0003Fh
	dw	0003Bh,00038h,00035h,00032h,0002Fh,0002Ch,0002Ah,00027h,00025h,00023h,00021h,0001Fh
	dw	0001Dh,0001Ch,0001Ah,00019h,00017h,00016h,00015h,00013h,00012h,00011h,00010h,0000Fh