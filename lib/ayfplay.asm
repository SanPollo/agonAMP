; ayfplay.asm - player for AY files (the ZXAYEMUL format).
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
; Part of the reusable agonAMP sound library in lib/. Needs z80emu.asm,
; and ay_regs from ayvdp.asm.
;
; An AY file holds the music of one or more songs (often from a game)
; together with the ZX Spectrum machine code that plays it. The code is
; run here on an emulated Z80 (z80emu.asm), as a Spectrum would run it,
; and what it writes to the AY chip's ports is caught in ay_regs.
;
; The format, as documented with the AYEmul program (all numbers are
; big-endian; a "pointer" is a signed 16 bit offset from where the
; pointer itself is):
;   0   "ZXAYEMUL"
;   12  pointer to the author's name   16  number of songs - 1
;   17  the song to play first         18  pointer to the song table
; Song table, 4 bytes a song: pointer to its name, pointer to its data.
; Song data: 4 bytes of channel order, length (frames, 0 if unknown),
; fade length, the high and low bytes that every register pair starts
; with, pointer to the "points" (stack, INIT and INTERRUPT addresses)
; and pointer to the blocks: each the address in the Z80's memory, the
; length, and a pointer to the bytes, ending with an address of 0.
;
; Each song starts with the Z80's memory set up as the format says: 0FFh
; up to 3FFFh (the ROM) except for RET (0C9h) at 0 to 0FFh and EI at
; 38h, zeros above, the blocks loaded, and at 0 a little program that
; calls INIT and then, every interrupt, INTERRUPT (or, when INTERRUPT is
; 0, sets IM 2 and leaves the interrupts to the song's own code).
;
; Entry points:
;   ayf_init    HL = an AY file in memory, BC = its length, A = the top
;               address byte (MBASE value) of a 64 KB page for the Z80's
;               memory, which must not overlap the file. Sets up the first
;               song to be played. Carry set if it is not an AY file, or
;               none of its songs can be played.
;   ayf_play    play one frame (1/50 s) into ay_regs. When a song's length
;               has been played, the next song in the file starts.
;   ayf_start   A = a song number: start that song, or if its data is bad
;               the next good one after it. Carry set if none can be
;               played (the Z80 is then left stopped).
;   ayf_startb  as ayf_start, but the nearest good song before it.
;   ayf_song    A = a song number: start that song. Carry set if its data
;               is bad (nothing is then changed, but the Z80 is stopped).
;   ayf_nextno  A = a song number: A = the song after it, wrapping round.
;   ayf_length  HL = the length of all the songs together, in frames
;
; Results:
;   ayf_cur     the song now playing (0 for the first in the file)
;   ayf_count   the number of songs in the file (0 for 256)
;   ayf_last    the last song's number (ayf_count - 1)
;   ayf_title   address of the name of the song now playing
;   ayf_author  address of the author's name
;   ayf_loops   goes up by one each time all the songs have been played;
;               playing then starts again with the first one played
;
; Songs of unknown length are given 3 minutes. Code that keeps the Z80
; busy for most of a frame (sampled sound, for instance) cannot be kept
; up with, and beeper music (port 0FEh) is not heard.
;
; All registers are used.

AYF_UNKNOWN:	equ	9000	; frames given to a song of unknown length
AYF_FRAME:	equ	1000	; jumps etc. allowed per frame
AYF_START:	equ	25000	; and for the song's set-up code

ayf_cur:	ds	1	; song playing
ayf_count:	ds	1	; songs in the file (0 for 256)
ayf_last:	ds	1	; the last song's number
ayf_first:	ds	1	; song played first
ayf_title:	ds	3	; its name
ayf_author:	ds	3	; the author's name
ayf_loops:	ds	1	; times all the songs have been played
ayf_file:	ds	3	; the file
ayf_end:	ds	3	; its end
ayf_songs:	ds	3	; the song table
ayf_mem:	ds	3	; the Z80's memory
ayf_len:	ds	3	; frames in this song
ayf_frame:	ds	3	; frames of it played
ayf_total:	ds	3
ayf_tmp:	ds	3
ayf_blk:	ds	3	; block being loaded
ayf_baddr:	ds	3	; its address
ayf_blen:	ds	3	; its length
ayf_init_a:	ds	3	; INIT
ayf_int_a:	ds	3	; INTERRUPT
ayf_sel:	ds	1	; AY register chosen
ayf_shadow:	ds	16	; what was written to each AY register

; ayf_init: see above.
ayf_init:
	ld	(ayf_file),hl
	ld	(z_page),a
	push	hl
	ld	hl,20			; (too short for the header?)
	or	a
	sbc	hl,bc
	pop	hl
	ccf
	ret	c
	push	hl
	add	hl,bc
	ld	(ayf_end),hl
	pop	ix
	ld	hl,ayf_sig		; "ZXAYEMUL"
	lea	de,ix+0
	ld	b,8
@sig:
	ld	a,(de)
	cp	(hl)
	scf
	ret	nz
	inc	hl
	inc	de
	djnz	@sig
	ld	a,(ix+16)
	ld	(ayf_last),a
	inc	a			; (0 for 256)
	ld	(ayf_count),a
	lea	hl,ix+12		; the author
	call	ayf_ptr
	ret	c
	ld	(ayf_author),hl
	lea	hl,ix+18		; the song table
	call	ayf_ptr
	ret	c
	ld	(ayf_songs),hl
	ld	hl,ayf_out
	ld	(z_outfn),hl
	ld	hl,ayf_in
	ld	(z_infn),hl
	xor	a
	ld	(ayf_loops),a
	ld	a,(ix+17)		; the first song (if there is one)
	ld	hl,ayf_last
	cp	(hl)
	jr	c,@first
	jr	z,@first
	xor	a
@first:
	ld	(ayf_first),a
	; fall through

; ayf_start: start song A, or if its data is bad the next good one
; after it. ayf_startb: the same, but the nearest good one before it.
; Out: carry set if no song in the file can be played; the Z80 is then
; left stopped (see ayf_stop).
ayf_start:
	ld	d,0			; D: 1 = search backwards
	jr	ayf_search
ayf_startb:
	ld	d,1
ayf_search:
	ld	c,a			; C = the song to try
	ld	a,(ayf_last)
	ld	b,a
	inc	b			; every song once (0 is 256)
@try:
	push	bc
	push	de
	ld	a,c
	call	ayf_song
	pop	de
	pop	bc
	ret	nc
	ld	a,c
	dec	d
	inc	d
	jr	nz,@back
	call	ayf_nextno
	jr	@step
@back:
	call	ayf_prevno
@step:
	ld	c,a
	djnz	@try
	scf				; none (ayf_song has stopped the Z80)
	ret

; ayf_stop: leave the Z80 stopped and the AY silent (when no song can
; be played). Out: carry set.
ayf_stop:
	xor	a
	ld	(z_iff1),a
	ld	(z_iff2),a
	inc	a
	ld	(z_halted),a
	ld	hl,ay_regs
	ld	b,13
@z:
	ld	(hl),0
	inc	hl
	djnz	@z
	ld	(hl),0FFh		; (R13 not written)
	scf
	ret

; ayf_nextno: A = the song after song A, round to the first.
ayf_nextno:
	push	hl
	ld	hl,ayf_last
	cp	(hl)
	pop	hl
	jr	nz,@up
	ld	a,0FFh
@up:
	inc	a
	ret

; ayf_prevno: A = the song before song A, round to the last.
ayf_prevno:
	or	a
	jr	nz,@down
	ld	a,(ayf_last)
	inc	a
@down:
	dec	a
	ret

; ayf_check: are song A's pointers sound (the same tests ayf_song makes
; before it changes anything)? Out: carry set if not; else IX = its
; data. Preserves BC.
ayf_check:
	ld	hl,0			; the entry in the song table
	ld	l,a
	add	hl,hl
	add	hl,hl
	ld	de,(ayf_songs)
	add	hl,de
	push	hl
	call	ayf_ptr			; its name
	pop	hl
	ret	c
	inc	hl
	inc	hl
	call	ayf_ptr			; its data
	ret	c
	push	hl
	pop	ix
	lea	hl,ix+10		; the points
	call	ayf_ptr
	ret	c
	lea	hl,ix+12		; the blocks (at least the first
	call	ayf_ptr			; must be there)
	ret	c
	jp	ayf_inside

