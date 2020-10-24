
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
nextchar:
	mov al,[bx]
	cmp al,0
	jz done
	cmp al,9
	jz @F
	cmp al,' '
	jnz done
@@:
	inc bx
	jmp nextchar
done:
	ret
ignws endp

;*** test for valid decimal number

deztest proc near
	cmp al,'0'
	jc deztst1
	cmp al,'9' + 1
	jnc deztst1
	sub al,'0'
	and al,al
	ret
deztst1:stc
	ret
deztest endp

;*** out: number in EAX
;--- digits in CH

getdez proc stdcall pStr:ptr byte
	push edx
	mov ch,0
	mov edx,0
	mov bx,pStr
getdez2:mov al,[bx]
	call deztest
	jc getdez1
	inc ch
	movzx eax,al
	shl edx, 1
	lea edx, [edx*4+edx]
	add edx, eax
	inc bx
	jmp getdez2
getdez1:
	and ch,ch
	jz @F
	cmp al,0
	jz sm1
	cmp al,9
	jz sm1
	cmp al,' '
	jz sm1
@@:
	stc
sm1:
	mov eax,edx
	pop edx
	ret
getdez endp

main proc c argv:ptr ptr

local	handle:word
local	xmsadr:dword
local	bSext:byte

	mov ax,4300h
	int 2fh
	cmp al,80h
	jz @F
	invoke printf, CStr("no XMS host found",lf)
	jmp mainex
@@:
	mov bSext,0
	mov ax,4310h
	int 2fh
	mov word ptr xmsadr+0,bx
	mov word ptr xmsadr+2,es
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
	jnz error
	mov bSext,1
	inc bx
	call ignws
@@:
	invoke getdez,bx
	jnc @F
error:
	invoke printf, CStr("usage: XMSALLOC [-x] size (kB to alloc)",lf)
	invoke printf, CStr("       -x: use super-extended allocation (HimemSX)",lf)
	jmp mainex
@@:
	mov edx,eax
	mov ah,0C9h
	cmp bSext,1
	jz @F
	mov ah,09h
	test edx,0FFFF0000h
	jz @F
	mov ah,89h				;use xms 3.0
@@:
	call xmsadr
	cmp ax,1
	jz @F
	movzx ax,bl
	invoke printf, CStr("alloc failed, bl=%X",lf),ax
	jmp mainex
@@:
	invoke printf, CStr("handle %X",lf),dx
mainex:
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
	mov ax,@data
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
