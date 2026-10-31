; z80emu.asm - runs Z80 machine code (such as the players in AY files).
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
; Part of the reusable agonAMP sound library in lib/. Needs z80tab.inc
; (made by tools/mkz80tab.py).
;
; The Z80 has 64 KB of memory; here that is a 64 KB page of the Agon's
; memory, chosen by z_page (its top address byte, as for the eZ80's MBASE
; register). The eZ80 runs Z80 instructions itself, so most of them are
; simply copied, one at a time, into a small piece of code here and run
; there with the .SIS prefix (40h). That prefix makes the eZ80 work as a
; Z80 for the one instruction: 16 bit registers, and memory addresses in
; the page MBASE points to. While the Z80 code runs, the eZ80's alternate
; registers AF', BC', DE' and HL' hold the Z80's AF, BC, DE and HL, its
; IX and IY hold the Z80's IX and IY, and its 16 bit stack pointer SPS is
; the Z80's SP; the code here uses the main registers (DE holds the Z80's
; program counter). The instructions that cannot be run that way are
; carried out by the code here: jumps, calls and returns (the program
; counter is DE here), EXX and EX AF,AF' (which would swap the two
; register sets), HALT, DI, EI, IM, RETI, RETN, LD I,A, LD A,I, the
; input and output instructions, and the few that the eZ80 does not have
; (SLL, the undocumented DD CB forms, the ED duplicates of NEG and the
; like).
;
; Interrupts are only taken when z_int is called. There is no T-state
; timing: z_run carries on until a HALT, or until it has used up a given
; count, which goes down by one for each jump, call and return and for
; every 16 instructions.
;
; Entry points:
;   z_run   run until HALT or until the count in (z_left) is used up.
;           Out: (z_halted) non-zero if it stopped at HALT.
;   z_int   take an interrupt now, if they are enabled (IM 0 and 1: a
;           call to 0038h; IM 2: a call to the address held at
;           I * 256 + 0FFh, the Spectrum's bus giving 0FFh)
; Before z_run is first called, the registers (z_af and so on) and
; z_page must be set, and z_outfn and z_infn must point to routines for
; the OUT and IN instructions:
;   z_outfn  In: BC = port, A = value. May use AF, BC, HL only.
;   z_infn   In: BC = port. Out: A = value. May use AF, BC, HL only.
;
; All registers are used, except IX and IY. While the Z80 code runs, the
; eZ80's B counts instructions down to the next step of the count (see
; z_slow), so every piece of code below that changes B keeps it.

; What z_edtab says about the byte after ED.
ZE_NOP:		equ	0	; does nothing (two bytes)
ZE_N2:		equ	1	; run as it stands, two bytes
ZE_N4:		equ	2	; run as it stands, four bytes
ZE_IN:		equ	3	; IN r,(C)
ZE_OUT:		equ	4	; OUT (C),r
ZE_RETN:	equ	5	; RETN, RETI
ZE_IM:		equ	6	; IM 0, 1, 2
ZE_LDIA:	equ	7	; LD I,A
ZE_LDAI:	equ	8	; LD A,I
ZE_NEG:		equ	9	; a duplicate of NEG
ZE_BLKIN:	equ	10	; INI, IND, INIR, INDR
ZE_BLKOUT:	equ	11	; OUTI, OUTD, OTIR, OTDR
ZE_HLNN:	equ	12	; the ED forms of LD (nn),HL and LD HL,(nn)
ZE_CPR:		equ	13	; CPIR, CPDR
ZE_LDAR:	equ	14	; LD A,R

; The Z80's registers (3 bytes each, only the low 16 bits counting).
z_af:		ds	3
z_bc:		ds	3
z_de:		ds	3
z_hl:		ds	3
z_ix:		ds	3
z_iy:		ds	3
z_sp:		ds	3
z_pc:		ds	3
z_af2:		ds	3	; the alternate set
z_bc2:		ds	3
z_de2:		ds	3
z_hl2:		ds	3
z_i:		ds	1
z_im:		ds	1	; interrupt mode
z_iff1:		ds	1	; interrupts enabled
z_iff2:		ds	1
z_halted:	ds	1	; non-zero if stopped at HALT
z_left:		ds	3	; jumps etc. still allowed (see the top)
z_page:		ds	1	; MBASE value of the Z80's memory
z_outfn:	ds	3	; OUT routine
z_infn:		ds	3	; IN routine
z_oldmb:	ds	1	; MBASE as it was
z_edop:		ds	1	; the byte after ED
z_bin:		ds	1	; block I/O: 1 for input
z_xr:		ds	11	; z_getr: registers laid out

