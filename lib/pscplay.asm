; pscplay.asm - Pro Sound Creator (.psc) module replayer.
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
; Sound Creator module held in memory into AY-3-8912 register values,
; one set per 50 Hz frame, in the table ay_regs (which ayvdp.asm defines
; and plays). It needs only
; notetab.inc (its note table, nt_asc) from the rest of the library.
;
; Written for the eZ80 in ADL mode. I found no written description of
; this format to work from: the behaviour was taken from reading the
; source of an existing player, PSCPlay.h of the ESP32AY project, and
; this code was then written to do the same. No code was copied. The
; note table is the one ASC Sound Master modules use (see ascplay.asm).
;
; The module: 69 characters of text ("PSC V1.0x COMPILATION OF", a 20
; character name, "BY" and a 20 character author), a pointer that is
; not used, the pointer to the position list, the speed, the pointer to
; the ornament table, then the sample table. Samples are runs of 6 byte
; steps and ornaments runs of 2 byte steps, each step carrying its own
; loop and end marks. A position is 8 bytes: a number, the row count
; (255 marks the end of the list, and the next two bytes then say where
; to carry on from), and a pattern stream address for each channel.
; Pattern streams hold:
;   00h-56h  note                       57h      volume 15, envelope on
;   58h-66h  volume, envelope off       6Bh n, 6Ch n  slide up / down
;   6Dh n    slide to this row's note   6Eh n    speed
;   6Fh n    ornament off               70h n    fade the volume
;   71h n    leave the ornament's loop  7Ah s,l,h  envelope shape and
;   7Bh n    noise offset                        period (channel B only)
;   7Ch      sound off                  7Dh      leave the sample's loop
;   80h-9Fh  select sample              A0h-BFh  select ornament
;   C0h-FFh  ends the row, and says how many rows until the next
;
; Entry points:
;   psc_init   HL = address of the module, BC = its length. Returns with
;              carry set if the header does not look like a PSC module.
;   psc_play   advance one frame and fill ay_regs
;   psc_length frames the song lasts (call psc_init again afterwards)
;
; Results:
;   ay_regs    R13 is 0FFh on frames where the shape was not written.
;   psc_loops  goes up by one each time the song ends and loops.
;   psc_pos, psc_numpos, psc_pat, psc_row, psc_delay (in that order in
;   memory) and the first four bytes of psc_chA/B/C (note, sample,
;   ornament, sounding) can be read for display.
;
; All registers are used. 16 bit signed quantities are kept sign
; extended in 3 byte slots.

; Per-channel state, addressed through IX.
PSCC_NOTE:	equ	0	; 1: note number
PSCC_SAMNUM:	equ	1	; 1: sample number (for display)
PSCC_ORNNUM:	equ	2	; 1: ornament number (for display)
; 1: non-zero if the channel is sounding
PSCC_ON:		equ	3
PSCC_ADDR:	equ	4	; 3: address of next byte of pattern data
PSCC_ORNPTR:	equ	7	; 3: address of the ornament's steps
PSCC_SAMPTR:	equ	10	; 3: address of the sample's steps
PSCC_TON:		equ	13	; 3: tone period sent to the AY
PSCC_CTS:		equ	16	; 3: tone slide so far (signed)
PSCC_TACC:	equ	19	; 3: tone offset built up by the sample
PSCC_ADD:		equ	22	; 3: tone slide per frame (signed)
PSCC_IVOL:	equ	25	; 1: volume set by the pattern
PSCC_SKIPCNT:	equ	26	; 1: rows left before the next one
PSCC_VOL:		equ	27	; 1: volume now
PSCC_AMP:		equ	28	; 1: amplitude sent to the AY
; 1: frames until the next step of a fade
PSCC_VC:		equ	29
PSCC_VC1:		equ	30	; 1: fade rate as given in the pattern
PSCC_VCI:		equ	31	; 1: frames between steps of a fade
PSCC_NACC:	equ	32	; 1: noise period built up
PSCC_SAMPOS:	equ	33	; 1
PSCC_SAMLOOP:	equ	34	; 1
PSCC_ORNPOS:	equ	35	; 1
PSCC_ORNLOOP:	equ	36	; 1
PSCC_ORNEN:	equ	37	; 1: non-zero if the ornament is running
PSCC_ENV:		equ	38	; 1: non-zero if the envelope is in use
PSCC_GLISS:	equ	39	; 1: non-zero if sliding to a note
PSCC_TSEN:	equ	40	; 1: non-zero while a tone slide is on
PSCC_BRKS:	equ	41	; 1: non-zero to leave the sample's loop
PSCC_BRKO:	equ	42	; 1: non-zero to leave the ornament's loop
PSCC_VINC:	equ	43	; 1: non-zero if a fade goes upwards
PSCC_SIZE:	equ	44

