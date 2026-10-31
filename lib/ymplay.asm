; ymplay.asm - player for YM and VTX register dumps.
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
; Part of the reusable agonAMP sound library in lib/. YM files (from the
; ST-Sound project, mostly Atari ST music) and VTX files (from the Vortex
; project, mostly ZX Spectrum music) hold the AY registers for every
; frame of a song. Both are normally packed with LH5 (see lh5.asm): a YM
; file is a one-file LHA archive, and a VTX file has a header followed by
; LH5 data. This plays the unpacked registers into ay_regs.
;
; The layouts followed here (as documented by the ST-Sound and Vortex
; projects, and as read by the zxtune player):
;
;   YM2!, YM3!  4 byte identifier, then registers 0 to 13 of every frame,
;               interleaved (all of register 0, then all of register 1
;               ...). 50 frames a second, 2 MHz clock.
;   YM3b        the same, followed by a 4 byte loop frame number.
;   YM5!, YM6!  "YMx!LeOnArD!", then big-endian fields: frames (4 bytes,
;               at 12), attributes (4, at 16; bit 0 = interleaved),
;               digidrums (2, at 20), clock (4, at 22), frames per second
;               (2, at 26), loop frame (4, at 28), extra bytes (2, at 32);
;               then the extra bytes, the digidrums (each a 4 byte size and
;               the sample), title, author and comment (each ending with a
;               zero), and 16 registers per frame.
;   VTX         chip ("ay" or "ym", or "AY" or "YM" in older files), stereo
;               layout (1 byte), loop frame (2, little-endian), clock (4),
;               frames per second (1), then in newer files the year (2);
;               the unpacked size (4); title and author, and in newer files
;               program, tracker and comment (each ending with a zero);
;               then the LH5 data: registers 0 to 13, interleaved.
;
; A register 13 value of 0FFh means that the register was not written in
; that frame (the envelope is not restarted). The YM5 and YM6 special
; effects (digidrums, SID voice and the like) are not reproduced: the
; bits that select them are masked off, so the plain AY sound is heard.
;
; Entry points:
;   ym_load     HL = a YM or VTX file (packed or not) at the start of a
;               buffer, BC = its length, DE = the size of the buffer,
;               (lh5_work) = 20 KB of working space for lh5_unpack.
;               Unpacks it within the buffer if need be (the unpacked
;               registers and the file must fit in it side by side) and
;               sets up as below. Carry set if it cannot be played, with
;               A = 0 if it is not a YM or VTX file at all (the buffer is
;               then untouched), or 1 if it is one but is damaged or too
;               big.
;   ym_init     HL = an unpacked YM file in memory, BC = its length.
;               Carry set if it is not a YM file that can be played.
;   vtx_check   HL = a VTX file in memory, BC = its length. Carry set if it
;               is not a VTX file. Otherwise reads the header (the file
;               must stay where it is while the song plays: the title and
;               author are pointed to in it) and returns HL = the packed
;               data, BC = its length, DE = the unpacked length.
;   vtx_init    after vtx_check: DE = the unpacked registers, BC = their
;               length. Carry set if they are no use.
;   ym_play     advance 1/50 s and update ay_regs
;   ym_length   HL = how long the song lasts, in 1/50 s
;
; Results:
;   ym_clock    the AY clock the song was made for, in Hz (for ay_clock)
;   ym_title    address of the title (ending with a zero), or 0
;   ym_author   address of the author's name likewise, or 0
;   ym_loops    goes up by one each time the end is reached; playing then
;               goes on from the loop frame.
;
; Songs made for other than 50 frames a second play at their own speed:
; each 1/50 s, as many frames are taken as are due (none, one, or more),
; and an envelope restart in a frame that is passed over is kept.
;
; Corrupts AF, BC, DE, HL, IX.

ym_clock:	ds	3	; AY clock, Hz
ym_title:	ds	3	; title, or 0
ym_author:	ds	3	; author, or 0
ym_loops:	ds	1	; times the end has been reached
ym_end:		ds	3	; end of the file (or of its frames)
ym_data:	ds	3	; first frame
ym_frames:	ds	3	; frames in the song
ym_loop:	ds	3	; frame to go back to at the end
ym_loopptr:	ds	3	; its first register
ym_rate:	ds	3	; frames per second
ym_fstride:	ds	3	; bytes from one frame to the next
ym_rstride:	ds	3	; bytes from one register to the next
ym_ptr:		ds	3	; next frame's first register
ym_pos:		ds	3	; next frame's number
ym_acc:		ds	3	; frames due, in 1/50ths
ym_vsize:	ds	3	; VTX: unpacked length
ym_tmp:		ds	3
ym_buf:		ds	3	; ym_load: the buffer
ym_bufsz:	ds	3	; its size
ym_flen:	ds	3	; the file's length

