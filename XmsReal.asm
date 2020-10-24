
	.286
	.model small
	.dosseg
	.stack 4096
	.386

lf	equ 10

CStr macro text:vararg
local sym
	.const
sym db text,0
	.code
	exitm <offset sym>
endm

	.code

	include printf.inc

;--- this returns timer value in ms

_GetTimerValue proc uses es bx

	push 0040h
	pop es
	cli
	mov bx, ax
tryagain:
	mov edx,es:[06ch] 
	mov al,0C2h		;read timer 0 status + value low/high
	out 43h, al
	xchg edx, edx
	in al,40h
	mov cl,al		;CL = status
	xchg edx, edx
	in al,40h
	mov ah, al		;AH = value low
	xchg edx, edx
	in al,40h		;AL = value high

	test cl,40h		;was latch valid?
	jnz tryagain
	cmp edx,es:[06ch]	;did an interrupt occur in the meantime?
	jnz tryagain		;then do it again!

	sti

	xchg al,ah
;--- usually (counter mode 3) the timer is set to count down *twice*! 
;--- however, sometimes counter mode 2 is set!
	mov ch,cl
	and ch,0110B	;bit 1+2 relevant
	cmp ch,0110B	;counter mode 3?
	jnz @F
;--- in mode 3, PIN status of OUT0 will become bit 15
	shr ax,1
	and cl,80h
	or ah, cl
@@:
;--- now the counter is in AX (counts from FFFF to 0000)
	neg ax
;--- now the count is from 0 to FFFF
	ret
_GetTimerValue endp

;--- get timer value in ms in eax

gettimer proc
	call _GetTimerValue

;--- the timer ticks are in EDX:AX, timer counts down 
;--- a 16bit value with 1,193,180 Hz -> 1193180/65536 = 18.20648 Hz
;--- which are 54.83 ms
;--- to convert in ms:
;--- 1. subticks in ms: AX / 1193
;--- 2. ticks in ms: EDX * 55
;--- 3. total 1+2

	push edx
	movzx eax,ax	;step 1
	cdq
	mov ecx, 1193
	div ecx
	mov ecx, eax
	pop eax 		;step 2
	mov edx, 55
	mul edx
	add eax, ecx	;step 3
	ret
gettimer endp

;*** test for valid decimal number

deztest proc near
	cmp al,'0'
	jc deztst1
	cmp al,'9' + 1
	jnc deztst1
	sub al,'0'
	and al,al
	ret
deztst1:
	stc
	ret
deztest endp

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
	and ch,ch
	jz @F
	call whitesp
	jz sm1
@@:
	stc
sm1:
	mov eax,edx
	pop edx
	ret
getdez endp

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

local handle:word
local xmsadr:dword
local starttime:dword

	mov ax,4300h
	int 2fh
	cmp al,80h
	jz @F
	invoke printf, CStr("no XMS host found",lf)
	jmp exit
@@:
	mov ax,4310h
	int 2fh
	mov word ptr xmsadr+0,bx
	mov word ptr xmsadr+2,es
	push ds
	pop es
	mov bx,argv
	call ignws
	invoke getwhex,bx
	jc error
	mov handle,ax
	call ignws
	invoke getdez,bx
	jc error
	mov ebx, eax

	invoke gettimer
	mov starttime, eax

	mov dx,handle
	mov ah,0Fh
	test ebx,0FFFF0000h
	jz @F
	mov ah,8Fh				;use xms 3.0
@@:
	call xmsadr
	cmp ax,1
	jz @F
	movzx ax,bl
	invoke printf, CStr(<"XMS realloc failed, error=%X",lf>),ax
	jmp exit
@@:
	call gettimer
	sub eax,starttime
	invoke printf, CStr(<"ok, ebx=0x%lX (%lu), time=%lu ms",lf>), ebx, ebx, eax
	jmp exit
error:
	invoke printf, CStr(<"usage: XMSREAL handle (hex number) size (decimal number)",lf>)
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
