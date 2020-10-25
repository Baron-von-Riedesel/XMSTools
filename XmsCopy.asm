
;--- copy from file|EMB to file|EMB

	.286
	.model small
	.dosseg
	.stack 4096
	option casemap:none
	.386

DGROUP group _TEXT

lf equ 10

CStr macro text:vararg
local sym
	.const
sym db text,0
	.code
	exitm <offset sym>
endm

	.386

XMSMOVE struct
dwSize	dd ?
wSrc	dw ?
dwOfsSrc dd ?
wDst	dw ?
dwOfsDst dd ?
XMSMOVE ends

	.data?

buffer	db 4000h dup (?)

	.code

	include printf.inc
	include timerms.inc

;*** out: EAX=number, DX -> behind number

gethex proc stdcall uses si pStr:ptr byte
	mov ch,00
	mov edx,0000
	mov si,pStr
gethex2:
	mov al,[si]
	cmp al,'0'
	jb gethex1
	cmp al,'9'
	jbe @F
	or al,20h
	cmp al,'a'
	jb gethex1
	cmp al,'f'
	ja gethex1
	sub al,27h
@@:
	sub al,30h
	movzx eax,al
	test edx,0F0000000h
	jnz toobig
	shl edx, 4
	add edx, eax
	jc toobig
	inc ch
	inc si
	jmp gethex2
gethex1:
	mov eax,edx
	mov dx,si
	clc
	ret
toobig:
	stc
	ret
gethex endp

main proc c argc:word,argv:ptr ptr 

local	xmsadr:dword
local	xmsm:XMSMOVE
local	dwTimeStart:dword
local	handle1:word
local	handle2:word
local	hFile1:word
local	hFile2:word
local	pszFile1:word
local	pszFile2:word
local	dwOfs1:dword
local	dwOfs2:dword
local	dwSiz1:dword
local	dwSiz2:dword
local	bAskOverwrite:byte
local	bTime:byte
local	breserved:byte

	mov dwOfs1,0
	mov dwOfs2,0
	mov dwSiz1,-1
	mov dwSiz2,-1
	mov hFile1, -1
	mov hFile2, -1
	mov handle1, 0
	mov handle2, 0
	mov bAskOverwrite,1
	mov bTime,0
	mov ax,4300h
	int 2Fh
	cmp al,80h
	jz @F
	invoke printf, CStr(<"no XMS host found",lf>)
	jmp exit
@@:
	push es
	mov ax,4310h
	int 2Fh
	mov word ptr xmsadr+0,bx
	mov word ptr xmsadr+2,es
	pop es
	mov ax,argc
	cmp ax,2
	jb error
	jz error1
	mov bx,argv
@@:
	add bx,2
	mov si,[bx]
	.if !si
		jmp error
	.endif
	mov ax,[si]
	.if ((al == '-') || (al == '/'))
		call getoption
		jc error
		jmp @B
	.endif

;--- get source parameters
	mov si, [bx]
	.if !si
		jmp error
	.endif
	mov pszFile1, si
	add bx, 2
	.if (byte ptr [si] == ':')
		inc si
		invoke gethex, si
		jc numtoobig
		cmp ch,0
		jz error3
		mov handle1,ax
		mov si,dx
	.else
		.while byte ptr [si] && byte ptr [si] != ','
			inc si
		.endw
	.endif
	.if byte ptr [si] == ','
		mov byte ptr [si],0
		inc si
		invoke gethex, si
		jc numtoobig
		.if (ch)
			mov dwOfs1, eax
		.endif
		mov si,dx
		.if byte ptr [si] == ','
			inc si
			invoke gethex, si
			jc numtoobig
			.if (ch)
				mov dwSiz1, eax
			.endif
			mov si,dx
		.endif
		cmp byte ptr [si],0
		jnz error
	.endif