; ---------------------------------------------------------------------
; z_run: see above.
; ---------------------------------------------------------------------
z_run:
	push	ix
	push	iy
	ld	a,mb			; the Z80's memory
	ld	(z_oldmb),a
	ld	a,(z_page)
	ld	mb,a
	ld	ix,(z_ix)		; its registers
	ld	iy,(z_iy)
	ld	hl,(z_sp)
	ld.sis	sp,hl
	ld	hl,(z_af)
	push	hl
	pop	af
	ex	af,af'
	exx
	ld	bc,(z_bc)
	ld	de,(z_de)
	ld	hl,(z_hl)
	exx
	ld	de,(z_pc)
	xor	a
	ld	(z_halted),a
	ld	b,16			; B: instructions to the next count
	jr	z_loop

; The piece of code for one-byte instructions (see z_n1) comes straight
; before the main loop, so that it runs on into it without a jump.
z_j1:	db	0D9h,08h,40h,0,08h,0D9h

; The main loop: one instruction each time round. DE = the address of
; the next instruction (only its low 16 bits count).
z_loop:
	dec	b			; every 16 instructions also count as
	jr	z,z_slow		; a jump, so that code which never
z_disp:					; jumps cannot run for ever
	ld.sis	a,(de)			; its first byte
	ld	hl,z_tabl		; picks a handler
	ld	l,a
	ld	c,(hl)
	inc	h
	ld	h,(hl)
	ld	l,c
	jp	(hl)			; with A = first byte

; z_slow: another 16 instructions have been run.
z_slow:
	ld	b,16
	ld	hl,(z_left)
	dec	hl
	ld	(z_left),hl
	ld	a,(z_left+2)
	or	a
	jp	p,z_disp
	jr	z_stop

; z_next: after a jump, call or return: count it, and stop when the
; count runs out.
z_next:
	ld	hl,(z_left)
	dec	hl
	ld	(z_left),hl
	ld	a,(z_left+2)
	or	a
	jp	p,z_loop
	; fall through

; z_stop: put the Z80's state away and return from z_run.
z_stop:
	ld	(z_pc),de
	exx
	ld	(z_bc),bc
	ld	(z_de),de
	ld	(z_hl),hl
	exx
	ex	af,af'
	push	af
	pop	hl
	ld	(z_af),hl
	ld	hl,0
	add.sis	hl,sp
	ld	(z_sp),hl
	ld	(z_ix),ix
	ld	(z_iy),iy
	ld	a,(z_oldmb)
	ld	mb,a
	pop	iy
	pop	ix
	ret

; ---------------------------------------------------------------------
; Instructions run as they stand. Each piece of code swaps the Z80's
; registers in, runs the instruction with the .SIS prefix and swaps them
; out again.
; ---------------------------------------------------------------------
; (These three jump to their piece of code, which goes back to z_loop.)
z_n1:					; one byte
	ld	(z_j1+3),a
	inc	de
	jp	z_j1
z_n2:					; two bytes
	ld	(z_j2+3),a
	inc	de
	ld.sis	a,(de)
	ld	(z_j2+4),a
	inc	de
	jp	z_j2
z_n3:					; three bytes
	ld	(z_j3+3),a
	inc	de
	ld.sis	a,(de)
	ld	(z_j3+4),a
	inc	de
	ld.sis	a,(de)
	ld	(z_j3+5),a
	inc	de
	jp	z_j3

; z_nb: run the C bytes (1 to 4) at DE as one instruction, through z_t4.
; The SCF/NOP byte at z_t4+2 must be set first.
z_nb:
	xor	a			; NOPs where there are fewer than 4
	ld	hl,z_t4+4
	ld	(hl),a
	inc	hl
	ld	(hl),a
	inc	hl
	ld	(hl),a
	inc	hl
	ld	(hl),a
	ld	hl,z_t4+4
@copy:
	ld.sis	a,(de)
	inc	de
	ld	(hl),a
	inc	hl
	dec	c
	jr	nz,@copy
	call	z_t4
	jp	z_loop

