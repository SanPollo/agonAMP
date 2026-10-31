; util.asm - text output helpers, number printing and string routines
; for agonAMP.
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
; All output goes through the buffered vdu_put / vdu_flush routines in
; lib/libsupport.asm.

; vseq: queue a raw byte sequence ended by 0FFh (may contain zeros).
; In: HL -> sequence. Out: HL -> byte after the 0FFh.
vseq:
	ld	a,(hl)
	inc	hl
	cp	0FFh
	ret	z
	call	vdu_put
	jr	vseq

; vat: move the text cursor. In: D = column, E = row.
vat:
	ld	a,1			; (for the pacing in ui_paced)
	ld	(ui_drew),a
	ld	a,31
	call	vdu_put
	ld	a,d
	call	vdu_put
	ld	a,e
	jp	vdu_put

; vcol: set a text colour. In: A = colour, or colour + BG for background.
; The colours last sent are remembered and nothing is sent if the VDP
; already has the one asked for. Preserves all registers except F.
vcol:
	push	hl
	ld	hl,col_fg
	cp	128
	jr	c,@which
	ld	hl,col_bg
@which:
	cp	(hl)
	jr	z,@same
	ld	(hl),a
	push	af
	ld	a,17
	call	vdu_put
	pop	af
	call	vdu_put
@same:
	pop	hl
	ret
	; text colour the VDP has, 0FFh = unknown
col_fg:	db	0FFh
col_bg:	db	0FFh			; background colour likewise

; vtext: queue printable text, padded with spaces to a fixed width.
; Control codes in the text are shown as '?' so that an odd file name
; cannot be taken for a VDU command. Stops at a zero byte.
; In: HL -> text, B = width. Out: HL -> where it stopped.
vtext:
	ld	a,(hl)
	or	a
	jr	z,@pad
	inc	hl
	cp	32
	jr	c,@bad
	cp	127
	jr	nz,@ok
@bad:
	ld	a,'?'
@ok:
	call	vdu_put
	djnz	vtext
	ret
@pad:
	ld	a,' '
	call	vdu_put
	djnz	@pad
	ret

; vspaces: queue B spaces.
vspaces:
	ld	a,' '
	call	vdu_put
	djnz	vspaces
	ret

; vhex1 / vhex2: queue A as one or two hex digits.
vhex2:
	push	af
	rrca
	rrca
	rrca
	rrca
	call	vhex1
	pop	af
vhex1:
	and	0Fh
	add	a,090h
	daa
	adc	a,040h
	daa
	jp	vdu_put

; vdec2 / vdec3: queue A as two (00-99) or three (000-255) digits.
vdec3:
	ld	c,'0'-1
@h:
	inc	c
	sub	100
	jr	nc,@h
	add	a,100
	push	af
	ld	a,c
	call	vdu_put
	pop	af
vdec2:
	ld	c,'0'-1
@t:
	inc	c
	sub	10
	jr	nc,@t
	add	a,10+'0'
	push	af
	ld	a,c
	call	vdu_put
	pop	af
	jp	vdu_put

; mdec3: write A as three decimal digits into memory.
; In: A = value, DE -> destination. Out: DE -> after the digits.
mdec3:
	ld	b,100
	call	@digit
	ld	b,10
	call	@digit
	add	a,'0'
	ld	(de),a
	inc	de
	ret
@digit:
	ld	c,'0'-1
@sub:
	inc	c
	sub	b
	jr	nc,@sub
	add	a,b
	push	af
	ld	a,c
	ld	(de),a
	inc	de
	pop	af
	ret

; strcpy: copy a zero terminated string, terminator included.
; In: HL = source, DE = destination. Out: DE -> the copied terminator.
strcpy:
	ld	a,(hl)
	ld	(de),a
	or	a
	ret	z
	inc	hl
	inc	de
	jr	strcpy

; strlen: In: HL -> string. Out: BC = length. Preserves HL, DE.
strlen:
	push	hl
	ld	bc,0
@l:
	ld	a,(hl)
	or	a
	jr	z,@e
	inc	hl
	inc	bc
	jr	@l
@e:
	pop	hl
	ret

; upcase: fold a-z in A to upper case.
upcase:
	cp	'a'
	ret	c
	cp	'z'+1
	ret	nc
	sub	32
	ret

; memcmp: compare B bytes at HL and DE. Out: Z set if they match.
memcmp:
	ld	a,(de)
	cp	(hl)
	ret	nz
	inc	hl
	inc	de
	djnz	memcmp
	ret

; path_join: build "dir/name". In: HL = directory, BC = name,
; DE = destination. The directory must not be empty.
path_join:
	call	strcpy
	dec	de
	ld	a,(de)
	inc	de
	cp	'/'
	jr	z,@slash
	ld	a,'/'
	ld	(de),a
	inc	de
@slash:
	push	bc
	pop	hl
	jp	strcpy

; path_up: cut the last component off an absolute path, in place.
; In: HL -> path. "/a/b" becomes "/a"; "/a" becomes "/".
path_up:
	push	hl
	pop	de			; DE = start
	ld	bc,0			; BC = address of the last '/'
@scan:
	ld	a,(hl)
	or	a
	jr	z,@cut
	cp	'/'
	jr	nz,@nx
	push	hl
	pop	bc
@nx:
	inc	hl
	jr	@scan
@cut:
	push	bc
	pop	hl
	or	a
	sbc	hl,de
	add	hl,de
	jr	nz,@notroot
	inc	hl			; keep the leading '/'
@notroot:
	ld	(hl),0
	ret

; mul3: HL = HL * 3. Preserves DE.
mul3:
	push	de
	push	hl
	pop	de
	add	hl,hl
	add	hl,de
	pop	de
	ret