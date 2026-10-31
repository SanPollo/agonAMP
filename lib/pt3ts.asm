; pt3ts.asm - TurboSound: PT3 music for two AY chips.
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
; Part of the reusable agonAMP sound library in lib/. A TurboSound card
; holds two AY chips, and a TurboSound PT3 tune is two sets of three
; channels played together. This file plays one by running the PT3
; replayer (pt3play.asm, which it needs) twice a frame, keeping a copy
; of the replayer's state for each chip.
;
; There are two kinds of TurboSound PT3 file:
;
; 1. Two complete PT3 modules one after the other, usually followed by
;    a 16 byte footer ("PT3!", length, "PT3!", length, "02TS"). Each
;    chip plays its own module, and the two are independent: each has
;    its own speed and its own position.
; 2. One module whose header byte 98 is not a space but the number of
;    patterns. The first chip plays the module as it is. The second
;    plays the same position list with pattern n replaced by pattern
;    (count - 1 - n). The speed is shared: a speed command met by either
;    chip applies to both, so that the two stay in step.
;
; The file layouts were checked against the zxtune sources (formats/
; chiptune/aym/turbosound.cpp and protracker3*.cpp, GPL 3), which were
; read for the purpose; no code was copied. The sharing of the speed in
; the second kind is my reading of how the original Z80 player behaves;
; I had no source to check it against. It is what keeps the one tune of
; that kind I had to test in step.
;
; Entry points:
;   pt3ts_detect HL = address of the file, BC = its length. Returns A =
;                0 (and Z) if it is not a TurboSound tune, else 1 or 2
;                for the kinds above. Call it only on a file that is
;                known to be a PT3 module.
;   pt3ts_init   get the tune that pt3ts_detect accepted ready to play
;   pt3ts_play   advance one frame: fill ay_regs (first chip) and
;                ay_regs2 (second chip)
;   pt3ts_length frames the tune lasts (call pt3ts_init again afterwards)
;
; Results:
;   ay_regs, ay_regs2   as pt3play.asm fills ay_regs; ayvdp.asm defines
;                both and plays both (see ay_chips there). A program that
;                does not use ayvdp.asm must define them itself.
;   pt3_loops, pt3_pos, pt3_row and the rest of the replayer's variables
;                describe the first chip between calls.
;   pt3ts_c2     the second chip's copy of the replayer's state: the
;                variable pt3_xxx is at pt3ts_c2 + (pt3_xxx - pt3_ctx).
;                pt3ts_chA2, pt3ts_chB2 and pt3ts_chC2 are its channels.
;   pt3ts_kind   which kind of tune is being played
;
; All registers are used.

pt3ts_kind:	ds	1	; 0 not TurboSound, 1 two modules, 2 mirrored
pt3ts_count:	ds	1	; kind 2: number of patterns, else 0
pt3ts_speed:	ds	1	; kind 2: the speed both chips are playing at
pt3ts_base1:	ds	3	; address of the first chip's module
pt3ts_base2:	ds	3	; address of the second chip's module
pt3ts_frames:	ds	3	; pt3ts_length: frames counted
pt3ts_regs1:	ds	16	; the first chip's registers, put aside
; the first chip's state, put aside
pt3ts_c1:	ds	pt3_ctx_end-pt3_ctx
pt3ts_c2:	ds	pt3_ctx_end-pt3_ctx	; the second chip's state
; Places in the second chip's state.
pt3ts_chA2:	equ	pt3ts_c2+pt3_chA-pt3_ctx
pt3ts_chB2:	equ	pt3ts_c2+pt3_chB-pt3_ctx
pt3ts_chC2:	equ	pt3ts_c2+pt3_chC-pt3_ctx
pt3ts_delay2:	equ	pt3ts_c2+pt3_delay-pt3_ctx
pt3ts_pos2:	equ	pt3ts_c2+pt3_pos-pt3_ctx
pt3ts_row2:	equ	pt3ts_c2+pt3_row-pt3_ctx
pt3ts_rows:	ds	3	; length: rows counted

