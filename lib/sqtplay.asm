; sqtplay.asm - SQ-Tracker (.sqt) module replayer.
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
; Part of the reusable agonAMP sound library in lib/. It turns an
; SQ-Tracker module held in memory into AY-3-8912 register values, one
; set per 50 Hz frame, in the table ay_regs (which ayvdp.asm defines and
; plays). It needs nothing else from the library.
;
; Written for the eZ80 in ADL mode. I found no written description of
; this format to work from: the behaviour was taken from reading the
; source of an existing player, SQTPlay.h of the ESP32AY project (itself
; a translation of the original Z80 player), and this code was then
; written to do the same. No code was copied. The note table is that
; player's.
;
; The module starts with its size and five pointers: to the sample
; table, the ornament table, the pattern table, the position list and
; the position the song loops to. All the pointers in a module, these
; and the tables' entries, are addresses in the memory of the machine
; it was compiled for; sqt_init converts them to offsets, changing the
; module in memory (doing it twice is harmless).
;
; A position is 7 bytes: for each of channels C, B and A a pattern
; number (bit 7 set lets that channel's volume and speed commands take
; effect) and a byte holding volume and transposition, then the speed.
; A pattern is shared by the three channels of a position only in the
; sense that the first byte of channel C's pattern is the number of
; rows. A zero where a position should start ends the song.
;
; Entry points:
;   sqt_init   HL = address of the module, BC = its length. Returns with
;              carry set if the pointers make no sense.
;   sqt_play   advance one frame and fill ay_regs
;   sqt_length frames the song lasts (call sqt_init again afterwards)
;
; Results:
;   ay_regs    R13 is 0FFh on frames where the shape was not written.
;   sqt_loops  goes up by one each time the song ends and loops.
;   sqt_pos, sqt_numpos, sqt_pat, sqt_row, sqt_delay (in that order in
;   memory) and the first four bytes of sqt_chA/B/C (note, sample,
;   ornament, sounding) can be read for display.
;
; All registers are used.

; Per-channel state, addressed through IX.
SQ_NOTE:	equ	0	; 1: note number
SQ_SAMNUM:	equ	1	; 1: sample number (for display)
SQ_ORNNUM:	equ	2	; 1: ornament number (for display)
SQ_ON:		equ	3	; 1: non-zero if the channel is sounding
SQ_ADDR:	equ	4	; 3: address of next byte of pattern data
SQ_SAMPTR:	equ	7	; 3: address of the sample
SQ_PIS:		equ	10	; 3: address of the current sample step
SQ_ORNPTR:	equ	13	; 3: address of the ornament
SQ_PIO:		equ	16	; 3: address of the current ornament step
SQ_TON:		equ	19	; 3: tone period sent to the AY
SQ_LAST:	equ	22	; 3: address of the last note read, which
				;    "repeat" commands play again
SQ_CTS:		equ	25	; 3: tone slide so far
SQ_STEP:	equ	28	; 3: tone slide per frame
SQ_VOL:		equ	31	; 1: attenuation
SQ_AMP:		equ	32	; 1: amplitude sent to the AY
SQ_WAIT:	equ	33	; 1: rows still to wait or repeat
SQ_STC:		equ	34	; 1: sample steps left before it loops
SQ_OTC:		equ	35	; 1: ornament steps left before it loops
SQ_TRANSP:	equ	36	; 1: transposition (signed)
SQ_ENV:		equ	37	; 1: non-zero if the envelope is in use
SQ_ORNEN:	equ	38	; 1: non-zero if an ornament is in use
SQ_GLISS:	equ	39	; 1: non-zero while sliding
SQ_MIXN:	equ	40	; 1: zero forces noise off
SQ_MIXT:	equ	41	; 1: zero forces tone off
SQ_GLOBAL:	equ	42	; 1: non-zero if volume and speed commands
				;    in this channel take effect
SQ_SETADDR:	equ	43	; 1: non-zero if the pattern address is
				;    still to be moved on for this row
SQ_REPEAT:	equ	44	; 1: non-zero to repeat the last note on
				;    each row of a wait
SQ_SIZE:	equ	45

