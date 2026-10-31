; files.asm - the playlist, M3U playlist files and the file browser.
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
; The playlist is a table of pointers to absolute path strings held in a
; pool. The browser lists one directory at a time: sub-directories, PT3
; music files of the kinds agonAMP plays and M3U playlists, sorted with
; directories first.
;
; M3U files are plain text, one path per line; lines starting with '#'
; are comments. Paths that do not start with '/' are taken relative to
; the directory the playlist file is in. LF, CR LF and CR line endings
; are read; CR LF is written.

; ---------------------------------------------------------------------
; Playlist
; ---------------------------------------------------------------------

; pl_clear: empty the playlist.
pl_clear:
	call	shuf_zero
	ld	hl,0
	ld	(pl_count),hl
	ld	(pl_sel),hl
	ld	(pl_top),hl
	dec	hl
	ld	(pl_cur),hl		; no current entry
	ld	(pl_resume),hl
	ld	hl,PL_POOL
	ld	(pl_free),hl
	xor	a
	ld	(pan_line),a
	ld	(pl_name),a		; no name now
	ret

; pl_setname: note the file name (without its directory) of the path at
; HL as the playlist's name, cut to 40 characters, in DE (pl_name or
; pl_name2).
pl_setname:
	push	de
	push	hl			; find the last '/'
	pop	de
@find:
	ld	a,(hl)
	or	a
	jr	z,@found
	inc	hl
	cp	'/'
	jr	nz,@find
	push	hl
	pop	de
	jr	@find
@found:
	ex	de,hl
	pop	de
	ld	b,40
@copy:
	ld	a,(hl)
	or	a
	jr	z,@end
	ld	(de),a
	inc	hl
	inc	de
	djnz	@copy
@end:
	xor	a
	ld	(de),a
	ret

; pl_get: HL = entry number. Out: HL -> its path.
pl_get:
	call	mul3
	ld	de,pl_ptr
	add	hl,de
	ld	hl,(hl)
	ret

; pl_add: append a path. In: HL -> path. Out: carry set if there was no
; room for it.
pl_add:
	push	hl
	ld	hl,(pl_count)
	ld	de,PL_MAX
	or	a
	sbc	hl,de
	pop	hl
	ccf
	ret	c
	call	strlen
	push	hl
	ld	hl,(pl_free)
	add	hl,bc
	ld	de,PL_POOL_END
	or	a
	sbc	hl,de
	pop	hl
	ccf
	ret	c
	push	hl
	ld	hl,(pl_count)
	call	mul3
	ld	de,pl_ptr
	add	hl,de
	ld	de,(pl_free)
	ld	(hl),de
	pop	hl
	call	strcpy
	inc	de
	ld	(pl_free),de
	ld	hl,(pl_count)		; not known to be unplayable
	ld	de,pl_bad
	add	hl,de
	ld	(hl),0
	ld	hl,(pl_count)
	inc	hl
	ld	(pl_count),hl
	ld	a,(panel)		; show it if the playlist is on screen
	or	a
	ret	nz
	ld	(pan_line),a
	ret

; pl_del: remove the selected entry, and its text from the pool.
pl_del:
	call	shuf_zero		; entry numbers are about to change
	ld	hl,(pl_count)
	ld	a,h
	or	l
	ret	z
	; Close the gap its text leaves in the pool: the text after it
	; moves down, and every entry whose text was after it (not
	; necessarily a later entry: [ and ] move entries, not text) is
	; pointed that much lower.
	ld	hl,(pl_sel)
	call	pl_get			; HL -> its text
	ld	(pd_text),hl
	call	strlen
	inc	bc			; (and its terminator)
	ld	(pd_len),bc
	add	hl,bc			; HL -> the text after it
	ex	de,hl
	ld	hl,(pl_free)
	or	a
	sbc	hl,de			; HL = bytes of text after it
	jr	z,@shut
	push	hl
	pop	bc
	ex	de,hl
	ld	de,(pd_text)
	ldir
@shut:
	ld	hl,(pl_free)
	ld	de,(pd_len)
	or	a
	sbc	hl,de
	ld	(pl_free),hl
	ld	ix,pl_ptr
	ld	a,(pl_count)		; (at most 255 entries)
	ld	b,a
