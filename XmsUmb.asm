
	.286
	.model small
	.stack 4096
	.dosseg
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

main proc c

local xmscall:dword
local _size:word
local segadr:word

	mov ax,4300h
	int 2fh
	test al,80h			;xmm installed?
	jnz @F
	invoke printf, CStr('no XMM host found',lf)
	jmp mainex
@@:
	mov ax,4310h		;get entry address
	int 2fh
	mov word ptr [xmscall+0],bx
	mov word ptr [xmscall+2],es

	mov _size,0ffffh
nexttry:
	invoke printf, CStr("calling XMS with ah=10h (request UMB), dx=%X",10), _size
	mov dx,_size
	mov ah,10h				;request UMB (upper memory block)
	call [xmscall]
	cmp ax,0
	jnz done
	push bx
	push dx
	movzx bx,bl
	invoke printf, CStr("call failed, BL=%X, DX=%X",lf), bx, dx
	pop dx
	pop bx
	cmp bl,0B0h				;B0h=a smaller UMB is available
	jnz mainex
	cmp _size,-1
	jnz mainex
	mov _size,dx
	jmp nexttry
done:
	mov segadr, bx
	invoke printf, CStr("call succeeded, bx=%X, dx=%X",lf), bx, dx
	invoke printf, CStr("calling XMS with ah=11h (release UMB), dx=%X",lf), segadr
	mov dx,segadr
	mov ah,11h				;release the UMB
	call [xmscall]
	cmp ax,0
	jnz mainex
	movzx bx,bl
	invoke printf, CStr("call failed, BL=%X",lf), bx
mainex:
	ret
main endp

start:
	mov ax,@data
	mov ds,ax
	mov cx,ss
	sub cx,ax
	shl cx,4
	mov ss,ax
	add sp,cx
	invoke main
	mov ah,4ch
	int 21h

	END start
