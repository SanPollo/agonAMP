; ascplay.asm - ASC Sound Master (.asc) module replayer.
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
; Part of the reusable agonAMP sound library in lib/. It turns an ASC
; Sound Master module (the later layout, with a loop position in its
; header) held in memory into AY-3-8912 register values, one set per
; 50 Hz frame, in the table ay_regs (which ayvdp.asm defines and plays).
; It needs only
; notetab.inc (its note table, nt_asc) from the rest of the library.
;
; Written for the eZ80 in ADL mode. I found no written description of
; this format to work from: the behaviour was taken from reading the
; source of an existing player, ASCPlay.h of the ESP32AY project, and
; this code was then written to do the same. No code was copied. The
; note table (86 periods) is that player's.
;
; The module: speed, loop position, then pointers to the pattern table,
; the sample table and the ornament table, the number of positions and
; the position list. Samples are runs of 3 byte steps and ornaments runs
; of 2 byte steps, each carrying its own loop and end marks. Pattern
; streams hold:
;   00h-55h  note (followed by the envelope period if the envelope is
;            on); ends the row
;   56h-5Dh  nothing; ends the row      5Eh  leave the sample's loop
;   5Fh      sound off; ends the row    60h-9Fh  rows to leave empty
;   A0h-BFh  select sample              C0h-DFh  select ornament
;   E0h      volume 15, envelope on     E1h-EFh  volume, envelope off
;   F0h n    noise period               F1h-F3h  do not restart the
;            sample / ornament / both on the next note
;   F4h n    speed                      F5h n, F6h n  slide down / up
;   F7h n, F9h n  slide to the next note in n frames
;   F8h, FAh, FCh, FEh  envelope shape 8, 10, 12, 14
;   FBh n    fade the volume            FFh at a row start: pattern end
;
; Entry points:
;   asc_init   HL = address of the module, BC = its length. Returns with
;              carry set if the header does not look like an ASC module.
;   asc_play   advance one frame and fill ay_regs
;   asc_length frames the song lasts (call asc_init again afterwards)
;
; Results:
;   ay_regs    R13 is 0FFh on frames where the shape was not written.
;   asc_loops  goes up by one each time the song ends and loops.
;   asc_pos, asc_numpos, asc_pat, asc_row, asc_delay (in that order in
;   memory) and the first four bytes of asc_chA/B/C (note, sample,
;   ornament, sounding) can be read for display.
;
; All registers are used. 16 bit signed quantities are kept sign
; extended in 3 byte slots.

; Per-channel state, addressed through IX.
AC_NOTE:	equ	0	; 1: note number
AC_SAMNUM:	equ	1	; 1: sample number (for display)
AC_ORNNUM:	equ	2	; 1: ornament number (for display)
AC_ON:		equ	3	; 1: non-zero if the channel is sounding
AC_ADDR:	equ	4	; 3: address of next byte of pattern data
AC_PS:		equ	7	; 3: address of the current sample step
AC_IPS:		equ	10	; 3: address of the sample's first step
AC_LPS:		equ	13	; 3: address the sample loops back to
AC_PO:		equ	16	; 3: address of the current ornament step
AC_IPO:		equ	19	; 3: address of the ornament's first step
AC_LPO:		equ	22	; 3: address the ornament loops back to
AC_TON:		equ	25	; 3: tone period sent to the AY
AC_TDEV:	equ	28	; 3: tone offset built up by the sample
AC_CTS:		equ	31	; 3: tone slide so far, in 1/16 (signed)
AC_SUB:		equ	34	; 3: tone slide per frame (signed)
AC_ADDNOTE:	equ	37	; 1: note offset built up by the ornament
AC_SKIPN:	equ	38	; 1: empty rows after each row
AC_INOISE:	equ	39	; 1: noise period set by the pattern
AC_CNOISE:	equ	40	; 1: noise period now
AC_VOL:		equ	41	; 1: channel volume, 0 to 15
AC_TSC:		equ	42	; 1: frames of tone slide left (signed)
AC_AMP:		equ	43	; 1: amplitude sent to the AY
AC_AD:		equ	44	; 1: volume fade rate
AC_ADC:		equ	45	; 1: volume fade counter
AC_SKIPCNT:	equ	46	; 1: rows left before the next one (signed)
AC_ADDAMP:	equ	47	; 1: amplitude offset (signed)
AC_ENV:		equ	48	; 1: non-zero if the envelope is in use
AC_SOUND:	equ	49	; 1: non-zero unless the sound was cut
AC_FIN:		equ	50	; 1: non-zero when the sample has run out
AC_BRK:		equ	51	; 1: non-zero to leave the sample's loop
AC_SIZE:	equ	52

