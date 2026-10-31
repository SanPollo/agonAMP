; z80tab.inc - decoding tables for z80emu.asm. Made by
; tools/mkz80tab.py; do not edit by hand.
	.align	256
z_tabl:				; low bytes of the handlers
	db	z_n1 & 0FFh,z_n3 & 0FFh,z_n1 & 0FFh,z_n1 & 0FFh
	db	z_n1 & 0FFh,z_n1 & 0FFh,z_n2 & 0FFh,z_n1 & 0FFh
	db	z_exaf & 0FFh,z_n1 & 0FFh,z_n1 & 0FFh,z_n1 & 0FFh
	db	z_n1 & 0FFh,z_n1 & 0FFh,z_n2 & 0FFh,z_n1 & 0FFh
	db	z_djnz & 0FFh,z_n3 & 0FFh,z_n1 & 0FFh,z_n1 & 0FFh
	db	z_n1 & 0FFh,z_n1 & 0FFh,z_n2 & 0FFh,z_n1 & 0FFh
	db	z_jr & 0FFh,z_n1 & 0FFh,z_n1 & 0FFh,z_n1 & 0FFh
	db	z_n1 & 0FFh,z_n1 & 0FFh,z_n2 & 0FFh,z_n1 & 0FFh
	db	z_jrcc & 0FFh,z_n3 & 0FFh,z_n3 & 0FFh,z_n1 & 0FFh
	db	z_n1 & 0FFh,z_n1 & 0FFh,z_n2 & 0FFh,z_n1 & 0FFh
	db	z_jrcc & 0FFh,z_n1 & 0FFh,z_n3 & 0FFh,z_n1 & 0FFh
	db	z_n1 & 0FFh,z_n1 & 0FFh,z_n2 & 0FFh,z_n1 & 0FFh
	db	z_jrcc & 0FFh,z_n3 & 0FFh,z_n3 & 0FFh,z_n1 & 0FFh
	db	z_n1 & 0FFh,z_n1 & 0FFh,z_n2 & 0FFh,z_n1 & 0FFh
	db	z_jrcc & 0FFh,z_n1 & 0FFh,z_n3 & 0FFh,z_n1 & 0FFh
	db	z_n1 & 0FFh,z_n1 & 0FFh,z_n2 & 0FFh,z_n1 & 0FFh
	db	z_nop & 0FFh,z_n1 & 0FFh,z_n1 & 0FFh,z_n1 & 0FFh
	db	z_n1 & 0FFh,z_n1 & 0FFh,z_n1 & 0FFh,z_n1 & 0FFh
	db	z_n1 & 0FFh,z_nop & 0FFh,z_n1 & 0FFh,z_n1 & 0FFh
	db	z_n1 & 0FFh,z_n1 & 0FFh,z_n1 & 0FFh,z_n1 & 0FFh
	db	z_n1 & 0FFh,z_n1 & 0FFh,z_nop & 0FFh,z_n1 & 0FFh
	db	z_n1 & 0FFh,z_n1 & 0FFh,z_n1 & 0FFh,z_n1 & 0FFh
	db	z_n1 & 0FFh,z_n1 & 0FFh,z_n1 & 0FFh,z_nop & 0FFh
	db	z_n1 & 0FFh,z_n1 & 0FFh,z_n1 & 0FFh,z_n1 & 0FFh
	db	z_n1 & 0FFh,z_n1 & 0FFh,z_n1 & 0FFh,z_n1 & 0FFh
	db	z_n1 & 0FFh,z_n1 & 0FFh,z_n1 & 0FFh,z_n1 & 0FFh
	db	z_n1 & 0FFh,z_n1 & 0FFh,z_n1 & 0FFh,z_n1 & 0FFh
	db	z_n1 & 0FFh,z_n1 & 0FFh,z_n1 & 0FFh,z_n1 & 0FFh
	db	z_n1 & 0FFh,z_n1 & 0FFh,z_n1 & 0FFh,z_n1 & 0FFh
	db	z_n1 & 0FFh,z_n1 & 0FFh,z_halt & 0FFh,z_n1 & 0FFh
	db	z_n1 & 0FFh,z_n1 & 0FFh,z_n1 & 0FFh,z_n1 & 0FFh
	db	z_n1 & 0FFh,z_n1 & 0FFh,z_n1 & 0FFh,z_n1 & 0FFh
	db	z_n1 & 0FFh,z_n1 & 0FFh,z_n1 & 0FFh,z_n1 & 0FFh
	db	z_n1 & 0FFh,z_n1 & 0FFh,z_n1 & 0FFh,z_n1 & 0FFh
	db	z_n1 & 0FFh,z_n1 & 0FFh,z_n1 & 0FFh,z_n1 & 0FFh
	db	z_n1 & 0FFh,z_n1 & 0FFh,z_n1 & 0FFh,z_n1 & 0FFh
	db	z_n1 & 0FFh,z_n1 & 0FFh,z_n1 & 0FFh,z_n1 & 0FFh
	db	z_n1 & 0FFh,z_n1 & 0FFh,z_n1 & 0FFh,z_n1 & 0FFh
	db	z_n1 & 0FFh,z_n1 & 0FFh,z_n1 & 0FFh,z_n1 & 0FFh
	db	z_n1 & 0FFh,z_n1 & 0FFh,z_n1 & 0FFh,z_n1 & 0FFh
	db	z_n1 & 0FFh,z_n1 & 0FFh,z_n1 & 0FFh,z_n1 & 0FFh
	db	z_n1 & 0FFh,z_n1 & 0FFh,z_n1 & 0FFh,z_n1 & 0FFh
	db	z_n1 & 0FFh,z_n1 & 0FFh,z_n1 & 0FFh,z_n1 & 0FFh
	db	z_n1 & 0FFh,z_n1 & 0FFh,z_n1 & 0FFh,z_n1 & 0FFh
	db	z_n1 & 0FFh,z_n1 & 0FFh,z_n1 & 0FFh,z_n1 & 0FFh
	db	z_n1 & 0FFh,z_n1 & 0FFh,z_n1 & 0FFh,z_n1 & 0FFh
	db	z_n1 & 0FFh,z_n1 & 0FFh,z_n1 & 0FFh,z_n1 & 0FFh
	db	z_n1 & 0FFh,z_n1 & 0FFh,z_n1 & 0FFh,z_n1 & 0FFh
	db	z_retcc & 0FFh,z_n1 & 0FFh,z_jpcc & 0FFh,z_jp & 0FFh
	db	z_callcc & 0FFh,z_n1 & 0FFh,z_n2 & 0FFh,z_rst & 0FFh
	db	z_retcc & 0FFh,z_ret & 0FFh,z_jpcc & 0FFh,z_cb & 0FFh
	db	z_callcc & 0FFh,z_call & 0FFh,z_n2 & 0FFh,z_rst & 0FFh
	db	z_retcc & 0FFh,z_n1 & 0FFh,z_jpcc & 0FFh,z_outn & 0FFh
	db	z_callcc & 0FFh,z_n1 & 0FFh,z_n2 & 0FFh,z_rst & 0FFh
	db	z_retcc & 0FFh,z_exx & 0FFh,z_jpcc & 0FFh,z_inn & 0FFh
	db	z_callcc & 0FFh,z_dd & 0FFh,z_n2 & 0FFh,z_rst & 0FFh
	db	z_retcc & 0FFh,z_n1 & 0FFh,z_jpcc & 0FFh,z_n1 & 0FFh
	db	z_callcc & 0FFh,z_n1 & 0FFh,z_n2 & 0FFh,z_rst & 0FFh
	db	z_retcc & 0FFh,z_jphl & 0FFh,z_jpcc & 0FFh,z_n1 & 0FFh
	db	z_callcc & 0FFh,z_ed & 0FFh,z_n2 & 0FFh,z_rst & 0FFh
	db	z_retcc & 0FFh,z_n1 & 0FFh,z_jpcc & 0FFh,z_di & 0FFh
	db	z_callcc & 0FFh,z_n1 & 0FFh,z_n2 & 0FFh,z_rst & 0FFh
	db	z_retcc & 0FFh,z_n1 & 0FFh,z_jpcc & 0FFh,z_ei & 0FFh
	db	z_callcc & 0FFh,z_dd & 0FFh,z_n2 & 0FFh,z_rst & 0FFh
