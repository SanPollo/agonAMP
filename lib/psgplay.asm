; psgplay.asm - player for PSG files (AY register dumps).
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
; Part of the reusable agonAMP sound library in lib/. A PSG file is a
; log of the values written to an AY-3-8912 by an emulator, frame by
; frame. This reads one frame per call into ay_regs, which ayvdp.asm
; then plays. It needs nothing but the 16 byte table ay_regs.
;
; Format (from the Ay_Emul documentation): a header of 'PSG', 1Ah and 12
; more bytes, then a stream of:
;   0FFh        start of the next frame
;   0FEh, n     n * 4 frame starts, as n * 4 0FFh bytes would be: the
;               writes that follow belong to the last of those frames
;               (as zxtune reads it)
;   0FDh        end of the music
;   r, v        r = 0 to 15: write value v to AY register r
;               r = 16 to 252: something for another device; ignored
; Some files have only the first 4 bytes of the header; this is spotted
; by the byte at offset 4 being 0FEh or 0FFh. The file does not say what
; the AY's clock was. One frame is taken as 1/50 s.
;
; Entry points:
;   psg_init   HL = address of the file in memory, BC = its length.
;              Returns with carry set if it is not a PSG file.
;   psg_play   advance one frame and update ay_regs
;   psg_length frames the file lasts
;
; Results:
;   ay_regs    R13 is 0FFh on frames where it was not written.
;   psg_loops  goes up by one each time the end is reached; playing then
;              starts again from the beginning.
;
; Corrupts AF, BC, DE, HL.

psg_start:	ds	3	; first byte after the header
psg_end:	ds	3	; first byte after the data
psg_ptr:	ds	3	; next byte to read
psg_skip:	ds	3	; empty frames still to wait through
psg_frames:	ds	3	; psg_length: frames counted
psg_loops:	ds	1	; times the end has been reached

psg_init:
	push	hl
	add	hl,bc
	ld	(psg_end),hl
	ld	hl,4			; too short to be anything?
	or	a
	sbc	hl,bc
	pop	hl
	jr	c,@sig
@bad:
	scf
	ret
@sig:
	ld	a,(hl)
	cp	'P'
	jr	nz,@bad
	inc	hl
	ld	a,(hl)
	cp	'S'
	jr	nz,@bad
	inc	hl
	ld	a,(hl)
	cp	'G'
	jr	nz,@bad
	inc	hl
	ld	a,(hl)
	cp	01Ah
	jr	nz,@bad
	inc	hl
	ld	a,(hl)			; a marker here means a 4 byte header
	cp	0FEh
	jr	nc,@start
	ld	de,12
	add	hl,de
@start:
	ld	(psg_start),hl
	ld	(psg_ptr),hl
	ld	hl,0
	ld	(psg_skip),hl
	xor	a
	ld	(psg_loops),a
	ld	hl,ay_regs
	ld	b,13
@clr:
	ld	(hl),a
	inc	hl
	djnz	@clr
	ld	(hl),0FFh
	or	a			; carry clear: accepted
	ret

psg_play:
	ld	a,0FFh
	ld	(ay_regs+13),a
	ld	hl,(psg_skip)		; frame ends still due from an FE n?
	ld	a,h
	or	l
	jr	z,@read
	dec	hl
	ld	(psg_skip),hl
	ld	a,h
	or	l
	ret	nz			; more follow: this frame is empty
	ld	hl,(psg_ptr)		; the last: the writes after FE n are
	jr	@pairs			; this frame's
@read:
	ld	hl,(psg_ptr)
@token:
	call	psg_atend
	jr	c,@end
	ld	a,(hl)
	cp	0FFh
	jr	nz,@notff
	inc	hl
	jr	@pairs
@notff:
	cp	0FEh
	jr	nz,@notfe
	inc	hl
	call	psg_atend		; (no count after it: the end)
	jr	c,@end
	ld	a,(hl)			; FE n: n * 4 frame ends, this frame's
	inc	hl			; the first; the writes after it belong
	or	a			; to the last (FE 00: none, read on)
	jr	z,@token
	ld	(psg_ptr),hl
	ld	hl,0
	ld	l,a
	add	hl,hl
	add	hl,hl
	dec	hl
	ld	(psg_skip),hl
	ret
@notfe:
	cp	0FDh
	jr	z,@end
@pairs:
	call	psg_atend
	jr	c,@done
	ld	a,(hl)
	cp	0FDh			; any marker ends this frame's writes
	jr	nc,@done
	inc	hl
	ld	c,a
	call	psg_atend
	jr	c,@done
	ld	b,(hl)
	inc	hl
	ld	a,c
	cp	14			; only R0 to R13 are sound registers
	jr	nc,@pairs
	cp	13
	jr	nz,@store
	ld	a,b			; the shape is 4 bits; 0FFh is kept to
	and	0Fh			; mean "not written"
	ld	b,a
	ld	a,c
@store:
	push	hl
	ld	hl,ay_regs
	ld	de,0
	ld	e,a
	add	hl,de
	ld	(hl),b
	pop	hl
	jr	@pairs
@done:
	ld	(psg_ptr),hl
	ret
@end:
	ld	hl,psg_loops		; note the end and go round again
	inc	(hl)
	ld	hl,(psg_start)
	ld	(psg_ptr),hl
	ret

; psg_length: how many frames the file lasts. Call it after psg_init;
; it does not disturb the playing position. Out: HL = frames.
psg_length:
	ld	hl,0
	ld	(psg_frames),hl
	ld	hl,(psg_start)
@scan:
	call	psg_atend
	jr	c,@done
	ld	a,(hl)
	inc	hl
	cp	0FFh
	jr	z,@one
	cp	0FEh
	jr	z,@many
	cp	0FDh
	jr	z,@done
	; a register number: step over its value
	inc	hl
	jr	@scan
@one:
	ld	bc,1
	jr	@add
@many:
	call	psg_atend
	jr	c,@done
	ld	bc,0
	ld	c,(hl)
	inc	hl
	ld	a,c			; (FE 00 is no frame, as psg_play
	or	a			; takes it)
	jr	z,@scan
	push	hl
	push	bc
	pop	hl
	add	hl,hl
	add	hl,hl
	push	hl
	pop	bc
	pop	hl
@add:
	push	hl
	ld	hl,(psg_frames)
	add	hl,bc
	ld	(psg_frames),hl
	pop	hl
	jr	nc,@scan
	ld	hl,0FFFFFFh		; (more than 24 bits can count)
	ld	(psg_frames),hl
@done:
	ld	hl,(psg_frames)
	ret

; psg_atend: carry set if HL is at or past the end of the data.
; Preserves HL and BC.
psg_atend:
	push	hl
	ld	de,(psg_end)
	or	a
	sbc	hl,de
	pop	hl
	ccf
	ret