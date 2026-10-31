; lh5.asm - unpacker for LH5 compressed data (as in LHA archives).
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
; Part of the reusable agonAMP sound library in lib/. YM and VTX music
; files are compressed with the "-lh5-" method of the LHA archiver; this
; turns such data back into the original bytes.
;
; LH5 is LZ77 compression (repeats are given as a distance back, up to
; 8 KB, and a length, 3 to 256 bytes) with the literals, lengths and
; distances Huffman coded in blocks, each block carrying its own code
; tables. It was devised by Haruhiko Okumura and Haruyasu Yoshizaki;
; this code was written from my understanding of the method as Okumura
; published it (the "ar002" program, public domain). No code was copied.
;
; Entry point:
;   lh5_unpack   In:  HL = packed data, BC = its length, DE = where to put
;                     the result, (lh5_size) = the length of the result,
;                     (lh5_work) = address of 20 KB of working space.
;                Out: carry set if the data is not valid LH5 data.
;                The output buffer must not overlap the input, except
;                that the input may lie above the output if it starts at
;                least the length of the result above it.
;
; All registers are used.

LH_NC:		equ	510	; literals (256) + lengths (253) + 1
LH_NT:		equ	19	; code length codes
LH_NP:		equ	14	; distance codes (8 KB dictionary)
LH_CBIT:	equ	9
LH_TBIT:	equ	5
LH_PBIT:	equ	4

; The working space. All table entries are 3 bytes so that they can be
; loaded and stored whole. (The assembler works expressions out strictly
; from left to right, so products are written first.)
LHW_CTAB:	equ	0		; 4096 entries: first 12 bits -> code
LHW_PTTAB:	equ	4096*3+LHW_CTAB	; 256 entries: first 8 bits -> code
LHW_LEFT:	equ	256*3+LHW_PTTAB	; tree for codes longer than the
LHW_RIGHT:	equ	1019*3+LHW_LEFT	;   table: 2 * LH_NC - 1 nodes each
LHW_CLEN:	equ	1019*3+LHW_RIGHT ; LH_NC code lengths
LHW_PTLEN:	equ	LHW_CLEN+LH_NC	; LH_NT code lengths (and LH_NP)
LHW_SIZE:	equ	LHW_PTLEN+20

; ---------------------------------------------------------------------
; Reading bits. lh_bitbuf holds the next 16 bits of input in its low
; 16 bits (what is above them is of no account).
; ---------------------------------------------------------------------

lh5_size:	ds	3	; length of the result wanted
lh5_work:	ds	3	; address of the working space (LHW_SIZE)
lh_in:		ds	3	; next byte of input
lh_left:	ds	3	; bytes of input left
lh_out:		ds	3	; next byte of output
lh_start:	ds	3	; first byte of output
lh_todo:	ds	3	; bytes of output still wanted
lh_len:		ds	3	; length of a repeat
lh_bitbuf:	ds	3	; the next 16 bits of input (low 16 bits)
lh_tmp:		ds	3
lh_block:	ds	3	; codes left in the block
lh_cur:		ds	1	; input byte being taken apart
lh_cnt:		ds	1	; bits left in it
lh_bad:		ds	1	; non-zero if the input ran out
lh_mask:	ds	1	; lh_tree: bit being looked at (low byte)
lh_maskhi:	ds	1	; (high byte)
lh_over:	ds	1	; bytes read past the end
mt_n:		ds	3	; lh_make: number of codes
mt_len:		ds	3	; lh_make: address of their lengths
mt_tab:		ds	3	; lh_make: offset of the table
mt_bits:	ds	1	; lh_make: bits looked up directly
mt_jut:		ds	1	; 16 - mt_bits
mt_l:		ds	1	; length of the code being placed
mt_steps:	ds	1	; steps down the tree still to take
mt_i:		ds	3
mt_k:		ds	3
mt_kk:		ds	3
mt_ch:		ds	3	; code being placed
mt_next:	ds	3	; the code after it
mt_sp:		ds	3	; address of start[len]
mt_p:		ds	3	; where the code (or a node) goes
mt_avail:	ds	3	; next free tree node
mt_mask:	ds	3	; bit of k that chooses left or right
mt_count:	ds	17*3	; codes of each length
mt_start:	ds	18*3	; first code of each length
mt_weight:	ds	17*3	; codes per table entry, by length
pt_nn:		ds	1	; lh_ptlen: number of codes (C)
pt_nbit:	ds	1	; lh_ptlen: bits in the count (B)
pt_special:	ds	1
pt_n:		ds	1
pt_i:		ds	1
pt_c:		ds	3
cl_n:		ds	3	; lh_clen: lengths given
cl_i:		ds	3
cl_c:		ds	3
cl_run:		ds	3