z_tabh:				; and their high bytes
	db	z_n1 >> 8 & 0FFh,z_n3 >> 8 & 0FFh,z_n1 >> 8 & 0FFh
	db	z_n1 >> 8 & 0FFh,z_n1 >> 8 & 0FFh,z_n1 >> 8 & 0FFh
	db	z_n2 >> 8 & 0FFh,z_n1 >> 8 & 0FFh,z_exaf >> 8 & 0FFh
	db	z_n1 >> 8 & 0FFh,z_n1 >> 8 & 0FFh,z_n1 >> 8 & 0FFh
	db	z_n1 >> 8 & 0FFh,z_n1 >> 8 & 0FFh,z_n2 >> 8 & 0FFh
	db	z_n1 >> 8 & 0FFh,z_djnz >> 8 & 0FFh,z_n3 >> 8 & 0FFh
	db	z_n1 >> 8 & 0FFh,z_n1 >> 8 & 0FFh,z_n1 >> 8 & 0FFh
	db	z_n1 >> 8 & 0FFh,z_n2 >> 8 & 0FFh,z_n1 >> 8 & 0FFh
	db	z_jr >> 8 & 0FFh,z_n1 >> 8 & 0FFh,z_n1 >> 8 & 0FFh
	db	z_n1 >> 8 & 0FFh,z_n1 >> 8 & 0FFh,z_n1 >> 8 & 0FFh
	db	z_n2 >> 8 & 0FFh,z_n1 >> 8 & 0FFh,z_jrcc >> 8 & 0FFh
	db	z_n3 >> 8 & 0FFh,z_n3 >> 8 & 0FFh,z_n1 >> 8 & 0FFh
	db	z_n1 >> 8 & 0FFh,z_n1 >> 8 & 0FFh,z_n2 >> 8 & 0FFh
	db	z_n1 >> 8 & 0FFh,z_jrcc >> 8 & 0FFh,z_n1 >> 8 & 0FFh
	db	z_n3 >> 8 & 0FFh,z_n1 >> 8 & 0FFh,z_n1 >> 8 & 0FFh
	db	z_n1 >> 8 & 0FFh,z_n2 >> 8 & 0FFh,z_n1 >> 8 & 0FFh
	db	z_jrcc >> 8 & 0FFh,z_n3 >> 8 & 0FFh,z_n3 >> 8 & 0FFh
	db	z_n1 >> 8 & 0FFh,z_n1 >> 8 & 0FFh,z_n1 >> 8 & 0FFh
	db	z_n2 >> 8 & 0FFh,z_n1 >> 8 & 0FFh,z_jrcc >> 8 & 0FFh
	db	z_n1 >> 8 & 0FFh,z_n3 >> 8 & 0FFh,z_n1 >> 8 & 0FFh
	db	z_n1 >> 8 & 0FFh,z_n1 >> 8 & 0FFh,z_n2 >> 8 & 0FFh
	db	z_n1 >> 8 & 0FFh,z_nop >> 8 & 0FFh,z_n1 >> 8 & 0FFh
	db	z_n1 >> 8 & 0FFh,z_n1 >> 8 & 0FFh,z_n1 >> 8 & 0FFh
	db	z_n1 >> 8 & 0FFh,z_n1 >> 8 & 0FFh,z_n1 >> 8 & 0FFh
	db	z_n1 >> 8 & 0FFh,z_nop >> 8 & 0FFh,z_n1 >> 8 & 0FFh
	db	z_n1 >> 8 & 0FFh,z_n1 >> 8 & 0FFh,z_n1 >> 8 & 0FFh
	db	z_n1 >> 8 & 0FFh,z_n1 >> 8 & 0FFh,z_n1 >> 8 & 0FFh
	db	z_n1 >> 8 & 0FFh,z_nop >> 8 & 0FFh,z_n1 >> 8 & 0FFh
	db	z_n1 >> 8 & 0FFh,z_n1 >> 8 & 0FFh,z_n1 >> 8 & 0FFh
	db	z_n1 >> 8 & 0FFh,z_n1 >> 8 & 0FFh,z_n1 >> 8 & 0FFh
	db	z_n1 >> 8 & 0FFh,z_nop >> 8 & 0FFh,z_n1 >> 8 & 0FFh
	db	z_n1 >> 8 & 0FFh,z_n1 >> 8 & 0FFh,z_n1 >> 8 & 0FFh
	db	z_n1 >> 8 & 0FFh,z_n1 >> 8 & 0FFh,z_n1 >> 8 & 0FFh
	db	z_n1 >> 8 & 0FFh,z_n1 >> 8 & 0FFh,z_n1 >> 8 & 0FFh
	db	z_n1 >> 8 & 0FFh,z_n1 >> 8 & 0FFh,z_n1 >> 8 & 0FFh
	db	z_n1 >> 8 & 0FFh,z_n1 >> 8 & 0FFh,z_n1 >> 8 & 0FFh
	db	z_n1 >> 8 & 0FFh,z_n1 >> 8 & 0FFh,z_n1 >> 8 & 0FFh
	db	z_n1 >> 8 & 0FFh,z_n1 >> 8 & 0FFh,z_n1 >> 8 & 0FFh
	db	z_n1 >> 8 & 0FFh,z_n1 >> 8 & 0FFh,z_n1 >> 8 & 0FFh
	db	z_n1 >> 8 & 0FFh,z_halt >> 8 & 0FFh,z_n1 >> 8 & 0FFh
	db	z_n1 >> 8 & 0FFh,z_n1 >> 8 & 0FFh,z_n1 >> 8 & 0FFh
	db	z_n1 >> 8 & 0FFh,z_n1 >> 8 & 0FFh,z_n1 >> 8 & 0FFh
	db	z_n1 >> 8 & 0FFh,z_n1 >> 8 & 0FFh,z_n1 >> 8 & 0FFh
	db	z_n1 >> 8 & 0FFh,z_n1 >> 8 & 0FFh,z_n1 >> 8 & 0FFh
	db	z_n1 >> 8 & 0FFh,z_n1 >> 8 & 0FFh,z_n1 >> 8 & 0FFh
	db	z_n1 >> 8 & 0FFh,z_n1 >> 8 & 0FFh,z_n1 >> 8 & 0FFh
	db	z_n1 >> 8 & 0FFh,z_n1 >> 8 & 0FFh,z_n1 >> 8 & 0FFh
	db	z_n1 >> 8 & 0FFh,z_n1 >> 8 & 0FFh,z_n1 >> 8 & 0FFh
	db	z_n1 >> 8 & 0FFh,z_n1 >> 8 & 0FFh,z_n1 >> 8 & 0FFh
	db	z_n1 >> 8 & 0FFh,z_n1 >> 8 & 0FFh,z_n1 >> 8 & 0FFh
	db	z_n1 >> 8 & 0FFh,z_n1 >> 8 & 0FFh,z_n1 >> 8 & 0FFh
	db	z_n1 >> 8 & 0FFh,z_n1 >> 8 & 0FFh,z_n1 >> 8 & 0FFh
	db	z_n1 >> 8 & 0FFh,z_n1 >> 8 & 0FFh,z_n1 >> 8 & 0FFh
	db	z_n1 >> 8 & 0FFh,z_n1 >> 8 & 0FFh,z_n1 >> 8 & 0FFh
	db	z_n1 >> 8 & 0FFh,z_n1 >> 8 & 0FFh,z_n1 >> 8 & 0FFh
	db	z_n1 >> 8 & 0FFh,z_n1 >> 8 & 0FFh,z_n1 >> 8 & 0FFh
	db	z_n1 >> 8 & 0FFh,z_n1 >> 8 & 0FFh,z_n1 >> 8 & 0FFh
	db	z_n1 >> 8 & 0FFh,z_n1 >> 8 & 0FFh,z_n1 >> 8 & 0FFh
	db	z_n1 >> 8 & 0FFh,z_n1 >> 8 & 0FFh,z_n1 >> 8 & 0FFh
	db	z_n1 >> 8 & 0FFh,z_n1 >> 8 & 0FFh,z_n1 >> 8 & 0FFh
	db	z_n1 >> 8 & 0FFh,z_n1 >> 8 & 0FFh,z_n1 >> 8 & 0FFh
	db	z_n1 >> 8 & 0FFh,z_n1 >> 8 & 0FFh,z_n1 >> 8 & 0FFh
	db	z_n1 >> 8 & 0FFh,z_n1 >> 8 & 0FFh,z_n1 >> 8 & 0FFh
	db	z_n1 >> 8 & 0FFh,z_n1 >> 8 & 0FFh,z_n1 >> 8 & 0FFh
	db	z_retcc >> 8 & 0FFh,z_n1 >> 8 & 0FFh,z_jpcc >> 8 & 0FFh
	db	z_jp >> 8 & 0FFh,z_callcc >> 8 & 0FFh,z_n1 >> 8 & 0FFh
	db	z_n2 >> 8 & 0FFh,z_rst >> 8 & 0FFh,z_retcc >> 8 & 0FFh
	db	z_ret >> 8 & 0FFh,z_jpcc >> 8 & 0FFh,z_cb >> 8 & 0FFh
	db	z_callcc >> 8 & 0FFh,z_call >> 8 & 0FFh,z_n2 >> 8 & 0FFh
	db	z_rst >> 8 & 0FFh,z_retcc >> 8 & 0FFh,z_n1 >> 8 & 0FFh
	db	z_jpcc >> 8 & 0FFh,z_outn >> 8 & 0FFh,z_callcc >> 8 & 0FFh
	db	z_n1 >> 8 & 0FFh,z_n2 >> 8 & 0FFh,z_rst >> 8 & 0FFh
	db	z_retcc >> 8 & 0FFh,z_exx >> 8 & 0FFh,z_jpcc >> 8 & 0FFh
	db	z_inn >> 8 & 0FFh,z_callcc >> 8 & 0FFh,z_dd >> 8 & 0FFh
	db	z_n2 >> 8 & 0FFh,z_rst >> 8 & 0FFh,z_retcc >> 8 & 0FFh
	db	z_n1 >> 8 & 0FFh,z_jpcc >> 8 & 0FFh,z_n1 >> 8 & 0FFh
	db	z_callcc >> 8 & 0FFh,z_n1 >> 8 & 0FFh,z_n2 >> 8 & 0FFh
	db	z_rst >> 8 & 0FFh,z_retcc >> 8 & 0FFh,z_jphl >> 8 & 0FFh
	db	z_jpcc >> 8 & 0FFh,z_n1 >> 8 & 0FFh,z_callcc >> 8 & 0FFh
	db	z_ed >> 8 & 0FFh,z_n2 >> 8 & 0FFh,z_rst >> 8 & 0FFh
	db	z_retcc >> 8 & 0FFh,z_n1 >> 8 & 0FFh,z_jpcc >> 8 & 0FFh
	db	z_di >> 8 & 0FFh,z_callcc >> 8 & 0FFh,z_n1 >> 8 & 0FFh
	db	z_n2 >> 8 & 0FFh,z_rst >> 8 & 0FFh,z_retcc >> 8 & 0FFh
	db	z_n1 >> 8 & 0FFh,z_jpcc >> 8 & 0FFh,z_ei >> 8 & 0FFh
	db	z_callcc >> 8 & 0FFh,z_dd >> 8 & 0FFh,z_n2 >> 8 & 0FFh
	db	z_rst >> 8 & 0FFh