PSC_NAME:	equ	25	; header: 20 character name
PSC_AUTHOR:	equ	49	; header: 20 character author
PSC_PATPTR:	equ	71	; header: position list pointer
PSC_DELAY:	equ	73	; header: speed
PSC_ORNPTR:	equ	74	; header: ornament table pointer
PSC_SAMTAB:	equ	76	; header: sample table (offsets from here)

psc_base:	ds	3	; address of the module
psc_len:	ds	3	; its length
psc_patptr:	ds	3	; address of the position list
psc_ornptr:	ds	3	; address of the ornament table
psc_tmp:	ds	3	; scratch for sign extension
psc_rec:	ds	3	; address of the current sample step
psc_ton:	ds	3	; tone period being worked out
; Everything from here to psc_vars_end is cleared by psc_init.
psc_vars:
psc_chA:	ds	PSCC_SIZE
psc_chB:	ds	PSCC_SIZE
psc_chC:	ds	PSCC_SIZE
		ds	2	; spill room for 24 bit loads
psc_pos:	ds	1	; current position       (these five are
psc_numpos:	ds	1	; number of positions     kept together,
psc_pat:	ds	1	; the position's number   in this order,
psc_row:	ds	1	; row within the pattern  for display)
psc_delay:	ds	1	; frames per row
psc_delay_cnt:	ds	1	; frames until the next row
psc_lines:	ds	1	; rows left in the pattern
psc_noise:	ds	1	; noise offset added on every row
psc_pp:		ds	3	; address of the next position
psc_chan:	ds	1	; number of the channel being read
psc_fl:		ds	1	; what the row being read asks for
psc_j:		ds	1	; note being played, with its ornament
psc_mixer:	ds	1	; mixer value being assembled
psc_frames:	ds	3	; psc_length: frames counted
psc_loops:	ds	1	; times the end of the song was reached
psc_vars_end:
psc_rows:	ds	3	; length: rows counted
psc_rowlim:	ds	3	; bytes left in this pattern row

; psc_word: HL = address of a 16 bit value. Out: HL = the value.
psc_word:
	ld	e,(hl)
	inc	hl
	ld	d,(hl)
	ld	hl,0
	ld	l,e
	ld	h,d
	ret

; psc_abs: HL = address of a 16 bit offset. Out: HL = module address +
; that offset. Preserves BC.
psc_abs:
	call	psc_word
	ld	de,(psc_base)
	add	hl,de
	ret

; psc_sx: sign extend the low 16 bits of HL to 24 bits. Corrupts A.
psc_sx:
	ld	(psc_tmp),hl
	ld	a,h
	rla
	sbc	a,a
	ld	(psc_tmp+2),a
	ld	hl,(psc_tmp)
	ret

; psc_freq: HL = tone period of note A. Preserves BC, DE.
psc_freq:
	cp	86			; (the table has 86 entries)
	jr	c,@ok
	ld	a,85
@ok:
	push	de
	ld	hl,0
	ld	l,a
	add	hl,hl
	ld	de,nt_asc
	add	hl,de
	call	psc_word
	pop	de
	ret

