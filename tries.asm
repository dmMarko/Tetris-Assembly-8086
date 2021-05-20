IDEAL
MODEL small
STACK 100h
p186
jumps
DATASEG
modulus dw 6075
multiplier dw 106
increment dw 1283
seed dw ?

top_limit dw 7

rand_num db ?



CODESEG


proc initializeRandom
	; This proc doesn't get any value
	; This proc will set the modulus, multplier, increment and seed

	; al = modulus
	; ah = multiplier 		
	; bl = increment
	; bh = seed

	pusha

	mov ah, 0h
	int 1ah
	mov ax, dx
	mov ah, 0h

	; getting the seed
	mov dh, 0h
	mov cx, ax
	mov ax, [modulus]
	mov cx, dx
	mov dx, 0h
	div cx

	mov dx, 0h
	mov cx, 2
	mul cx


	mov [seed], ax

	popa
	ret
endp initializeRandom


proc randomNum
    pusha
	; This proc generates random number between 0 and the number in the register cx
	; The cx number must be under 99!
	; cx = top boundry of the random number
	; 
	; result: 
	; 	dl = the random number
	mov cx, [top_limit]

	inc cx

	mov ax, [seed]
	mov cx, [multiplier]
	mul cx

	add ax, [increment]

	mov cx, [modulus]
	mov dx, 0
	div cx

	mov [seed], dx
	mov ax, dx
    mov dx, 0
    mov cx, [top_limit]
    div cx

	mov [rand_num], dl

    popa
	ret
endp randomNum

start:
    mov ax, @data
    mov ds, ax

    call initializeRandom
    
    mov cx, 10
    loop1:
        push cx
        mov [top_limit], cx
            
        mov cx, 79
        loop2:

            call randomnum

            mov dl, [rand_num]
            add dl, '0'
            
            mov ah, 02h
            int 21h

        loop loop2

        mov dl, ' '
        
        mov ah, 02h
        int 21h

        pop cx
        loop loop1


    exit:       
    mov ax, 4c00h
    int 21h
END start