asc_base:	ds	3	; address of the module
asc_len:	ds	3	; its length
asc_patptr:	ds	3	; address of the pattern table
asc_samptr:	ds	3	; address of the sample table
asc_ornptr:	ds	3	; address of the ornament table
asc_tmp:	ds	3	; scratch for sign tests
asc_tmp2:	ds	3	; scratch: pattern address
asc_delta:	ds	3	; scratch: distance of a slide to a note
; Everything from here to asc_vars_end is cleared by asc_init.
asc_vars:
asc_chA:	ds	AC_SIZE
asc_chB:	ds	AC_SIZE
asc_chC:	ds	AC_SIZE
		ds	2	; spill room for 24 bit loads
asc_pos:	ds	1	; current position       (these five are
asc_numpos:	ds	1	; number of positions     kept together,
asc_pat:	ds	1	; current pattern number  in this order,
asc_row:	ds	1	; row within the pattern  for display)
asc_delay:	ds	1	; frames per row
asc_delay_cnt:	ds	1	; frames until the next row
asc_mixer:	ds	1	; mixer value being assembled
asc_fl:		ds	1	; what the next note must not restart
asc_f7:		ds	1	; which kind of slide to a note
asc_n:		ds	1	; frames a slide to a note takes
asc_s2:		ds	1	; sample step: third byte
asc_ctl:	ds	1	; sample step: amplitude control bits
asc_frames:	ds	3	; asc_length: frames counted
asc_loops:	ds	1	; times the end of the song was reached
asc_vars_end:
asc_rows:	ds	3	; length: rows counted
asc_rowlim:	ds	3	; bytes left in this pattern row

; asc_rel: follow an entry of a pointer table whose entries are relative
; to the table itself. In: HL = address of the table, A = entry number.
; Out: HL = address pointed to. Preserves BC, DE.
asc_rel:
	push	de
	push	bc
	push	hl
	pop	bc
	ld	de,0
	ld	e,a
	add	hl,de
	add	hl,de
	ld	e,(hl)
	inc	hl
	ld	d,(hl)
	ld	hl,0
	ld	l,e
	ld	h,d
	add	hl,bc
	pop	bc
	pop	de
	ret

; asc_sx: sign extend the low 16 bits of HL to 24 bits. Corrupts A.
asc_sx:
	ld	(asc_tmp),hl
	ld	a,h
	rla
	sbc	a,a
	ld	(asc_tmp+2),a
	ld	hl,(asc_tmp)
	ret

; asc_neg: HL = -HL. Preserves BC, DE.
asc_neg:
	push	de
	ex	de,hl
	ld	hl,0
	or	a
	sbc	hl,de
	pop	de
	ret

; asc_d16: HL = HL / 16, rounding towards zero (HL signed). Preserves
; BC, DE.
asc_d16:
	push	bc
	ld	(asc_tmp),hl
	ld	a,(asc_tmp+2)
	rla
	jr	nc,@pos
	call	asc_neg
	call	@shift
	call	asc_neg
	pop	bc
	ret
@pos:
	call	@shift
	pop	bc
	ret
@shift:
	ld	b,4
@bit:
	srl	h
	rr	l
	djnz	@bit
	ret