psc_init:
	ld	(psc_base),hl
	ld	(psc_len),bc
	push	hl
	ld	hl,PSC_SAMTAB+2		; too short for a header?
	or	a
	sbc	hl,bc
	pop	hl
	ccf
	ret	c
	; The ornament table follows the sample table, which has at
	; least one entry and at most 32, and both pointers are even.
	ld	de,PSC_ORNPTR
	add	hl,de
	call	psc_word
	ld	a,l
	and	1
	scf
	ret	nz
	push	hl
	ld	de,PSC_SAMTAB+2
	or	a
	sbc	hl,de
	pop	hl
	ret	c
	push	hl
	ld	de,PSC_SAMTAB+64+1
	or	a
	sbc	hl,de
	pop	hl
	ccf
	ret	c
	call	@inside
	ret	c
	ld	de,(psc_base)
	add	hl,de
	ld	(psc_ornptr),hl
	ld	hl,(psc_base)
	ld	de,PSC_PATPTR
	add	hl,de
	call	psc_word
	push	hl
	ld	de,11
	add	hl,de
	call	@inside
	pop	hl
	ret	c
	ld	de,(psc_base)
	add	hl,de
	ld	(psc_patptr),hl
	inc	hl
	ld	a,(hl)			; an empty position list?
	inc	a
	scf
	ret	z
	ld	hl,psc_vars		; clear the playing state
	ld	de,psc_vars+1
	ld	bc,psc_vars_end-psc_vars-1
	ld	(hl),0
	ldir
	ld	hl,ay_regs
	ld	b,13
@regs:
	ld	(hl),0
	inc	hl
	djnz	@regs
	ld	(hl),0FFh
	ld	ix,(psc_base)
	ld	a,(ix+PSC_DELAY)
	ld	(psc_delay),a
	ld	hl,(psc_patptr)
	ld	(psc_pp),hl
	ld	c,0			; count the positions
	ld	de,8
@count:
	inc	hl
	ld	a,(hl)
	dec	hl
	inc	a
	jr	z,@counted
	inc	c
	jr	z,@counted
	add	hl,de
	jr	@count
@counted:
	push	hl			; (HL = the end mark) the position the
	inc	hl			; list carries on from must be one of
	inc	hl			; its entries
	call	psc_abs
	pop	de			; DE = the end mark
	push	hl
	or	a
	sbc	hl,de
	pop	hl
	ccf
	ret	c			; at or past the end mark
	ld	de,(psc_patptr)
	or	a
	sbc	hl,de
	ret	c			; before the list
	ld	a,l
	and	7
	scf
	ret	nz			; not at the start of an entry
	ld	a,c
	ld	(psc_numpos),a
	ld	a,1
	ld	(psc_delay_cnt),a
	ld	(psc_lines),a
	ld	a,0FFh
	ld	(psc_pos),a
	ld	(psc_row),a
	ld	ix,psc_chA
	call	@chinit
	ld	ix,psc_chB
	call	@chinit
	ld	ix,psc_chC
	call	@chinit
	or	a
	ret
@chinit:
	xor	a
	call	psc_setsam
	xor	a
	call	psc_setorn
	ld	(ix+PSCC_SKIPCNT),1
	ret
@inside:				; carry if offset HL is not inside the
	push	hl			; module; preserves HL, BC
	ld	de,(psc_len)
	or	a
	sbc	hl,de
	pop	hl
	ccf
	ret

; psc_setsam / psc_setorn: select sample or ornament A for the channel
; at IX. Preserve HL and BC.
psc_setsam:
	push	hl
	ld	(ix+PSCC_SAMNUM),a
	ld	hl,0
	ld	l,a
	add	hl,hl
	ld	de,PSC_SAMTAB
	add	hl,de
	ld	de,(psc_base)
	add	hl,de
	call	psc_abs
	ld	de,PSC_SAMTAB
	add	hl,de
	ld	(ix+PSCC_SAMPTR),hl
	pop	hl
	ret