sqt_base:	ds	3	; address of the module
sqt_len:	ds	3	; its length
sqt_delta:	ds	3	; amount to take off compiled-in addresses
sqt_samptr:	ds	3	; addresses of the tables
sqt_ornptr:	ds	3
sqt_patptr:	ds	3
sqt_posptr:	ds	3
sqt_loopptr:	ds	3	; address of the position the song loops to
sqt_looppos:	ds	1	; and its number
; Everything from here to sqt_vars_end is cleared by sqt_init.
sqt_vars:
sqt_chA:	ds	SQ_SIZE
sqt_chB:	ds	SQ_SIZE
sqt_chC:	ds	SQ_SIZE
		ds	2	; spill room for 24 bit loads
sqt_pos:	ds	1	; current position       (these five are
sqt_numpos:	ds	1	; number of positions     kept together,
sqt_pat:	ds	1	; channel C's pattern     in this order,
sqt_row:	ds	1	; row within the pattern  for display)
sqt_delay:	ds	1	; frames per row
sqt_delay_cnt:	ds	1	; frames until the next row
sqt_lines:	ds	1	; rows left in the pattern
sqt_pp:		ds	3	; address of the next position
sqt_ptr:	ds	3	; address being read in a pattern
sqt_ton:	ds	3	; tone period being worked out
sqt_mixer:	ds	1	; mixer value being assembled
sqt_b2:		ds	1	; sample step: low byte of tone offset
sqt_frames:	ds	3	; sqt_length: frames counted
sqt_loops:	ds	1	; times the end of the song was reached
sqt_vars_end:
sqt_rows:	ds	3	; length: rows counted

; sqt_word: HL = address of a 16 bit value. Out: HL = the value.
sqt_word:
	ld	e,(hl)
	inc	hl
	ld	d,(hl)
	ld	hl,0
	ld	l,e
	ld	h,d
	ret

; sqt_abs: HL = address of a 16 bit offset. Out: HL = module address +
; that offset. Preserves BC.
sqt_abs:
	call	sqt_word
	ld	de,(sqt_base)
	add	hl,de
	ret

sqt_init:
	ld	(sqt_base),hl
	ld	(sqt_len),bc
	push	hl
	ld	hl,12			; too short for a header?
	or	a
	sbc	hl,bc
	pop	hl
	ccf
	ret	c
	; Convert the pointers. The sample table follows the 10 byte
	; header, so its pointer shows where the module was compiled for.
	inc	hl
	inc	hl
	call	sqt_word
	ld	de,10
	or	a
	sbc	hl,de
	ret	c
	ld	(sqt_delta),hl
	ld	a,h
	or	l
	jp	z,@converted		; already done
	ld	hl,(sqt_base)		; find the highest pattern number used
	ld	de,8
	add	hl,de
	call	sqt_word
	ld	de,(sqt_delta)
	or	a
	sbc	hl,de
	ret	c
	call	@inside
	ret	c
	ld	de,(sqt_base)
	add	hl,de			; HL -> position list
	ld	c,0
@scan:
	ld	a,(hl)
	or	a
	jr	z,@scanned
	push	hl			; (stay inside the module)
	ld	de,(sqt_base)
	or	a
	sbc	hl,de
	ld	de,8
	add	hl,de
	call	@inside
	pop	hl
	ret	c
	call	@max
	inc	hl
	inc	hl
	call	@max
	inc	hl
	inc	hl
	call	@max
	inc	hl
	inc	hl
	inc	hl
	jr	@scan
@scanned:
	ld	hl,(sqt_base)		; words to convert: from the header's
	ld	de,6			; first pointer to the entry of that
	add	hl,de			; pattern in the pattern table
	call	sqt_word
	ld	de,(sqt_delta)
	or	a
	sbc	hl,de
	ret	c
	ld	de,0
	ld	e,c
	add	hl,de
	add	hl,de
	inc	hl			; (both bytes of the last word)
	call	@inside
	dec	hl
	ret	c
	srl	h
	rr	l
	ld	a,h
	or	l
	scf
	ret	z
	push	hl
	pop	bc
	push	bc			; first check every word, so that a
	ld	hl,(sqt_base)		; module that is refused is left as
	inc	hl			; it was
	inc	hl