; asc_sdiv: signed division, rounding towards zero.
; In: HL = dividend (signed, within 16 bits), A = divisor (signed, not 0).
; Out: HL = quotient, DE = remainder (with the sign of the dividend).
asc_sdiv:
	ld	c,a
	; B bit 0: dividend < 0, bit 1: divisor < 0
	ld	b,0
	ld	(asc_tmp),hl
	ld	a,(asc_tmp+2)
	rla
	jr	nc,@dpos
	set	0,b
	call	asc_neg
@dpos:
	ld	a,c
	or	a
	jp	p,@vpos
	neg
	ld	c,a
	set	1,b
@vpos:
	push	bc
	xor	a
	ld	b,24
@bit:
	add	hl,hl
	rla
	jr	c,@sub			; (only when the divisor is 128)
	cp	c
	jr	c,@next
@sub:
	sub	c
	inc	l
@next:
	djnz	@bit
	pop	bc
	ld	de,0
	ld	e,a
	bit	0,b
	jr	z,@rsign
	ex	de,hl
	call	asc_neg
	ex	de,hl
@rsign:
	ld	a,b
	and	3
	ret	z
	cp	3
	ret	z
	jp	asc_neg

; asc_freq: HL = tone period of note A (0 to 85). Preserves BC, DE.
asc_freq:
	push	de
	ld	hl,0
	ld	l,a
	add	hl,hl
	ld	de,nt_asc
	add	hl,de
	ld	e,(hl)
	inc	hl
	ld	d,(hl)
	ld	hl,0
	ld	l,e
	ld	h,d
	pop	de
	ret

; asc_word: HL = address of a 16 bit value. Out: HL = the value.
asc_word:
	ld	e,(hl)
	inc	hl
	ld	d,(hl)
	ld	hl,0
	ld	l,e
	ld	h,d
	ret

asc_init:
	ld	(asc_base),hl
	ld	(asc_len),bc
	push	hl
	ld	hl,10			; too short for a header?
	or	a
	sbc	hl,bc
	pop	hl
	ccf
	ret	c
	; The pattern table follows the position list closely, and the
	; sample and ornament tables each start with the value 40h.
	push	hl
	pop	ix
	ld	a,(ix+1)		; the loop position must be one of the
	cp	(ix+8)			; positions (so there must be one)
	ccf
	ret	c
	inc	hl
	inc	hl
	call	asc_word		; offset of the pattern table
	ld	de,0
	ld	e,(ix+8)		; number of positions
	or	a
	sbc	hl,de
	ld	de,9
	or	a
	sbc	hl,de
	ret	c			; less than 9 apart
	ld	de,64
	or	a
	sbc	hl,de
	ccf
	ret	c			; more than 72 apart
	ld	a,4
	call	@table
	ret	c
	ld	(asc_samptr),hl
	call	asc_word
	ld	de,040h
	or	a
	sbc	hl,de
	scf
	ret	nz
	ld	a,6
	call	@table
	ret	c
	ld	(asc_ornptr),hl
	call	asc_word
	ld	de,040h
	or	a
	sbc	hl,de
	scf
	ret	nz
	ld	a,2
	call	@table
	ret	c
	ld	(asc_patptr),hl
	ld	hl,asc_vars		; clear the playing state
	ld	de,asc_vars+1
	ld	bc,asc_vars_end-asc_vars-1
	ld	(hl),0
	ldir
	ld	hl,ay_regs
	ld	b,13
@regs:
	ld	(hl),0
	inc	hl
	djnz	@regs
	ld	(hl),0FFh
	ld	ix,(asc_base)
	ld	a,(ix+0)
	ld	(asc_delay),a
	ld	a,(ix+8)
	ld	(asc_numpos),a
	ld	a,1
	ld	(asc_delay_cnt),a
	ld	ix,asc_chA
	call	@chinit
	ld	ix,asc_chB
	call	@chinit
	ld	ix,asc_chC
	call	@chinit
	xor	a
	call	asc_setpos
	ld	a,0FFh			; becomes row 0 on the first frame
	ld	(asc_row),a
	or	a
	ret