; ym_load: see the top of the file.
ym_load:
	ld	(ym_buf),hl
	ld	(ym_bufsz),de
	ld	(ym_flen),bc
	push	hl
	pop	ix
	ld	de,ym_lh5		; an LHA archive (level 0, "-lh5-")?
	lea	hl,ix+2
	ld	b,5
@sig:
	ld	a,(de)
	cp	(hl)
	jr	nz,@notlha
	inc	hl
	inc	de
	djnz	@sig
	ld	a,(ix+20)
	or	a
	jr	z,@lha
@notlha:
	ld	hl,(ym_buf)		; a VTX file?
	ld	bc,(ym_flen)
	call	vtx_check
	jr	nc,@vtx
	ld	hl,(ym_buf)		; an unpacked YM file?
	ld	bc,(ym_flen)
	call	ym_init
	ret	nc
	xor	a
	scf
	ret
@lha:
	ld	a,(ix+10)		; packed and unpacked sizes (below
	or	(ix+14)			; 16 MB)
	jr	nz,@broken
	ld	hl,(ix+11)
	ld	(ym_vsize),hl
	ld	(lh5_size),hl
	ld	bc,(ix+7)		; the packed data must be in the file
	ld	de,0
	ld	e,(ix+0)
	inc	de
	inc	de
	ld	hl,(ym_flen)		; (DE = where it starts)
	or	a
	sbc	hl,de
	jr	c,@broken
	sbc	hl,bc
	jr	c,@broken
	push	bc
	push	de
	call	ym_top
	pop	de
	pop	bc
	jr	c,@broken
	add	hl,de
	ld	de,(ym_buf)
	call	lh5_unpack
	jr	c,@broken
	ld	hl,(ym_buf)
	ld	bc,(ym_vsize)
	call	ym_init
	ret	nc
	jr	@broken
@vtx:
	ld	(ym_vsize),de
	call	ym_top
	jr	c,@broken
	ld	bc,(ym_flen)		; read the header again where it
	call	vtx_check		; is now, so the names are there
	ld	(lh5_size),de
	ld	de,(ym_buf)
	call	lh5_unpack
	jr	c,@broken
	ld	de,(ym_buf)
	ld	bc,(ym_vsize)
	call	vtx_init
	ret	nc
@broken:
	ld	a,1
	scf
	ret

; ym_top: move the file to the top of the buffer, if (ym_vsize) bytes
; still fit below it. Out: HL = its new address; carry set if no room.
ym_top:
	ld	hl,(ym_bufsz)
	ld	de,(ym_flen)
	or	a
	sbc	hl,de
	ret	c
	ld	de,(ym_vsize)
	sbc	hl,de
	ret	c
	ld	hl,(ym_buf)		; last byte of the file
	ld	de,(ym_flen)
	add	hl,de
	dec	hl
	push	hl
	ld	hl,(ym_buf)		; last byte of the buffer
	ld	de,(ym_bufsz)
	add	hl,de
	dec	hl
	ex	de,hl
	pop	hl
	ld	bc,(ym_flen)
	lddr
	ex	de,hl
	inc	hl
	or	a
	ret

; ym_init: set up for an unpacked YM file. In: HL = file, BC = length.
ym_init:
	call	ym_defaults
	push	hl
	add	hl,bc
	ld	(ym_end),hl
	pop	ix
	ld	hl,2000000		; the Atari ST's 2 MHz
	ld	(ym_clock),hl
	ld	a,(ix+0)
	cp	'Y'
	jr	nz,@bad
	ld	a,(ix+1)
	cp	'M'
	jr	nz,@bad
	ld	a,(ix+3)
	ld	c,a
	ld	a,(ix+2)
	cp	'5'
	jr	z,@v5
	cp	'6'
	jr	z,@v5
	cp	'2'
	jr	z,@v3
	cp	'3'
	jr	nz,@bad
	ld	a,c			; YM3b: a loop frame at the end
	cp	'b'
	jr	nz,@v3
	ld	hl,(ym_end)
	dec	hl
	dec	hl
	dec	hl
	dec	hl
	ld	(ym_end),hl
	ld	a,(hl)			; big-endian normally, but some files
	or	a			; have it the other way round: take
	jr	z,@be			; whichever reading is smaller
	ld	hl,(hl)
	jr	@lp
