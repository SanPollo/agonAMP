; notetab.inc - note tables shared by the replayers in lib/.
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
; Part of the reusable agonAMP sound library in lib/. Two tables of AY
; tone periods, kept here so that the replayers that use the same one
; share it: stcplay.asm and stpplay.asm use nt_st, ascplay.asm and
; pscplay.asm use nt_asc. Include this file once with any of them.

; Sound Tracker's note table: 96 AY tone periods, as published in the
; format description. (It is not quite the same as the "ST" table that
; PT3 modules can select: two entries differ.)
nt_st:
	dw	00EF8h,00E10h,00D60h,00C80h,00BD8h,00B28h,00A88h,009F0h,00960h,008E0h,00858h,007E0h
	dw	0077Ch,00708h,006B0h,00640h,005ECh,00594h,00544h,004F8h,004B0h,00470h,0042Ch,003F0h
	dw	003BEh,00384h,00358h,00320h,002F6h,002CAh,002A2h,0027Ch,00258h,00238h,00216h,001F8h
	dw	001DFh,001C2h,001ACh,00190h,0017Bh,00165h,00151h,0013Eh,0012Ch,0011Ch,0010Bh,000FCh
	dw	000EFh,000E1h,000D6h,000C8h,000BDh,000B2h,000A8h,0009Fh,00096h,0008Eh,00085h,0007Eh
	dw	00077h,00070h,0006Bh,00064h,0005Eh,00059h,00054h,0004Fh,0004Bh,00047h,00042h,0003Fh
	dw	0003Bh,00038h,00035h,00032h,0002Fh,0002Ch,0002Ah,00027h,00025h,00023h,00021h,0001Fh
	dw	0001Dh,0001Ch,0001Ah,00019h,00017h,00016h,00015h,00013h,00012h,00011h,00010h,0000Fh

; ASC Sound Master's note table: 86 AY tone periods.
nt_asc:
	dw	00EDCh,00E07h,00D3Eh,00C80h,00BCCh,00B22h,00A82h,009ECh,0095Ch,008D6h,00858h,007E0h
	dw	0076Eh,00704h,0069Fh,00640h,005E6h,00591h,00541h,004F6h,004AEh,0046Bh,0042Ch,003F0h
	dw	003B7h,00382h,0034Fh,00320h,002F3h,002C8h,002A1h,0027Bh,00257h,00236h,00216h,001F8h
	dw	001DCh,001C1h,001A8h,00190h,00179h,00164h,00150h,0013Dh,0012Ch,0011Bh,0010Bh,000FCh
	dw	000EEh,000E0h,000D4h,000C8h,000BDh,000B2h,000A8h,0009Fh,00096h,0008Dh,00085h,0007Eh
	dw	00077h,00070h,0006Ah,00064h,0005Eh,00059h,00054h,00050h,0004Bh,00047h,00043h,0003Fh
	dw	0003Ch,00038h,00035h,00032h,0002Fh,0002Dh,0002Ah,00028h,00026h,00024h,00022h,00020h
	dw	0001Eh,0001Ch