
;--- setup __argc & __argv

DELIM MACRO target
    cmp al,13           ;; Test for end-of-line character
    je  target
    or  al,al           ;; Either CR or Null
    je  target
ENDM

    .data

__argc dw 0
__argv dw 0
_psp   dw 0
_brk   dw 0

    .code

malloc proc c wSize:word
    mov dx,wSize
    mov ax,_brk
    add _brk,dx
    ret
malloc endp

;--- ES=PSP, DS=DGROUP, SS=DGROUP

_setargv proc c uses di si

    mov [_psp],es
if 0
    call InitFilename       ; if filename is needed
else
    xor ax,ax
endif
    push ax                 ; save this address
    xor di,di               ; init argc
    xor dx,dx               ; init size of mem block
    mov si,81H
    mov ds,[_psp]
    assume ds:nothing
    jmp arg110
;--- DI holds argc
;--- DX holds block size (not including null terminators)
arg100:
    push bx
arg110:
@@:
    lodsb
    cmp al,' '
    je @B
    cmp al,9
    je @B
    DELIM arg400            ; exit if eol
    inc di                  ; another argument
    mov bx,0                ; init argument size
    dec si                  ; back up to reload character
    push si                 ; save start of argument
@@:
    lodsb
    cmp al,' '              ; end argument?
    je arg100
    cmp al,9
    je arg100               ; white space terminates argument
    DELIM arg399            ; exit if eol
    inc bx
    inc dx
    jmp @B
arg399:
    push bx                 ; last argument
arg400:
;--- address & size of arguments are pushed
    push ss
    pop ds                  ; DS = DGROUP
    assume  ds:DGROUP
    mov __argc,di           ; Store number of arguments
    add dx,di               ; add in terminator bytes
    inc di                  ; add one for NULL pointer
    inc di                  ; add one for filename
    shl di,1                ; each pointer needs 2 bytes
    add dx,di               ; add space for pointers to space for chars
    invoke malloc, dx
    and ax,ax
    jnz @F
    jmp _amsg_exit
@@:
    mov __argv,ax
    mov cx,__argc
    add di,ax               ; di -> behind vector table (strings)
    lea bx,[di-2]
    mov word ptr [bx],0000
    sub bx,2
    jcxz arg500
    push bp
    mov bp,sp
    add bp,2
    push ds
    pop es
    mov ds,[_psp]
    assume ds:nothing
@@:
    push cx
    mov cx,[bp+0]           ; size
    mov si,[bp+2]           ; address
    add bp,4
    mov ss:[bx],di
    sub bx,2
    rep movsb
    xor al,al
    stosb
    pop cx
    loop @B
    push ss
    pop ds
    assume ds:DGROUP
    pop bp
arg500:
    mov ax,__argc
    add ax,ax
    add ax,ax
    add sp,ax
    pop ax
    mov [bx],ax         ; store address filename as first item
    inc __argc
    ret
_setargv endp