@be:
	inc	hl
	call	ym_be24
@lp:
	ld	(ym_loop),hl
	jr	@v3b
@v3:
	ld	a,c
	cp	'!'
	jr	nz,@bad
@v3b:
	lea	hl,ix+4			; 14 registers a frame, interleaved
	ld	(ym_data),hl
	ex	de,hl
	ld	hl,(ym_end)
	or	a
	sbc	hl,de
	jr	c,@bad
	ld	de,14
	call	lib_div24
	ld	(ym_frames),hl
	jp	@inter
@bad:
	scf
	ret
@v5:
	ld	a,c
	cp	'!'
	jr	nz,@bad
	lea	hl,ix+4			; "LeOnArD!"
	ld	de,ym_leonard
	ld	b,8
@sig:
	ld	a,(de)
	cp	(hl)
	jr	nz,@bad
	inc	hl
	inc	de
	djnz	@sig
	lea	hl,ix+13		; frames (the top byte must be 0)
	ld	a,(ix+12)
	or	a
	jr	nz,@bad
	call	ym_be24
	ld	(ym_frames),hl
	lea	hl,ix+23		; clock
	call	ym_be24
	ld	a,(ix+22)		; (16 MHz or more: as high as can be;
	or	a			; ay_clock keeps it in range)
	jr	z,@clk
	ld	hl,0FFFFFFh
@clk:
	ld	(ym_clock),hl
	lea	hl,ix+26-1		; frames per second (2 bytes)
	call	ym_be16
	ld	(ym_rate),hl
	lea	hl,ix+29		; loop frame
	call	ym_be24
	ld	a,(ix+28)		; (past any song: ym_start makes it 0)
	or	a
	jr	z,@lp5
	ld	hl,0FFFFFFh
@lp5:
	ld	(ym_loop),hl
	lea	hl,ix+32-1		; extra bytes, skipped
	call	ym_be16
	lea	de,ix+34
	add	hl,de
	push	hl
	lea	hl,ix+20-1		; digidrums, skipped
	call	ym_be16
	ld	b,l
	ld	a,h			; (256 or more cannot fit in the file)
	pop	hl
	or	a
	jr	nz,@bad5
	inc	b
	jr	@drum1
@drum:
	push	bc
	ld	a,(hl)			; (a size of 16 MB or more cannot fit)
	or	a
	jr	nz,@bad5p
	inc	hl
	push	hl
	call	ym_be24
	pop	de
	add	hl,de
	jr	c,@bad5p		; (nor can one that wraps the address)
	inc	hl
	inc	hl
	inc	hl
	pop	bc
	call	ym_inside
	jr	c,@bad5
@drum1:
	djnz	@drum
	ld	(ym_title),hl
	call	ym_skipz
	jr	c,@bad5
	ld	(ym_author),hl
	call	ym_skipz
	jr	c,@bad5
	call	ym_skipz		; comment
	jr	c,@bad5
	ld	(ym_data),hl
	ex	de,hl			; are all the frames there?
	ld	hl,(ym_end)
	or	a
	sbc	hl,de
	ld	de,16
	call	lib_div24
	ld	de,(ym_frames)
	or	a
	sbc	hl,de
	jr	c,@bad5
	bit	0,(ix+19)		; interleaved?
	jr	nz,@inter
	ld	hl,16			; no: 16 bytes a frame
	ld	(ym_fstride),hl
	ld	hl,1
	ld	(ym_rstride),hl
	jr	ym_start
@bad5p:
	pop	bc
@bad5:
	scf
	ret
@inter:
	ld	hl,(ym_frames)
	ld	(ym_rstride),hl
	ld	hl,1
	ld	(ym_fstride),hl
	; fall through

