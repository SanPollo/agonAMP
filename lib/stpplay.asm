; stpplay.asm - Sound Tracker Pro (.stp) module replayer.
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
; Part of the reusable agonAMP sound library in lib/. It turns a Sound
; Tracker Pro module held in memory into AY-3-8912 register values, one
; set per 50 Hz frame, in the table ay_regs (which ayvdp.asm defines and
; plays). It needs only
; notetab.inc (its note table, nt_st) from the rest of the library.
;
; Written for the eZ80 in ADL mode. I found no written description of
; this format to work from: the behaviour was taken from reading the
; source of an existing player, STPPlay.h of the ESP32AY project, and
; this code was then written to do the same. No code was copied. The
; note table is Sound Tracker's (see stcplay.asm).
;
; The module: speed, then pointers to the position list, the pattern
; table, the ornament table and the sample table, and a byte that is 0
; if the tables still hold the addresses the module was compiled for
; (stp_init then converts them, changing the module in memory). The
; position list is a count, a loop position, then a pattern and a note
; offset for each position. Pattern streams hold:
;   01h-60h  note; ends the row         61h-6Fh  select sample
;   70h-7Fh  select ornament, envelope and slide off
;   80h-BFh  rows to leave empty
;   C0h-CFh  envelope on (C1h-CFh: shape, then its period, 1 byte)
;   D0h-DFh  sound off; ends the row    E0h-EFh  nothing; ends the row
;   F0h n    slide by n per frame       F1h-FFh  volume (attenuation)
;   00h at a row start: end of the pattern
;
; Entry points:
;   stp_init   HL = address of the module, BC = its length. Returns with
;              carry set if the header does not look like an STP module.
;   stp_play   advance one frame and fill ay_regs
;   stp_length frames the song lasts (call stp_init again afterwards)
;
; Results:
;   ay_regs    R13 is 0FFh on frames where the shape was not written.
;   stp_loops  goes up by one each time the song ends and loops.
;   stp_pos, stp_numpos, stp_pat, stp_row, stp_delay (in that order in
;   memory) and the first four bytes of stp_chA/B/C (note, sample,
;   ornament, sounding) can be read for display.
;
; All registers are used.

; Per-channel state, addressed through IX.
TP_NOTE:	equ	0	; 1: note number
TP_SAMNUM:	equ	1	; 1: sample number (for display)
TP_ORNNUM:	equ	2	; 1: ornament number (for display)
TP_ON:		equ	3	; 1: non-zero if the channel is sounding
TP_ADDR:	equ	4	; 3: address of next byte of pattern data
TP_ORNPTR:	equ	7	; 3: address of the ornament's offsets
TP_SAMPTR:	equ	10	; 3: address of the sample's 4 byte steps
TP_TON:		equ	13	; 3: tone period sent to the AY
TP_CTS:		equ	16	; 3: tone slide so far
TP_ORNPOS:	equ	19	; 1
TP_ORNLOOP:	equ	20	; 1
TP_ORNLEN:	equ	21	; 1
TP_SAMPOS:	equ	22	; 1
TP_SAMLOOP:	equ	23	; 1
TP_SAMLEN:	equ	24	; 1
TP_VOL:		equ	25	; 1: attenuation, 0 to 14
TP_SKIPN:	equ	26	; 1: empty rows after each row
TP_AMP:		equ	27	; 1: amplitude sent to the AY
TP_ENV:		equ	28	; 1: non-zero if the envelope is in use
TP_GLISS:	equ	29	; 1: slide per frame (signed)
TP_SKIPCNT:	equ	30	; 1: rows left before the next one (signed)
TP_SIZE:	equ	31

stp_base:	ds	3	; address of the module
stp_len:	ds	3	; its length
stp_o_pos:	ds	3	; offsets of the four tables in the module
stp_o_pat:	ds	3
stp_o_orn:	ds	3
stp_o_sam:	ds	3
stp_o_end:	ds	3	; offset just past the sample table
stp_delta:	ds	3	; amount to take off compiled-in addresses
stp_posptr:	ds	3	; addresses of the four tables
stp_patptr:	ds	3
stp_ornptr:	ds	3
stp_samptr:	ds	3
; Everything from here to stp_vars_end is cleared by stp_init.
stp_vars:
stp_chA:	ds	TP_SIZE
stp_chB:	ds	TP_SIZE
stp_chC:	ds	TP_SIZE
		ds	2	; spill room for 24 bit loads