; HL = address of the table whose offset
@table:
	ld	hl,(asc_base)		; is at header byte A; carry if beyond
	ld	de,0			; the end of the module
	ld	e,a
	add	hl,de
	call	asc_word
	push	hl
	ld	de,(asc_len)
	or	a
	sbc	hl,de
	pop	hl
	ccf
	ld	de,(asc_base)
	push	af
	add	hl,de
	pop	af
	ret
@chinit:
	ld	hl,(asc_base)
	ld	(ix+AC_PS),hl
	ld	(ix+AC_IPS),hl
	ld	(ix+AC_LPS),hl
	ld	(ix+AC_PO),hl
	ld	(ix+AC_IPO),hl
	ld	(ix+AC_LPO),hl
	ret

; asc_setpos: point the channels at the pattern for position A.
asc_setpos:
	ld	(asc_pos),a
	ld	hl,0
	ld	l,a
	ld	de,9
	add	hl,de
	ld	de,(asc_base)
	add	hl,de
	ld	a,(hl)
	ld	(asc_pat),a
	ld	c,a
	add	a,a
	add	a,c			; pattern * 3: entry for channel A is
	ld	c,a			; table entry number pattern * 3
	ld	ix,asc_chA
	call	@addr
	ld	ix,asc_chB
	call	@addr
	ld	ix,asc_chC
@addr:
	ld	hl,(asc_patptr)
	ld	a,c
	call	asc_rel
	ld	(ix+AC_ADDR),hl
	inc	c
	ret

; asc_interp: read one row of pattern data for the channel at IX.
asc_interp:
	xor	a
	ld	(ix+AC_TSC),a
	ld	(ix+AC_ADC),a
	; bit 0: keep sample, bit 1: keep ornament
	ld	(asc_fl),a
	ld	hl,(ix+AC_ADDR)
	push	hl			; (bytes read in this row: see @loop)
	ld	hl,0
	ld	(asc_rowlim),hl
	pop	hl
@loop:
	push	hl			; a damaged pattern: give up on the
	ld	hl,(asc_rowlim)	; row after 65536 bytes
	dec	hl
	ld	(asc_rowlim),hl
	ld	a,h
	or	l
	pop	hl
	jp	z,@done
	ld	a,(hl)
	cp	056h
	jp	c,@note
	cp	05Eh
	jp	c,@empty
	jp	z,@break
	cp	05Fh
	jp	z,@off
	cp	0A0h
	jp	c,@skip
	cp	0C0h
	jp	c,@sample
	cp	0E0h
	jp	c,@ornament
	jp	z,@envon
	cp	0F0h
	jp	c,@volume
	sub	0F0h
	jp	z,@noise
	dec	a
	jp	z,@keepsam
	dec	a
	jp	z,@keeporn
	dec	a
	jp	z,@keepboth
	dec	a
	jp	z,@speed
	dec	a
	jp	z,@slidedn
	dec	a
	jp	z,@slideup
	dec	a
	jp	z,@porta7
	dec	a
	jp	z,@shape8
	dec	a
	jp	z,@porta9
	dec	a
	jp	z,@shape10
	dec	a
	jp	z,@fade
	dec	a
	jp	z,@shape12
	dec	a
	jr	z,@next			; FDh: nothing
	dec	a
	jp	z,@shape14
@next:
	inc	hl
	jp	@loop

@note:
	ld	(ix+AC_NOTE),a
	inc	hl
	ld	a,(ix+AC_INOISE)
	ld	(ix+AC_CNOISE),a
	ld	a,(ix+AC_TSC)		; no slide in progress: forget the last
	or	a
	jr	z,@noslide
	jp	p,@sliding
@noslide:
	ld	de,0
	ld	(ix+AC_CTS),de
@sliding:
	ld	a,(asc_fl)
	bit	0,a
	jr	nz,@samkept
	ld	(ix+AC_ADDAMP),0
	ld	de,0
	ld	(ix+AC_TDEV),de
	ld	de,(ix+AC_IPS)
	ld	(ix+AC_PS),de
	ld	(ix+AC_SOUND),1
	ld	(ix+AC_FIN),0
	ld	(ix+AC_BRK),0