psc_setorn:
	push	hl
	ld	(ix+PSCC_ORNNUM),a
	ld	hl,0
	ld	l,a
	add	hl,hl
	ld	de,(psc_ornptr)
	add	hl,de
	call	psc_word
	ld	de,(psc_ornptr)
	add	hl,de
	ld	(ix+PSCC_ORNPTR),hl
	pop	hl
	ret

; psc_interp: read one row of pattern data for the channel at IX, whose
; number (0 to 2) is in psc_chan. What the row asks for is noted in
; psc_fl and acted on once the whole row has been read:
;   bit 0 ornament off, 1 sound off, 2 fade, 3 slide to note,
;   4 slide, 5 volume given, 6 note given.
psc_interp:
	xor	a
	ld	(psc_fl),a
	ld	hl,(ix+PSCC_ADDR)
	push	hl			; (bytes read in this row: see @loop)
	ld	hl,0
	ld	(psc_rowlim),hl
	pop	hl
@loop:
	push	hl			; a damaged pattern: give up on the
	ld	hl,(psc_rowlim)	; row after 65536 bytes
	dec	hl
	ld	(psc_rowlim),hl
	ld	a,h
	or	l
	pop	hl
	jp	z,@rowlim
	ld	a,(hl)
	cp	0C0h
	jp	nc,@endrow
	cp	0A0h
	jp	nc,@ornament
	cp	07Eh
	jp	nc,@sample
	cp	057h
	jp	c,@note
	jp	z,@envvol
	cp	067h
	jp	c,@volume
	cp	06Bh
	jr	c,@skip1		; 67h-6Ah: a parameter to step over
	sub	06Bh
	jp	z,@slideup
	dec	a
	jp	z,@slidedn
	dec	a
	jp	z,@porta
	dec	a
	jp	z,@speed
	dec	a
	jp	z,@ornoff
	dec	a
	jp	z,@fade
	dec	a
	jp	z,@breakorn
	sub	9			; 72h-79h: a parameter to step over
	jr	c,@skip1
	jp	z,@envelope
	dec	a
	jp	z,@noise
	dec	a
	jp	z,@off
	ld	(ix+PSCC_BRKS),1		; 7Dh
	jr	@next
@skip1:
	inc	hl
@next:
	inc	hl
	jp	@loop
@ornament:
	sub	0A0h
	call	psc_setorn
	jr	@next
@sample:
	cp	080h
	jr	c,@next
	sub	080h
	call	psc_setsam
	jr	@next
@slideup:
	inc	hl
	ld	de,0
	ld	e,(hl)
	ld	(ix+PSCC_ADD),de
	ld	a,16
	jp	@flag
@slidedn:
	inc	hl
	push	hl
	ld	a,(hl)			; minus the signed byte
	ld	l,a
	rla
	sbc	a,a
	ld	h,a
	call	psc_sx
	ex	de,hl
	ld	hl,0
	or	a
	sbc	hl,de
	ld	(ix+PSCC_ADD),hl
	pop	hl
	ld	a,16
	jp	@flag
@porta:
	inc	hl
	ld	de,0
	ld	e,(hl)
	ld	(ix+PSCC_ADD),de
	ld	a,8
	jr	@flag
@speed:
	inc	hl
	ld	a,(hl)
	ld	(psc_delay),a
	jr	@next
@ornoff:
	inc	hl
	ld	a,1
	jr	@flag
@fade:
	inc	hl
	ld	a,(hl)
	ld	(ix+PSCC_VC1),a
	ld	a,4
	jr	@flag
@breakorn:
	ld	(ix+PSCC_BRKO),1
	jr	@skip1
@envelope:
	inc	hl
	ld	a,(psc_chan)		; only channel B's are obeyed
	dec	a
	jr	nz,@next
	ld	a,(hl)
	and	15
	ld	(ay_regs+13),a
	inc	hl
	ld	a,(hl)
	ld	(ay_regs+11),a
	inc	hl
	ld	a,(hl)
	ld	(ay_regs+12),a
	jp	@next