;--- get destination parameters
	mov si, [bx]
	.if !si
		jmp error
	.endif
	mov pszFile2, si
	add bx, 2
	.if (byte ptr [si] == ':')
		inc si
		invoke gethex, si
		jc numtoobig
		cmp ch,0
		jz error3
		mov handle2,ax
		mov si,dx
	.else
		.while byte ptr [si] && byte ptr [si] != ','
			inc si
		.endw
	.endif
	.if byte ptr [si] == ','
		mov byte ptr [si],0
		inc si
		invoke gethex, si
		jc numtoobig
		.if (ch)
			mov dwOfs2, eax
		.endif
		mov si,dx
		cmp byte ptr [si],0
		jnz error
	.endif

	.if word ptr [bx]
		jmp error
	.endif

	mov dx,handle1
	.if dx 
		mov ah,8Eh				;get handle info (size in kB in edx)
		call xmsadr
		.if ax==0
			movzx bx,bl
			invoke printf, CStr(<"XMS get handle info failed for %X, error=%X",lf>), handle1, bx
			jmp exit
		.endif
		.if edx & 0FFC00000h
			invoke printf, CStr(<"warning: handle %X size exceeds 4 GB",lf>), handle1
			mov edx,0fffffffeh
		.else
			shl edx,10
		.endif
		mov eax, dwOfs1
		cmp edx, eax	;handle size < offset?
		jc sizerr1
		mov xmsm.dwOfsSrc, eax
		sub edx, eax	;max remaining size
		.if dwSiz1 == -1
			mov dwSiz1, edx
		.endif
		mov ax,handle1
		mov xmsm.wSrc, ax
	.else
		mov dx, pszFile1
		mov ax,3D00h
		int 21h
		jc openerr
		mov hFile1, ax
		.if (dwOfs1)
			mov dx,word ptr dwOfs1+0
			mov cx,word ptr dwOfs1+2
			mov bx,hFile1
			mov ax,4200h
			int 21h
		.endif
		mov xmsm.wSrc,0
		mov ax,ds
		shl eax,16
		mov ax,offset buffer
		mov xmsm.dwOfsSrc,eax
	.endif

	mov dx,handle2
	.if dx 
		mov ah,8Eh				;get handle info (size in EDX in kB)
		call xmsadr
		.if ax==0
			movzx bx,bl
			invoke printf, CStr(<"XMS get handle info failed for %X, error=%X",lf>), handle2, bx
			jmp exit
		.endif
		.if edx & 0FFC00000h
			invoke printf, CStr(<"warning: handle %X size exceeds 4 GB",lf>), handle2
			mov edx,0fffffffeh
		.else
			shl edx,10
		.endif
		mov eax, dwOfs2
		cmp edx, eax	;handle size < offset?
		jc sizerr2
		mov xmsm.dwOfsDst, eax
		sub edx, eax	;max remaining size
		mov dwSiz2, edx
		mov ax,handle2
		mov xmsm.wDst, ax
	.else
		mov dx, pszFile2
		mov ax,3D01h
		int 21h
		.if (CARRY?)
			mov dx, pszFile2
			mov cx,0
			mov ax,3C00h
			int 21h
			jc createrr
			mov hFile2, ax
		.else
			mov hFile2, ax
			.if (bAskOverwrite)
				invoke printf, CStr(<"file '%s' exists, overwrite? [y/n]">), dx
				.while (1)
					mov ah,8
					int 21h
					or al,20h
					.break .if ((al == 'n') || (al == 'y'))
				.endw
				push ax
				invoke printf, CStr(lf)
				pop ax
				.if (al == 'n')
					call closefiles
					jmp exit
				.endif
			.endif
		.endif
		.if (dwOfs2)
			mov dx,word ptr dwOfs2+0
			mov cx,word ptr dwOfs2+2
			mov bx,hFile2
			mov ax,4200h
			int 21h
		.endif
		mov xmsm.wDst,0
		mov ax,ds
		shl eax,16
		mov ax,offset buffer
		mov xmsm.dwOfsDst,eax
	.endif

	.if bTime
		call gettimer
		mov dwTimeStart,eax
	.endif

	xor edi, edi
	.while edi < dwSiz1 && edi < dwSiz2
		.if handle1 && handle2
			mov xmsm.dwSize,-1
		.else
			mov xmsm.dwSize, sizeof buffer
		.endif
		mov edx, dwSiz1
		sub edx, edi
		mov eax, dwSiz2
		sub eax, edi
		.if edx < xmsm.dwSize
			mov xmsm.dwSize, edx
		.endif
		.if eax < xmsm.dwSize
			mov xmsm.dwSize, eax
		.endif
		.if hFile1 != -1
			mov dx, offset buffer
			mov cx, word ptr xmsm.dwSize
			mov bx, hFile1
			mov ah, 3Fh
			int 21h
			jc readerr
			add ax,1		;make size even to avoid XMS block move error
			and al,0feh
			movzx eax, ax
			mov xmsm.dwSize, eax
		.endif
		.if handle1 || handle2
			mov ah,0Bh
			lea si, xmsm
			call xmsadr
			.if (ax!=1)
				movzx ax,bl
				invoke printf, CStr(<"XMS block move error [BL=%X]. EMMS.len=%lu EMMS.src=%X:%lX EMMS.dst=%X:%lX",lf>),
					ax, xmsm.dwSize, xmsm.wSrc, xmsm.dwOfsSrc, xmsm.wDst, xmsm.dwOfsDst
				.break
			.endif
			mov eax, xmsm.dwSize
			.if handle1
				add xmsm.dwOfsSrc, eax
			.endif
			.if handle2
				add xmsm.dwOfsDst, eax
			.endif
		.endif
		.if hFile2 != -1
			mov dx, offset buffer
			mov cx, word ptr xmsm.dwSize
			mov bx, hFile2
			mov ah, 40h
			int 21h
			jc writeerr
			.if (ax != cx)
				invoke printf, CStr(<"error on write: %u bytes written, should have been %u",lf>),ax,cx
				.break
			.endif
		.endif
		add edi, xmsm.dwSize
	.endw

	.if hFile2 != -1
		mov cx,0		;truncate the file
		mov bx,hFile2
		mov ah,40h
		int 21h
	.endif

	.if (bTime)
		call gettimer
		sub eax, dwTimeStart
		invoke printf, CStr(<"time for copy op: %lu ms",lf>), eax
	.endif

	call closefiles

	.if edi >= 10000h
		mov ax,di
		shr edi,10
		and ax,3ffh
		.if ZERO?
			invoke printf, CStr(<"%lu kB written",lf>), edi
		.else
			invoke printf, CStr(<"%lu kB and %u bytes written",lf>), edi, ax
		.endif
	.else
		invoke printf, CStr(<"%u bytes written",lf>), di
	.endif
	mov al,0
	jmp exit