@samkept:
	ld	a,(asc_fl)
	bit	1,a
	jr	nz,@ornkept
	ld	de,(ix+AC_IPO)
	ld	(ix+AC_PO),de
	ld	(ix+AC_ADDNOTE),0
@ornkept:
	ld	a,(ix+AC_ENV)
	or	a
	jp	z,@done
	ld	a,(hl)			; the envelope period follows the note
	ld	(ay_regs+11),a
	inc	hl
	jp	@done
@empty:
	inc	hl
	jp	@done
@break:
	ld	(ix+AC_BRK),1
	inc	hl
	jp	@done
@off:
	ld	(ix+AC_SOUND),0
	inc	hl
	jp	@done
@skip:
	sub	060h
	ld	(ix+AC_SKIPN),a
	jp	@next
@sample:
	sub	0A0h
	ld	(ix+AC_SAMNUM),a
	push	hl
	ld	hl,(asc_samptr)
	call	asc_rel
	ld	(ix+AC_IPS),hl
	pop	hl
	jp	@next
@ornament:
	sub	0C0h
	ld	(ix+AC_ORNNUM),a
	push	hl
	ld	hl,(asc_ornptr)
	call	asc_rel
	ld	(ix+AC_IPO),hl
	pop	hl
	jp	@next
@envon:
	ld	(ix+AC_VOL),15
	ld	(ix+AC_ENV),1
	jp	@next
@volume:
	sub	0E0h
	ld	(ix+AC_VOL),a
	ld	(ix+AC_ENV),0
	jp	@next
@noise:
	inc	hl
	ld	a,(hl)
	ld	(ix+AC_INOISE),a
	jp	@next
@keepsam:
	ld	a,1
	jr	@keep
@keeporn:
	ld	a,2
	jr	@keep
@keepboth:
	ld	a,3
@keep:
	push	hl
	ld	hl,asc_fl
	or	(hl)
	ld	(hl),a
	pop	hl
	jp	@next
@speed:
	inc	hl
	ld	a,(hl)
	ld	(asc_delay),a
	jp	@next
@slidedn:
	inc	hl
	call	@times16
	call	asc_neg
	jr	@slide
@slideup:
	inc	hl
	call	@times16
@slide:
	ld	(ix+AC_SUB),hl
	ld	(ix+AC_TSC),255
	ld	hl,(asc_tmp2)
	jp	@next
@times16:				; HL = 16 * the signed byte at (HL);
	; the pattern address is put in asc_tmp2
	ld	(asc_tmp2),hl
	ld	a,(hl)
	ld	l,a
	rla
	sbc	a,a
	ld	h,a
	call	asc_sx
	add	hl,hl
	add	hl,hl
	add	hl,hl
	add	hl,hl
	ret
@porta7:
	inc	hl
	ld	a,(asc_fl)		; this one also keeps the sample going
	or	1
	ld	(asc_fl),a
	ld	a,1
	jr	@porta
@porta9:
	inc	hl
	xor	a
@porta:
	ld	(asc_f7),a
	push	hl
	ld	a,(hl)
	or	a
	jr	nz,@frames
	inc	a			; (0 frames would divide by zero)
@frames:
	ld	(asc_n),a
	inc	hl
	; the note being slid to, if one follows
	ld	a,(hl)
	cp	056h
	jr	nc,@fromhere
	call	asc_freq
	ex	de,hl
	ld	a,(ix+AC_NOTE)
	call	asc_freq
	or	a
	sbc	hl,de			; period now - period wanted
	ld	a,(asc_f7)
	or	a
	jr	z,@scaled
	push	hl
	ld	hl,(ix+AC_CTS)
	call	asc_d16
	pop	de
	add	hl,de
	jr	@scaled
@fromhere:
	ld	hl,(ix+AC_CTS)
	call	asc_d16
