
;--- copy from file|EMB to file|EMB
;--- files cannot exceed 2 GB
;--- max size of EMB is 4 GB

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
hSrc	dw ?
dwOfsSrc dd ?
hDst	dw ?
dwOfsDst dd ?
XMSMOVE ends

_BSS segment para public 'BSS'	;make sure bss is para aligned
_BSS ends

	.data?

buffer	db 8000h dup (?)

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
local	hFile1:word
local	hFile2:word
local	pszFile1:word
local	pszFile2:word
local	dwOfs1:dword
local	dwOfs2:dword
local	dwSizSrc:dword
local	bAskOverwrite:byte
local	bTime:byte
local	bVerbose:byte
local	bDisable:byte

	mov xmsm.hSrc, 0
	mov xmsm.hDst, 0
	mov hFile1, -1
	mov hFile2, -1
	mov dwOfs1,0
	mov dwOfs2,0
	mov dwSizSrc,-1
	mov bAskOverwrite,1
	mov bTime,0
	mov bVerbose,0
	mov bDisable,0

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
		mov xmsm.hSrc,ax
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
				mov dwSizSrc, eax
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
		mov xmsm.hDst,ax
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

	mov dx,xmsm.hSrc
	.if dx 
		mov ah,8Eh				;get handle info (size in kB in edx)
		call xmsadr
		.if ax==0
			movzx bx,bl
			invoke printf, CStr(<"XMS get handle info failed for %X, error=%X",lf>), xmsm.hSrc, bx
			jmp exit
		.endif
		mov eax, dwOfs1
		mov xmsm.dwOfsSrc, eax
		.if edx & 0FFC00000h
			invoke printf, CStr(<"warning: src handle %X size >= 4 GB",lf>), xmsm.hSrc
			mov eax, dwOfs1
			mov edx, 0
			sub edx,eax
			.if !edx
				mov edx,-2
			.endif
		.else
			shl edx,10
			cmp edx, eax	;handle size < offset?
			jc sizerr1
			sub edx, eax	;max remaining size
		.endif
		.if dwSizSrc == -1
			mov dwSizSrc, edx
		.endif
	.else
;------------------------ open source

		mov si, pszFile1
		mov cx,0			;normal file
		mov di,0
		mov dl,1h			;fail if file not exists
		mov dh,0
		mov bx,0			;read
		mov ax,716Ch		;open
		int 21h
		jnc @F
		cmp ax,7100h
		jnz openerr
		mov ax,6C00h
		int 21h
		jc openerr
@@:
		mov hFile1, ax
		.if (dwOfs1)
			mov dx,word ptr dwOfs1+0
			mov cx,word ptr dwOfs1+2
			mov bx,hFile1
			mov ax,4200h
			int 21h
		.endif
		mov ax,ds
		shl eax,16
		mov ax,offset buffer
		mov xmsm.dwOfsSrc,eax
	.endif

	mov dx,xmsm.hDst
	.if dx 
		mov eax, dwOfs2
		mov xmsm.dwOfsDst, eax
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
	.while edi < dwSizSrc
		.if xmsm.hSrc && xmsm.hDst
			mov xmsm.dwSize,-1
		.else
			mov xmsm.dwSize, sizeof buffer
		.endif
		mov edx, dwSizSrc
		sub edx, edi
		.if edx < xmsm.dwSize
			mov xmsm.dwSize, edx
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
		.if xmsm.hSrc || xmsm.hDst
			pushf
			.if bDisable
				cli
			.endif
			mov ah,0Bh
			lea si, xmsm
			call xmsadr
			popf
			.if (ax!=1)
				call dispcopytime
				movzx ax,bl
				invoke printf, CStr(<"XMS block move error [BL=%X]. EMMS.len=%lu EMMS.src=%X:%lX EMMS.dst=%X:%lX",lf>),
					ax, xmsm.dwSize, xmsm.hSrc, xmsm.dwOfsSrc, xmsm.hDst, xmsm.dwOfsDst
				.break
			.elseif bVerbose
				invoke printf, CStr(<"XMS block move ok, EMMS.len=%lu EMMS.src=%X:%lX EMMS.dst=%X:%lX",lf>),
					xmsm.dwSize, xmsm.hSrc, xmsm.dwOfsSrc, xmsm.hDst, xmsm.dwOfsDst
			.endif
			mov eax, xmsm.dwSize
			.if xmsm.hSrc
				add xmsm.dwOfsSrc, eax
			.endif
			.if xmsm.hDst
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
		.break .if !xmsm.dwSize
	.endw

	.if hFile2 != -1
		mov cx,0		;truncate the file
		mov bx,hFile2
		mov ah,40h
		int 21h
	.endif

	call dispcopytime

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
dispcopytime:
	.if (bTime)
		call gettimer
		sub eax, dwTimeStart
		invoke printf, CStr(<"time for copy op: %lu ms",lf>), eax
		mov bTime,0
	.endif
	retn
createrr:
	invoke printf, CStr(<"file '%s' creation error [%X]",lf>), dx, ax
	jmp exiterr
openerr:
	invoke printf, CStr(<"file '%s' open error [%X]",lf>), si, ax
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
	invoke printf, CStr(<"   -d: disable interrupts during copy operation",lf>)
	invoke printf, CStr(<"   -n: no user confirmation if file will be overwritten",lf>)
	invoke printf, CStr(<"   -t: display time needed for copy operation",lf>)
	invoke printf, CStr(<"   -v: display each block move call",lf>)
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
	.elseif (ah == 'v')
		mov bVerbose, 1
		retn
	.elseif (ah == 'd')
		mov bDisable, 1
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