createrr:
	invoke printf, CStr(<"file '%s' creation error [%X]",lf>), dx, ax
	jmp exiterr
openerr:
	invoke printf, CStr(<"file '%s' open error [%X]",lf>), dx, ax
	jmp exiterr
readerr:
	invoke printf, CStr(<"read error [%X]",lf>), ax
	call closefiles
	jmp exiterr
writeerr:
	invoke printf, CStr(<"write error [%X]",lf>), ax
	call closefiles
	jmp exiterr
sizerr1:
	invoke printf, CStr(<"offset or size too large for source",lf>)
	call closefiles
	jmp exiterr
sizerr2:
	invoke printf, CStr(<"offset or size too large for destination",lf>)
	call closefiles
	jmp exiterr
numtoobig:
	invoke printf, CStr(<"number magnitude exceeds 32 bits",lf>)
	jmp exiterr
error3:
	invoke printf, CStr(<"handle invalid, must be a hex number",lf>)
	jmp exiterr
error1:
	invoke printf, CStr(<"parameter missing",lf,lf>)
error:
	invoke printf, CStr(<"XMSCOPY v1.1 Public Domain (written by Japheth)",lf>)
	invoke printf, CStr(<"usage: XMSCOPY [options] src[,offset][,size] dst[,offset]",lf>)
	invoke printf, CStr(<"   options are:",lf>)
	invoke printf, CStr(<"   -n: no user confirmation if file will be overwritten",lf>)
	invoke printf, CStr(<"   -t: display time needed for copy operation",lf>)
	invoke printf, CStr(<" src & dst: if preceded by a ':' it's meant to be a XMS handle,",lf>)
	invoke printf, CStr(<"            else it's regarded as a filename.",lf>)
	invoke printf, CStr(<" XMS handles, offsets and size must be entered as hex values.",lf>)
exiterr:
	mov al,1
exit:
	ret

closefiles:
	mov bx,hFile1
	.if (bx != -1)
		mov ah,3Eh
		int 21h
	.endif
	mov bx,hFile2
	.if (bx != -1)
		mov ah,3Eh
		int 21h
	.endif
	retn
getoption:
	or ah,20h
	.if (ah == 'n')
		mov bAskOverwrite, 0
		retn
	.elseif (ah == 't')
		mov bTime, 1
		retn
	.endif
opterror:
	stc
	retn

main endp

	include setargv.inc

start:
	mov ax,@data
	mov ds,ax
	mov cx,ss
	sub cx,ax
	shl cx,4
	mov ss,ax
	add sp,cx
	sub sp,256
	mov _brk,sp
	call _setargv
	invoke main, __argc, __argv
_amsg_exit:
	mov ah,4ch
	int 21h

	END start