@scaled:
	add	hl,hl			; in sixteenths, as a 16 bit number
	add	hl,hl
	add	hl,hl
	add	hl,hl
	call	asc_sx
	ld	(asc_delta),hl
	ld	a,(asc_n)
	call	asc_sdiv
	call	asc_neg			; step per frame = -(distance / frames)
	ld	(ix+AC_SUB),hl
	ld	hl,(asc_delta)		; start a whole number of steps away
	or	a
	sbc	hl,de
	ld	(ix+AC_CTS),hl
	ld	a,(asc_n)
	ld	(ix+AC_TSC),a
	pop	hl
	jp	@next
@shape8:
	ld	a,8
	jr	@shape
@shape10:
	ld	a,10
	jr	@shape
@shape12:
	ld	a,12
	jr	@shape
@shape14:
	ld	a,14
@shape:
	ld	(ay_regs+13),a
	jp	@next
@fade:
	inc	hl
	ld	a,(hl)
	bit	5,a
	jr	nz,@fadeup
	add	a,a
	add	a,a
	add	a,a
	jr	@fadeset
@fadeup:
	add	a,a
	add	a,a
	add	a,a
	xor	0F8h
	add	a,9
@fadeset:
	ld	(ix+AC_AD),a
	ld	(ix+AC_ADC),a
	jp	@next
@done:
	ld	(ix+AC_ADDR),hl
	ld	a,(ix+AC_SKIPN)
	ld	(ix+AC_SKIPCNT),a
	ret

; asc_decamp / asc_incamp: move the amplitude offset one step down or
; up, within -15 to 15. Corrupt A only.
asc_decamp:
	ld	a,(ix+AC_ADDAMP)
	add	a,14
	ret	m
	dec	(ix+AC_ADDAMP)
	ret
asc_incamp:
	ld	a,(ix+AC_ADDAMP)
	sub	15
	ret	p
	inc	(ix+AC_ADDAMP)
	ret

; asc_chreg: work out this frame's tone and amplitude for the channel at
; IX and add its bits to the mixer.
asc_chreg:
	ld	(ix+AC_ON),0
	ld	a,(ix+AC_FIN)
	or	a
	jp	nz,@silent
	ld	a,(ix+AC_SOUND)
	or	a
	jp	z,@silent
	ld	(ix+AC_ON),1
	ld	a,(ix+AC_ADC)		; volume fade
	or	a
	jr	z,@step
	cp	16
	jr	c,@fadelow
	sub	8
	ld	(ix+AC_ADC),a
	ld	a,(ix+AC_ADDAMP)
	add	a,15
	jp	p,@notbelow
	inc	(ix+AC_ADDAMP)
	jr	@step
@notbelow:
	ld	a,(ix+AC_ADDAMP)
	sub	16
	jp	m,@step
	dec	(ix+AC_ADDAMP)
	jr	@step
@fadelow:
	bit	0,a
	jr	z,@fadeeven
	call	asc_decamp
	jr	@fadereload
@fadeeven:
	call	asc_incamp
@fadereload:
	ld	a,(ix+AC_AD)
	ld	(ix+AC_ADC),a
@step:
	ld	hl,(ix+AC_PS)		; the 3 byte sample step
	ld	b,(hl)			; B = marks and noise/envelope offset
	inc	hl
	ld	c,(hl)			; C = tone offset to add
	inc	hl
	ld	a,(hl)			; amplitude, masks, amplitude control
	ld	(asc_s2),a
	bit	7,b
	jr	z,@noloop
	ld	hl,(ix+AC_PS)
	ld	(ix+AC_LPS),hl
@noloop:
	ld	a,b
	and	96
	cp	32
	jr	nz,@notlast
	ld	(ix+AC_FIN),1
@notlast:
	ld	a,c
	ld	e,a
	rla
	sbc	a,a
	ld	d,a
	ld	hl,(ix+AC_TDEV)
	add	hl,de
	ld	(ix+AC_TDEV),hl
	ld	a,(asc_s2)
	and	9
	add	a,a
	add	a,a
	add	a,a
	ld	hl,asc_mixer
	or	(hl)
	ld	(hl),a
	ld	a,(asc_s2)
	and	6
	ld	(asc_ctl),a
	cp	4
	jr	nz,@not4
	call	asc_decamp