@noise:
	inc	hl
	ld	a,(psc_chan)
	dec	a
	jp	nz,@next
	ld	a,(hl)
	ld	(psc_noise),a
	jp	@next
@off:
	ld	a,2			; this cancels what came before it
	ld	(psc_fl),a
	jp	@next
@envvol:
	ld	(ix+PSCC_IVOL),15
	ld	(ix+PSCC_ENV),1
	ld	a,32
	jr	@flag
@volume:
	sub	057h
	ld	(ix+PSCC_IVOL),a
	ld	(ix+PSCC_ENV),0
	ld	a,32
	jr	@flag
@note:
	ld	(ix+PSCC_NOTE),a
	ld	a,96
@flag:
	push	hl
	ld	hl,psc_fl
	or	(hl)
	ld	(hl),a
	pop	hl
	jp	@next
@rowlim:				; (as a one-row gap)
	ld	a,0C0h
@endrow:
	sub	0BFh
	ld	(ix+PSCC_SKIPCNT),a
	inc	hl
	ld	(ix+PSCC_ADDR),hl
	ld	a,(psc_fl)
	ld	c,a
	bit	6,c			; a note: everything starts afresh
	jr	z,@nonote
	xor	a
	ld	(ix+PSCC_BRKO),a
	ld	(ix+PSCC_BRKS),a
	ld	(ix+PSCC_TSEN),a
	ld	(ix+PSCC_NACC),a
	ld	(ix+PSCC_VC),a
	ld	(ix+PSCC_SAMPOS),a
	ld	(ix+PSCC_ORNPOS),a
	ld	hl,0
	ld	(ix+PSCC_TACC),hl
	ld	(ix+PSCC_CTS),hl
	inc	a
	ld	(ix+PSCC_ORNEN),a
	ld	(ix+PSCC_ON),a
@nonote:
	bit	5,c
	jr	z,@novol
	ld	a,(ix+PSCC_IVOL)
	ld	(ix+PSCC_VOL),a
@novol:
	bit	4,c
	jr	z,@noslide
	ld	(ix+PSCC_GLISS),0
	ld	(ix+PSCC_TSEN),1
@noslide:
	bit	3,c			; slide from the pitch now sounding to
	jr	z,@noporta		; this row's note
	ld	a,(ix+PSCC_NOTE)
	call	psc_freq
	ex	de,hl
	ld	hl,0
	ld	l,(ix+PSCC_TON)
	ld	h,(ix+PSCC_TON+1)
	or	a
	sbc	hl,de
	ld	(ix+PSCC_CTS),hl
	ld	(ix+PSCC_GLISS),1
	ld	(ix+PSCC_TSEN),1
	jp	m,@noporta
	ld	de,(ix+PSCC_ADD)		; above it: slide downwards
	ld	hl,0
	or	a
	sbc	hl,de
	ld	(ix+PSCC_ADD),hl
@noporta:
	bit	2,c
	jr	z,@nofade
	ld	a,(ix+PSCC_VC1)
	ld	(ix+PSCC_VINC),1
	bit	6,a
	jr	z,@fadeset
	or	080h
	neg
	ld	(ix+PSCC_VINC),0
@fadeset:
	ld	(ix+PSCC_VC),a
	ld	(ix+PSCC_VCI),a
@nofade:
	bit	1,c
	jr	z,@notoff
	xor	a
	ld	(ix+PSCC_BRKO),a
	ld	(ix+PSCC_ORNEN),a
	ld	(ix+PSCC_ON),a
	ld	(ix+PSCC_BRKS),a
	ld	(ix+PSCC_TSEN),a
@notoff:
	bit	0,c
	ret	z
	ld	(ix+PSCC_ORNEN),0
	ret