; lh_fill: move B bits on. Corrupts A, B, HL.
lh_fill:
	ld	a,b
	or	a
	ret	z
	push	de
	ld	a,(lh_cur)		; E = the input byte being taken apart,
	ld	e,a			; D = how many of its bits are left
	ld	a,(lh_cnt)
	ld	d,a
	ld	hl,(lh_bitbuf)
@bit:
	inc	d
	dec	d
	call	z,lh_byte
	dec	d
	sla	e			; next bit into carry
	adc	hl,hl			; and into the buffer
	djnz	@bit
	ld	(lh_bitbuf),hl
	ld	a,e
	ld	(lh_cur),a
	ld	a,d
	ld	(lh_cnt),a
	pop	de
	ret

; lh_byte: E = the next input byte, D = 8. Preserves BC, HL.
lh_byte:
	push	hl
	ld	d,8
	ld	hl,(lh_left)		; any input left?
	ld	a,h
	or	l
	jr	nz,@more
	ld	a,(lh_left+2)
	or	a
	jr	nz,@more
	; Past the end zeros are read. A few bytes are expected, since the
	; next 16 bits are always read ahead; more mean the data is bad.
	ld	hl,lh_over
	inc	(hl)
	ld	a,(hl)
	cp	5
	jr	c,@zero
	ld	a,1
	ld	(lh_bad),a
@zero:
	ld	e,0
	pop	hl
	ret
@more:
	dec	hl
	ld	(lh_left),hl
	ld	hl,(lh_in)
	ld	e,(hl)
	inc	hl
	ld	(lh_in),hl
	pop	hl
	ret

; lh_peek: DE = the next 16 bits (bit 15 first), zero extended.
; Preserves BC, HL.
lh_peek:
	push	hl
	ld	hl,(lh_bitbuf)
	ld	de,0
	ld	d,h
	ld	e,l
	pop	hl
	ret

; lh_get: HL = the next B bits (1 to 16), and move on past them.
; Corrupts A, BC, DE.
lh_get:
	call	lh_peek
	ld	a,16
	sub	b
	jr	z,@none
	ld	c,a
@shift:
	srl	d
	rr	e
	dec	c
	jr	nz,@shift
@none:
	push	de
	call	lh_fill
	pop	hl
	ret

; lh_ent: HL = address of entry HL of the table at offset DE in the
; working space. Preserves BC.
lh_ent:
	push	de
	push	hl
	pop	de
	add	hl,hl
	add	hl,de			; * 3
	pop	de
	add	hl,de
	ld	de,(lh5_work)
	add	hl,de
	ret

; lh_tree: follow the tree from code HL, one bit of lh_bitbuf at a time,
; while the code is BC or more (that is, not yet a leaf). The bit to look
; at first is given as a mask on the 16 bits: A = its low byte, with
; (lh_maskhi) = its high byte. Out: HL = code.
lh_tree:
	ld	(lh_mask),a
@step:
	push	hl			; is it a leaf yet?
	ld	de,0
	ld	d,b
	ld	e,c
	or	a
	sbc	hl,de
	pop	hl
	ret	c
	push	bc
	call	lh_peek			; which way?
	ld	a,(lh_maskhi)
	and	d
	jr	nz,@right
	ld	a,(lh_mask)
	and	e
	jr	nz,@right
	ld	de,LHW_LEFT
	jr	@go
@right:
	ld	de,LHW_RIGHT
@go:
	call	lh_ent
	ld	hl,(hl)
	ld	a,(lh_maskhi)		; next bit along
	srl	a
	ld	(lh_maskhi),a
	ld	a,(lh_mask)
	rra
	ld	(lh_mask),a
	pop	bc
	jr	@step

; lh_w16: HL = HL with its top byte cleared. Preserves everything else.
lh_w16:
	ld	(lh_tmp),hl
	push	af
	xor	a
	ld	(lh_tmp+2),a
	pop	af
	ld	hl,(lh_tmp)
	ret

