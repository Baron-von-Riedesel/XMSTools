
;--- alloc XMS memory until a given amount is free.
;--- TSR program, works with XMM v3+ only.
;--- create binary with: jwasm -mz xmsres.asm

	.286
	.model tiny
	.dosseg
	.stack 2048
	.386

STARTHDLTAB equ 80h+4	; handle table offset (stored in PSP)

CStr macro text:vararg
local sym
	.const
sym db text, 0
	.code
	exitm <offset sym>
endm

OPT_L equ 1	; prefer lower addresses
OPT_U equ 2	; uninstall

	.data

xmscall dd ?
bOpt    db 0

hlptxt	db "XMSRes v1.0, japheth",13,10
		db "restricts free XMS memory.",13,10
		db "usage: XMSRes [/u][[/l] amount]",13,10
		db "  /u: uninstall",13,10
		db "  /l: prefer free low addresses",13,10
		db "  amount: XMS memory in MB that should remain free",13,10
		db '$'
uninstok db "XMSRes uninstalled",13,10,'$'
uninstfail db "No installed XMSRes found",13,10,'$'

	.data?

buffer dd 64 dup (?)	; room for max 64 handles

	.code

	include printf.inc

;*** test for valid decimal digit

isdigit proc near
	sub al, '0'
	jb @F
	cmp al, 9+1
	cmc
@@:
	ret
isdigit endp

;--- get a decimal number in EAX
;*** in: bx -> string

getdec proc stdcall pStr:ptr byte
	push edx
	xor edx, edx
	mov bx, pStr
nextchar:
	mov al,[bx]
	call isdigit
	jc done
	movzx eax,al
	shl edx, 1
	lea edx, [edx*4+edx]
	add edx, eax
	inc bx
	jmp nextchar
done:
	cmp byte ptr [bx], 1
	cmc
	mov eax,edx
	pop edx
	ret
getdec endp

;--- uninstall

uninst proc

	mov ax,5802h			;get umb link status
	int 21h
	xor ah,ah
	push ax
	mov ax,5803h			;link umbs
	mov bx,0001h
	int 21h
	mov ah,52h	; get list of lists
	int 21h
	mov es, es:[bx-2]
	xor bx, bx
	xor di, di
	.while byte ptr es:[bx] != 'Z'
		mov ax, es
		inc ax
		.if ax == es:[bx+1]	; PSP MCB?
			mov fs, ax
			.if dword ptr fs:[STARTHDLTAB-4] == "XMSR"	; an installed instance?
				inc di
				mov ax, cs
				sub ax, 10h
				mov es:[bx+1], ax	; assign this block to us
				mov si, STARTHDLTAB
nextitem:
				lodsw fs:[si]
				and ax, ax
				jz done
				mov dx, ax
				mov ah, 0Ah		; free xms handle
				call xmscall
				jmp nextitem
			.endif
		.endif
		mov ax,es:[bx+3]
		mov cx,es
		add ax,cx
		inc ax
		mov es,ax
	.endw
done:
	pop bx				;restore umb link status
	mov ax,5803h
	int 21h
	.if di
		mov dx, offset uninstok
	.else
		mov dx, offset uninstfail
	.endif
	mov ah, 9
	int 21h
	ret
uninst endp

;--- helper procs for sort

createsizetab proc
	mov ah, 8Eh		; get handle info
	call xmscall
	mov [di], edx
	ret
createsizetab endp

createaddrtab proc
	mov ah, 0Ch		; lock block, returns address in DX:BX
	call xmscall
	mov [di+0], bx
	mov [di+2], dx
	ret
createaddrtab endp

cmpl2h proc
	cmp eax, edx
	ret
cmpl2h endp

cmph2l proc
	cmp eax, edx
	cmc
	ret
cmph2l endp

;--- sort handle table
;--- creates a temp. table of either sizes or addresses
;--- es:si -> handle table
;--- bx -> proc to create helper items
;--- ax: compare proc

sorttable proc

