
	.286
	.model small
	.dosseg
	.stack 2048
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

	.code

	include printf.inc

ignws proc
	mov al,[bx]
	.while al == ' ' || al == 9
		inc bx
		mov al,[bx]
	.endw
	ret
ignws endp

whitesp proc
	cmp al,' '
	jz @F
	cmp al,9
	jz @F
	cmp al,0
@@:
	ret
whitesp endp

hextest proc
	cmp al,'0'
	jb nok
	cmp al,'9'
	jbe ok1
	or al,20h
	cmp al,'a'
	jb nok
	cmp al,'f'
	jbe ok2
nok:
	stc
	ret
ok1:
	sub al,'0'
	clc
	ret
ok2:
	sub al,'a'-10
	clc
	ret
hextest endp

;--- get hex word in AX

getwhex proc stdcall pStr:ptr byte

	push dx
	mov ch,00
	mov dx,0000
	mov bx,pStr
nextitem:
	mov al,[bx]
	call hextest
	jc gethex1
	inc ch
	mov ah,00
	push ax
	mov ax,dx
	add ax,ax
	add ax,ax
	add ax,ax
	add ax,ax
	pop dx
	add ax,dx
	mov dx,ax
	inc bx
	jmp nextitem
gethex1:
	cmp ch,1
	jc @F
	call whitesp
	jz @F
	stc
@@:
	mov ax,dx
	pop dx
	ret
getwhex endp

main proc c argv:ptr ptr

local xmscall:dword
local bSExt:byte

	mov bSExt,0
	mov ax,4300h
	int 2fh
	cmp al,80h
	jz @F
	invoke printf, CStr("no XMS host found",lf)
	jmp exit
@@:
	mov ax,4310h
	int 2fh
	mov word ptr xmscall+0,bx
	mov word ptr xmscall+2,es
	push ds
	pop es

	mov bx,argv
	call ignws
	cmp al,'-'
	jnz @F
	inc bx
	mov al,[bx]
	or al,20h
	cmp al,'x'
	jnz printusage
	mov bSExt,1
	inc bx
	call ignws
@@:
	invoke getwhex,bx
	jnc @F
printusage:
	invoke printf, CStr("usage: XMSLOCK [-x] handle (hexadecimal number)",lf)
	invoke printf, CStr("       -x: lock super-extended memory block (HimemSX)",lf)
	jmp exit
@@:
	mov dx, ax
	cmp bSExt,1
	jz sxlock
	mov ah, 0Ch
	call xmscall
	and ax,ax
	jnz @F
	movzx ax,bl
	invoke printf, CStr("XMS lock failed, error=%X",lf), ax
	jmp exit
@@:
	invoke printf, CStr("ok, physical address=%lX",lf), dx::bx
	jmp exit
sxlock:
	mov ah, 0CCh
	call xmscall
	and ax,ax
	jnz @F
	movzx ax,bl
	invoke printf, CStr("XMS super-lock failed, error=%X",lf), ax
	jmp exit
@@:
	invoke printf, CStr("ok, physical address=%lX%08lX",lf), edx, ebx
exit:
	ret
main endp

setargv proc
	pop bx
	mov si,81h
	mov ax,es
	mov ds,ax
	sub sp,128
	mov di,sp
	mov ax,ss
	mov es,ax
	mov cl,ds:[80h]
	mov ch,0
	rep movsb
	mov al,0
	stosb
	push ss
	pop ds
	push ds
	pop es
	jmp bx
setargv endp

start:
	mov ax,dgroup
	mov ds,ax
	mov cx,ss
	sub cx,ax
	shl cx,4
	mov ss,ax
	add sp,cx
	call setargv
	invoke main, sp
	mov ah,4ch
	int 21h

	END start