; ---------------------------------------------------------------------
; lh_make: build a decoding table and tree from a list of code lengths.
; In: (mt_n) = number of codes, (mt_len) = address of their lengths,
;     (mt_bits) = bits looked up directly, (mt_tab) = offset of the table
;     in the working space. Out: carry set if the lengths are not those
;     of a complete code.
; ---------------------------------------------------------------------
lh_make:
	ld	hl,mt_count		; how many codes of each length
	ld	b,17*3
@clr:
	ld	(hl),0
	inc	hl
	djnz	@clr
	ld	hl,(mt_len)
	ld	bc,(mt_n)
@count:
	ld	a,(hl)
	cp	17
	ccf
	ret	c			; (no code is longer than 16 bits)
	push	hl
	ld	hl,0
	ld	l,a
	push	hl
	pop	de
	add	hl,hl
	add	hl,de
	ld	de,mt_count
	add	hl,de
	push	hl
	ld	hl,(hl)
	inc	hl
	ex	de,hl
	pop	hl
	ld	(hl),de
	pop	hl
	inc	hl
	dec	bc
	ld	a,b
	or	c
	jr	nz,@count
	; start[1] = 0, start[i + 1] = start[i] + count[i] << (16 - i)
	ld	hl,0
	ld	(mt_start+3),hl
	ld	ix,mt_start+3
	ld	iy,mt_count+3
	ld	c,1
@starts:
	ld	hl,(iy+0)
	ld	a,16
	sub	c
	jr	z,@noshift
	ld	b,a
@sh:
	add	hl,hl
	djnz	@sh
@noshift:
	ld	de,(ix+0)		; (24 bits: the sum must not wrap,
	add	hl,de			; or a list of too many codes could
	ld	(ix+3),hl		; pass the check below)
	lea	ix,ix+3
	lea	iy,iy+3
	inc	c
	ld	a,c
	cp	17
	jr	nz,@starts
	ld	hl,(17*3+mt_start)	; the lengths must fill the code
	ld	de,010000h		; space exactly
	or	a
	sbc	hl,de
	scf
	ret	nz
	; start[i] >>= 16 - bits and weight[i] = 1 << (bits - i) for i up
	; to bits; weight[i] = 1 << (16 - i) above.
	ld	a,16
	ld	hl,mt_bits
	sub	(hl)
	ld	(mt_jut),a
	ld	ix,mt_start+3
	ld	iy,mt_weight+3
	ld	c,1
@weights:
	ld	a,(mt_bits)
	cp	c
	jr	c,@long
	ld	hl,(ix+0)		; a short code
	ld	a,(mt_jut)
	or	a
	jr	z,@nojut
	ld	b,a
@jut:
	srl	h
	rr	l
	djnz	@jut
@nojut:
	ld	(ix+0),hl
	ld	a,(mt_bits)
	sub	c
	jr	@weight
@long:
	ld	a,16
	sub	c
@weight:
	ld	hl,1
	or	a
	jr	z,@wdone
	ld	b,a
@w:
	add	hl,hl
	djnz	@w
@wdone:
	ld	(iy+0),hl
	lea	ix,ix+3
	lea	iy,iy+3
	inc	c
	ld	a,c
	cp	17
	jr	nz,@weights
	; Entries of the table that no short code reaches start empty.
	ld	a,(mt_bits)
	inc	a
	ld	hl,0
	ld	l,a
	push	hl
	pop	de
	add	hl,hl
	add	hl,de
	ld	de,mt_start
	add	hl,de
	ld	hl,(hl)			; start[bits + 1], 16 bits
	ld	a,h
	or	l
	jr	z,@full
	ld	a,(mt_jut)
	or	a
	jr	z,@nj2
	ld	b,a
@j2:
	srl	h
	rr	l
	djnz	@j2
@nj2:
	ld	(mt_i),hl
	ld	hl,1			; up to 1 << bits
	ld	a,(mt_bits)
	ld	b,a
@k:
	add	hl,hl
	djnz	@k
	ld	(mt_k),hl
@zero:
	ld	hl,(mt_i)
	ld	de,(mt_k)
	or	a
	sbc	hl,de
	jr	z,@full
	ld	hl,(mt_i)
	ld	de,(mt_tab)
	call	lh_ent
	ld	de,0
	ld	(hl),de
	ld	hl,(mt_i)
	inc	hl
	ld	(mt_i),hl
	jr	@zero