local start:word
local pCmp:word
local pStore:word
local bSwapped:byte

	mov start, si
	mov pCmp, ax
	mov pStore, bx
	mov di, offset buffer
	push di
nextitem:
	lodsw es:[si]
	and ax, ax
	jz done
	mov dx, ax
	call pStore
	add di, 4
	jmp nextitem
done:
	mov cx, di
	pop si
	sub cx, si
	shr cx, 2
	mov bx, start

;--- simple bubblesort
;--- cx=items
;--- ds:si=start items
;--- es:bx=hdl tab

nextsort:
	mov bSwapped, 0
	pusha
nextcmp:
	cmp cx, 2
	jb done2
	mov eax, [si+0]
	mov edx, [si+4]
	call pCmp
	jb @F
	mov [si+0], edx
	mov [si+4], eax
	mov ax, es:[bx]
	xchg ax, es:[bx+2]
	mov es:[bx], ax
	or bSwapped, 1
@@:
	add si, 4
	add bx, 2
	dec cx
	jmp nextcmp
done2:
	popa
	cmp bSwapped, 0
	jnz nextsort
	ret
sorttable endp

;--- unlock block if option -l was given

condUnlock proc
	mov ax, 1
	cmp bOpt, OPT_L
	jnz @F
	mov ah, 0Dh	; unlock
	call xmscall
@@:
	ret
condUnlock endp

;--- sort handle tab, either for (descending) sizes or (ascending) addresses;
;--- then free the amount of space given in cmdline

freeblocks proc stdcall dwHdl:dword, dwFree:dword
	les si, dwHdl
	mov bx, offset createaddrtab
	mov ax, offset cmpl2h
	cmp bOpt, OPT_L
	jz @F
	mov bx, offset createsizetab
	mov ax, offset cmph2l
@@:
	call sorttable
	mov edi, dwFree
	les si, dwHdl
nextbl:
	lodsw es:[si]
	mov dx, ax
	mov ah, 8Eh		; get handle info
	call xmscall
	cmp edx, edi	; block > free req?
	jae lastbl
	sub edi, edx	; adjust edi - blocks will be released later, after last block has been adjusted
	jmp nextbl

;--- last block needs special treatment
;--- and must be handled first:
;--- 1. block is resized ( size decreasing )
;--- 2. the released rest is allocated
;--- 3. the resized block is released

lastbl:
	sub si, 2
	mov dx, es:[si]
	call condUnlock
	cmp ax, 1
	jnz @F
	mov ebx, edi
	mov ah, 8fh		; resize EMB, new size in EBX
	call xmscall
	cmp ax, 1
	jnz @F
	mov ah, 88h		; get max free
	call xmscall
	mov edx, eax	; alloc largest block - will hopefully get the just released portion
	mov ah, 89h		; alloc EMB
	call xmscall
	cmp ax, 1
	jnz @F
	mov ax, dx
	xchg ax, es:[si]
	mov dx, ax
	mov ah, 0Ah		; free EMB
	call xmscall
@@:

;--- free all blocks that are located before the current one
	mov di, si
	.while di > STARTHDLTAB
		sub di, 2
		mov dx, es:[di]
		call condUnlock
		mov ah, 0Ah	; free block
		call xmscall
	.endw

;--- remove the released handles from the table

	.while 1
		lodsw es:[si]
		stosw
		.break .if !ax
		mov dx, ax
		call condUnlock
	.endw
	ret
freeblocks endp

;--- error occured; free all blocks in handle table
;--- DI=offset end of table

reset proc
	mov si, STARTHDLTAB
	.while si < di
		lodsw es:[si]
		mov dx, ax
		mov ah, 0Ah
		call xmscall
	.endw
	ret
reset endp

;--- allocate all free blocks
;--- store handles in handle tab in PSP
;--- in: esi=amount of requested free mem
;--- return: C if total free size is < esi

getallblocks proc stdcall dwDst:dword