; ayf_song: start song A. Out: carry set if its data is bad, in which
; case nothing has been changed but the Z80, which is left stopped.
ayf_song:
	push	af
	call	ayf_check
	pop	bc
	jp	c,ayf_stop
	ld	a,b
	ld	(ayf_cur),a
	ld	hl,0
	ld	(ayf_frame),hl
	ld	hl,0			; the entry in the song table
	ld	l,a
	add	hl,hl
	add	hl,hl
	ld	de,(ayf_songs)
	add	hl,de
	push	hl
	call	ayf_ptr			; its name
	pop	de
	ret	c
	ld	(ayf_title),hl
	ex	de,hl
	inc	hl
	inc	hl
	call	ayf_ptr			; its data
	ret	c
	push	hl
	pop	ix
	ld	hl,0			; its length
	ld	h,(ix+4)
	ld	l,(ix+5)
	ld	a,h
	or	l
	jr	nz,@len
	ld	hl,AYF_UNKNOWN
@len:
	ld	(ayf_len),hl
	; Registers: all pairs = hi, lo, except as below.
	ld	bc,0
	ld	b,(ix+8)
	ld	c,(ix+9)
	ld	hl,z_af
	ld	a,12
@regs:
	ld	(hl),bc			; (3 bytes each)
	inc	hl
	inc	hl
	inc	hl
	dec	a
	jr	nz,@regs
	; The memory.
	ld	hl,0
	ld	(ayf_mem),hl
	ld	a,(z_page)
	ld	(ayf_mem+2),a
	ld	hl,(ayf_mem)		; 0 to 0FFh: RET
	ld	bc,100h
	ld	a,0C9h
	call	@fill
	ld	bc,3F00h		; 100h to 3FFFh: 0FFh
	ld	a,0FFh
	call	@fill
	ld	bc,0C000h		; 4000h on: 0
	xor	a
	call	@fill
	ld	hl,(ayf_mem)
	ld	de,38h
	add	hl,de
	ld	(hl),0FBh		; EI at 38h
	lea	hl,ix+10		; the points
	call	ayf_ptr
	ret	c
	push	hl
	call	ayf_be			; stack
	ld	(z_sp),de
	pop	hl
	inc	hl
	inc	hl
	push	hl
	call	ayf_be			; INIT
	ld	(ayf_init_a),de
	pop	hl
	inc	hl
	inc	hl
	call	ayf_be			; INTERRUPT
	ld	(ayf_int_a),de
	lea	hl,ix+12		; the blocks
	call	ayf_ptr
	ret	c
	ld	(ayf_blk),hl
	call	ayf_inside		; (at least the first must be there)
	ret	c
	; The little program at 0.
	ld	hl,(ayf_init_a)		; INIT 0: the first block's address
	ld	a,h
	or	l
	jr	nz,@hasinit
	ld	hl,(ayf_blk)
	call	ayf_be
	ld	(ayf_init_a),de