; The two signatures a PT3 module can start with.
pt3ts_sig1:	db	"ProTracker 3."
pt3ts_sig2:	db	"Vortex Tracker II"

; pt3ts_match: does the text at DE (B characters) appear at HL?
; Out: Z if so. Preserves HL.
pt3ts_match:
	push	hl
@cmp:
	ld	a,(de)
	cp	(hl)
	jr	nz,@no
	inc	hl
	inc	de
	djnz	@cmp
@no:
	pop	hl
	ret

pt3ts_detect:
	ld	(pt3ts_base1),hl
	ld	(pt3ts_base2),hl
	xor	a
	ld	(pt3ts_kind),a
	ld	(pt3ts_count),a
	; Kind 1: a second module begins somewhere after the first one's
	; header (which is 99 bytes at the very least).
	push	hl
	ld	hl,99+17
	or	a
	sbc	hl,bc
	pop	hl
	jr	nc,@kind2		; too short to hold one
	push	bc
	ld	de,99
	add	hl,de
	pop	bc
	push	hl
	push	bc
	pop	hl
	ld	de,99+17
	or	a
	sbc	hl,de
	push	hl
	pop	bc			; BC = places left to look at
	pop	hl
@scan:
	ld	a,(hl)			; (both signatures start differently,
	; so most places are passed over at once)
	cp	'P'
	jr	z,@sig1
	cp	'V'
	jr	nz,@nexts
	ld	de,pt3ts_sig2
	push	bc
	ld	b,17
	call	pt3ts_match
	pop	bc
	jr	z,@two
	jr	@nexts
@sig1:
	ld	de,pt3ts_sig1
	push	bc
	ld	b,13
	call	pt3ts_match
	pop	bc
	jr	z,@two
@nexts:
	inc	hl
	dec	bc
	push	hl			; (all 24 bits: files may pass 64 KB)
	ld	hl,0
	or	a
	sbc	hl,bc
	pop	hl
	jr	nz,@scan
	jr	@kind2
@two:
	ld	(pt3ts_base2),hl
	ld	a,1
	ld	(pt3ts_kind),a
	or	a
	ret
	; Kind 2: header byte 98 holds the number of patterns. To be
	; believed it must be more than the highest pattern number in the
	; position list (or a mirrored pattern would not exist), and less
	; than twice that.
@kind2:
	ld	ix,(pt3ts_base1)
	ld	a,(ix+98)
	cp	' '
	jr	z,@none
	ld	c,a			; C = the count
	ld	b,(ix+PT3_NUMPOS)
	ld	a,b
	or	a
	jr	z,@none
	ld	hl,(pt3ts_base1)
	ld	de,PT3_POSLIST
	add	hl,de
	ld	e,0			; E = highest entry (pattern * 3)
@max:
	ld	a,(hl)
	cp	e
	jr	c,@lower
	ld	e,a
@lower:
	inc	hl
	djnz	@max
	ld	a,e			; D = highest pattern number
	ld	d,0FFh
@div3:
	inc	d
	sub	3
	jr	nc,@div3
	ld	a,d
	cp	c
	jr	nc,@none		; count <= highest
	add	a,a
	jr	c,@take
	cp	c
	jr	c,@none			; count > 2 * highest
	jr	z,@none
@take:
	ld	a,c			; (a position entry is pattern * 3 in a
	cp	87			; byte, so 86 patterns is the most the
	jr	nc,@none		; mirroring can handle)
	ld	(pt3ts_count),a
	ld	a,2
	ld	(pt3ts_kind),a
	or	a
	ret
@none:
	xor	a
	ret

pt3ts_init:
	ld	a,(pt3ts_count)		; the second chip first
	ld	hl,(pt3ts_base2)
	call	pt3_init_m
	ld	hl,pt3_ctx
	ld	de,pt3ts_c2
	ld	bc,pt3_ctx_end-pt3_ctx
	ldir
	ld	hl,(pt3ts_base1)
	call	pt3_init
	ld	a,(pt3_delay)
	ld	(pt3ts_speed),a
	ld	hl,ay_regs2
	ld	b,13