@adj:
	ld	hl,(ix+0)
	ld	de,(pd_text)
	or	a
	sbc	hl,de
	jr	c,@keep			; text before it: stays where it is
	jr	z,@keep			; (its own: the entry goes below)
	add	hl,de
	ld	de,(pd_len)
	or	a
	sbc	hl,de
	ld	(ix+0),hl
@keep:
	lea	ix,ix+3
	djnz	@adj
	ld	hl,(pl_count)		; then the entry itself goes
	ld	de,(pl_sel)
	or	a
	sbc	hl,de
	dec	hl			; entries after the selected one
	call	mul3
	push	hl
	ld	hl,(pl_sel)
	call	mul3
	ld	de,pl_ptr
	add	hl,de
	push	hl
	pop	de
	inc	hl
	inc	hl
	inc	hl
	pop	bc
	ld	a,b
	or	c
	jr	z,@nomove
	ldir
@nomove:
	ld	hl,(pl_count)		; the "unplayable" marks move up too
	ld	de,(pl_sel)
	or	a
	sbc	hl,de
	dec	hl
	ld	a,h
	or	l
	jr	z,@nobad
	push	hl
	pop	bc
	ld	hl,(pl_sel)
	ld	de,pl_bad
	add	hl,de
	push	hl
	pop	de
	inc	hl
	ldir
@nobad:
	ld	hl,(pl_count)
	dec	hl
	ld	(pl_count),hl
	ld	hl,(pl_count)		; keep "current" on the same song (if
	ld	de,(pl_cur)		; one is playing: the count is now one
	or	a			; less, so a real entry is no more
	sbc	hl,de			; than it)
	jr	c,@none
	ld	hl,(pl_sel)
	or	a
	sbc	hl,de
	jr	nc,@notbefore
	dec	de			; one before it went: one place up
	ld	(pl_cur),de
	jr	@cur
@notbefore:
	jr	nz,@cur			; one after it went: no change
	ld	hl,(pl_sel)		; the one playing went: none is now
	ld	(pl_resume),hl		; current, but Right and Left carry on
	ld	hl,0FFFFFFh		; from where it was
	ld	(pl_cur),hl
	jr	@cur
@none:
	ld	a,(pl_resume+2)		; (FFFFFFh: there is no such place)
	or	a
	jr	nz,@cur
	ld	hl,(pl_sel)		; none playing: an entry removed above
	ld	de,(pl_resume)		; where the removed playing one was
	or	a			; moves that place up
	sbc	hl,de
	jr	nc,@cur
	dec	de
	ld	(pl_resume),de
@cur:
	ld	hl,(pl_sel)		; keep the selection on the list
	ld	de,(pl_count)
	or	a
	sbc	hl,de
	jr	c,@sel
	ld	hl,(pl_count)
	ld	a,h
	or	l
	jr	z,@zero
	dec	hl
@zero:
	ld	(pl_sel),hl
@sel:
	ld	hl,(pl_sel)
	ld	de,(pl_top)
	or	a
	sbc	hl,de
	jr	nc,@top
	ld	hl,(pl_sel)
	ld	(pl_top),hl
@top:
	xor	a
	ld	(pan_line),a
	ret

; pl_moveup / pl_movedown: move the selected entry one place up or down
; the playlist, by swapping it with its neighbour. The selection goes
; with it, and so does the "now playing" mark if either was playing.
pl_moveup:
	ld	a,(panel)
	or	a
	ret	nz
	ld	hl,(pl_sel)
	ld	a,h
	or	l
	ret	z			; already at the top
	dec	hl
	ld	(mv_new),hl
	jr	pl_swap
pl_movedown:
	ld	a,(panel)
	or	a
	ret	nz
	ld	hl,(pl_sel)
	inc	hl
	ld	de,(pl_count)
	or	a
	sbc	hl,de
	ret	nc			; already at the bottom
	add	hl,de
	ld	(mv_new),hl
	dec	hl