; psc_chreg: work out this frame's tone and amplitude for the channel at
; IX and add its bits to the mixer.
psc_chreg:
	ld	a,(ix+PSCC_ON)
	or	a
	jp	z,@silent
	ld	a,(ix+PSCC_NOTE)
	ld	(psc_j),a
	ld	a,(ix+PSCC_ORNEN)
	or	a
	jr	z,@noorn
	ld	hl,0			; the 2 byte ornament step
	ld	l,(ix+PSCC_ORNPOS)
	add	hl,hl
	ld	de,(ix+PSCC_ORNPTR)
	add	hl,de
	ld	b,(hl)			; B = marks and noise offset
	inc	hl
	ld	c,(hl)			; C = note offset
	ld	a,(ix+PSCC_NACC)
	add	a,b
	ld	(ix+PSCC_NACC),a
	ld	a,(psc_j)		; the note moves by the offset and
	add	a,c			; wraps round within the 86 notes
	jp	p,@notlow
	add	a,056h
@notlow:
	cp	056h
	jr	c,@wrapped
	sub	056h
	cp	056h
	jr	c,@wrapped
	ld	a,055h
@wrapped:
	ld	(psc_j),a
	bit	7,b
	jr	nz,@ornkeep
	ld	a,(ix+PSCC_ORNPOS)
	ld	(ix+PSCC_ORNLOOP),a
@ornkeep:
	bit	6,b
	jr	nz,@ornon
	ld	a,(ix+PSCC_BRKO)
	or	a
	jr	nz,@ornbroken
	ld	a,(ix+PSCC_ORNLOOP)
	ld	(ix+PSCC_ORNPOS),a
	jr	@noorn
@ornbroken:
	ld	(ix+PSCC_BRKO),0
@ornon:
	bit	5,b
	jr	nz,@ornnext
	ld	(ix+PSCC_ORNEN),0
@ornnext:
	inc	(ix+PSCC_ORNPOS)
@noorn:
	ld	a,(psc_j)		; (the note itself is moved, for good)
	ld	(ix+PSCC_NOTE),a
	ld	hl,0			; the 6 byte sample step
	ld	l,(ix+PSCC_SAMPOS)
	add	hl,hl
	push	hl
	pop	de
	add	hl,hl
	add	hl,de
	ld	de,(ix+PSCC_SAMPTR)
	add	hl,de
	ld	(psc_rec),hl
	call	psc_word
	ld	de,(ix+PSCC_TACC)
	add	hl,de
	ld	(ix+PSCC_TACC),hl
	ex	de,hl
	ld	a,(psc_j)
	call	psc_freq
	add	hl,de
	ld	(psc_ton),hl
	ld	a,(ix+PSCC_TSEN)
	or	a
	jr	z,@noslide
	ld	hl,(ix+PSCC_CTS)
	ld	de,(ix+PSCC_ADD)
	add	hl,de
	call	psc_sx
	ld	(ix+PSCC_CTS),hl
	; a slide to a note stops when it
	ld	a,(ix+PSCC_GLISS)
	; passes zero in the direction of travel
	or	a
	jr	z,@slideon
	ld	a,(ix+PSCC_CTS+2)
	rla
	jr	nc,@cpos
	; slide below zero: stop if the step
	ld	a,(ix+PSCC_ADD+2)
	rla				; is zero or downwards
	jr	c,@stop
	ld	hl,(ix+PSCC_ADD)
	ld	a,h
	or	l
	jr	nz,@slideon
	jr	@stop
@cpos:
	; at or above zero: stop if the step is
	ld	a,(ix+PSCC_ADD+2)
	rla				; zero or upwards
	jr	c,@slideon
@stop:
	ld	(ix+PSCC_TSEN),0
@slideon:
	ld	hl,(psc_ton)
	ld	de,(ix+PSCC_CTS)
	add	hl,de
	ld	(psc_ton),hl
@noslide:
	ld	hl,(psc_ton)
	ld	(ix+PSCC_TON),l
	ld	a,h
	and	0Fh
	ld	(ix+PSCC_TON+1),a
	ld	iy,(psc_rec)
	ld	b,(iy+4)		; B = masks, volume steps, marks
	ld	a,b
	and	9
	add	a,a
	add	a,a
	add	a,a
	ld	hl,psc_mixer
	or	(hl)
	ld	(hl),a
	ld	d,0			; D = change of volume this frame
	bit	1,b
	jr	z,@noup
	inc	d