@full:
	; Then each code in turn.
	ld	hl,(mt_n)		; new tree nodes are numbered from here
	ld	(mt_avail),hl
	ld	a,15			; mask = 1 << (15 - bits), in 16 bits
	ld	hl,mt_bits
	sub	(hl)
	ld	hl,1
	or	a
	jr	z,@m0
	ld	b,a
@m:
	add	hl,hl
	djnz	@m
@m0:
	ld	(mt_mask),hl
	ld	hl,0
	ld	(mt_ch),hl
@char:
	ld	hl,(mt_ch)
	ld	de,(mt_n)
	or	a
	sbc	hl,de
	jr	c,@place
	or	a			; all done: carry clear
	ret
@place:
	ld	hl,(mt_len)		; its length
	ld	de,(mt_ch)
	add	hl,de
	ld	a,(hl)
	or	a
	jp	z,@nextch
	ld	(mt_l),a
	ld	hl,0			; start[len] and weight[len]
	ld	l,a
	push	hl
	pop	de
	add	hl,hl
	add	hl,de
	push	hl
	ld	de,mt_start
	add	hl,de
	ld	(mt_sp),hl
	ld	hl,(hl)
	ld	(mt_k),hl		; k = start[len]
	pop	hl
	ld	de,mt_weight
	add	hl,de
	ld	hl,(hl)
	ld	de,(mt_k)
	add	hl,de
	call	lh_w16
	ld	(mt_next),hl		; nextcode = start[len] + weight[len]
	ld	a,(mt_bits)
	ld	b,a
	ld	a,(mt_l)
	cp	b
	jr	z,@short
	jr	nc,@longc
@short:
	ld	hl,(mt_k)		; table[start .. nextcode - 1] = ch
	ld	(mt_i),hl
@fillt:
	ld	hl,(mt_i)
	ld	de,(mt_next)
	or	a
	sbc	hl,de
	jp	nc,@stored
	ld	hl,(mt_i)
	ld	de,(mt_tab)
	call	lh_ent
	ld	de,(mt_ch)
	ld	(hl),de
	ld	hl,(mt_i)
	inc	hl
	ld	(mt_i),hl
	jr	@fillt
@longc:
	ld	hl,(mt_k)		; p = &table[k >> jut]
	ld	a,(mt_jut)
	ld	b,a
@jk:
	srl	h
	rr	l
	djnz	@jk
	ld	de,(mt_tab)
	call	lh_ent
	ld	(mt_p),hl
	ld	a,(mt_l)		; i = len - bits steps down the tree
	ld	hl,mt_bits
	sub	(hl)
	ld	(mt_steps),a
	ld	hl,(mt_k)
	ld	(mt_kk),hl
@walk:
	ld	hl,(mt_p)		; an empty place: a new node
	ld	hl,(hl)
	ld	a,h
	or	l
	jr	nz,@node
	ld	hl,(mt_avail)
	ld	de,2*LH_NC-1		; (more nodes than can be: bad data)
	or	a
	sbc	hl,de
	ccf
	ret	c
	ld	hl,(mt_avail)
	ld	de,LHW_LEFT
	call	lh_ent
	ld	de,0
	ld	(hl),de
	ld	hl,(mt_avail)
	ld	de,LHW_RIGHT
	call	lh_ent
	ld	de,0
	ld	(hl),de
	ld	de,(mt_avail)
	ld	hl,(mt_p)
	ld	(hl),de
	inc	de
	ld	(mt_avail),de
	ld	hl,(mt_p)
	ld	hl,(hl)
@node:
	push	hl			; left or right of it, by the next bit
	ld	hl,(mt_kk)		; of k
	ld	de,(mt_mask)
	ld	a,h
	and	d
	jr	nz,@r
	ld	a,l
	and	e
	jr	nz,@r
	ld	de,LHW_LEFT
	jr	@lr
@r:
	ld	de,LHW_RIGHT
@lr:
	pop	hl
	call	lh_ent
	ld	(mt_p),hl
	ld	hl,(mt_kk)		; k <<= 1
	add	hl,hl
	ld	(mt_kk),hl
	ld	hl,mt_steps
	dec	(hl)
	jp	nz,@walk
	ld	hl,(mt_p)
	ld	de,(mt_ch)
	ld	(hl),de