; pl_swap: swap entries HL and HL + 1, then select entry (mv_new).
pl_swap:
	push	hl
	call	mul3
	ld	de,pl_ptr
	add	hl,de
	ld	de,(hl)			; the two path pointers
	inc	hl
	inc	hl
	inc	hl
	ld	bc,(hl)
	ld	(hl),de
	dec	hl
	dec	hl
	dec	hl
	ld	(hl),bc
	pop	hl
	push	hl
	ld	de,pl_bad		; the two "unplayable" marks
	add	hl,de
	ld	a,(hl)
	inc	hl
	ld	c,(hl)
	ld	(hl),a
	dec	hl
	ld	(hl),c
	pop	hl
	; and "now playing", if it was one of them
	ld	a,(pl_cur)
	cp	l
	jr	nz,@other
	inc	a
	jr	@cur
@other:
	dec	a
	cp	l
	jr	nz,@done
@cur:
	ld	(pl_cur),a
@done:
	; and the place a removed playing entry was, likewise
	ld	a,(pl_resume)
	cp	l
	jr	nz,@rother
	inc	a
	jr	@rset
@rother:
	dec	a
	cp	l
	jr	nz,@rdone
@rset:
	ld	(pl_resume),a
@rdone:
	; entry numbers changed: new shuffle round
	call	shuf_clear
	ld	ix,pl_count
	ld	hl,(mv_new)
	jp	lst_setsel

; pl_load_m3u: replace the playlist with the contents of an M3U file.
; In: HL -> absolute path of the file (may be tmp_path). Out: carry set
; if the file could not be read (or its path is too long to keep), in
; which case the playlist is left as it was.
pl_load_m3u:
	call	strlen			; the path must fit in pl_path, and
	push	hl			; its directory in m3u_dir with room
	ld	hl,PATH_LIM		; for a '/' to be added
	or	a
	sbc	hl,bc
	pop	hl
	ret	c
	push	hl			; (its name, kept until it is read)
	ld	de,pl_name2
	call	pl_setname
	pop	hl
	push	hl
	ld	de,m3u_dir		; directory the file is in
	call	strcpy
	ld	hl,m3u_dir
	call	path_up
	pop	hl
	push	hl
	ld	de,IOBUF
	ld	bc,IOBUF_MAX
	call	file_read
	pop	de
	ret	c
	push	de
	ld	de,IOBUF		; end the text with a zero
	add	hl,de
	ld	(hl),0
	call	pl_clear
	pop	hl			; the playlist takes the file's full
	ld	de,pl_path		; path
	call	strcpy
	ld	hl,pl_name2		; and its name
	ld	de,pl_name
	call	strcpy
	ld	hl,(IOBUF)		; skip a UTF-8 byte order mark (all
	ld	de,0BFBBEFh		; three bytes must match)
	or	a
	sbc	hl,de
	ld	hl,IOBUF
	jr	nz,@line
	ld	hl,IOBUF+3
@line:
	ld	a,(hl)
	or	a
	ret	z
	cp	13
	jr	z,@skip
	cp	10
	jr	z,@skip
	cp	' '
	jr	z,@skip
	cp	'#'
	jr	z,@comment
	ld	de,tmp_path
	cp	'/'
	jr	z,@copy
	cp	5Ch
	jr	z,@copy
	push	hl			; relative: start with the directory
	ld	hl,m3u_dir
	call	strcpy
	dec	de
	ld	a,(de)
	inc	de
	cp	'/'
	jr	z,@joined
	ld	a,'/'
	ld	(de),a
	inc	de
@joined:
	pop	hl
@copy:
	ld	a,(hl)
	or	a
	jr	z,@eol
	cp	13
	jr	z,@eol
	cp	10
	jr	z,@eol
	cp	5Ch			; accept '\' as a separator
	jr	nz,@put
	ld	a,'/'
@put:
	ld	(de),a
	inc	hl
	; stop storing if the line is absurdly long
	push	hl
	ld	hl,tmp_path+500
	or	a
	sbc	hl,de
	pop	hl
	jr	c,@copy
	inc	de
	jr	@copy
@eol:
	dec	de			; drop trailing spaces
	ld	a,(de)
	cp	' '
	jr	z,@eol
	inc	de
	xor	a
	ld	(de),a
	push	hl
	ld	hl,tmp_path
	call	pl_add
	pop	hl
	jr	@line