stp_pos:	ds	1	; current position       (these five are
stp_numpos:	ds	1	; number of positions     kept together,
stp_pat:	ds	1	; current pattern number  in this order,
stp_row:	ds	1	; row within the pattern  for display)
stp_delay:	ds	1	; frames per row
stp_delay_cnt:	ds	1	; frames until the next row
stp_transp:	ds	1	; note offset of the current position
stp_mixer:	ds	1	; mixer value being assembled
stp_frames:	ds	3	; stp_length: frames counted
stp_loops:	ds	1	; times the end of the song was reached
stp_vars_end:
stp_rows:	ds	3	; length: rows counted
stp_rowlim:	ds	3	; bytes left in this pattern row

; stp_word: HL = address of a 16 bit value. Out: HL = the value.
stp_word:
	ld	e,(hl)
	inc	hl
	ld	d,(hl)
	ld	hl,0
	ld	l,e
	ld	h,d
	ret

; stp_abs: HL = address of a 16 bit offset. Out: HL = module address +
; that offset. Preserves BC.
stp_abs:
	call	stp_word
	ld	de,(stp_base)
	add	hl,de
	ret

; stp_hdr: HL = the 16 bit offset at header byte A, with carry set if it
; lies beyond the end of the module.
stp_hdr:
	ld	hl,(stp_base)
	ld	de,0
	ld	e,a
	add	hl,de
	call	stp_word
	push	hl
	ex	de,hl
	ld	hl,(stp_len)
	or	a
	sbc	hl,de			; carry if offset > length
	pop	hl
	ret

stp_init:
	ld	(stp_base),hl
	ld	(stp_len),bc
	push	hl
	ld	hl,10			; too short for a header?
	or	a
	sbc	hl,bc
	pop	hl
	ccf
	ret	c
	; The four tables lie in a fixed arrangement: the pattern table
	; straight after the position list, the ornament table a whole
	; number of patterns later, the sample table 32 bytes after that.
	ld	a,1
	call	stp_hdr
	ret	c
	ld	(stp_o_pos),hl
	ld	a,3
	call	stp_hdr
	ret	c
	ld	(stp_o_pat),hl
	ld	a,5
	call	stp_hdr
	ret	c
	ld	(stp_o_orn),hl
	ld	a,7
	call	stp_hdr
	ret	c
	ld	(stp_o_sam),hl
	ld	de,(stp_o_orn)
	or	a
	sbc	hl,de
	ld	de,020h
	or	a
	sbc	hl,de
	scf
	ret	nz
	ld	hl,(stp_o_orn)
	ld	de,(stp_o_pat)
	or	a
	sbc	hl,de
	jr	z,@bad			; no patterns
	jr	c,@bad			; ornaments before patterns
@six:
	ld	de,6			; a multiple of 6 apart?
	or	a
	sbc	hl,de
	jr	z,@sixok
	jr	nc,@six
@bad:
	scf
	ret
@sixok:
	ld	hl,(stp_o_pos)		; positions * 2 + 2 bytes of list
	ld	de,(stp_base)
	add	hl,de
	inc	hl			; (the loop position must be one of
	ld	a,(hl)			; them, so there must be at least one)
	dec	hl
	cp	(hl)
	jr	nc,@bad
	ld	a,(hl)
	ld	hl,0
	ld	l,a
	add	hl,hl
	inc	hl
	inc	hl
	ld	de,(stp_o_pos)
	add	hl,de
	ld	de,(stp_o_pat)
	or	a
	sbc	hl,de
	scf
	ret	nz
	ld	hl,(stp_o_sam)		; room for the sample table?
	ld	de,30
	add	hl,de
	ld	(stp_o_end),hl
	ex	de,hl
	ld	hl,(stp_len)		; (the table ends before o_end)
	or	a
	sbc	hl,de
	ret	c
	; A module whose 10th byte is 0 still has compiled-in addresses
	; in its pattern, ornament and sample tables. They are turned
	; into offsets here, and the byte is set so that this is done once.
	ld	ix,(stp_base)
	ld	a,(ix+9)
	or	a
	jr	nz,@ready
	ld	hl,(stp_o_pat)
	ld	de,(stp_base)
	add	hl,de
	push	hl
	call	stp_word		; the first address in the table...
	push	hl
	ld	hl,(stp_base)		; ...is 10 bytes into the module, or 63
	ld	de,10			; if it starts with the "KSA" text
	add	hl,de
	ld	de,stp_ksa
	ld	b,28
@ksa:
	ld	a,(de)
	cp	(hl)
	jr	nz,@noksa
	inc	hl
	inc	de
	djnz	@ksa
@noksa:
	pop	hl
	ld	de,10
	ld	a,b
	or	a
	jr	nz,@plain
	ld	de,63