@stored:
	ld	hl,(mt_sp)		; start[len] = nextcode
	ld	de,(mt_next)
	ld	(hl),de
@nextch:
	ld	hl,(mt_ch)
	inc	hl
	ld	(mt_ch),hl
	jp	@char

; ---------------------------------------------------------------------
; lh_ptlen: read the code lengths of a small code (the one for the code
; lengths, or the one for distances) and build its table.
; In: C = number of codes (nn), B = bits in the count (nbit), A = the
; position after which a run of zero lengths may be given (or 0FFh).
; Out: carry set if the data is bad.
; ---------------------------------------------------------------------
lh_ptlen:
	ld	(pt_nn),bc
	ld	(pt_special),a
	ld	a,(pt_nbit)
	ld	b,a
	call	lh_get			; n = how many lengths are given
	ld	a,h
	or	a
	scf
	ret	nz
	ld	a,l
	ld	(pt_n),a
	or	a
	jr	nz,@lengths
	ld	a,(pt_nbit)		; none: every code is the next value
	ld	b,a
	call	lh_get
	ld	(pt_c),hl
	ld	a,(pt_nn)		; (which must be one of the codes)
	dec	a
	cp	l
	ret	c
	ld	hl,(lh5_work)
	ld	de,LHW_PTLEN
	add	hl,de
	ld	b,20
@z:
	ld	(hl),0
	inc	hl
	djnz	@z
	ld	hl,(lh5_work)
	ld	de,LHW_PTTAB
	add	hl,de
	ld	de,(pt_c)
	ld	b,0
@all:
	ld	(hl),de
	inc	hl
	inc	hl
	inc	hl
	djnz	@all
	or	a
	ret
@lengths:
	ld	a,(pt_nn)
	ld	b,a
	ld	a,(pt_n)
	cp	b
	jr	z,@nok
	ccf
	ret	c			; more lengths than codes
@nok:
	xor	a
	ld	(pt_i),a
@len:
	ld	a,(pt_i)
	ld	hl,pt_n
	cp	(hl)
	jr	nc,@rest
	call	lh_peek			; c = top 3 bits
	ld	a,d
	rlca
	rlca
	rlca
	and	7
	cp	7
	jr	nz,@small
	ld	bc,1000h		; 7: then one more for each 1 bit
@ones:
	push	af
	ld	a,d
	and	b
	jr	nz,@one
	ld	a,e
	and	c
	jr	z,@endones
@one:
	pop	af
	inc	a
	srl	b
	rr	c
	jr	@ones
@endones:
	pop	af
@small:
	ld	(pt_c),a
	ld	b,3
	cp	7
	jr	c,@f3
	sub	3
	ld	b,a
@f3:
	call	lh_fill
	call	@put
	ld	a,(pt_special)		; a run of zeros may follow here
	ld	hl,pt_i
	cp	(hl)
	jr	nz,@len
	ld	b,2
	call	lh_get
	ld	a,l
	or	a
	jr	z,@len
	ld	b,a
@zeros:
	push	bc
	xor	a
	ld	(pt_c),a
	call	@put
	pop	bc
	djnz	@zeros
	jr	@len
@rest:
	ld	a,(pt_i)		; the rest have no code
	ld	hl,pt_nn
	cp	(hl)
	jr	nc,@make
	xor	a
	ld	(pt_c),a
	call	@put
	jr	@rest
@make:
	ld	hl,0
	ld	a,(pt_nn)
	ld	l,a
	ld	(mt_n),hl
	ld	hl,(lh5_work)
	ld	de,LHW_PTLEN
	add	hl,de
	ld	(mt_len),hl
	ld	a,8
	ld	(mt_bits),a
	ld	hl,LHW_PTTAB
	ld	(mt_tab),hl
	jp	lh_make
@put:					; pt_len[i++] = c, if there is room
	ld	a,(pt_i)
	cp	20
	ret	nc
	ld	hl,(lh5_work)
	ld	de,LHW_PTLEN
	add	hl,de
	ld	de,0
	ld	e,a
	add	hl,de
	ld	a,(pt_c)
	ld	(hl),a
	ld	hl,pt_i
	inc	(hl)
	ret