; ym_start: check what the header said and start at the first frame.
; Out: carry set if there are no frames.
ym_start:
	ld	hl,(ym_frames)
	ld	de,1
	or	a
	sbc	hl,de
	ret	c
	ld	hl,(ym_rate)		; 0 is taken as 50, and over 400 as
	ld	a,h			; 400
	or	l
	jr	nz,@r1
	ld	l,50
@r1:
	ld	de,401
	or	a
	sbc	hl,de
	add	hl,de
	jr	c,@r2
	ld	hl,400
@r2:
	ld	(ym_rate),hl
	ld	hl,(ym_loop)		; a loop frame past the end means 0
	ld	de,(ym_frames)
	or	a
	sbc	hl,de
	jr	c,@l1
	ld	hl,0
	ld	(ym_loop),hl
@l1:
	ld	bc,(ym_loop)		; where the loop frame's bytes start
	call	ym_fptr
	ld	(ym_loopptr),hl
	ld	hl,(ym_data)
	ld	(ym_ptr),hl
	ld	hl,0
	ld	(ym_pos),hl
	ld	hl,49			; so that the first call takes frame 0
	ld	(ym_acc),hl
	xor	a
	ld	(ym_loops),a
	ret				; (carry clear)

; ym_fptr: HL = address of frame BC's first register.
ym_fptr:
	ld	hl,(ym_data)
	ld	de,(ym_fstride)
	ld	a,e
	cp	1
	jr	z,@one
	push	hl			; 16 bytes a frame
	push	bc
	pop	hl
	add	hl,hl
	add	hl,hl
	add	hl,hl
	add	hl,hl
	pop	de
	add	hl,de
	ret
@one:
	add	hl,bc
	ret

; ym_defaults: no loop, no names, 50 frames a second. Preserves BC, HL.
ym_defaults:
	push	hl
	ld	hl,0
	ld	(ym_loop),hl
	ld	(ym_title),hl
	ld	(ym_author),hl
	ld	l,50
	ld	(ym_rate),hl
	pop	hl
	ret

; ym_be24: HL = the big-endian 24 bit value at HL. Preserves BC, DE.
ym_be24:
	push	de
	ld	de,0
	ld	a,(hl)
	inc	hl
	ld	d,(hl)
	inc	hl
	ld	e,(hl)
	ld	(ym_tmp),de
	ld	(ym_tmp+2),a
	ld	hl,(ym_tmp)
	pop	de
	ret

; ym_be16: HL = the big-endian 16 bit value at HL + 1. Preserves BC, DE.
ym_be16:
	inc	hl
	push	de
	ld	d,(hl)
	inc	hl
	ld	e,(hl)
	ld	hl,0
	ld	h,d
	ld	l,e
	pop	de
	ret

; ym_inside: carry set if HL lies beyond ym_end. Preserves HL, BC.
ym_inside:
	push	hl
	ld	de,(ym_end)
	ex	de,hl
	or	a
	sbc	hl,de
	pop	hl
	ret

; ym_skipz: move HL past the next zero byte. Carry set if the zero is
; not found before ym_end. Preserves BC.
ym_skipz:
	push	hl
	ld	de,(ym_end)
	or	a
	sbc	hl,de
	pop	hl
	ccf
	ret	c
	ld	a,(hl)
	inc	hl
	or	a
	jr	nz,ym_skipz
	ret

; vtx_check: read a VTX file's header. In: HL = file, BC = length.
; Out: carry set if not a VTX file; else HL = packed data, BC = its
; length, DE = unpacked length.
vtx_check:
	call	ym_defaults
	push	hl
	pop	ix
	add	hl,bc
	ld	(ym_end),hl
	ld	a,(ix+1)		; "ay", "ym", "AY" or "YM"
	or	20h			; (both cases)
	ld	c,a
	ld	a,(ix+0)
	ld	b,a
	or	20h
	cp	'a'
	jr	nz,@ym
	ld	a,c
	cp	'y'
	jr	nz,@bad
	jr	@chip
@bad:
	scf
	ret
@ym:
	cp	'y'
	jr	nz,@bad
	ld	a,c
	cp	'm'
	jr	nz,@bad