@plain:
	or	a
	sbc	hl,de
	jr	nc,@delta
	pop	hl
	scf
	ret
@delta:
	ld	(stp_delta),hl
	ld	hl,(stp_o_end)		; words from the pattern table on
	ld	de,(stp_o_pat)
	or	a
	sbc	hl,de
	srl	h
	rr	l
	push	hl
	pop	bc
	pop	hl
@fix:
	ld	a,b
	or	c
	jr	z,@fixed
	push	bc
	push	hl
	call	stp_word
	ld	de,(stp_delta)
	or	a
	sbc	hl,de
	ex	de,hl
	pop	hl
	ld	(hl),e
	inc	hl
	ld	(hl),d
	inc	hl
	pop	bc
	dec	bc
	jr	@fix
@fixed:
	ld	(ix+9),1
@ready:
	ld	hl,stp_vars		; clear the playing state
	ld	de,stp_vars+1
	ld	bc,stp_vars_end-stp_vars-1
	ld	(hl),0
	ldir
	ld	hl,ay_regs
	ld	b,13
@regs:
	ld	(hl),0
	inc	hl
	djnz	@regs
	ld	(hl),0FFh
	ld	de,(stp_base)		; the tables as addresses
	ld	hl,(stp_o_pos)
	add	hl,de
	ld	(stp_posptr),hl
	ld	a,(hl)
	ld	(stp_numpos),a
	ld	hl,(stp_o_pat)
	add	hl,de
	ld	(stp_patptr),hl
	ld	hl,(stp_o_orn)
	add	hl,de
	ld	(stp_ornptr),hl
	ld	hl,(stp_o_sam)
	add	hl,de
	ld	(stp_samptr),hl
	ld	a,(de)
	ld	(stp_delay),a
	ld	a,1
	ld	(stp_delay_cnt),a
	ld	ix,stp_chA
	call	@chinit
	ld	ix,stp_chB
	call	@chinit
	ld	ix,stp_chC
	call	@chinit
	xor	a
	call	stp_setpos
	ld	a,0FFh			; becomes row 0 on the first frame
	ld	(stp_row),a
	or	a
	ret
@chinit:
	xor	a
	call	stp_setsam
	xor	a
	jp	stp_setorn
stp_ksa:	db	"KSA SOFTWARE COMPILATION OF "

; stp_setpos: point the channels at the pattern for position A.
stp_setpos:
	ld	(stp_pos),a
	ld	hl,0
	ld	l,a
	add	hl,hl
	ld	de,(stp_posptr)
	add	hl,de
	inc	hl
	inc	hl
	ld	a,(hl)			; offset of the pattern in the table
	inc	hl
	ld	c,(hl)			; note offset for the whole position
	ld	hl,stp_transp
	ld	(hl),c
	ld	hl,0
	ld	l,a
	ld	c,0FFh			; pattern number = offset / 6
@div6:
	inc	c
	sub	6
	jr	nc,@div6
	ld	a,c
	ld	(stp_pat),a
	ld	de,(stp_patptr)
	add	hl,de
	ld	ix,stp_chA
	call	@addr
	ld	ix,stp_chB
	call	@addr
	ld	ix,stp_chC
@addr:
	push	hl
	call	stp_abs
	ld	(ix+TP_ADDR),hl
	pop	hl
	inc	hl
	inc	hl
	ret

; stp_setsam / stp_setorn: select sample or ornament A for the channel
; at IX. Each starts with a loop position and a length. Preserve HL, BC.
stp_setsam:
	push	hl
	ld	(ix+TP_SAMNUM),a
	ld	hl,0
	ld	l,a
	add	hl,hl
	ld	de,(stp_samptr)
	add	hl,de
	call	stp_abs
	ld	a,(hl)
	ld	(ix+TP_SAMLOOP),a
	inc	hl
	ld	a,(hl)
	ld	(ix+TP_SAMLEN),a
	inc	hl
	ld	(ix+TP_SAMPTR),hl
	pop	hl
	ret
stp_setorn:
	push	hl
	ld	(ix+TP_ORNNUM),a
	ld	hl,0
	ld	l,a
	add	hl,hl
	ld	de,(stp_ornptr)
	add	hl,de
	call	stp_abs
	ld	a,(hl)
	ld	(ix+TP_ORNLOOP),a
	inc	hl
	ld	a,(hl)
	ld	(ix+TP_ORNLEN),a
	inc	hl
	ld	(ix+TP_ORNPTR),hl
	pop	hl
	ret

; stp_interp: read one row of pattern data for the channel at IX.
stp_interp:
	ld	hl,(ix+TP_ADDR)
	push	hl			; (bytes read in this row: see @loop)
	ld	hl,0
	ld	(stp_rowlim),hl
	pop	hl