@noup:
	bit	2,b
	jr	z,@nodown
	dec	d
@nodown:
	ld	a,(ix+PSCC_VC)		; fade
	or	a
	jr	z,@nofade
	dec	a
	ld	(ix+PSCC_VC),a
	jr	nz,@nofade
	ld	a,(ix+PSCC_VINC)
	or	a
	jr	z,@fadedown
	inc	d
	jr	@fadeagain
@fadedown:
	dec	d
@fadeagain:
	ld	a,(ix+PSCC_VCI)
	ld	(ix+PSCC_VC),a
@nofade:
	ld	a,(ix+PSCC_VOL)
	add	a,d
	jp	p,@volpos
	xor	a
@volpos:
	cp	16
	jr	c,@volok
	ld	a,15
@volok:
	ld	(ix+PSCC_VOL),a
	inc	a			; (volume + 1) * level / 16
	ld	l,a
	ld	a,(iy+3)
	and	15
	ld	h,a
	mlt	hl
	ld	a,l
	rrca
	rrca
	rrca
	rrca
	and	15
	ld	c,a
	ld	a,(ix+PSCC_ENV)
	or	a
	jr	z,@noenv
	bit	4,b
	jr	nz,@noenv
	set	4,c
@noenv:
	ld	(ix+PSCC_AMP),c
	bit	4,c			; under the envelope with noise masked,
	jr	z,@tonoise		; the step's offset moves the envelope
	bit	3,b			; period; otherwise the noise period
	jr	z,@tonoise
	ld	hl,ay_regs+11
	call	psc_word
	ld	a,(iy+2)
	ld	e,a
	rla
	sbc	a,a
	ld	d,a
	add	hl,de
	ld	a,l
	ld	(ay_regs+11),a
	ld	a,h
	ld	(ay_regs+12),a
	jr	@loop
@tonoise:
	ld	a,(ix+PSCC_NACC)
	add	a,(iy+2)
	ld	(ix+PSCC_NACC),a
	bit	3,b
	jr	nz,@loop
	and	31
	ld	(ay_regs+6),a
@loop:
	bit	7,b
	jr	nz,@samkeep
	ld	a,(ix+PSCC_SAMPOS)
	ld	(ix+PSCC_SAMLOOP),a
@samkeep:
	bit	6,b
	jr	nz,@samon
	ld	a,(ix+PSCC_BRKS)
	or	a
	jr	nz,@sambroken
	ld	a,(ix+PSCC_SAMLOOP)
	ld	(ix+PSCC_SAMPOS),a
	jr	@done
@sambroken:
	ld	(ix+PSCC_BRKS),0
@samon:
	bit	5,b
	jr	nz,@samnext
	ld	(ix+PSCC_ON),0
@samnext:
	inc	(ix+PSCC_SAMPOS)
	jr	@done
@silent:
	ld	(ix+PSCC_AMP),0
@done:
	ld	hl,psc_mixer
	srl	(hl)
	ret

; psc_play: advance the song by one frame and fill ay_regs.
psc_play:
	ld	a,0FFh
	ld	(ay_regs+13),a
	ld	hl,psc_delay_cnt
	dec	(hl)
	call	z,psc_rowtick
	xor	a
	ld	(psc_mixer),a
	ld	ix,psc_chA
	call	psc_chreg
	ld	ix,psc_chB
	call	psc_chreg
	ld	ix,psc_chC
	call	psc_chreg
	ld	a,(psc_mixer)
	ld	(ay_regs+7),a
	ld	hl,(psc_chA+PSCC_TON)
	ld	(ay_regs+0),hl
	ld	hl,(psc_chB+PSCC_TON)
	ld	(ay_regs+2),hl
	ld	hl,(psc_chC+PSCC_TON)
	ld	a,l
	ld	(ay_regs+4),a
	ld	a,h
	ld	(ay_regs+5),a
	ld	a,(psc_chA+PSCC_AMP)
	ld	(ay_regs+8),a
	ld	a,(psc_chB+PSCC_AMP)
	ld	(ay_regs+9),a
	ld	a,(psc_chC+PSCC_AMP)
	ld	(ay_regs+10),a
	ret