z_j2:	db	0D9h,08h,40h,0,0,08h,0D9h,0C3h
	dl	z_loop
z_j3:	db	0D9h,08h,40h,0,0,0,08h,0D9h,0C3h
	dl	z_loop
; (and called, for instructions that need more done afterwards)
z_t2:	db	0D9h,08h,40h,0,0,08h,0D9h,0C9h
; (z_t4+2 is SCF (37h) for SLL, otherwise NOP)
z_t4:	db	0D9h,08h,0,40h,0,0,0,0,08h,0D9h,0C9h

z_nop:					; LD B,B and the like
	inc	de
	jp	z_loop

; CB: all but SLL run as they stand. SLL r is SCF then RL r.
z_cb:
	inc	de
	ld.sis	a,(de)
	dec	de
	ld	c,a
	and	0F8h
	cp	30h
	jr	z,@sll
	ld	a,0CBh
	ld	(z_t2+3),a
	ld	a,c
	ld	(z_t2+4),a
	inc	de
	inc	de
	call	z_t2
	jp	z_loop
@sll:
	ld	a,37h			; SCF
	ld	(z_t4+2),a
	call	z_cbcopy
	ld	a,c
	and	07h
	or	10h			; RL r
	ld	(z_t4+5),a
	call	z_t4
	jp	z_loop

; z_cbcopy: copy the two bytes at DE into z_t4 (with NOPs after them)
; and move DE past them.
z_cbcopy:
	ld	hl,z_t4+4
	ld.sis	a,(de)
	ld	(hl),a
	inc	de
	inc	hl
	ld.sis	a,(de)
	ld	(hl),a
	inc	de
	inc	hl
	xor	a
	ld	(hl),a
	inc	hl
	ld	(hl),a
	ret

; ---------------------------------------------------------------------
; Jumps, calls and returns.
; ---------------------------------------------------------------------
z_jp:					; JP nn
	ex	de,hl
	inc	hl
	ld.sis	hl,(hl)
	ex	de,hl
	jp	z_next
z_jpcc:					; JP cc,nn
	call	z_cond
	jr	c,z_jp
	inc	de
	inc	de
	inc	de
	jp	z_loop
z_jr:					; JR e
	inc	de
	ld.sis	a,(de)
	inc	de
	ld	l,a			; sign extended into HL
	add	a,a
	sbc	a,a
	ld	h,a
	add	hl,de			; (only the low 16 bits count)
	ex	de,hl
	jp	z_next
z_jrcc:					; JR cc,e: cc is in bits 3 and 4
	and	18h
	call	z_cond
	jr	c,z_jr
	inc	de
	inc	de
	jp	z_loop
z_djnz:					; DJNZ e
	exx
	dec	b
	exx
	jr	nz,z_jr
	inc	de
	inc	de
	jp	z_loop
z_call:					; CALL nn
	ex	de,hl
	inc	hl
	ld.sis	de,(hl)
	inc	hl
	inc	hl
	push.sis	hl
	jp	z_next
z_callcc:				; CALL cc,nn
	call	z_cond
	jr	c,z_call
	inc	de
	inc	de
	inc	de
	jp	z_loop
z_ret:					; RET
	pop.sis	de
	jp	z_next
z_retcc:				; RET cc
	call	z_cond
	jr	c,z_ret
	inc	de
	jp	z_loop
z_rst:					; RST p
	inc	de
	push.sis	de
	and	38h
	ld	de,0
	ld	e,a
	jp	z_next
z_jphl:					; JP (HL)
	exx
	push	hl
	exx
	pop	de
	jp	z_next

; z_cond: is condition cc (bits 3 to 5 of A) true of the Z80's flags?
; Out: carry set if so.
z_cond:
	and	38h
	or	0C2h			; JP cc
	ld	(@test),a
	ex	af,af'
	jr	@test			; (a jump, so the new byte is fetched)
@test:	jp	nz,@true		; (the condition is put in above)
	ex	af,af'
	or	a
	ret
@true:
	ex	af,af'
	scf
	ret

; ---------------------------------------------------------------------
; The rest of the unprefixed instructions that need special handling.
; ---------------------------------------------------------------------
z_halt:					; HALT: stop here
	inc	de
	ld	a,1
	ld	(z_halted),a
	jp	z_stop