@skip:
	inc	hl
	jr	@line
@comment:
	ld	a,(hl)
	or	a
	ret	z
	cp	10
	jr	z,@line
	cp	13			; (CR alone ends a line too)
	jr	z,@line
	inc	hl
	jr	@comment

; pl_save: write the playlist as an M3U file named in_buf, in the
; directory the browser is showing; or, if in_buf is the playlist's own
; name, over the file it came from (or was last saved as), even if that
; name was too long to show in full. ".m3u" is added if a new name has no
; extension. Entries inside the directory are written relative to it. An
; existing file of the same name is replaced.
pl_save:
	ld	hl,(pl_count)
	ld	a,h
	or	l
	jp	z,ui_helpbar
	ld	a,(pl_name)
	or	a
	jr	z,@dir
	ld	hl,pl_name
	call	strlen
	inc	c			; (the zeros must match too)
	ld	b,c
	ld	hl,pl_name
	ld	de,in_buf
	call	memcmp
	jr	nz,@dir
	ld	hl,pl_path		; its own name: the same file again
	ld	de,tmp_path
	call	strcpy
	ld	hl,pl_path
	ld	de,sv_path
	call	strcpy
	ld	hl,sv_path
	call	path_up
	jr	@named
@dir:
	ld	hl,br_path		; a new name: the browser's directory
	ld	de,sv_path
	call	strcpy
	ld	hl,sv_path
	ld	bc,in_buf
	ld	de,tmp_path
	call	path_join
	ld	hl,in_buf
@dot:
	ld	a,(hl)
	or	a
	jr	z,@addext
	cp	'.'
	jr	z,@named
	inc	hl
	jr	@dot
@addext:
	ld	hl,ext_m3u_lc
	call	strcpy
@named:
	ld	hl,sv_path		; the prefix that makes a path relative
	ld	de,m3u_dir
	call	strcpy
	dec	de
	ld	a,(de)
	inc	de
	cp	'/'
	jr	z,@pfx
	ld	a,'/'
	ld	(de),a
	inc	de
	xor	a
	ld	(de),a
@pfx:
	ld	hl,0
	ld	(sv_i),hl
	ld	hl,IOBUF
	ld	(sv_out),hl
@entry:
	ld	hl,(sv_i)
	ld	de,(pl_count)
	or	a
	sbc	hl,de
	jr	nc,@write
	ld	hl,(sv_i)
	call	pl_get
	push	hl
	ld	de,m3u_dir		; does it start with the prefix?
@cmp:
	ld	a,(de)
	or	a
	jr	z,@rel			; yes: HL is past the prefix
	cp	(hl)
	jr	nz,@abs
	inc	hl
	inc	de
	jr	@cmp
@abs:
	pop	hl			; no: the whole path
	jr	@emit
@rel:
	pop	de
@emit:
	ld	de,(sv_out)
	call	strcpy
	ld	a,13
	ld	(de),a
	inc	de
	ld	a,10
	ld	(de),a
	inc	de
	ld	(sv_out),de
	ld	hl,(sv_i)
	inc	hl
	ld	(sv_i),hl
	jr	@entry
@write:
	ld	hl,(sv_out)
	ld	de,IOBUF
	or	a
	sbc	hl,de
	push	hl
	pop	bc
	ld	hl,tmp_path
	ld	de,IOBUF
	call	file_write
	push	af
	jr	c,@failed
	ld	hl,tmp_path		; saved: the playlist has this name now
	ld	de,pl_name
	call	pl_setname
	ld	hl,tmp_path		; and this full path
	ld	de,pl_path
	call	strcpy
	ld	hl,sv_path		; saved where the browser is looking?
	ld	de,br_path
@same:
	ld	a,(de)
	cp	(hl)
	jr	nz,@failed
	inc	hl
	inc	de
	or	a
	jr	nz,@same
	call	br_reread		; then list the new file there
@failed:
	pop	af
	ld	hl,txt_saved
	jr	nc,@msg
	ld	hl,txt_notsaved