@chk:
	push	bc
	push	hl
	call	sqt_word
	ld	de,(sqt_delta)
	or	a
	sbc	hl,de
	pop	hl
	pop	bc
	jp	c,@chkbad		; an address below the module's start
	inc	hl
	inc	hl
	dec	bc
	ld	a,b
	or	c
	jr	nz,@chk
	pop	bc
	ld	hl,(sqt_base)
	inc	hl
	inc	hl
@fix:
	push	bc
	push	hl
	call	sqt_word
	ld	de,(sqt_delta)
	or	a
	sbc	hl,de
	ex	de,hl
	pop	hl
	pop	bc
	ret	c			; an address below the module's start
	ld	(hl),e
	inc	hl
	ld	(hl),d
	inc	hl
	dec	bc
	ld	a,b
	or	c
	jr	nz,@fix
@converted:
	ld	hl,sqt_vars		; clear the playing state
	ld	de,sqt_vars+1
	ld	bc,sqt_vars_end-sqt_vars-1
	ld	(hl),0
	ldir
	ld	hl,ay_regs
	ld	b,13
@regs:
	ld	(hl),0
	inc	hl
	djnz	@regs
	ld	(hl),0FFh
	ld	a,2			; the five tables as addresses
	call	@table
	ret	c
	ld	(sqt_samptr),hl
	ld	a,4
	call	@table
	ret	c
	ld	(sqt_ornptr),hl
	ld	a,6
	call	@table
	ret	c
	ld	(sqt_patptr),hl
	ld	a,8
	call	@table
	ret	c
	ld	(sqt_posptr),hl
	ld	(sqt_pp),hl
	ld	a,10
	call	@table
	ret	c
	ld	(sqt_loopptr),hl
	ld	de,(sqt_posptr)		; which position that is (it must be
	or	a			; one of them)
	sbc	hl,de
	ret	c
	ld	c,0FFh
	ld	de,7
@lp:
	inc	c
	or	a
	sbc	hl,de
	jr	nc,@lp
	add	hl,de			; (a whole number of positions on)
	ld	a,h
	or	l
	scf
	ret	nz
	ld	a,c
	ld	(sqt_looppos),a
	ld	hl,(sqt_posptr)		; count the positions
	ld	c,0
@count:
	ld	a,(hl)
	or	a
	jr	z,@counted
	inc	c
	jr	z,@counted
	add	hl,de
	jr	@count
@counted:
	ld	a,(sqt_looppos)		; (the loop must be inside the list)
	cp	c
	ccf
	ret	c
	ld	a,c
	ld	(sqt_numpos),a
	ld	a,1
	ld	(sqt_delay),a
	ld	(sqt_delay_cnt),a
	ld	(sqt_lines),a
	ld	a,0FFh
	ld	(sqt_pos),a
	ld	(sqt_row),a
	or	a
	ret
@chkbad:
	pop	bc
	scf
	ret
; C = larger of C and the pattern number
@max:
	ld	a,(hl)			; at (HL)
	and	07Fh
	cp	c
	ret	c
	ld	c,a
	ret
@inside:				; carry if offset HL is not inside the
	push	hl			; module; preserves HL, BC
	ld	de,(sqt_len)
	or	a
	sbc	hl,de
	pop	hl
	ccf
	ret
; HL = address of the table whose offset
@table:
	ld	hl,(sqt_base)		; is at header byte A; carry if outside
	ld	de,0
	ld	e,a
	add	hl,de
	call	sqt_word
	call	@inside
	ld	de,(sqt_base)
	push	af
	add	hl,de
	pop	af
	ret

; sqt_sample: start sample A on the channel at IX (this is also what
; starts a note sounding). Preserves BC.
sqt_sample:
	ld	(ix+SQ_SAMNUM),a
	ld	hl,0
	ld	l,a
	add	hl,hl
	ld	de,(sqt_samptr)
	add	hl,de
	call	sqt_abs
	ld	(ix+SQ_SAMPTR),hl
	inc	hl
	inc	hl
	ld	(ix+SQ_PIS),hl
	xor	a
	ld	(ix+SQ_ENV),a
	ld	(ix+SQ_ORNEN),a
	ld	(ix+SQ_GLISS),a
	inc	a
	ld	(ix+SQ_ON),a
	ld	(ix+SQ_MIXN),a
	ld	(ix+SQ_MIXT),a
	ld	(ix+SQ_STC),32
	ret