z_di:					; DI
	xor	a
	jr	z_setiff
z_ei:					; EI
	ld	a,1
z_setiff:
	ld	(z_iff1),a
	ld	(z_iff2),a
	inc	de
	jp	z_loop
z_exaf:					; EX AF,AF'
	ex	af,af'
	push	af
	ld	hl,(z_af2)
	push	hl
	pop	af
	pop	hl
	ld	(z_af2),hl
	ex	af,af'
	inc	de
	jp	z_loop
z_exx:					; EXX
	exx
	push	hl
	push	de
	push	bc
	ld	bc,(z_bc2)
	ld	de,(z_de2)
	ld	hl,(z_hl2)
	exx
	pop	hl
	ld	(z_bc2),hl
	pop	hl
	ld	(z_de2),hl
	pop	hl
	ld	(z_hl2),hl
	inc	de
	jp	z_loop
z_outn:					; OUT (n),A: the port is A * 256 + n
	push	bc			; (the instruction count)
	inc	de
	ld.sis	a,(de)
	inc	de
	ld	c,a
	ex	af,af'
	ld	b,a
	ex	af,af'
	ld	a,b
	call	z_out
	pop	bc
	jp	z_loop
z_inn:					; IN A,(n)
	push	bc			; (the instruction count)
	inc	de
	ld.sis	a,(de)
	inc	de
	ld	c,a
	ex	af,af'
	ld	b,a
	ex	af,af'
	call	z_in
	ld	b,a			; into A; the flags stay as they are
	ex	af,af'
	ld	a,b
	ex	af,af'
	pop	bc
	jp	z_loop

; z_out, z_in: call the routines z_outfn and z_infn point to.
z_out:
	ld	hl,(z_outfn)
	jp	(hl)
z_in:
	ld	hl,(z_infn)
	jp	(hl)

; ---------------------------------------------------------------------
; DD and FD (IX and IY).
; ---------------------------------------------------------------------
z_dd:
	inc	de
	ld.sis	a,(de)			; what follows the prefix
	ld	hl,z_ddtab
	ld	l,a
	ld	a,(hl)
	or	a
	jp	z,z_loop		; not an IX one: as if no prefix
	dec	de
	ld	c,a
	cp	5
	jr	z,@cb
	xor	a			; (no SCF)
	ld	(z_t4+2),a
	ld	a,c
	cp	1
	jp	nz,z_nb			; run it as it stands (C bytes)
	ld.sis	a,(de)			; JP (IX) or JP (IY)
	cp	0DDh
	jr	nz,@iy
	push	ix
	pop	de
	jp	z_next
@iy:
	push	iy
	pop	de
	jp	z_next
@cb:
	; DD CB d op. The forms with op & 7 other than 6 also copy the
	; result to a register; the eZ80 lacks them, so the plain form is
	; run and then LD r,(IX+d). SLL is SCF then RL, as above.
	ld	hl,z_t4+4
	ld	c,4
@copy:
	ld.sis	a,(de)
	ld	(hl),a
	inc	de
	inc	hl
	dec	c
	jr	nz,@copy
	ld	a,(z_t4+7)		; op
	ld	c,a
	and	0F8h
	cp	30h
	ld	a,0
	jr	nz,@notsll
	ld	a,c
	and	07h
	or	10h
	ld	c,a
	ld	a,37h			; SCF
@notsll:
	ld	(z_t4+2),a
	ld	a,c
	and	0F8h
	or	06h
	ld	(z_t4+7),a
	call	z_t4
	ld	a,c			; a register to copy to?
	cp	40h
	jr	c,@copyr
	cp	80h
	jp	c,z_loop		; (BIT has no such form)
@copyr:
	and	07h
	cp	06h
	jp	z,z_loop
	add	a,a			; LD r,(IX+d): 46h + 8 * r
	add	a,a
	add	a,a
	add	a,46h
	ld	(z_t4+5),a		; (prefix and d are still in place)
	xor	a
	ld	(z_t4+2),a
	ld	(z_t4+7),a
	call	z_t4
	jp	z_loop

; ---------------------------------------------------------------------
; ED.
; ---------------------------------------------------------------------
z_ed:
	inc	de
	ld.sis	a,(de)
	ld	(z_edop),a
	dec	de
	ld	hl,z_edtab
	ld	l,a
	ld	a,(hl)
	ld	c,a			; jump through the table below
	add	a,a
	add	a,c
	push	de
	ld	de,0
	ld	e,a
	ld	hl,z_edjp
	add	hl,de
	pop	de
	ld	hl,(hl)
	jp	(hl)