@chip:
	ld	a,(ix+2)		; stereo layout 0 to 6
	cp	7
	jr	nc,@bad
	ld	a,(ix+9)		; 25 to 100 frames a second
	cp	25
	jr	c,@bad
	cp	101
	jr	nc,@bad
	ld	hl,0
	ld	l,a
	ld	(ym_rate),hl
	ld	hl,(ix+3)		; loop frame
	ld	a,l
	ld	(ym_loop),a
	ld	a,h
	ld	(ym_loop+1),a
	ld	a,(ix+8)		; clock (below 16 MHz)
	or	a
	jr	nz,@bad
	ld	hl,(ix+5)
	ld	(ym_clock),hl
	lea	hl,ix+16		; newer files: 5 names
	ld	de,(ix+12)
	ld	a,(ix+15)
	ld	c,5
	bit	5,b			; (lower case chip name)
	jr	nz,@new
	lea	hl,ix+14		; older ones: 2
	ld	de,(ix+10)
	ld	a,(ix+13)
	ld	c,2
@new:
	or	a			; (below 16 MB)
	jr	nz,@bad
	ld	(ym_vsize),de
	ld	(ym_title),hl
	ld	b,c
@names:
	call	ym_skipz
	jr	c,@bad
	ld	a,b
	cp	c
	jr	nz,@n1
	ld	(ym_author),hl
@n1:
	djnz	@names
	push	hl			; packed data and its length
	ex	de,hl
	ld	hl,(ym_end)
	or	a
	sbc	hl,de
	push	hl
	pop	bc
	pop	hl
	ld	de,(ym_vsize)
	ret

; vtx_init: after vtx_check. In: DE = unpacked registers, BC = length.
vtx_init:
	ld	(ym_data),de
	push	bc
	pop	hl
	ld	de,14
	call	lib_div24
	ld	(ym_frames),hl
	ld	(ym_rstride),hl
	ld	hl,1
	ld	(ym_fstride),hl
	jp	ym_start

; ym_play: advance 1/50 s. Every frame that falls due is read into
; ay_regs in turn; register 13 is left 0FFh unless one of them wrote it.
ym_play:
	ld	a,0FFh
	ld	(ay_regs+13),a
	ld	hl,(ym_acc)
	ld	de,(ym_rate)
	add	hl,de
@due:
	ld	de,50
	or	a
	sbc	hl,de
	jr	c,@done
	ld	(ym_acc),hl
	call	ym_frame
	ld	hl,(ym_acc)
	jr	@due
@done:
	add	hl,de
	ld	(ym_acc),hl
	ret

; ym_frame: read one frame into ay_regs and move on to the next.
ym_frame:
	ld	hl,(ym_ptr)
	ld	de,(ym_rstride)
	ld	ix,ym_masks
	ld	bc,ay_regs
@reg:
	ld	a,(ix+0)
	or	a			; (0 marks the end)
	jr	z,@r13
	and	(hl)
	ld	(bc),a
	inc	bc
	add	hl,de
	inc	ix
	jr	@reg
@r13:
	ld	a,(hl)			; 0FFh: not written this frame
	cp	0FFh
	jr	z,@next
	and	0Fh
	ld	(ay_regs+13),a
@next:
	ld	hl,(ym_ptr)
	ld	de,(ym_fstride)
	add	hl,de
	ld	(ym_ptr),hl
	ld	hl,(ym_pos)
	inc	hl
	ld	(ym_pos),hl
	ld	de,(ym_frames)
	or	a
	sbc	hl,de
	ret	c
	ld	hl,(ym_loop)		; the end: on from the loop frame
	ld	(ym_pos),hl
	ld	hl,(ym_loopptr)
	ld	(ym_ptr),hl
	ld	hl,ym_loops
	inc	(hl)
	ret

; ym_length: HL = frames * 50 / frames per second.
ym_length:
	ld	hl,(ym_frames)
	add	hl,hl			; * 2
	push	hl
	add	hl,hl			; * 16
	add	hl,hl
	add	hl,hl
	push	hl
	add	hl,hl			; * 32
	pop	de
	add	hl,de
	pop	de
	add	hl,de
	ld	de,(ym_rate)
	jp	lib_div24

; The bits of registers 0 to 12 that the AY uses (the rest select YM5
; and YM6 special effects), then 0 to end the list.
ym_masks:	db	0FFh,0Fh,0FFh,0Fh,0FFh,0Fh,1Fh,3Fh,1Fh,1Fh,1Fh,0FFh
		db	0FFh,0
ym_leonard:	db	"LeOnArD!"
ym_lh5:		db	"-lh5-"