; sqt_ornament: start ornament A on the channel at IX. Preserves BC.
sqt_ornament:
	ld	(ix+SQ_ORNNUM),a
	ld	hl,0
	ld	l,a
	add	hl,hl
	ld	de,(sqt_ornptr)
	add	hl,de
	call	sqt_abs
	ld	(ix+SQ_ORNPTR),hl
	inc	hl
	inc	hl
	ld	(ix+SQ_PIO),hl
	ld	(ix+SQ_OTC),32
	ld	(ix+SQ_ORNEN),1
	ret

; sqt_effect: carry out effect number A, whose parameter is the byte
; after the one (sqt_ptr) points at. 1/2 set/change this channel's
; volume, 3/4 all channels' volume, 5/6 set/change the speed, 7/8 slide
; down/up; anything else selects that envelope shape, the parameter
; being its period.
sqt_effect:
	ld	c,a
	ld	hl,(sqt_ptr)
	inc	hl
	ld	(sqt_ptr),hl
	ld	a,(ix+SQ_SETADDR)
	or	a
	jr	z,@which
	push	hl
	inc	hl
	ld	(ix+SQ_ADDR),hl
	pop	hl
	ld	(ix+SQ_SETADDR),0
@which:
	ld	b,(hl)			; the parameter
	ld	a,c
	dec	a
	cp	8
	jp	nc,@envelope
	or	a
	jr	z,@vol
	dec	a
	jr	z,@voladd
	dec	a
	jr	z,@allvol
	dec	a
	jr	z,@alladd
	dec	a
	jr	z,@speed
	dec	a
	jr	z,@speedadd
	dec	a
	jr	z,@down
	ld	hl,0			; slide up in period
	ld	l,b
	jr	@slide
@down:
	ld	de,0
	ld	e,b
	ld	hl,0
	or	a
	sbc	hl,de
@slide:
	ld	(ix+SQ_STEP),hl
	ld	hl,0
	ld	(ix+SQ_CTS),hl
	ld	(ix+SQ_GLISS),1
	ret
@vol:
	ld	a,(ix+SQ_GLOBAL)
	or	a
	ret	z
	ld	a,b
	and	15
	ld	(ix+SQ_VOL),a
	ret
@voladd:
	ld	a,(ix+SQ_GLOBAL)
	or	a
	ret	z
	ld	a,(ix+SQ_VOL)
	add	a,b
	and	15
	ld	(ix+SQ_VOL),a
	ret
@allvol:
	ld	a,(ix+SQ_GLOBAL)
	or	a
	ret	z
	ld	a,b
	ld	(sqt_chA+SQ_VOL),a
	ld	(sqt_chB+SQ_VOL),a
	ld	(sqt_chC+SQ_VOL),a
	ret
@alladd:
	ld	a,(ix+SQ_GLOBAL)
	or	a
	ret	z
	ld	hl,sqt_chA+SQ_VOL
	call	@add15
	ld	hl,sqt_chB+SQ_VOL
	call	@add15
	ld	hl,sqt_chC+SQ_VOL
@add15:
	ld	a,(hl)
	add	a,b
	and	15
	ld	(hl),a
	ret
@speed:
	ld	a,(ix+SQ_GLOBAL)
	or	a
	ret	z
	ld	a,b
	jr	@setspeed
@speedadd:
	ld	a,(ix+SQ_GLOBAL)
	or	a
	ret	z
	ld	a,(sqt_delay_cnt)
	add	a,b
@setspeed:
	and	31
	jr	nz,@speedok
	ld	a,32
@speedok:
	ld	(sqt_delay_cnt),a
	ld	(sqt_delay),a
	ret
@envelope:
	ld	(ix+SQ_ENV),1
	ld	a,c
	dec	a
	and	15
	ld	(ay_regs+13),a
	ld	a,b
	ld	(ay_regs+11),a
	ret