@loop:
	push	hl			; a damaged pattern: give up on the
	ld	hl,(stp_rowlim)	; row after 65536 bytes
	dec	hl
	ld	(stp_rowlim),hl
	ld	a,h
	or	l
	pop	hl
	jp	z,@quit
	ld	a,(hl)
	or	a
	jr	z,@next
	cp	061h
	jr	c,@note
	cp	070h
	jr	c,@sample
	cp	080h
	jr	c,@ornament
	cp	0C0h
	jr	c,@skip
	cp	0D0h
	jr	c,@envelope
	cp	0E0h
	jr	c,@off
	cp	0F0h
	jr	c,@quit
	jr	z,@slide
	sub	0F1h
	ld	(ix+TP_VOL),a
@next:
	inc	hl
	jr	@loop
@note:
	dec	a
	ld	(ix+TP_NOTE),a
	xor	a
	ld	(ix+TP_SAMPOS),a
	ld	(ix+TP_ORNPOS),a
	ld	de,0
	ld	(ix+TP_CTS),de
	ld	(ix+TP_ON),1
	jr	@quit
@sample:
	sub	061h
	call	stp_setsam
	jr	@next
@ornament:
	sub	070h
	call	stp_setorn
	ld	(ix+TP_ENV),0
	ld	(ix+TP_GLISS),0
	jr	@next
@skip:
	sub	080h
	ld	(ix+TP_SKIPN),a
	jr	@next
@envelope:
	cp	0C0h
	jr	z,@envon
	sub	0C0h
	ld	(ay_regs+13),a
	inc	hl
	ld	a,(hl)
	ld	(ay_regs+11),a
@envon:
	ld	(ix+TP_ENV),1
	ld	(ix+TP_ORNLOOP),0
	ld	(ix+TP_GLISS),0
	ld	(ix+TP_ORNLEN),1
	jr	@next
@off:
	ld	(ix+TP_ON),0
	jr	@quit
@slide:
	inc	hl
	ld	a,(hl)
	ld	(ix+TP_GLISS),a
	jr	@next
@quit:
	inc	hl
	ld	(ix+TP_ADDR),hl
	ld	a,(ix+TP_SKIPN)
	ld	(ix+TP_SKIPCNT),a
	ret

; stp_chreg: work out this frame's tone and amplitude for the channel at
; IX and add its bits to the mixer.
stp_chreg:
	ld	a,(ix+TP_ON)
	or	a
	jp	z,@silent
	ld	a,(ix+TP_GLISS)		; the slide, sign extended
	ld	e,a
	rla
	sbc	a,a
	ld	d,a
	ld	hl,(ix+TP_CTS)
	add	hl,de
	ld	(ix+TP_CTS),hl
	ld	a,(stp_transp)
	add	a,(ix+TP_NOTE)
	ld	c,a
	ld	a,(ix+TP_ENV)		; no ornament while the envelope is on
	or	a
	jr	nz,@noorn
	ld	hl,0
	ld	l,(ix+TP_ORNPOS)
	ld	de,(ix+TP_ORNPTR)
	add	hl,de
	ld	a,c
	add	a,(hl)
	ld	c,a
@noorn:
	ld	a,c
	cp	96
	jr	c,@inrange
	ld	a,95
@inrange:
	ld	hl,0
	ld	l,a
	add	hl,hl
	ld	de,nt_st
	add	hl,de
	call	stp_word
	ld	de,(ix+TP_CTS)
	add	hl,de
	push	hl
	ld	hl,0			; the 4 byte sample step
	ld	l,(ix+TP_SAMPOS)
	add	hl,hl
	add	hl,hl
	ld	de,(ix+TP_SAMPTR)
	add	hl,de
	ld	b,(hl)			; B = noise mask, tone mask, amplitude
	inc	hl
	ld	c,(hl)			; C = noise period, envelope flag
	inc	hl
	call	stp_word		; tone offset
	pop	de
	add	hl,de
	ld	(ix+TP_TON),l
	ld	a,h
	and	0Fh
	ld	(ix+TP_TON+1),a
	ld	a,b
	and	15
	sub	(ix+TP_VOL)
	jp	p,@amppos
	xor	a
@amppos:
	bit	0,c
	jr	z,@noenv
	bit	0,(ix+TP_ENV)
	jr	z,@noenv
	or	16
@noenv:
	ld	(ix+TP_AMP),a
	ld	a,b
	srl	a
	and	048h
	ld	hl,stp_mixer
	or	(hl)
	ld	(hl),a
	bit	7,b
	jr	nz,@step
	ld	a,c
	srl	a
	and	31
	ld	(ay_regs+6),a
