; tick50.asm - a 50 Hz tick from eZ80 timer 1, for music timing.
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
; Part of the reusable agonAMP sound library in lib/. PT3 music is timed
; at 50 frames a second, but Agon screen modes refresh at 60 Hz or more,
; so the vertical blank cannot be used as the clock. MOS uses timer 0
; itself, so this uses timer 1.
;
; The interrupt only counts. The program's main loop should do, as often
; as it can:
;
;       ld      a,(tick_count)
;       or      a
;       jr      z,nothing_due
;       ld      hl,tick_count
;       dec     (hl)
;       call    pt3_play
;       call    ay_update
;
; The music is not played from inside the interrupt because its VDU
; bytes could then land in the middle of a VDU sequence that the main
; program was sending.
;
; Entry points:
;   tick_start  start the timer (corrupts AF, DE, HL)
;   tick_stop   stop it and give the interrupt vector back to MOS

TICK_CTL_PORT:	equ	83h	; TMR1_CTL
TICK_RRL_PORT:	equ	84h	; TMR1_RR_L
TICK_RRH_PORT:	equ	85h	; TMR1_RR_H
TICK_VECTOR:	equ	0Ch	; PRT1 interrupt vector
; 18.432 MHz / 256 = 72000 Hz; 72000 / 1440 = 50 Hz.
TICK_RELOAD:	equ	1440
; Enable, reload, divide by 256, continuous, interrupt on.
TICK_CTL:	equ	5Fh
TICK_MAX:	equ	4	; ticks kept if the program falls behind

tick_count:	ds	1	; ticks waiting to be played
tick_oldvec:	ds	3	; the vector as MOS had it

tick_start:
	xor	a
	ld	(tick_count),a
	ld	e,TICK_VECTOR
	ld	hl,tick_isr
	ld	a,14h			; mos_setintvector
	rst.lil	08h
	ld	(tick_oldvec),hl
	ld	a,TICK_RELOAD & 0FFh
	out0	(TICK_RRL_PORT),a
	ld	a,TICK_RELOAD >> 8
	out0	(TICK_RRH_PORT),a
	ld	a,TICK_CTL
	out0	(TICK_CTL_PORT),a
	ret

tick_stop:
	xor	a
	out0	(TICK_CTL_PORT),a
	ld	e,TICK_VECTOR
	ld	hl,(tick_oldvec)
	ld	a,14h			; mos_setintvector
	rst.lil	08h
	ret

; The interrupt routine. At most TICK_MAX ticks are kept, so that after
; a hold-up (reading a directory, say) the music resumes rather than
; races to catch up.
tick_isr:
	di
	push	af
	; reading the register clears the request
	in0	a,(TICK_CTL_PORT)
	ld	a,(tick_count)
	cp	TICK_MAX
	jr	nc,@full
	inc	a
	ld	(tick_count),a
@full:
	pop	af
	ei
	reti.l