@msg:
	ld	de,pb_buf
	call	strcpy
	push	de
	ld	hl,tmp_path
	ld	b,60
	call	vtail			; (corrupts DE)
	pop	de
	call	strcpy
	ld	hl,pb_buf
	jp	ui_msg

; ---------------------------------------------------------------------
; File browser
; ---------------------------------------------------------------------

; has_ext: does a name end with a 4 character extension (any case)?
; In: HL -> name, DE -> extension in upper case. Out: Z if it does.
; has_extn: the same for an extension of A characters.
has_ext:
	ld	a,4
has_extn:
	ld	(he_len),a
	push	de
	call	strlen
	push	hl
	ld	hl,0
	ld	a,(he_len)
	ld	l,a
	or	a
	sbc	hl,bc
	pop	hl
	pop	de
	jr	c,@long
	jr	z,@long
	or	1			; too short
	ret
@long:
	add	hl,bc
	ld	a,(he_len)
	ld	b,a
@back:
	dec	hl
	djnz	@back
	ld	b,a
@cmp:
	ld	a,(hl)
	call	upcase
	ld	c,a
	ld	a,(de)
	cp	c
	ret	nz
	inc	hl
	inc	de
	djnz	@cmp
	xor	a
	ret

; br_add: add an entry to the browser list. In: A = kind (0 directory,
; 1 module, 2 playlist), HL -> name.
br_add:
	ld	c,a
	push	hl
	ld	hl,(br_count)
	ld	de,BR_MAX
	or	a
	sbc	hl,de
	pop	hl
	ret	nc
	push	hl
	ld	hl,(br_free)
	ld	de,BR_POOL_END
	or	a
	sbc	hl,de
	pop	hl
	ret	nc
	push	hl
	ld	hl,(br_count)
	call	mul3
	ld	de,br_ptr
	add	hl,de
	ld	de,(br_free)
	ld	(hl),de
	pop	hl
	ld	a,c
	ld	(de),a
	inc	de
	call	strcpy
	inc	de
	ld	(br_free),de
	ld	hl,(br_count)
	inc	hl
	ld	(br_count),hl
	ret

; br_read: read the directory br_path into the browser list.
br_read:
	ld	hl,0
	ld	(br_count),hl
	ld	(br_sel),hl
	ld	(br_top),hl
	ld	hl,BR_POOL
	ld	(br_free),hl
	ld	a,(br_path+1)		; anything but "/" has a parent
	or	a
	jr	z,@open
	ld	hl,txt_dotdot
	xor	a
	call	br_add
@open:
	ld	hl,dirobj
	ld	de,br_path
	ld	a,ffs_dopen
	rst.lil	08h
	or	a
	jp	nz,@sort
@next:
	ld	hl,dirobj
	ld	de,filinfo
	ld	a,ffs_dread
	rst.lil	08h
	or	a
	jp	nz,@close
	ld	a,(filinfo+FI_NAME)
	or	a
	jp	z,@close		; an empty name marks the end
	cp	'.'
	jr	z,@next
	ld	a,(filinfo+FI_ATTRIB)
	bit	1,a			; hidden
	jr	nz,@next
	bit	4,a			; directory
	jr	z,@file
	xor	a
	jp	@add
@file:
	ld	iy,mod_exts		; a music file?
@ext:
	ld	a,(iy+0)
	or	a
	jr	z,@notmod
	lea	de,iy+1
	ld	hl,filinfo+FI_NAME
	push	iy
	call	has_extn
	pop	iy
	ld	a,1
	jr	z,@add
	ld	de,0
	ld	e,(iy+0)
	inc	e
	add	iy,de
	jr	@ext
@notmod:
	ld	hl,filinfo+FI_NAME
	ld	de,ext_m3u
	call	has_ext
	ld	a,2
	jp	nz,@next
@add:
	ld	hl,filinfo+FI_NAME
	call	br_add
	jp	@next
@close:
	ld	hl,dirobj
	ld	a,ffs_dclose
	rst.lil	08h
@sort:
	; Shell sort of the pointer table. ".." is left out of it, so that
	; it stays first.
	ld	hl,br_ptr
	ld	a,(br_path+1)
	or	a
	jr	z,@base
	inc	hl
	inc	hl
	inc	hl