; psc_rowtick: the work done once per row: move to the next position if
; the pattern has run out, then read a row for each channel whose turn
; it is.
psc_rowtick:
	ld	hl,psc_row
	inc	(hl)
	ld	hl,psc_lines
	dec	(hl)
	call	z,psc_newpos
	xor	a
	ld	(psc_chan),a
	ld	ix,psc_chA
	dec	(ix+PSCC_SKIPCNT)
	call	z,psc_interp
	ld	a,1
	ld	(psc_chan),a
	ld	ix,psc_chB
	dec	(ix+PSCC_SKIPCNT)
	call	z,psc_interp
	ld	a,2
	ld	(psc_chan),a
	ld	ix,psc_chC
	dec	(ix+PSCC_SKIPCNT)
	call	z,psc_interp
	ld	a,(psc_noise)
	ld	c,a
	ld	hl,psc_chA+PSCC_NACC
	call	@addnoise
	ld	hl,psc_chB+PSCC_NACC
	call	@addnoise
	ld	hl,psc_chC+PSCC_NACC
	call	@addnoise
	ld	a,(psc_delay)
	ld	(psc_delay_cnt),a
	ret
@addnoise:
	ld	a,(hl)
	add	a,c
	ld	(hl),a
	ret

; psc_newpos: set the three channels up from the next position.
psc_newpos:
	ld	hl,psc_pos
	inc	(hl)
	xor	a
	ld	(psc_row),a
	ld	hl,(psc_pp)
	inc	hl
	ld	a,(hl)
	dec	hl
	inc	a
	jr	nz,@more
	ld	hl,psc_loops		; end of the list: note it, and go to
	inc	(hl)			; where the list says to carry on
	ld	hl,(psc_pp)
	inc	hl
	inc	hl
	call	psc_abs
	push	hl
	ld	de,(psc_patptr)		; which position that is
	or	a
	sbc	hl,de
	srl	h
	rr	l
	srl	h
	rr	l
	srl	h
	rr	l
	ld	a,l
	ld	(psc_pos),a
	pop	hl
@more:
	ld	a,(hl)
	ld	(psc_pat),a
	inc	hl
	ld	a,(hl)
	ld	(psc_lines),a
	inc	hl
	ld	ix,psc_chA
	call	@addr
	ld	ix,psc_chB
	call	@addr
	ld	ix,psc_chC
	call	@addr
	ld	(psc_pp),hl
	ret
@addr:
	push	hl
	call	psc_abs
	ld	(ix+PSCC_ADDR),hl
	ld	(ix+PSCC_SKIPCNT),1
	pop	hl
	inc	hl
	inc	hl
	ret

; psc_length: how many frames the song lasts before it ends. Call it
; straight after psc_init, and call psc_init again afterwards, because
; it works by running through all the song's rows. Out: HL = frames.
psc_length:
	ld	hl,0
	ld	(psc_frames),hl
	ld	(psc_rows),hl	; (rows counted)
@row:
	call	psc_rowtick
	ld	hl,(psc_rows)		; give up after 65536 rows, which no
	inc	hl			; real song needs (a damaged one that
	ld	(psc_rows),hl		; never ends)
	ld	a,(psc_rows+2)
	or	a
	jp	nz,@done
	ld	a,(psc_loops)
	or	a
	jr	nz,@done
	ld	de,0
	ld	a,(psc_delay)
	ld	e,a
	or	a
	jr	nz,@add
	inc	d			; a speed of 0 lasts 256 frames
@add:
	ld	hl,(psc_frames)
	add	hl,de
	ld	(psc_frames),hl
	ld	a,(psc_frames+2)	; give up on a song that never ends
	cp	10h
	jr	c,@row
@done:
	ld	hl,(psc_frames)
	ret