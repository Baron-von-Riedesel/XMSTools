
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

;*** test for valid decimal digit

dectest proc near
	cmp al,'0'
	jc dectst1
	cmp al,'9' + 1
	jnc dectst1
	sub al,'0'
	and al,al
	ret
dectst1:
	stc
	ret
dectest endp

;*** test for valid hex digit

hextest proc near
	cmp al,'0'
	jc hextst1
	cmp al,'9'
	jbe @F
	or al,20h
	cmp al,'a'
	jb hextst1
	cmp al,'f'
	ja hextst1
	sub al,'a'-10
	ret
@@:
	sub al,'0'
	ret
hextst1:
	stc
	ret
hextest endp

;--- in: bx->string
;--- out: number in EAX
;--- out: bx->behind number
;--- digits in CH

getdec proc
	push edx
	mov ch,0
	mov edx,0
nextdigit:
	mov al,[bx]
	call dectest
	jc done
	inc ch
	movzx eax,al
	shl edx, 1
	lea edx, [edx*4+edx]
	add edx, eax
	inc bx
	jmp nextdigit
done:
	cmp ch,1
	mov eax,edx
	pop edx
	ret
getdec endp

;--- in: bx->string
;--- out: number in EAX
;--- out: bx->behind number
;--- digits in CH

gethex proc
	push edx
	mov ch,0
	mov edx,0
nextdigit:
	mov al,[bx]
	call hextest
	jc done
	inc ch
	movzx eax,al
	test edx,0f0000000h
	jnz error
	shl edx, 4
	add edx, eax
	inc bx
	jmp nextdigit
error:
	mov ch,0
done:
	cmp ch,1
	mov eax,edx
	pop edx
	ret
gethex endp

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
	mov ax,[bx]
	or ah,20h
	cmp ax,"x0"
	jnz @F
	add bx,2
	call gethex
	jc error
	jmp cont
@@:
	call getdec
	jc error
cont:
	mov cl,[bx]
	or cl,20h
	cmp cl,'g'
	jz useg
	cmp cl,'m'
	jz usem
	jmp @F
useg:
	shl eax,10
usem:
	shl eax,10
@@:
	mov bl,-1
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
	movzx ax,bl
	jz @F
	invoke printf, CStr("alloc failed, bl=%X, dx=%X",lf),ax,dx
	jmp mainex
@@:
	invoke printf, CStr("handle %X, bl=%X",lf),dx,ax
mainex:
	ret
error:
	invoke printf, CStr("usage: XMSALLOC [-x] size",lf)
	invoke printf, CStr("       <size> may be a decimal or, if preceded by '0x', hexadecimal number.",lf)
	invoke printf, CStr("       Without suffix, <size> will be interpreted as KB to be allocated.",lf)
	invoke printf, CStr("       It may be succeeded by a 'M' or 'G' to alloc MBs or GBs instead.",lf)
	invoke printf, CStr("       -x: use super-extended allocation (XMS v3.5)",lf)
	jmp mainex

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