@base:
	ld	(srt_base),hl
	ld	hl,(br_count)
	call	mul3
	ld	de,br_ptr
	add	hl,de
	ld	(srt_end),hl
	ld	iy,srt_gaps
@gap:
	ld	hl,0			; the next gap, in bytes; 0 ends
	ld	l,(iy+0)
	ld	h,(iy+1)
	ld	a,h
	or	l
	ret	z
	lea	iy,iy+2
	ld	(srt_gb),hl
	ld	de,(srt_base)
	add	hl,de
	ld	(srt_i),hl		; first slot to place for this gap
@outer:
	ld	hl,(srt_i)
	ld	de,(srt_end)
	or	a
	sbc	hl,de
	jr	nc,@gap
	ld	hl,(srt_i)
	ld	de,(hl)
	ld	(srt_key),de
@inner:
	ld	(srt_p),hl		; the slot being filled
	ld	de,(srt_gb)		; the slot one gap before it
	or	a
	sbc	hl,de
	ld	de,(srt_base)
	or	a
	sbc	hl,de
	jr	c,@place		; (none: before the start)
	add	hl,de
	push	hl
	ld	hl,(hl)
	ld	de,(srt_key)
	call	br_cmp
	pop	hl
	jr	nc,@place
	push	hl			; move the larger entry up one gap
	ld	de,(hl)
	ld	hl,(srt_p)
	ld	(hl),de
	pop	hl
	jr	@inner
@place:
	ld	hl,(srt_p)
	ld	de,(srt_key)
	ld	(hl),de
	ld	hl,(srt_i)
	inc	hl
	inc	hl
	inc	hl
	ld	(srt_i),hl
	jr	@outer

; srt_gaps: the gaps for the Shell sort (Ciura's sequence, times 3 for
; the size of a pointer), largest first; BR_MAX is 500.
srt_gaps:	dw	301*3,132*3,57*3,23*3,10*3,4*3,1*3,0

; br_cmp: order two browser entries: kind first, then name without
; regard to case. In: HL, DE -> entries. Out: carry if (HL) sorts after
; (DE).
br_cmp:
	ld	a,(de)
	cp	(hl)
	ret	nz
@ch:
	inc	hl
	inc	de
	ld	a,(hl)
	call	upcase
	ld	c,a
	ld	a,(de)
	call	upcase
	cp	c
	ret	nz
	or	a
	ret	z
	jr	@ch

; br_reread: read the directory again, keeping the selection on the same
; entry number (or the last, if there are fewer now).
br_reread:
	ld	hl,(br_sel)
	push	hl
	call	br_show
	pop	hl
	ld	de,(br_count)
	ld	a,d
	or	e
	ret	z
	or	a
	sbc	hl,de
	add	hl,de
	jr	c,@keep
	ex	de,hl
	dec	hl
@keep:
	ld	ix,br_count
	jp	lst_setsel

; br_show: read the directory again and redraw the browser.
br_show:
	call	br_read
	ld	a,1
	ld	(dirty_panbar),a
	xor	a
	ld	(pan_line),a
	ret

; br_selected: Out: A = kind and HL -> name of the selected entry, with
; carry set if the list is empty.
br_selected:
	ld	hl,(br_count)
	ld	a,h
	or	l
	scf
	ret	z
	ld	hl,(br_sel)
	call	mul3
	ld	de,br_ptr
	add	hl,de
	ld	hl,(hl)
	ld	a,(hl)
	inc	hl
	or	a
	ret

; br_fullpath: tmp_path = br_path + "/" + name at HL.
br_fullpath:
	push	hl
	pop	bc
	ld	hl,br_path
	ld	de,tmp_path
	jp	path_join

; br_parent: go up one directory.
br_parent:
	ld	hl,br_path
	call	path_up
	jp	br_show