; sqt_after: deal with the byte at (sqt_ptr), which follows a note: an
; effect, or a sample (and perhaps an ornament and an effect too). On
; return (sqt_ptr) is past whatever was used.
sqt_after:
	ld	hl,(sqt_ptr)
	ld	a,(hl)
	bit	7,a
	jr	nz,@sample
	call	sqt_effect
	jr	@end
@sample:
	ld	c,a
	rrca
	and	31
	call	nz,sqt_sample
	bit	6,c
	jr	z,@end
	ld	hl,(sqt_ptr)
	inc	hl
	ld	a,(hl)
	rrca
	rrca
	rrca
	rrca
	and	15
	bit	0,c
	jr	z,@orn
	or	16
@orn:
	or	a
	call	nz,sqt_ornament
	ld	hl,(sqt_ptr)
	inc	hl
	ld	(sqt_ptr),hl
	ld	a,(hl)
	and	15
	call	nz,sqt_effect
@end:
	ld	hl,(sqt_ptr)
	inc	hl
	ld	(sqt_ptr),hl
	ret

; sqt_again: play the last note read once more.
sqt_again:
	ld	hl,(ix+SQ_LAST)
	ld	(sqt_ptr),hl
	ld	(ix+SQ_SETADDR),0
	ld	a,(hl)
	bit	7,a
	jr	nz,@sample
	inc	hl
	ld	(sqt_ptr),hl
	jp	sqt_after
@sample:
	and	31
	jp	sqt_sample

; sqt_interp: read one row of pattern data for the channel at IX.
;   00h-5Fh  note, followed by an effect or a sample byte
;   60h-6Eh  effect on its own
;   6Fh-7Fh  sound off (70h and up: with an effect)
;   80h-9Fh  the last note again, some semitones up or down
;   A0h-BFh  wait a number of rows (B0h and up: repeating the last note)
;   C0h-FFh  sample on its own
sqt_interp:
	ld	a,(ix+SQ_WAIT)
	or	a
	jr	z,@read
	dec	(ix+SQ_WAIT)
	ld	a,(ix+SQ_REPEAT)
	or	a
	ret	z
	jp	sqt_again
@read:
	ld	hl,(ix+SQ_ADDR)
	ld	(sqt_ptr),hl
	ld	(ix+SQ_SETADDR),1
	ld	(ix+SQ_REPEAT),0
	ld	a,(hl)
	cp	060h
	jr	nc,@notnote
	ld	(ix+SQ_NOTE),a
	ld	(ix+SQ_LAST),hl
	inc	hl
	ld	(sqt_ptr),hl
	call	sqt_after
	ld	a,(ix+SQ_SETADDR)
	or	a
	ret	z
	ld	hl,(sqt_ptr)
	ld	(ix+SQ_ADDR),hl
	ret
@notnote:
	cp	06Fh
	jr	nc,@notfx
	sub	060h
	jp	sqt_effect
@notfx:
	cp	080h
	jr	nc,@notoff
	ld	(ix+SQ_MIXN),0
	ld	(ix+SQ_MIXT),0
	ld	(ix+SQ_ON),0
	cp	06Fh
	jr	z,@justoff
	sub	06Fh
	jp	sqt_effect
@justoff:
	inc	hl
	ld	(ix+SQ_ADDR),hl
	ret
@notoff:
	cp	0C0h
	jr	nc,@sample
	inc	hl
	ld	(ix+SQ_ADDR),hl
	ld	c,a
	cp	0A0h
	jr	nc,@wait
	and	15			; the last note, shifted
	ld	b,a
	ld	a,(ix+SQ_NOTE)
	bit	4,c
	jr	nz,@lower
	add	a,b
	jr	@shifted
@lower:
	sub	b
@shifted:
	ld	(ix+SQ_NOTE),a
	jp	sqt_again
@wait:
	and	15
	ld	(ix+SQ_WAIT),a
	bit	4,c
	ret	z
	or	a
	jp	z,sqt_again
	ld	(ix+SQ_REPEAT),1
	jp	sqt_again
@sample:
	ld	(ix+SQ_LAST),hl
	inc	hl
	ld	(ix+SQ_ADDR),hl
	and	31
	jp	sqt_sample