@not4:
	ld	a,(asc_ctl)
	cp	6
	jr	nz,@not6
	call	asc_incamp
@not6:
	ld	a,(asc_s2)
	rrca
	rrca
	rrca
	rrca
	and	15
	add	a,(ix+AC_ADDAMP)
	jp	p,@notneg
	xor	a
@notneg:
	cp	16
	jr	c,@inrange
	ld	a,15
@inrange:
	ld	h,a			; amplitude * (volume + 1) / 16
	ld	l,(ix+AC_VOL)
	inc	l
	mlt	hl
	ld	a,l
	rrca
	rrca
	rrca
	rrca
	and	15
	ld	(ix+AC_AMP),a
	; a signed 5 bit offset: for the envelope
	ld	a,b
	; period if the sample says so and noise
	and	31
	bit	4,a			; is masked, otherwise for the noise
	jr	z,@off5
	or	0E0h
@off5:
	ld	e,a
	ld	a,(asc_ctl)
	cp	2
	jr	nz,@tonoise
	ld	a,(asc_mixer)
	bit	6,a
	jr	z,@tonoise
	ld	a,(ay_regs+11)
	add	a,e
	ld	(ay_regs+11),a
	jr	@advance
@tonoise:
	ld	a,(ix+AC_CNOISE)
	add	a,e
	ld	(ix+AC_CNOISE),a
@advance:
	ld	hl,(ix+AC_PS)
	inc	hl
	inc	hl
	inc	hl
	ld	(ix+AC_PS),hl
	bit	6,b
	jr	z,@orn
	ld	a,(ix+AC_BRK)
	or	a
	jr	nz,@broken
	ld	hl,(ix+AC_LPS)
	ld	(ix+AC_PS),hl
	jr	@orn
@broken:
	bit	5,b
	jr	z,@orn
	ld	(ix+AC_FIN),1
@orn:
	ld	hl,(ix+AC_PO)		; the 2 byte ornament step
	ld	b,(hl)
	inc	hl
	ld	c,(hl)
	bit	7,b
	jr	z,@ornnoloop
	ld	hl,(ix+AC_PO)
	ld	(ix+AC_LPO),hl
@ornnoloop:
	ld	a,(ix+AC_ADDNOTE)
	add	a,c
	ld	(ix+AC_ADDNOTE),a
	ld	a,b
	bit	4,a
	jr	z,@ornnoise
	or	0F0h
@ornnoise:
	add	a,(ix+AC_CNOISE)
	ld	(ix+AC_CNOISE),a
	ld	hl,(ix+AC_PO)
	inc	hl
	inc	hl
	ld	(ix+AC_PO),hl
	bit	6,b
	jr	z,@ornnext
	ld	hl,(ix+AC_LPO)
	ld	(ix+AC_PO),hl
@ornnext:
	ld	a,(asc_mixer)
	bit	6,a
	jr	nz,@tone
	ld	a,(ix+AC_CTS+1)
	add	a,(ix+AC_CNOISE)
	and	1Fh
	ld	(ay_regs+6),a
@tone:
	ld	a,(ix+AC_NOTE)
	add	a,(ix+AC_ADDNOTE)
	jp	p,@jpos
	xor	a
@jpos:
	cp	056h
	jr	c,@jok
	ld	a,055h
@jok:
	call	asc_freq
	ld	de,(ix+AC_TDEV)
	add	hl,de
	push	hl
	ld	hl,(ix+AC_CTS)
	call	asc_d16
	pop	de
	add	hl,de
	ld	(ix+AC_TON),l
	ld	a,h
	and	0Fh
	ld	(ix+AC_TON+1),a
	ld	a,(ix+AC_TSC)		; tone slide
	or	a
	jr	z,@env
	jp	m,@endless
	dec	(ix+AC_TSC)
@endless:
	ld	hl,(ix+AC_CTS)
	ld	de,(ix+AC_SUB)
	add	hl,de
	call	asc_sx
	ld	(ix+AC_CTS),hl