; br_activate: Enter on the selected entry: go into a directory, play a
; module (adding it to the playlist), or load a playlist and play it.
br_activate:
	call	br_selected
	ret	c
	or	a
	jr	nz,@isfile
	ld	a,(hl)
	cp	'.'			; ".." is the only dot entry listed
	jr	z,br_parent
	call	br_fullpath
	ld	hl,tmp_path		; a path too long to keep is refused
	call	strlen
	ld	hl,PATH_LIM
	or	a
	sbc	hl,bc
	jr	c,br_toolong
	ld	hl,tmp_path
	ld	de,br_path
	call	strcpy
	jp	br_show
@isfile:
	push	af
	call	br_fullpath
	pop	af
	cp	2
	jr	z,@m3u
	ld	hl,tmp_path
	call	pl_add
	ld	hl,txt_full		; (no room: say so)
	jp	c,ui_msg
	ld	hl,(pl_count)
	dec	hl
	jp	play_index
@m3u:
	ld	hl,tmp_path
	call	pl_load_m3u
	jr	c,br_noload
	xor	a
	ld	(panel),a
	ld	(pan_line),a
	inc	a
	ld	(dirty_panbar),a
	ld	hl,(pl_count)
	ld	a,h
	or	l
	ret	z
	ld	hl,0
	jp	play_index

; br_noload: say that the playlist at tmp_path could not be loaded.
; br_toolong: say that the path at tmp_path is too long.
br_noload:
	ld	hl,txt_nolist
	jr	br_pathmsg
br_toolong:
	ld	hl,txt_toolong
br_pathmsg:
	ld	de,pb_buf
	call	strcpy
	push	de
	ld	hl,tmp_path
	ld	b,40
	call	vtail			; (corrupts DE)
	pop	de
	call	strcpy
	ld	hl,pb_buf
	jp	ui_err

; br_addsel: add the selected module to the playlist without playing
; it, and say on the bottom row what happened.
br_addsel:
	call	br_selected
	ret	c
	cp	1
	jr	z,@module
	ld	hl,txt_notmod
	jp	ui_msg
@module:
	push	hl
	call	br_fullpath
	ld	hl,tmp_path
	call	pl_add
	pop	hl
	jr	nc,@added
	ld	hl,txt_full
	jp	ui_msg
@added:
	push	hl
	call	br_seldown		; ready for the next one to be added
	ld	hl,txt_added
	ld	de,pb_buf
	call	strcpy
	ld	a,(pl_count)
	call	mdec3
	ld	a,':'
	ld	(de),a
	inc	de
	ld	a,' '
	ld	(de),a
	inc	de
	pop	hl
	ld	b,40			; as much of the name as fits
@name:
	ld	a,(hl)
	ld	(de),a
	or	a
	jr	z,@show
	inc	hl
	inc	de
	djnz	@name
	xor	a
	ld	(de),a
@show:
	ld	hl,pb_buf
	jp	ui_msg

; br_seldown: move the browser's selection down one, if it can go.
br_seldown:
	ld	ix,br_count
	ld	hl,(br_sel)
	inc	hl
	ld	de,(br_count)
	or	a
	sbc	hl,de
	ret	nc
	add	hl,de
	jp	lst_setsel

; file_read: read a whole file into memory.
; In: HL -> path, DE = where to put it, BC = most bytes to read.
; Out: carry set if it could not be opened, else HL = bytes read.
file_read:
	ld	(fw_data),de
	ld	(fw_len),bc
	ld	c,01h			; read access
	ld	a,mos_fopen
	rst.lil	08h
	or	a
	scf
	ret	z
	ld	(fw_handle),a
	ld	c,a
	ld	hl,(fw_data)
	ld	de,(fw_len)
	ld	a,mos_fread
	rst.lil	08h
	push	de			; bytes actually read
	ld	a,(fw_handle)
	ld	c,a
	ld	a,mos_fclose
	rst.lil	08h
	pop	hl
	or	a
	ret