z_edjp:
	dl	@nop,@n2,@n4,@in,@out,@retn,@im,@ldia,@ldai,@neg,@blkin
	dl	@blkout,@hlnn,@cpr,@ldar
@nop:
	inc	de
	inc	de
	jp	z_loop
@n2:
	ld	a,0EDh
	jp	z_n2
@n4:
	xor	a
	ld	(z_t4+2),a
	ld	c,4
	jp	z_nb
@neg:					; as ED 44
	ld	a,44h
	ld	(z_t2+4),a
	ld	a,0EDh
	ld	(z_t2+3),a
	inc	de
	inc	de
	call	z_t2
	jp	z_loop
@hlnn:					; ED 63 nn is 22 nn, ED 6B nn is 2A nn
	inc	de
	ld	a,(z_edop)
	sub	41h
	jp	z_n3
@cpr:
	; CPIR and CPDR are run as CPI or CPD over and over: the emulator
	; this was tested on leaves the S and H flags of the repeating forms
	; different from a Z80's, but gets those of CPI and CPD right.
	ld	a,(z_edop)
	sub	10h			; CPI or CPD
	ld	(z_t2+4),a
	ld	a,0EDh
	ld	(z_t2+3),a
	inc	de
	inc	de
@cpr1:
	call	z_t2
	ex	af,af'			; stop when found, Z, or BC is 0, PO
	jr	z,@cpr2
	jp	po,@cpr2
	ex	af,af'
	jr	@cpr1
@cpr2:
	ex	af,af'
	jp	z_loop
@in:					; IN r,(C)
	push	bc			; (the instruction count)
	call	z_getbc
	call	z_in
	pop	bc
	ld	c,a
	ld	a,(z_edop)
	and	38h
	cp	30h			; IN (C) only sets the flags
	jr	z,@in6
	or	06h			; LD r,n
	ld	(z_t2+3),a
	ld	a,c
	ld	(z_t2+4),a
	call	z_t2
@in6:
	xor	a			; S, Z and P/V (parity) from the value
	call	z_szp
	inc	de
	inc	de
	jp	z_loop
@out:					; OUT (C),r
	push	bc			; (the instruction count)
	ld	a,(z_edop)
	rrca
	rrca
	rrca
	and	07h
	call	z_getr
	push	af
	call	z_getbc
	pop	af
	call	z_out
	pop	bc
	inc	de
	inc	de
	jp	z_loop
@retn:					; RETN, RETI: IFF1 = IFF2, RET
	ld	a,(z_iff2)
	ld	(z_iff1),a
	jp	z_ret
@im:					; IM 0, 1 or 2
	ld	a,(z_edop)
	rrca
	rrca
	rrca
	and	03h			; 0, 0, 1, 2
	jr	z,@im0
	dec	a
@im0:
	ld	(z_im),a
	inc	de
	inc	de
	jp	z_loop
@ldia:					; LD I,A
	ex	af,af'
	ld	c,a
	ex	af,af'
	ld	a,c
	ld	(z_i),a
	inc	de
	inc	de
	jp	z_loop
@ldar:					; LD A,R: the eZ80's refresh count
	ld	a,r			; will do for the Z80's
	jr	@ldx
@ldai:					; LD A,I
	ld	a,(z_i)
@ldx:	ld	c,a
	ex	af,af'
	ld	a,c
	ex	af,af'
	ld	a,1			; S and Z from I, P/V = IFF2
	call	z_szp
	inc	de
	inc	de
	jp	z_loop
@blkin:
	ld	a,1
	jr	@blk
@blkout:
	xor	a
@blk:
	ld	(z_bin),a
	push	bc			; (the instruction count)
	inc	de
	inc	de
	; INI, OUTI and the rest. B goes down by one (before the port is
	; formed, for output), a byte goes between (HL) and the port, and HL
	; goes up (or down). The repeating forms carry on until B is 0.
@again:
	ld	a,(z_bin)
	or	a
	jr	z,@bout
	call	z_getbc			; input: port BC, then B goes down
	call	z_in
	exx
	ld.sis	(hl),a
	dec	b
	exx
	jr	@bstep