local dwFree:dword

	mov dwFree, 0
	les di, dwDst
nextitem:
	mov ah, 88h		; get largest/total free in eax/edx
	call xmscall
	cmp bl, 0A0h	; all XMS allocated?
	jz done
	cmp bl, 0
	jnz failed88
	add dwFree, eax
	mov edx, eax	; get largest block
	mov ah, 89h		; alloc XMS memory
	call xmscall
	cmp ax, 1
	jnz failed89
	mov ax, dx
	stosw
	jmp nextitem
done:
	cmp dwFree, esi	; dwFree >= esi?
	jc failed
	jz justright
	ret
failed:
	invoke printf, CStr("XMSRes: currently just %lu kB free, not installed",10), dwFree
	call reset
	stc
	ret
justright:
	invoke printf, CStr("XMSRes: currently %lu kB free, not installed",10), dwFree
	call reset
	stc
	ret
failed88:
	invoke printf, CStr("XMSRes: XMS call ah=88 failed",10)
	call reset
	stc
	ret
failed89:
	invoke printf, CStr("XMSRes: XMS call ah=89, edx=%lX failed",10), edx
	call reset
	stc
	ret
getallblocks endp

main proc c argc:word, argv:ptr ptr

	cmp argc, 2
	jb disphelp
	mov si, argv
nextarg:
	add si, 2
	mov bx, [si]
	and bx, bx
	jz disphelp
	cmp byte ptr [bx],'-'
	jz @F
	cmp byte ptr [bx],'/'
	jnz isamount
@@:
	mov ax,[bx+1]
	or al,20h
	cmp ax, 'u'
	jz isoptu
	cmp ax, 'l'
	jz isoptl
	jmp disphelp
isoptu:
	mov bOpt, OPT_U
	cmp word ptr [si+2], 0
	jnz disphelp
	jmp doneargs
isoptl:
	mov bOpt, OPT_L
	jmp nextarg
isamount:
	invoke getdec, bx	; get amount
	jc disphelp
	mov esi, eax	; memory to remain free ( in MB )
	shl esi, 10		; convert to kB

doneargs:
	mov ax, 4300h
	int 2fh
	cmp al, 80h
	jnz nohost
	mov ax, 4310h
	int 2fh
	mov word ptr xmscall+0,bx
	mov word ptr xmscall+2,es
	mov ah, 00
	call xmscall
	cmp ah, 3
	jb nohost3

	cmp bOpt, OPT_U	; -u option?
	jnz @F
	call uninst
	jmp exit
@@:
	mov ah, 51h
	int 21h
	mov es, bx
	mov di, STARTHDLTAB-4
	mov eax, "XMSR"
	stosd
	invoke getallblocks, es::di
	jc exit
	cmp di, STARTHDLTAB		; anything allocated at all?
	jz noalloc
	xor ax, ax		; mark end of handle list
	stosw

	mov ax, STARTHDLTAB
	invoke freeblocks, es::ax, esi	; free blocks 

	mov es, es:[2Ch]
	mov ah, 49h
	int 21h
	mov cx, 5
	xor bx, bx
@@:
	mov ah, 3Eh
	int 21h
	inc bx
	loop @B
	mov dx, 10h
	mov ax, 3100h
	int 21h

nohost:
	invoke printf, CStr("XMSRes: No XMS host found",10)
	jmp exit
nohost3:
	invoke printf, CStr("XMSRes: XMM isn't version 3 or better",10)
	jmp exit
noalloc:
	invoke printf, CStr("XMSRes: nothing allocated, not installed",10)
	jmp exit
disphelp:
	mov dx, offset hlptxt
	mov ah, 9
	int 21h
exit:
	ret
main endp

	include setargv.new

start:
	mov ax,dgroup
	mov ds,ax
	mov cx,ss
	sub cx,ax
	shl cx,4
	mov ss,ax
	add sp,cx
	call _setargv
	invoke main, [_argc], [_argv]
	mov ah,4ch
	int 21h

	END start