@env:
	ld	a,(ix+AC_ENV)
	or	a
	jr	z,@done
	ld	a,(asc_ctl)
	cp	2
	jr	nz,@done
	set	4,(ix+AC_AMP)
	jr	@done
@silent:
	ld	(ix+AC_AMP),0
@done:
	ld	hl,asc_mixer		; make room for the next channel
	srl	(hl)
	ret

; asc_play: advance the song by one frame and fill ay_regs.
asc_play:
	ld	a,0FFh
	ld	(ay_regs+13),a
	ld	hl,asc_delay_cnt
	dec	(hl)
	call	z,asc_rowtick
	xor	a
	ld	(asc_mixer),a
	ld	ix,asc_chA
	call	asc_chreg
	ld	ix,asc_chB
	call	asc_chreg
	ld	ix,asc_chC
	call	asc_chreg
	ld	a,(asc_mixer)
	ld	(ay_regs+7),a
	ld	hl,(asc_chA+AC_TON)
	ld	(ay_regs+0),hl
	ld	hl,(asc_chB+AC_TON)
	ld	(ay_regs+2),hl
	ld	hl,(asc_chC+AC_TON)
	ld	a,l
	ld	(ay_regs+4),a
	ld	a,h
	ld	(ay_regs+5),a
	ld	a,(asc_chA+AC_AMP)
	ld	(ay_regs+8),a
	ld	a,(asc_chB+AC_AMP)
	ld	(ay_regs+9),a
	ld	a,(asc_chC+AC_AMP)
	ld	(ay_regs+10),a
	ret

; asc_rowtick: the work done once per row: read the next row for each
; channel whose turn it is, moving to the next pattern when one ends.
asc_rowtick:
	ld	hl,asc_row
	inc	(hl)
	ld	ix,asc_chA
	dec	(ix+AC_SKIPCNT)
	jp	p,@chb
	ld	hl,(ix+AC_ADDR)
	ld	a,(hl)
	inc	a			; 0FFh in channel A ends the pattern
	jr	nz,@cha
	ld	a,(asc_numpos)
	ld	b,a
	ld	a,(asc_pos)
	inc	a
	cp	b
	jr	c,@newpos
	ld	hl,asc_loops		; end of song: note it and loop
	inc	(hl)
	ld	hl,(asc_base)
	inc	hl
	ld	a,(hl)
@newpos:
	call	asc_setpos
	xor	a
	ld	(asc_row),a
	ld	(asc_chA+AC_INOISE),a
	ld	(asc_chB+AC_INOISE),a
	ld	(asc_chC+AC_INOISE),a
	ld	ix,asc_chA
@cha:
	call	asc_interp
@chb:
	ld	ix,asc_chB
	dec	(ix+AC_SKIPCNT)
	call	m,asc_interp
	ld	ix,asc_chC
	dec	(ix+AC_SKIPCNT)
	call	m,asc_interp
	ld	a,(asc_delay)
	ld	(asc_delay_cnt),a
	ret

; asc_length: how many frames the song lasts before it ends. Call it
; straight after asc_init, and call asc_init again afterwards, because
; it works by running through all the song's rows. Out: HL = frames.
asc_length:
	ld	hl,0
	ld	(asc_frames),hl
	ld	(asc_rows),hl	; (rows counted)
@row:
	call	asc_rowtick
	ld	hl,(asc_rows)		; give up after 65536 rows, which no
	inc	hl			; real song needs (a damaged one that
	ld	(asc_rows),hl		; never ends)
	ld	a,(asc_rows+2)
	or	a
	jp	nz,@done
	ld	a,(asc_loops)
	or	a
	jr	nz,@done
	ld	de,0
	ld	a,(asc_delay)
	ld	e,a
	or	a
	jr	nz,@add
	inc	d			; a speed of 0 lasts 256 frames
@add:
	ld	hl,(asc_frames)
	add	hl,de
	ld	(asc_frames),hl
	ld	a,(asc_frames+2)	; give up on a song that never ends
	cp	10h
	jr	c,@row
@done:
	ld	hl,(asc_frames)
	ret