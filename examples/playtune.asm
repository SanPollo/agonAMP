; playtune.asm - the smallest program that uses the agonAMP sound
; library: it plays a PT3 module that is built into the program until a
; key is pressed. Use it as a pattern for music in a game.
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
; Put a module called tune.pt3 in this directory, then from here run:
;       ez80asm playtune.asm playtune.bin
	.assume	adl=1
	.org	040000h
	jp	start
	.align	64
	.db	"MOS",0,1		; MOS executable header, ADL mode

start:
	push	ix
	push	iy
	ld	a,08h			; mos_sysvars: IX -> system variables
	rst.lil	08h
	ld	(sysvars),ix
	ld	a,(ix+19h)		; sysvar_vkeycount
	ld	(keycount),a

	call	ay_init			; prepare the VDP sound channels
	ld	hl,tune
	call	pt3_init		; point the replayer at the module
	call	tick_start		; start the 50 Hz tick

loop:
	ld	a,(tick_count)		; is a frame of music due?
	or	a
	jr	z,idle
	ld	hl,tick_count
	dec	(hl)
	call	pt3_play		; work out this frame's AY registers
	call	ay_update		; and play them
	jr	loop
idle:
	; A game would do its own work here. This just waits for a key:
	; the count changes on every key event, and vkeydown says whether
	; it was a press.
	ld	ix,(sysvars)
	ld	a,(ix+19h)
	ld	hl,keycount
	cp	(hl)
	jr	z,loop
	ld	(hl),a
	ld	a,(ix+18h)		; sysvar_vkeydown
	or	a
	jr	z,loop

	call	tick_stop
	call	ay_shutdown
	pop	iy
	pop	ix
	ld	hl,0			; return "no error" to MOS
	ret

sysvars:	ds	3
keycount:	ds	1
tune:
	incbin	"tune.pt3"

	include	"../lib/libsupport.asm"
	include	"../lib/pt3play.asm"
	include	"../lib/pt3tab.inc"
	include	"../lib/ayvdp.asm"
	include	"../lib/tick50.asm"