@hasinit:
	ld	hl,ayf_stub2		; INTERRUPT 0: IM 2 and wait
	ld	bc,10
	ld	a,(ayf_int_a)
	ld	d,a
	ld	a,(ayf_int_a+1)
	or	d
	jr	z,@stub
	ld	hl,ayf_stub1		; else IM 1, wait, call INTERRUPT
	ld	bc,13
	ld	a,(ayf_int_a)
	ld	(ayf_stub1+9),a
	ld	a,(ayf_int_a+1)
	ld	(ayf_stub1+10),a
@stub:
	ld	a,(ayf_init_a)
	ld	(ayf_stub1+2),a
	ld	(ayf_stub2+2),a
	ld	a,(ayf_init_a+1)
	ld	(ayf_stub1+3),a
	ld	(ayf_stub2+3),a
	ld	de,(ayf_mem)
	ldir
	; Then the blocks, over it if they cover it.
@block:
	ld	hl,(ayf_blk)
	call	ayf_inside
	jp	c,@blkend
	call	ayf_be			; address
	ld	a,d
	or	e
	jp	z,@blkend
	ld	(ayf_baddr),de
	ld	hl,(ayf_blk)
	inc	hl
	inc	hl
	call	ayf_be			; length
	ld	(ayf_blen),de
	ld	hl,(ayf_blk)
	ld	de,4
	add	hl,de
	call	ayf_ptr			; where the bytes are
	jr	c,@nextb
	push	hl
	; length = min(length, 10000h - address, end of file - bytes)
	ld	hl,10000h
	ld	de,(ayf_baddr)
	or	a
	sbc	hl,de
	ld	de,(ayf_blen)
	call	@min
	pop	de
	push	de
	ld	hl,(ayf_end)
	or	a
	sbc	hl,de
	ld	de,(ayf_blen)
	call	@min
	pop	hl			; HL = bytes, length in ayf_blen
	ld	bc,(ayf_blen)
	ld	a,b
	or	c
	jr	z,@nextb
	push	hl
	ld	hl,(ayf_mem)
	ld	de,(ayf_baddr)
	add	hl,de
	ex	de,hl
	pop	hl
	ldir
