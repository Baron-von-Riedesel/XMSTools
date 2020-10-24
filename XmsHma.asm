
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

;*** test for valid decimal number

deztest proc near
	cmp 	al,'0'
	jc		deztst1
	cmp 	al,'9' + 1
	jnc 	deztst1
	sub 	al,'0'
	and 	al,al
	ret
deztst1:
	stc
	ret
deztest endp

;*** out: zahl in EAX
;--- ziffern in CH

getdez proc stdcall pStr:ptr byte
	push edx
	mov ch,00
	mov edx,0000
	mov bx,pStr
getdez2:
	mov al,[bx]
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
	cmp ch,1
	jc @F
	call whitesp
	jz @F
	stc
@@:
	mov eax,edx
	pop edx
	ret
getdez endp

main proc c argv:ptr ptr

local	handle:word
local	xmscall:dword

	mov ax,4300h
	int 2fh
	cmp al,80h
	jz @F
	invoke printf, CStr("no XMS host found",lf)
	jmp mainex
@@:
	mov ax,4310h
	int 2fh
	mov word ptr xmscall+0,bx
	mov word ptr xmscall+2,es
	push ds
	pop es

	mov bx,argv
	call ignws
	invoke getdez, bx
	jnc @F
	invoke printf, CStr("usage: XMSHMA 1|0 (1=request HMA, 0=release HMA)",lf)
	jmp mainex
@@:
	push ax
	mov ah,0	;get version
	call xmscall
	movzx cx,ah
	movzx ax,al
	invoke printf, CStr("XMS version %X.%X, HMA available=%u",lf),cx,ax,dx
	pop ax

	mov bx,-1
	mov dx,-1
	mov cx,ax
	mov ah,1	;ah=1 request HMA
	cmp cx,0
	jnz @F
	mov ah,2	;ah=2 release HMA
@@:
	call xmscall
	cmp ax,1
	jz @F
	movzx bx,bl
	invoke printf, CStr("failed, bl=%X",lf), bx
	jmp mainex
@@:
	movzx bx,bl
	invoke printf, CStr("ok, bl=%X",lf), bx
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