; lh_clen: read the code lengths of the main code (literals and match
; lengths) and build its table. Out: carry set if the data is bad.
lh_clen:
	ld	b,LH_CBIT
	call	lh_get
	ld	(cl_n),hl
	ld	a,h
	or	l
	jr	nz,@lengths
	ld	b,LH_CBIT		; none: every code is the next value
	call	lh_get
	ld	de,LH_NC		; (which must be one of the codes)
	or	a
	sbc	hl,de
	ccf
	ret	c
	add	hl,de
	ex	de,hl
	ld	hl,(lh5_work)
	ld	bc,4096
@all:
	ld	(hl),de
	inc	hl
	inc	hl
	inc	hl
	dec	bc
	ld	a,b
	or	c
	jr	nz,@all
	ld	hl,(lh5_work)
	ld	de,LHW_CLEN
	add	hl,de
	ld	bc,LH_NC
@z:
	ld	(hl),0
	inc	hl
	dec	bc
	ld	a,b
	or	c
	jr	nz,@z
	or	a
	ret
@lengths:
	ld	de,LH_NC+1		; more lengths than codes?
	or	a
	sbc	hl,de
	ccf
	ret	c
	ld	hl,0
	ld	(cl_i),hl
@len:
	ld	hl,(cl_i)
	ld	de,(cl_n)
	or	a
	sbc	hl,de
	jp	nc,@rest
	call	lh_peek			; look up the length's code
	ld	hl,0
	ld	l,d
	ld	de,LHW_PTTAB
	call	lh_ent
	ld	hl,(hl)
	xor	a			; longer than 8 bits: down the tree,
	ld	(lh_maskhi),a		; from bit 7
	ld	a,80h
	ld	bc,LH_NT
	call	lh_tree
	ld	(cl_c),hl
	ld	de,LHW_PTLEN		; move past it
	ld	hl,(lh5_work)
	add	hl,de
	ld	de,(cl_c)
	add	hl,de
	ld	b,(hl)
	call	lh_fill
	ld	a,(cl_c)
	cp	3
	jr	nc,@plain
	ld	hl,1			; 0: one zero length
	or	a
	jr	z,@zeros
	cp	1
	jr	nz,@many
	ld	b,4			; 1: 3 to 18 zero lengths
	call	lh_get
	inc	hl
	inc	hl
	inc	hl
	jr	@zeros
@many:
	ld	b,LH_CBIT		; 2: 20 to 531 zero lengths
	call	lh_get
	ld	de,20
	add	hl,de
@zeros:
	ld	(cl_run),hl
@zl:
	xor	a
	call	@put
	ret	c
	ld	hl,(cl_run)
	dec	hl
	ld	(cl_run),hl
	ld	a,h
	or	l
	jr	nz,@zl
	jp	@len
@plain:
	sub	2			; 3 and up: a length of c - 2
	call	@put
	ret	c
	jp	@len
@rest:
	ld	hl,(cl_i)		; the rest have no code
	ld	de,LH_NC
	or	a
	sbc	hl,de
	jr	nc,@make
	xor	a
	call	@put
	jr	@rest
@make:
	ld	hl,LH_NC
	ld	(mt_n),hl
	ld	hl,(lh5_work)
	ld	de,LHW_CLEN
	add	hl,de
	ld	(mt_len),hl
	ld	a,12
	ld	(mt_bits),a
	ld	hl,LHW_CTAB
	ld	(mt_tab),hl
	jp	lh_make
@put:					; c_len[i++] = A; carry if no room
	push	af
	ld	hl,(cl_i)
	ld	de,LH_NC
	or	a
	sbc	hl,de
	jr	c,@room
	pop	af
	scf
	ret
@room:
	ld	hl,(lh5_work)
	ld	de,LHW_CLEN
	add	hl,de
	ld	de,(cl_i)
	add	hl,de
	pop	af
	ld	(hl),a
	ld	hl,(cl_i)
	inc	hl
	ld	(cl_i),hl
	or	a
	ret

; lh_code: HL = the next literal-or-length code (0 to 509), reading a
; new block's tables first when the last block is used up.
; Out: carry set if the data is bad.
lh_code:
	ld	hl,(lh_block)
	ld	a,h
	or	l
	jr	nz,@inblock
	ld	b,16			; a new block: size, then tables
	call	lh_get
	ld	(lh_block),hl
	ld	a,h
	or	l
	scf
	ret	z
	ld	c,LH_NT
	ld	b,LH_TBIT
	ld	a,3
	call	lh_ptlen
	ret	c
	call	lh_clen
	ret	c
	ld	c,LH_NP
	ld	b,LH_PBIT
	ld	a,0FFh
	call	lh_ptlen
	ret	c
	ld	hl,(lh_block)