@bout:
	exx				; output: B goes down, then port BC
	ld.sis	a,(hl)
	dec	b
	push	bc
	exx
	pop	bc
	call	z_out
@bstep:
	ld	a,(z_edop)
	bit	3,a			; up or down
	exx
	jr	nz,@down
	inc	hl
	jr	@moved
@down:
	dec	hl
@moved:
	ld	a,b
	exx
	; flags: Z if B is now 0, N set; the rest left alone
	ld	c,02h
	or	a
	jr	nz,@nz
	ld	c,42h
@nz:
	ex	af,af'
	push	af
	ex	af,af'
	pop	hl
	ld	a,l
	and	0BDh
	or	c
	ld	l,a
	push	hl
	ex	af,af'
	pop	af
	ex	af,af'
	ld	a,(z_edop)		; repeat?
	bit	4,a
	jr	z,@bdone
	ld	a,c
	cp	42h
	jr	z,@bdone
	ld	hl,(z_left)		; (each time round counts as a jump)
	dec	hl
	ld	(z_left),hl
	ld	a,(z_left+2)
	or	a
	jp	p,@again
	pop	bc
	dec	de			; out of time: do it again next run
	dec	de
	jp	z_stop
@bdone:
	pop	bc
	jp	z_loop

; z_szp: set the Z80's flags as IN r,(C) and LD A,I do: S and Z from
; the value C, H and N clear, carry kept, and P/V the parity of C (A = 0)
; or IFF2 (A not 0). Preserves B and DE.
z_szp:
	or	a			; (which P/V?)
	ld	a,c
	jr	z,@byc
	or	a			; S and Z of C; H, N clear
	push	af
	pop	hl
	res	2,l			; P/V = IFF2 instead
	ld	a,(z_iff2)
	or	a
	jr	z,@par
	set	2,l
	jr	@par
@byc:
	or	a			; S, Z and parity of C; H, N clear
	push	af
	pop	hl
@par:
	ld	a,l
	and	0C4h
	ld	c,a
	ex	af,af'			; the Z80's F: keep only the carry
	push	af
	ex	af,af'
	pop	hl
	ld	a,l
	and	01h
	or	c
	ld	l,a
	push	hl
	ex	af,af'
	pop	af
	ex	af,af'
	ret

; z_getbc: BC = the Z80's BC. Preserves DE.
z_getbc:
	exx
	push	bc
	exx
	pop	bc
	ret

; z_getr: A = the Z80's register A (0 to 7: B, C, D, E, H, L, -, A),
; 0 for 6. Preserves DE.
z_getr:
	push	de
	exx
	ld	(z_xr),bc
	ld	(z_xr+3),de
	ld	(z_xr+6),hl
	exx
	ld	b,a
	ex	af,af'
	ld	(z_xr+9),a
	ex	af,af'
	xor	a
	ld	(z_xr+10),a
	ld	hl,z_rofs
	ld	de,0
	ld	e,b
	add	hl,de
	ld	e,(hl)
	ld	hl,z_xr
	add	hl,de
	ld	a,(hl)
	pop	de
	ret
z_rofs:	db	1,0,4,3,7,6,10,9	; where each register is in z_xr

; ---------------------------------------------------------------------
; z_int: take an interrupt if they are enabled.
; ---------------------------------------------------------------------
z_int:
	ld	a,(z_iff1)
	or	a
	ret	z
	xor	a
	ld	(z_iff1),a
	ld	(z_iff2),a
	ld	(z_halted),a
	ld	a,mb
	ld	(z_oldmb),a
	ld	a,(z_page)
	ld	mb,a
	ld	hl,(z_sp)		; push the program counter
	dec	hl
	dec	hl
	ld	(z_sp),hl
	ld	bc,(z_pc)
	ld.sis	(hl),bc
	ld	hl,0038h		; IM 0 and 1: RST 38h
	ld	a,(z_im)
	cp	2
	jr	nz,@go
	ld	a,(z_i)			; IM 2: the address at I * 256 + 0FFh
	ld	h,a
	ld	l,0FFh
	ld.sis	hl,(hl)
@go:
	ld	(z_pc),hl
	ld	a,(z_oldmb)
	ld	mb,a
	ret

	include	"../lib/z80tab.inc"