@nextb:
	ld	hl,(ayf_blk)
	ld	de,6
	add	hl,de
	ld	(ayf_blk),hl
	jp	@block
@fill:					; BC bytes of A from HL on; HL after
	ld	(hl),a
	push	hl
	pop	de
	inc	de
	dec	bc
	ldir
	ex	de,hl
	ret
@min:					; ayf_blen = smaller of HL and DE
	or	a
	sbc	hl,de
	add	hl,de
	jr	nc,@m1
	ex	de,hl
@m1:
	ld	(ayf_blen),de
	ret
@blkend:
	; The rest of the Z80's state.
	ld	hl,0
	ld	(z_pc),hl
	xor	a
	ld	(z_im),a
	ld	(z_iff1),a
	ld	(z_iff2),a
	ld	(z_halted),a
	ld	(ayf_sel),a
	ld	a,3
	ld	(z_i),a
	ld	hl,ayf_shadow		; the AY's registers start at 0
	ld	b,16
@clr:
	ld	(hl),0
	inc	hl
	djnz	@clr
	ld	hl,ay_regs		; (and so does what is played)
	ld	b,13
@clr2:
	ld	(hl),0
	inc	hl
	djnz	@clr2
	ld	(hl),0FFh
	; Run the set-up: until the HALT after INIT.
	ld	hl,(ayf_sbudget)
	ld	(z_left),hl
	call	z_run
	or	a			; (carry clear)
	ret

; ayf_play: one frame. When the song playing has had its length, the
; next song that can be played starts first (and its set-up runs), so
; that every frame of a song is heard.
ayf_play:
	ld	hl,(ayf_frame)		; the end of the song?
	ld	de,(ayf_len)
	or	a
	sbc	hl,de
	call	nc,ayf_next
	ld	a,0FFh			; R13 not written yet
	ld	(ay_regs+13),a
	call	z_int
	ld	a,(z_halted)		; halted with interrupts off: stuck
	or	a
	jr	nz,@count
	ld	hl,AYF_FRAME
	ld	(z_left),hl
	call	z_run
@count:
	ld	hl,(ayf_frame)
	inc	hl
	ld	(ayf_frame),hl
	ret

; ayf_next: start the next song that can be played, round to the first.
; Passing the song played first counts as having played them all, even
; if that song has bad data and is passed over.
ayf_next:
	ld	a,(ayf_last)
	ld	b,a
	inc	b			; every song once (0 is 256)
	ld	a,(ayf_cur)
@try:
	call	ayf_nextno
	ld	hl,ayf_first
	cp	(hl)
	jr	nz,@song
	ld	hl,ayf_loops
	inc	(hl)
@song:
	push	af
	push	bc
	call	ayf_song
	pop	bc
	pop	hl
	ret	nc
	ld	a,h			; (the song number, from AF)
	djnz	@try
	ret				; none: ayf_song has stopped the Z80