; sqt_chreg: work out this frame's tone and amplitude for the channel at
; IX and add its bits to the mixer. (The mixer is built up with a set
; bit meaning "on" and turned over at the end.)
sqt_chreg:
	ld	hl,sqt_mixer
	sla	(hl)
	ld	a,(ix+SQ_ON)
	or	a
	jr	nz,@on
	ld	(ix+SQ_AMP),0
	ret
@on:
	ld	hl,(ix+SQ_PIS)		; the 3 byte sample step
	ld	b,(hl)			; B = noise period, amplitude
	inc	hl
	ld	c,(hl)			; C = masks, tone sign, top of offset
	inc	hl
	ld	a,(hl)
	ld	(sqt_b2),a
	ld	a,b
	and	15
	jr	z,@zero
	sub	(ix+SQ_VOL)		; (borrow, not sign: the all-channels
	jp	nc,@amp			; volume command does not mask its
	xor	a			; value, so it can be 16 or more)
	jr	@amp
@zero:
	; a silent step lets the envelope through
	ld	a,(ix+SQ_ENV)
	or	a
	jr	z,@amp
	ld	a,16
@amp:
	ld	(ix+SQ_AMP),a
	ld	hl,sqt_mixer
	bit	5,c
	jr	z,@nonoise
	set	3,(hl)
	ld	a,b
	and	0F0h
	rrca
	rrca
	rrca
	bit	7,c
	jr	z,@noiseok
	inc	a
@noiseok:
	ld	(ay_regs+6),a
@nonoise:
	bit	6,c
	jr	z,@notone
	set	0,(hl)
@notone:
	ld	d,(ix+SQ_NOTE)		; D = note + ornament + transposition
	ld	a,(ix+SQ_ORNEN)
	or	a
	jr	z,@noorn
	ld	hl,(ix+SQ_PIO)
	ld	a,d
	add	a,(hl)
	ld	d,a
	dec	(ix+SQ_OTC)
	jr	nz,@ornnext
	; The ornament has run out: go back to its loop position. An
	; ornament whose loop position is 32 takes its loop from the
	; sample instead.
	ld	hl,(ix+SQ_ORNPTR)
	ld	a,(hl)
	cp	32
	jr	nz,@ornloop
	ld	hl,(ix+SQ_SAMPTR)
@ornloop:
	ld	e,(hl)
	inc	hl
	ld	a,(hl)
	ld	(ix+SQ_OTC),a
	ld	hl,(ix+SQ_ORNPTR)
	inc	hl
	inc	hl
	push	de
	ld	a,e
	ld	de,0
	ld	e,a
	add	hl,de
	pop	de
	ld	(ix+SQ_PIO),hl
	jr	@noorn
@ornnext:
	ld	hl,(ix+SQ_PIO)
	inc	hl
	ld	(ix+SQ_PIO),hl
@noorn:
	ld	a,d
	add	a,(ix+SQ_TRANSP)
	cp	060h
	jr	c,@inrange
	ld	a,05Fh
@inrange:
	ld	hl,0
	ld	l,a
	add	hl,hl
	ld	de,sqt_notes
	add	hl,de
	call	sqt_word
	ld	de,0			; the sample's 12 bit tone offset
	ld	a,c
	and	15
	ld	d,a
	ld	a,(sqt_b2)
	ld	e,a
	bit	4,c
	jr	nz,@plus
	or	a
	sbc	hl,de
	jr	@toned
@plus:
	add	hl,de
@toned:
	ld	(sqt_ton),hl
	dec	(ix+SQ_STC)
	jr	nz,@samnext
	ld	hl,(ix+SQ_SAMPTR)	; the sample has run out: loop, or stop
	inc	hl			; if its loop position is 32
	ld	a,(hl)
	ld	(ix+SQ_STC),a
	dec	hl
	ld	a,(hl)
	cp	32
	jr	nz,@samloop
	ld	(ix+SQ_ON),0
	ld	(ix+SQ_ORNEN),0
@samloop:
	ld	de,0
	ld	e,a
	ld	hl,(ix+SQ_SAMPTR)
	inc	hl
	inc	hl
	add	hl,de
	add	hl,de
	add	hl,de
	ld	(ix+SQ_PIS),hl
	jr	@slide