@regs:
	ld	(hl),0
	inc	hl
	djnz	@regs
	ld	(hl),0FFh
	ret

; pt3ts_in2: put the first chip's state and registers aside and bring
; the second chip's state in. pt3ts_out2: the reverse, leaving the
; registers just made in ay_regs2.
pt3ts_in2:
	ld	hl,pt3_ctx
	ld	de,pt3ts_c1
	ld	bc,pt3_ctx_end-pt3_ctx
	ldir
	ld	hl,pt3ts_c2
	ld	de,pt3_ctx
	ld	bc,pt3_ctx_end-pt3_ctx
	ldir
	ld	hl,ay_regs
	ld	de,pt3ts_regs1
	ld	bc,14
	ldir
	ret
pt3ts_out2:
	ld	hl,ay_regs
	ld	de,ay_regs2
	ld	bc,14
	ldir
	ld	hl,pt3ts_regs1
	ld	de,ay_regs
	ld	bc,14
	ldir
	ld	hl,pt3_ctx
	ld	de,pt3ts_c2
	ld	bc,pt3_ctx_end-pt3_ctx
	ldir
	ld	hl,pt3ts_c1
	ld	de,pt3_ctx
	ld	bc,pt3_ctx_end-pt3_ctx
	ldir
	ret

; pt3ts_share1: after the first chip has played (kind 2 only): if it met
; a speed command, the second chip takes the new speed too. It has not
; read its row yet this frame, so it will count from the new speed.
pt3ts_share1:
	ld	a,(pt3ts_kind)
	cp	2
	ret	nz
	ld	a,(pt3_delay)
	ld	hl,pt3ts_speed
	cp	(hl)
	ret	z
	ld	(hl),a
	ld	(pt3ts_delay2),a
	ret

; pt3ts_share2: after the second chip has played and its state has been
; put away (kind 2 only): if it met a speed command, the first chip
; takes the new speed. The first chip has already started counting this
; row at the old speed, so its count is set as well.
pt3ts_share2:
	ld	a,(pt3ts_kind)
	cp	2
	ret	nz
	ld	a,(pt3ts_delay2)
	ld	hl,pt3ts_speed
	cp	(hl)
	ret	z
	ld	(hl),a
	ld	(pt3_delay),a
	ld	(pt3_delay_cnt),a
	ret

pt3ts_play:
	call	pt3_play
	call	pt3ts_share1
	call	pt3ts_in2
	call	pt3_play
	call	pt3ts_out2
	jp	pt3ts_share2

; pt3ts_length: how many frames the tune lasts: until the first chip's
; module ends. Call it straight after pt3ts_init, and call pt3ts_init
; again afterwards. Out: HL = frames.
pt3ts_length:
	ld	a,(pt3ts_kind)
	cp	2
	jp	nz,pt3_length		; kind 1: the first module on its own
	ld	hl,0			; kind 2: both, row by row, because
	ld	(pt3ts_frames),hl	; either can change the speed
	ld	(pt3ts_rows),hl	; (rows counted)
@row:
	call	pt3_rowtick
	ld	hl,(pt3ts_rows)		; give up after 65536 rows, which no
	inc	hl			; real song needs (a damaged one that
	ld	(pt3ts_rows),hl		; never ends)
	ld	a,(pt3ts_rows+2)
	or	a
	jp	nz,@done
	call	pt3ts_share1
	call	pt3ts_in2
	call	pt3_rowtick
	call	pt3ts_out2
	call	pt3ts_share2
	ld	a,(pt3_loops)
	or	a
	jr	nz,@done
	ld	de,0
	ld	a,(pt3_delay)
	ld	e,a
	or	a
	jr	nz,@add
	inc	d			; a speed of 0 lasts 256 frames
@add:
	ld	hl,(pt3ts_frames)
	add	hl,de
	ld	(pt3ts_frames),hl
	ld	a,(pt3ts_frames+2)	; give up on a song that never ends
	cp	10h
	jr	c,@row
@done:
	ld	hl,(pt3ts_frames)
	ret