; ayf_length: HL = all the songs' lengths added up.
ayf_length:
	ld	hl,0
	ld	(ayf_total),hl
	ld	a,(ayf_count)
	ld	b,a
	ld	c,0
@song:
	push	bc
	ld	a,c			; a song with bad data is passed over
	call	ayf_check		; when playing, so it adds nothing
	ld	de,0
	jr	c,@add
	lea	hl,ix+4			; the length of song C
	call	ayf_be
	ld	a,d
	or	e
	jr	nz,@add
	ld	de,AYF_UNKNOWN
@add:
	ld	hl,(ayf_total)
	add	hl,de
	ld	(ayf_total),hl
	pop	bc
	inc	c
	djnz	@song
	ret

; ayf_ptr: follow the pointer at HL. Out: HL = where it points; carry
; set if that is outside the file. Preserves IX.
ayf_ptr:
	push	hl
	call	ayf_be			; DE = offset, sign extended
	ld	a,d
	rla
	sbc	a,a
	ld	(ayf_tmp),de
	ld	(ayf_tmp+2),a
	ld	de,(ayf_tmp)
	pop	hl
	add	hl,de
	; fall through

; ayf_inside: carry set if HL is not inside the file. Preserves HL.
ayf_inside:
	push	hl
	ld	de,(ayf_file)
	or	a
	sbc	hl,de
	pop	hl
	ret	c
	push	hl
	ld	de,(ayf_end)
	or	a
	sbc	hl,de
	pop	hl
	ccf
	ret

; ayf_be: DE = the big-endian 16 bit value at HL. Preserves HL.
ayf_be:
	ld	de,0
	ld	d,(hl)
	inc	hl
	ld	e,(hl)
	dec	hl
	ret

; The Spectrum's AY ports, as decoded by the Spectrum 128: port 0FFFDh
; (A15 and A14 high, A1 low) chooses a register, port 0BFFDh (A15 high,
; A14 and A1 low) writes to it. Reading 0FFFDh gives the register's
; value; any other input gives 0FFh (no keys pressed, and so on).
ayf_out:				; BC = port, A = value
	ld	l,a
	ld	a,c
	and	02h
	ret	nz
	ld	a,b
	and	0C0h
	cp	0C0h
	jr	z,@sel
	cp	80h
	ret	nz
	ld	a,(ayf_sel)		; write the chosen register
	cp	16
	ret	nc
	ld	bc,0
	ld	c,a
	ld	a,l
	ld	hl,ayf_mask		; only the bits it has (R13: writing
	add	hl,bc			; restarts the envelope)
	and	(hl)
	ld	hl,ayf_shadow
	add	hl,bc
	ld	(hl),a
	ld	hl,ay_regs
	add	hl,bc
	ld	b,a
	ld	a,c
	cp	14			; (14 and 15 are the I/O ports)
	ret	nc
	ld	(hl),b
	ret
@sel:
	ld	a,l
	ld	(ayf_sel),a
	ret
; ayf_mask: the bits each AY register has, as a real AY reads them back.
ayf_mask:	db	0FFh,0Fh,0FFh,0Fh,0FFh,0Fh,1Fh,0FFh
		db	1Fh,1Fh,1Fh,0FFh,0FFh,0Fh,0FFh,0FFh
ayf_in:					; BC = port; A = value
	ld	a,c
	and	02h
	jr	nz,@ff
	ld	a,b
	and	0C0h
	cp	0C0h
	jr	nz,@ff
	ld	a,(ayf_sel)
	cp	16
	jr	nc,@ff
	ld	bc,0
	ld	c,a
	ld	hl,ayf_shadow
	add	hl,bc
	ld	a,(hl)
	ret
@ff:
	ld	a,0FFh
	ret

; The little programs put at 0 (INIT and INTERRUPT addresses filled in).
ayf_sbudget:	dl	AYF_START	; jumps etc. allowed for the set-up
ayf_stub1:	db	0F3h,0CDh,0,0,0EDh,56h,0FBh,76h,0CDh,0,0,18h,0F7h
ayf_stub2:	db	0F3h,0CDh,0,0,0EDh,5Eh,0FBh,76h,18h,0FAh
ayf_sig:	db	"ZXAYEMUL"