@samnext:
	ld	hl,(ix+SQ_PIS)
	inc	hl
	inc	hl
	inc	hl
	ld	(ix+SQ_PIS),hl
@slide:
	ld	hl,(sqt_ton)
	ld	a,(ix+SQ_GLISS)
	or	a
	jr	z,@store
	ld	de,(ix+SQ_CTS)
	add	hl,de
	push	hl
	ld	hl,(ix+SQ_CTS)
	ld	de,(ix+SQ_STEP)
	add	hl,de
	ld	(ix+SQ_CTS),hl
	pop	hl
@store:
	ld	(ix+SQ_TON),l
	ld	a,h
	and	0Fh
	ld	(ix+SQ_TON+1),a
	ret

; sqt_play: advance the song by one frame and fill ay_regs.
sqt_play:
	ld	a,0FFh
	ld	(ay_regs+13),a
	ld	hl,sqt_delay_cnt
	dec	(hl)
	call	z,sqt_rowtick
	xor	a
	ld	(sqt_mixer),a
	ld	ix,sqt_chC
	call	sqt_chreg
	ld	ix,sqt_chB
	call	sqt_chreg
	ld	ix,sqt_chA
	call	sqt_chreg
	; set bits meant "on": the AY wants "off"
	ld	a,(sqt_mixer)
	cpl
	and	03Fh
	ld	c,a
	ld	ix,sqt_chA
	ld	b,1			; tone bit of A; its noise bit is * 8
@forced:
	ld	a,(ix+SQ_MIXT)
	or	a
	jr	nz,@tone
	ld	a,c
	or	b
	ld	c,a
@tone:
	ld	a,(ix+SQ_MIXN)
	or	a
	jr	nz,@noise
	ld	a,b
	add	a,a
	add	a,a
	add	a,a
	or	c
	ld	c,a
@noise:
	ld	de,SQ_SIZE
	add	ix,de
	sla	b
	bit	3,b
	jr	z,@forced
	ld	a,c
	ld	(ay_regs+7),a
	ld	hl,(sqt_chA+SQ_TON)
	ld	(ay_regs+0),hl
	ld	hl,(sqt_chB+SQ_TON)
	ld	(ay_regs+2),hl
	ld	hl,(sqt_chC+SQ_TON)
	ld	a,l
	ld	(ay_regs+4),a
	ld	a,h
	ld	(ay_regs+5),a
	ld	a,(sqt_chA+SQ_AMP)
	ld	(ay_regs+8),a
	ld	a,(sqt_chB+SQ_AMP)
	ld	(ay_regs+9),a
	ld	a,(sqt_chC+SQ_AMP)
	ld	(ay_regs+10),a
	ret

; sqt_rowtick: the work done once per row: move to the next position if
; the pattern has run out, then read a row for each channel.
sqt_rowtick:
	ld	a,(sqt_delay)
	ld	(sqt_delay_cnt),a
	ld	hl,sqt_row
	inc	(hl)
	ld	hl,sqt_lines
	dec	(hl)
	call	z,sqt_newpos
	ld	ix,sqt_chC
	call	sqt_interp
	ld	ix,sqt_chB
	call	sqt_interp
	ld	ix,sqt_chA
	jp	sqt_interp

; sqt_newpos: set the three channels up from the next position.
sqt_newpos:
	ld	hl,sqt_pos
	inc	(hl)
	xor	a
	ld	(sqt_row),a
	ld	hl,(sqt_pp)
	ld	a,(hl)
	or	a
	jr	nz,@more
	ld	hl,sqt_loops		; end of song: note it and loop
	inc	(hl)
	ld	a,(sqt_looppos)
	ld	(sqt_pos),a
	ld	hl,(sqt_loopptr)
@more:
	ld	a,(hl)
	and	07Fh
	ld	(sqt_pat),a
	ld	ix,sqt_chC
	call	@chan
	push	hl
	ld	hl,(ix+SQ_ADDR)		; channel C's pattern starts with the
	ld	a,(hl)			; number of rows
	ld	(sqt_lines),a
	inc	hl
	ld	(ix+SQ_ADDR),hl
	pop	hl
	ld	ix,sqt_chB
	call	@chan
	call	@skip1
	ld	ix,sqt_chA
	call	@chan
	call	@skip1
	ld	a,(hl)
	ld	(sqt_delay),a
	ld	(sqt_delay_cnt),a
	inc	hl
	ld	(sqt_pp),hl
	ret