z_ddtab:			; after DD or FD
	db	0,0,0,0,0,0,0,0,0,2,0,0,0,0,0,0
	db	0,0,0,0,0,0,0,0,0,2,0,0,0,0,0,0
	db	0,4,4,2,2,2,3,0,0,2,4,2,2,2,3,0
	db	0,0,0,0,3,3,4,0,0,2,0,0,0,0,0,0
	db	0,0,0,0,2,2,3,0,0,0,0,0,2,2,3,0
	db	0,0,0,0,2,2,3,0,0,0,0,0,2,2,3,0
	db	2,2,2,2,2,2,3,2,2,2,2,2,2,2,3,2
	db	3,3,3,3,3,3,0,3,0,0,0,0,2,2,3,0
	db	0,0,0,0,2,2,3,0,0,0,0,0,2,2,3,0
	db	0,0,0,0,2,2,3,0,0,0,0,0,2,2,3,0
	db	0,0,0,0,2,2,3,0,0,0,0,0,2,2,3,0
	db	0,0,0,0,2,2,3,0,0,0,0,0,2,2,3,0
	db	0,0,0,0,0,0,0,0,0,0,0,5,0,0,0,0
	db	0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
	db	0,2,0,2,0,2,0,0,0,1,0,0,0,0,0,0
	db	0,0,0,0,0,0,0,0,0,2,0,0,0,0,0,0
z_edtab:			; after ED
	db	0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
	db	0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
	db	0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
	db	0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
	db	3,4,1,2,1,5,6,7,3,4,1,2,9,5,6,1
	db	3,4,1,2,9,5,6,8,3,4,1,2,9,5,6,14
	db	3,4,1,12,9,5,6,1,3,4,1,12,9,5,6,1
	db	3,4,1,2,9,5,6,0,3,4,1,2,9,5,6,0
	db	0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
	db	0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
	db	1,1,10,11,0,0,0,0,1,1,10,11,0,0,0,0
	db	1,13,10,11,0,0,0,0,1,13,10,11,0,0,0,0
	db	0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
	db	0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
	db	0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
	db	0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0