@step:
	ld	a,(ix+TP_ORNPOS)
	inc	a
	cp	(ix+TP_ORNLEN)
	jr	c,@ornok
	ld	a,(ix+TP_ORNLOOP)
@ornok:
	ld	(ix+TP_ORNPOS),a
	ld	a,(ix+TP_SAMPOS)
	inc	a
	cp	(ix+TP_SAMLEN)
	jr	c,@samok
	ld	a,(ix+TP_SAMLOOP)	; a loop position of 80h or more means
	bit	7,a			; the sample plays once and stops
	jr	z,@samok
	ld	(ix+TP_ON),0
@samok:
	ld	(ix+TP_SAMPOS),a
	jr	@done
@silent:
	ld	hl,stp_mixer
	ld	a,(hl)
	or	048h
	ld	(hl),a
	ld	(ix+TP_AMP),0
@done:
	ld	hl,stp_mixer
	srl	(hl)
	ret

; stp_play: advance the song by one frame and fill ay_regs.
stp_play:
	ld	a,0FFh
	ld	(ay_regs+13),a
	ld	hl,stp_delay_cnt
	dec	(hl)
	call	z,stp_rowtick
	xor	a
	ld	(stp_mixer),a
	ld	ix,stp_chA
	call	stp_chreg
	ld	ix,stp_chB
	call	stp_chreg
	ld	ix,stp_chC
	call	stp_chreg
	ld	a,(stp_mixer)
	ld	(ay_regs+7),a
	ld	hl,(stp_chA+TP_TON)
	ld	(ay_regs+0),hl
	ld	hl,(stp_chB+TP_TON)
	ld	(ay_regs+2),hl
	ld	hl,(stp_chC+TP_TON)
	ld	a,l
	ld	(ay_regs+4),a
	ld	a,h
	ld	(ay_regs+5),a
	ld	a,(stp_chA+TP_AMP)
	ld	(ay_regs+8),a
	ld	a,(stp_chB+TP_AMP)
	ld	(ay_regs+9),a
	ld	a,(stp_chC+TP_AMP)
	ld	(ay_regs+10),a
	ret

; stp_rowtick: the work done once per row: read the next row for each
; channel whose turn it is, moving to the next pattern when one ends.
stp_rowtick:
	ld	a,(stp_delay)
	ld	(stp_delay_cnt),a
	ld	hl,stp_row
	inc	(hl)
	ld	ix,stp_chA
	dec	(ix+TP_SKIPCNT)
	jp	p,@chb
	ld	hl,(ix+TP_ADDR)
	ld	a,(hl)
	or	a			; 0 in channel A ends the pattern
	jr	nz,@cha
	ld	a,(stp_numpos)
	ld	b,a
	ld	a,(stp_pos)
	inc	a
	cp	b
	jr	nz,@newpos
	ld	hl,stp_loops		; end of song: note it and loop
	inc	(hl)
	ld	hl,(stp_posptr)
	inc	hl
	ld	a,(hl)
@newpos:
	call	stp_setpos
	xor	a
	ld	(stp_row),a
	ld	ix,stp_chA
@cha:
	call	stp_interp
@chb:
	ld	ix,stp_chB
	dec	(ix+TP_SKIPCNT)
	call	m,stp_interp
	ld	ix,stp_chC
	dec	(ix+TP_SKIPCNT)
	call	m,stp_interp
	ret

; stp_length: how many frames the song lasts before it ends. Call it
; straight after stp_init, and call stp_init again afterwards, because
; it works by running through all the song's rows. Out: HL = frames.
stp_length:
	ld	hl,0
	ld	(stp_frames),hl
	ld	(stp_rows),hl	; (rows counted)
@row:
	call	stp_rowtick
	ld	hl,(stp_rows)		; give up after 65536 rows, which no
	inc	hl			; real song needs (a damaged one that
	ld	(stp_rows),hl		; never ends)
	ld	a,(stp_rows+2)
	or	a
	jp	nz,@done
	ld	a,(stp_loops)
	or	a
	jr	nz,@done
	ld	de,0
	ld	a,(stp_delay)
	ld	e,a
	or	a
	jr	nz,@add
	inc	d			; a speed of 0 lasts 256 frames
@add:
	ld	hl,(stp_frames)
	add	hl,de
	ld	(stp_frames),hl
	ld	a,(stp_frames+2)	; give up on a song that never ends
	cp	10h
	jr	c,@row
@done:
	ld	hl,(stp_frames)
	ret