@skip1:					; (the other channels' patterns have a
	push	hl			; first byte too, which is not used)
	ld	hl,(ix+SQ_ADDR)
	inc	hl
	ld	(ix+SQ_ADDR),hl
	pop	hl
	ret
@chan:					; two bytes at HL for the channel at IX
	ld	a,(hl)
	or	a
	jr	nz,@pattern
	ld	hl,(sqt_loopptr)	; (as the original player does)
	ld	a,(hl)
@pattern:
	ld	c,a
	rlca
	and	1
	ld	(ix+SQ_GLOBAL),a
	ld	a,c
	add	a,a
	ld	de,0
	ld	e,a
	push	hl
	ld	hl,(sqt_patptr)
	add	hl,de
	call	sqt_abs
	ld	(ix+SQ_ADDR),hl
	pop	hl
	inc	hl
	ld	a,(hl)
	ld	c,a
	and	15
	ld	(ix+SQ_VOL),a
	ld	a,c
	rrca
	rrca
	rrca
	rrca
	and	15
	cp	9			; 0 to 8 up, 9 to 15 mean -1 to -7
	jr	c,@transp
	ld	c,a
	ld	a,8
	sub	c
@transp:
	ld	(ix+SQ_TRANSP),a
	inc	hl
	ld	(ix+SQ_WAIT),0
	ret

; sqt_length: how many frames the song lasts before it ends. Call it
; straight after sqt_init, and call sqt_init again afterwards, because
; it works by running through all the song's rows. Out: HL = frames.
sqt_length:
	ld	hl,0
	ld	(sqt_frames),hl
	ld	(sqt_rows),hl	; (rows counted)
@row:
	call	sqt_rowtick
	ld	hl,(sqt_rows)		; give up after 65536 rows, which no
	inc	hl			; real song needs (a damaged one that
	ld	(sqt_rows),hl		; never ends)
	ld	a,(sqt_rows+2)
	or	a
	jp	nz,@done
	ld	a,(sqt_loops)
	or	a
	jr	nz,@done
	ld	de,0
	ld	a,(sqt_delay_cnt)
	ld	e,a
	or	a
	jr	nz,@add
	inc	d			; a speed of 0 lasts 256 frames
@add:
	ld	hl,(sqt_frames)
	add	hl,de
	ld	(sqt_frames),hl
	ld	a,(sqt_frames+2)	; give up on a song that never ends
	cp	10h
	jr	c,@row
@done:
	ld	hl,(sqt_frames)
	ret

; The note table: 96 AY tone periods.
sqt_notes:
	dw	00D5Dh,00C9Ch,00BE7h,00B3Ch,00A9Bh,00A02h,00973h,008EBh,0086Bh,007F2h,00780h,00714h
	dw	006AEh,0064Eh,005F4h,0059Eh,0054Fh,00501h,004B9h,00475h,00435h,003F9h,003C0h,0038Ah
	dw	00357h,00327h,002FAh,002CFh,002A7h,00281h,0025Dh,0023Bh,0021Bh,001FCh,001E0h,001C5h
	dw	001ACh,00194h,0017Dh,00168h,00153h,00140h,0012Eh,0011Dh,0010Dh,000FEh,000F0h,000E2h
	dw	000D6h,000CAh,000BEh,000B4h,000AAh,000A0h,00097h,0008Fh,00087h,0007Fh,00078h,00071h
	dw	0006Bh,00065h,0005Fh,0005Ah,00055h,00050h,0004Ch,00047h,00043h,00040h,0003Ch,00039h
	dw	00035h,00032h,00030h,0002Dh,0002Ah,00028h,00026h,00024h,00022h,00020h,0001Eh,0001Ch
	dw	0001Bh,00019h,00018h,00016h,00015h,00014h,00013h,00012h,00011h,00010h,0000Fh,0000Eh