; file_write: create a file, replacing any file of the same name, and
; write a block of memory to it. (mos_save cannot be used for this: in
; MOS 3.0.2 it refuses to write over a file that already exists.)
; In: HL -> path, DE = start of data, BC = length. Out: carry on failure.
file_write:
	ld	(fw_data),de
	ld	(fw_len),bc
	ld	c,0Ah			; write access, create or truncate
	ld	a,mos_fopen
	rst.lil	08h
	or	a
	scf
	ret	z			; could not open
	ld	(fw_handle),a
	ld	c,a
	ld	hl,(fw_data)
	ld	de,(fw_len)
	ld	a,mos_fwrite
	rst.lil	08h
	push	de			; bytes actually written
	ld	a,(fw_handle)
	ld	c,a
	ld	a,mos_fclose
	rst.lil	08h
	pop	hl
	ld	de,(fw_len)
	or	a
	sbc	hl,de
	ret	z
	scf
	ret

txt_added:	db	" Added to the playlist as entry ",0
txt_full:	db	" Not added: the playlist is full",0
txt_notmod:	db	" Only music files can be added to the playlist",0
txt_saved:	db	" Saved playlist: ",0
txt_notsaved:	db	" Could not save: ",0
txt_dotdot:	db	"..",0
txt_nolist:	db	" Cannot load playlist ",0
txt_toolong:	db	" Path too long: ",0
he_len:		ds	1	; has_ext: length of the extension
; The extensions of the music files the browser lists: each is its
; length and its text, and a 0 ends the list.
mod_exts:	db	4
ext_pt3:	db	".PT3"
		db	3
ext_ts:		db	".TS"
		db	4
ext_psg:	db	".PSG"
		db	4
ext_stc:	db	".STC"
		db	4
ext_pt2:	db	".PT2"
		db	4
ext_pt1:	db	".PT1"
		db	4
ext_asc:	db	".ASC"
		db	4
ext_stp:	db	".STP"
		db	4
ext_sqt:	db	".SQT"
		db	4
ext_psc:	db	".PSC"
		db	3
		db	".YM"
		db	4
		db	".VTX"
		db	3
		db	".AY"
		db	0
ext_m3u:	db	".M3U"
ext_m3u_lc:	db	".m3u",0

; List variables: count, selection, top line, in the order ui.asm needs.
pl_count:	ds	3
pl_sel:		ds	3
pl_top:		ds	3
br_count:	ds	3
br_sel:		ds	3
br_top:		ds	3
pl_cur:		ds	3	; entry being played, FFFFFFh if none
pl_resume:	ds	3	; where the playing entry was, if it was
				; removed (else FFFFFFh): see pl_none
mv_new:		ds	3	; pl_swap: entry to select afterwards
pd_text:	ds	3	; pl_del: the removed entry's text
pd_len:		ds	3	; pl_del: its length, terminator included
pl_bad:		ds	256	; per entry: non-zero if it would not play
pl_free:	ds	3	; next free byte of the playlist pool
br_free:	ds	3	; next free byte of the browser pool
srt_i:		ds	3	; sort: slot being placed
srt_p:		ds	3	; sort: slot being considered
srt_key:	ds	3	; sort: pointer being placed
srt_base:	ds	3	; sort: first slot of the table to sort
srt_end:	ds	3	; sort: end of the table
srt_gb:		ds	3	; sort: the gap, in bytes
sv_i:		ds	3	; save: entry number
sv_out:		ds	3	; save: output position
fw_data:	ds	3	; file_write: start of data
fw_len:		ds	3	; file_write: length
fw_handle:	ds	1	; file_write: MOS file handle
in_buf:		ds	48	; file name typed by the user
pl_name:	ds	41	; the playlist's file name, or empty
pl_name2:	ds	41	; (the name of one being loaded)
pl_path:	ds	PATH_LIM+48 ; full path of the file it came from
sv_path:	ds	PATH_SIZE ; pl_save: the directory it saves to
in_len:		ds	1
in_sel:		ds	1	; non-zero while the name offered is selected
br_path:	ds	PATH_SIZE ; directory the browser is showing
cfg_dir:	ds	PATH_SIZE ; settings: the browser's directory
m3u_dir:	ds	PATH_SIZE ; directory of the playlist file
cur_path:	ds	TMP_SIZE ; file being played
tmp_path:	ds	TMP_SIZE ; path being put together
dirobj:		ds	64	; FatFS directory object
filinfo:	ds	FI_SIZE	; FatFS file information
pl_ptr:		ds	[PL_MAX+1]*3
br_ptr:		ds	[BR_MAX+1]*3