@inblock:
	dec	hl
	ld	(lh_block),hl
	call	lh_peek			; first 12 bits through the table
	ex	de,hl
	ld	b,4
@sh:
	srl	h
	rr	l
	djnz	@sh
	ld	de,LHW_CTAB
	call	lh_ent
	ld	hl,(hl)
	xor	a			; then down the tree from bit 3
	ld	(lh_maskhi),a
	ld	a,8
	ld	bc,LH_NC
	call	lh_tree
	push	hl			; move past it
	ld	de,LHW_CLEN
	ld	hl,(lh5_work)
	add	hl,de
	pop	de
	push	de
	add	hl,de
	ld	b,(hl)
	call	lh_fill
	pop	hl
	or	a
	ret

; lh_dist: HL = the next distance (from the byte before, so 0 means the
; byte just written).
lh_dist:
	call	lh_peek
	ld	hl,0
	ld	l,d
	ld	de,LHW_PTTAB
	call	lh_ent
	ld	hl,(hl)
	xor	a
	ld	(lh_maskhi),a
	ld	a,80h
	ld	bc,LH_NP
	call	lh_tree
	push	hl
	ld	de,LHW_PTLEN
	ld	hl,(lh5_work)
	add	hl,de
	pop	de
	push	de
	add	hl,de
	ld	b,(hl)
	call	lh_fill
	pop	hl
	ld	a,l			; codes 1 and up: 1 << (j - 1) plus
	or	a			; j - 1 more bits
	ret	z
	dec	a
	ret	z			; (j = 1: just 1)
	ld	b,a
	ld	hl,1
@pow:
	add	hl,hl
	djnz	@pow
	push	hl
	ld	b,a
	call	lh_get
	pop	de
	add	hl,de
	ret

lh5_unpack:
	ld	(lh_in),hl
	ld	(lh_left),bc
	ld	(lh_out),de
	ld	(lh_start),de
	xor	a
	ld	(lh_cnt),a
	ld	(lh_bad),a
	ld	(lh_over),a
	ld	hl,0
	ld	(lh_bitbuf),hl
	ld	(lh_block),hl
	ld	hl,(lh5_size)
	ld	(lh_todo),hl
	ld	b,16
	call	lh_fill
@loop:
	ld	hl,(lh_todo)		; finished?
	ld	a,h
	or	l
	jr	nz,@more
	ld	a,(lh_todo+2)
	or	a
	jp	z,@done
@more:
	ld	a,(lh_bad)
	or	a
	scf
	ret	nz
	call	lh_code
	ret	c
	ld	a,h
	or	a
	jr	nz,@match
	ld	a,l			; a literal byte
	ld	hl,(lh_out)
	ld	(hl),a
	inc	hl
	ld	(lh_out),hl
	ld	hl,(lh_todo)
	dec	hl
	ld	(lh_todo),hl
	jr	@loop
@match:
	ld	de,253			; a repeat: length = code - 253
	or	a
	sbc	hl,de
	ld	(lh_len),hl
	call	lh_dist
	inc	hl			; it starts distance + 1 back
	ex	de,hl
	ld	hl,(lh_out)
	or	a
	sbc	hl,de
	push	hl
	ld	de,(lh_start)		; (not before the start)
	or	a
	sbc	hl,de
	pop	hl
	ret	c
	push	hl
	ld	hl,(lh_len)		; (no more than is still wanted)
	ld	de,(lh_todo)
	or	a
	sbc	hl,de
	jr	c,@fits
	ld	(lh_len),de
@fits:
	ld	hl,(lh_todo)
	ld	de,(lh_len)
	or	a
	sbc	hl,de
	ld	(lh_todo),hl
	ld	bc,(lh_len)
	pop	hl
	ld	de,(lh_out)
	ldir				; (bytewise: overlaps repeat)
	ld	(lh_out),de
	jp	@loop
@done:
	ld	a,(lh_bad)
	or	a
	ret	z
	scf
	ret