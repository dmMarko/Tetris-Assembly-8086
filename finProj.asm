IDEAL
MODEL small
STACK 100h
p186
jumps

DATASEG
; ---------------------------------
;            variables
; ---------------------------------

; --------- image handler ---------
filename dw ?
filename1 db 'pic2019.bmp',0
filename2 db 'pic2020.bmp',0
filename3 db 'pic2021.bmp',0

filehandle dw ?
Header db 54 dup (0)
Palette db 256*4 dup (0)
ScrLine db 320 dup (0)
ErrorMsg db 'Error', 13, 10,'$'

; -------- game variables ---------

x_coordinate dw 100
y_coordinate dw 100
colour dw 4 ; colour from code
pixelColour db 0 ; colour from screen

pressedKey db 0

square_size dw 8
main_colour dw 0ch ; block colour - unique for each piece
border_colour dw 4 ; block border colour - unique for each piece
light_colour dw 0Fh ; light colour - unique for each piece

current_piece dw 6 ; 0 = t-piece, 1 = o-piece, 2 = j-piece, 3 = l-piece, 4 = i-piece, 5 = s-piece, 6 = z-piece
current_piece_rotation dw 1 ; rotation of the piece, the number of the postion
move_down_speed dw 9000h ; speed of moving down, mostly the same, but shorter when sped up

move_down_failed db 0 ; boolean, whether moving down failed, 0 = not failed, 1 = failed
up_key_pressed db 0 ; boolean, whether up key was pressed, 0 = not, 1 = yes

line dw 0 ; the number of the line

game_over db 0 ; boolean, 0 = no game over, 1 = game is over

held_piece dw 100 ; the held piece big
held_this_turn db 0 ; boolean, 0 = didn't hold a piece this turn, 1 = held already this turn

queue dw 14 dup (?)

min_queue_last_7 db 14 ; when calculating the las 7 spots in the queue, when the first spot is taken, 
					   ; the first is now moved to the second spot
					   ; in order to not try again to use the first one

queue_iteration db 0

character db '2'
char_colour db 2

score db 10 dup(0), "$"
lines_cleared_this_turn db 0

level db 2 dup(0), "$"
level_num db 0
lines_cleared dw 0
lines_cleared_printable db 3 dup(0), "$"
default_speed dw 750h

; -------- rand variables ---------
modulus dw 6075
multiplier dw 106
increment dw 1283
seed dw ? ; the seed, the random number

top_limit dw 7 ; the limit of the random number
rand_num db ?

CODESEG
; ________BMP reader________
proc OpenFile
    ; Open file
    mov ah, 3Dh
    xor al, al
    mov dx, [filename]
    int 21h
    jc openerror
    mov [filehandle], ax

    ret
    openerror:
    mov dx, offset ErrorMsg
    mov ah, 9h
    int 21h
    ret
endp OpenFile

proc ReadHeader
    ; Read BMP file header, 54 bytes
    mov ah,3fh
    mov bx, [filehandle]
    mov cx,54
    mov dx,offset Header
    int 21h
    ret
endp ReadHeader

proc ReadPalette
    ; Read BMP file color palette, 256 colors * 4 bytes (400h)
    mov ah,3fh
    mov cx,400h
    mov dx,offset Palette
    int 21h
    ret
endp ReadPalette

proc CopyPal
    ; Copy the colors palette to the video memory
    ; The number of the first color should be sent to port 3C8h
    ; The palette is sent to port 3C9h
    mov si,offset Palette
    mov cx,256
    mov dx,3C8h
    mov al,0
    ; Copy starting color to port 3C8h
    out dx,al
    ; Copy palette itself to port 3C9h
    inc dx
    PalLoop:
    ; Note: Colors in a BMP file are saved as BGR values rather than RGB.
    mov al,[si+2] ; Get red value.
    shr al,2 ; Max. is 255, but video palette maximal
    ; value is 63. Therefore dividing by 4.
    out dx,al ; Send it.
    mov al,[si+1] ; Get green value.
    shr al,2
    out dx,al ; Send it.
    mov al,[si] ; Get blue value.
    shr al,2
    out dx,al ; Send it.
    add si,4 ; Point to next color.
    ; (There is a null chr. after every color.)

    loop PalLoop
    ret
endp CopyPal

proc CopyBitmap
    ; BMP graphics are saved upside-down.
    ; Read the graphic line by line (200 lines in VGA format),
    ; displaying the lines from bottom to top.
    mov ax, 0A000h
    mov es, ax
    mov cx,200
    PrintBMPLoop:
    push cx
    ; di = cx*320, point to the correct screen line
    mov di,cx
    shl cx,6
    shl di,8
    add di,cx
    ; Read one line
    mov ah,3fh
    mov cx,320
    mov dx,offset ScrLine
    int 21h
    ; Copy one line into video memory
    cld ; Clear direction flag, for movsb
    mov cx,320
    mov si,offset ScrLine

    rep movsb ; Copy line to the screen
    ;rep movsb is same as the following code:
    ;mov es:di, ds:si
    ;inc si
    ;inc di
    ;dec cx
    ;loop until cx=0
    pop cx
    loop PrintBMPLoop
    ret
endp CopyBitmap

; ______int shortcuts_______
proc enterGraphicMode
	push ax
	; graphic mode 
	mov ax, 13h
	int 10h
	pop ax
	ret
endp entergraphicmode

proc waitForKeyPress
	push ax
	; wait for key
	mov ah, 0h
	int 16h
	mov [pressedKey], al
	pop ax
	ret
endp waitForKeyPress

proc drawPixel
	push bp
	mov bp,sp
	pusha
	; print pixel interrupt
	xor bh, bh ; bh = 0
	mov cx, [x_coordinate] ; x coord
	mov dx, [y_coordinate] ; y coord
	mov ax, [bp+4] ; colour
	mov ah, 0ch
	int 10h
	popa
	pop bp
	ret 2
endp drawPixel

proc readPixel
	pusha
	mov cx, [x_coordinate] ; x coord
	mov dx, [y_coordinate] ; y coord
	mov ah, 0Dh ; read colour interrupt
	int 10h
	mov [pixelcolour], al
	popa
	ret
endp readPixel

proc delay
	pusha
	mov cx, 0h   ; High Word
	mov dx, [move_down_speed]   ;Low Word
	mov al, 0
	mov ah, 86h  ; Wait function
	int 15h
	popa
	ret
endp delay

local_x equ [bp+6]
local_y equ [bp+4]
proc Cursor_Location ;Place the cursor on the screen by bp
	push bp
	mov bp,sp
	pusha
	; set cursor location
	mov bh, 0
	mov dl, local_x ; in column/x
	mov dh, local_y ; in row/y
	mov ah, 2
	int 10h
	popa
	pop bp
	ret 4
endp Cursor_Location

proc Draw_Char
	pusha
	; print a single character to screen
	mov ah, 9
	mov al, [character] ;AL = character to display
	mov bh, 0h ;BH=Page
	mov bl, [char_colour] ; BL = Foreground
	mov cx, 1 ; number of times to write character
	int 10h ; Bois -&gt; show the character
	popa
	ret
endp Draw_Char

proc Print_Text ;print text in dx
	pusha
	mov ah, 9h
	int 21h
	popa
	ret
endp Print_Text
	
; _________graphics_________
proc drawSquare
		push cx
		; draw a basic square using the given colours

		; outer square
		push [y_coordinate]
		mov cx, [square_size] ; set column loop counter
		drawSquare_column:
			push cx ; push to not lose big loop counter
			push [x_coordinate] ; in order to reset the x_coord every row
			
			mov cx, [square_size] ; set row loop counter
			drawSquare_row:
				push [main_colour]
				call drawpixel ; draw pixel
				inc [x_coordinate] 
				loop drawsquare_row ; loop for the whole row 

			pop [x_coordinate] ; reset x_coord
			pop cx ; get big loop counter back
			inc [y_coordinate] ; next row
			loop drawsquare_column

		pop [y_coordinate] ; reset y_coord
		
		;border
		push [x_coordinate]
		push [y_coordinate] 
		mov cx, [square_size]
		drawSquare_border_top:
			push [light_colour]
			call drawpixel ; draw pixel
			inc [x_coordinate] 
			loop drawsquare_border_top ; loop for the whole row 
		dec [x_coordinate]
		inc [y_coordinate]

		mov cx, [square_size]
		dec cx
		drawSquare_border_right:
			push [border_colour]
			call drawpixel ; draw pixel
			inc [y_coordinate] 
			loop drawsquare_border_right ; loop for the whole column 
		dec [y_coordinate]

		mov cx, [square_size]
		drawSquare_border_bottom:
			push [border_colour]
			call drawpixel ; draw pixel
			dec [x_coordinate] 
			loop drawsquare_border_bottom ; loop for the whole row 
		inc [x_coordinate]
		dec [y_coordinate]

		mov cx, [square_size]
		dec cx
		drawSquare_border_left:
			push [light_colour]
			call drawpixel ; draw pixel
			dec [y_coordinate] 
			loop drawsquare_border_left ; loop for the whole column 
		pop [y_coordinate]
		pop [x_coordinate]

		pop cx
		ret
endp drawSquare

proc drawTPiece_1
		push [x_coordinate]
		push [y_coordinate]
		push cx
		push ax
		
		;  O
		; OOO
		
		mov [light_colour], 0efh
		mov [main_colour], 0deh
		mov [border_colour], 83h
		
		mov ax, [square_size] ; mov square size to a register

		add [x_coordinate], ax ; top square position
		call drawsquare ; draw top square
		
		sub [x_coordinate], ax ; bottom squares position
		add [y_coordinate], ax
		
		mov cx, 3 ; draw bottom 3 pieces
		drawTPiece_1_bottomLoop:
			call drawsquare
			add [x_coordinate], ax ; move to next
			loop drawTPiece_1_bottomLoop

		pop ax
		pop cx
		pop [y_coordinate]
		pop [x_coordinate]
		ret
endp drawTPiece_1

proc blackTPiece_1
		push [x_coordinate]
		push [y_coordinate]
		push cx
		push ax
		
		;  O
		; OOO
		
		mov [main_colour], 0
		mov [border_colour], 0
		mov [light_colour], 0
		
		mov ax, [square_size] ; mov square size to a register

		add [x_coordinate], ax ; top square position
		call drawsquare ; draw top square
		
		sub [x_coordinate], ax ; bottom squares position
		add [y_coordinate], ax
		
		mov cx, 3 ; draw bottom 3 pieces
		blackTPiece_1_bottomLoop:
			call drawsquare
			add [x_coordinate], ax ; move to next
			loop blackTPiece_1_bottomLoop

		pop ax
		pop cx
		pop [y_coordinate]
		pop [x_coordinate]
		ret
endp blackTPiece_1

proc drawTPiece_2
		push [x_coordinate]
		push [y_coordinate]
		push cx
		push ax
		
		;  O
		; OO
		;  O
		
		mov [light_colour], 0efh
		mov [main_colour], 0deh
		mov [border_colour], 83h
		
		mov ax, [square_size] ; mov square size to a register

		add [y_coordinate], ax ; left square position
		call drawsquare ; draw left square
		
		sub [y_coordinate], ax ; right squares position
		add [x_coordinate], ax
		
		mov cx, 3 ; draw middle 3 pieces
		drawTPiece_2_middleLoop:
			call drawsquare
			add [y_coordinate], ax ; move to next
			loop drawTPiece_2_middleLoop

		pop ax
		pop cx
		pop [y_coordinate]
		pop [x_coordinate]
		ret
endp drawTPiece_2

proc blackTPiece_2
		push [x_coordinate]
		push [y_coordinate]
		push cx
		push ax
		
		;  O
		; OO
		;  O
		
		mov [main_colour], 0
		mov [border_colour], 0
		mov [light_colour], 0
		
		mov ax, [square_size] ; mov square size to a register

		add [y_coordinate], ax ; left square position
		call drawsquare ; black left square
		
		sub [y_coordinate], ax ; right squares position
		add [x_coordinate], ax
		
		mov cx, 3 ; black middle 3 pieces
		blackTPiece_2_middleLoop:
			call drawsquare
			add [y_coordinate], ax ; move to next
			loop blackTPiece_2_middleLoop

		pop ax
		pop cx
		pop [y_coordinate]
		pop [x_coordinate]
		ret
endp blackTPiece_2

proc drawTPiece_3
		push [x_coordinate]
		push [y_coordinate]
		push cx
		push ax
		
		; OOO
		;  O 
		
		mov [light_colour], 0efh
		mov [main_colour], 0deh
		mov [border_colour], 83h
		
		mov ax, [square_size] ; mov square size to a register

		add [x_coordinate], ax ; bottom square position
		add [y_coordinate], ax
		add [y_coordinate], ax
		call drawsquare ; draw bottom square
		
		sub [x_coordinate], ax ; top squares position
		sub [y_coordinate], ax
		
		mov cx, 3 ; draw top 3 pieces
		drawTPiece_3_topLoop:
			call drawsquare
			add [x_coordinate], ax ; move to next
			loop drawTPiece_3_topLoop

		pop ax
		pop cx
		pop [y_coordinate]
		pop [x_coordinate]
		ret
endp drawTPiece_3

proc blackTPiece_3
		push [x_coordinate]
		push [y_coordinate]
		push cx
		push ax
		
		; OOO
		;  O 
		
		mov [main_colour], 0
		mov [border_colour], 0
		mov [light_colour], 0
		
		mov ax, [square_size] ; mov square size to a register

		add [x_coordinate], ax ; bottom square position
		add [y_coordinate], ax
		add [y_coordinate], ax
		call drawsquare ; black bottom square
		
		sub [x_coordinate], ax ; top squares position
		sub [y_coordinate], ax
		
		mov cx, 3 ; black top 3 pieces
		blackTPiece_3_topLoop:
			call drawsquare
			add [x_coordinate], ax ; move to next
			loop blackTPiece_3_topLoop

		pop ax
		pop cx
		pop [y_coordinate]
		pop [x_coordinate]
		ret
endp blackTPiece_3

proc drawTPiece_4
		push [x_coordinate]
		push [y_coordinate]
		push cx
		push ax
		
		;  O
		;  OO
		;  O
		
		mov [light_colour], 0efh
		mov [main_colour], 0deh
		mov [border_colour], 83h
		
		mov ax, [square_size] ; mov square size to a register

		add [y_coordinate], ax ; right square position
		add [x_coordinate], ax
		add [x_coordinate], ax
		call drawsquare ; draw right square
		
		sub [y_coordinate], ax ; middle squares position
		sub [x_coordinate], ax
		
		mov cx, 3 ; draw middle 3 pieces
		drawTPiece_4_middleLoop:
			call drawsquare
			add [y_coordinate], ax ; move to next
			loop drawTPiece_4_middleLoop

		pop ax
		pop cx
		pop [y_coordinate]
		pop [x_coordinate]
		ret
endp drawTPiece_4

proc blackTPiece_4
		push [x_coordinate]
		push [y_coordinate]
		push cx
		push ax
		
		;  O
		;  OO
		;  O
		
		mov [main_colour], 0
		mov [border_colour], 0
		mov [light_colour], 0
		
		mov ax, [square_size] ; mov square size to a register

		add [y_coordinate], ax ; right square position
		add [x_coordinate], ax
		add [x_coordinate], ax
		call drawsquare ; black right square
		
		sub [y_coordinate], ax ; middle squares position
		sub [x_coordinate], ax
		
		mov cx, 3 ; black middle 3 pieces
		blackTPiece_4_middleLoop:
			call drawsquare
			add [y_coordinate], ax ; move to next
			loop blackTPiece_4_middleLoop

		pop ax
		pop cx
		pop [y_coordinate]
		pop [x_coordinate]
		ret
endp blackTPiece_4

proc drawOPiece
	push [x_coordinate]
	push [y_coordinate]
	push ax
	; OO
	; OO
	mov ax, [square_size]

	; o-piece colours
	mov [main_colour], 37h ; orangish yellow
	mov [light_colour], 0bfh ; light yellow
	mov [border_colour], 5dh ; brown

	add [x_coordinate], ax
	call drawsquare ; top left

	add [x_coordinate], ax
	call drawsquare ; top right

	add [y_coordinate], ax
	call drawsquare ; bottom right

	sub [x_coordinate], ax
	call drawsquare ; bottom left

	pop ax
	pop [y_coordinate]
	pop [x_coordinate]
	ret
endp drawopiece

proc blackOPiece
	push [x_coordinate]
	push [y_coordinate]
	push ax
	; OO
	; OO
	mov ax, [square_size]

	; o-piece colours
	mov [main_colour], 0 ; black
	mov [light_colour], 0
	mov [border_colour], 0

	add [x_coordinate], ax
	call drawsquare ; top left

	add [x_coordinate], ax
	call drawsquare ; top right

	add [y_coordinate], ax
	call drawsquare ; bottom right

	sub [x_coordinate], ax
	call drawsquare ; bottom left

	pop ax
	pop [y_coordinate]
	pop [x_coordinate]
	ret
endp blackopiece

proc drawJPiece_1
		push [x_coordinate]
		push [y_coordinate]
		push cx
		push ax

		mov ax, [square_size] ; mov square size to a register
		
		; OOO
		;   O
		
		mov [light_colour], 9h ; blues
		mov [main_colour], 0d0h
		mov [border_colour], 40h

		mov cx, 3 ; draw top 3 pieces
		drawJPiece_1_topLoop:
			call drawsquare
			add [x_coordinate], ax ; move to next
			loop drawJPiece_1_topLoop

		sub [x_coordinate], ax 
		add [y_coordinate], ax ; bottom square position
		call drawsquare ; draw bottom square

		pop ax
		pop cx
		pop [y_coordinate]
		pop [x_coordinate]
		ret
endp drawJPiece_1

proc blackJPiece_1
		push [x_coordinate]
		push [y_coordinate]
		push cx
		push ax

		mov ax, [square_size] ; mov square size to a register
		
		; OOO
		;   O
		
		mov [light_colour], 0 ; blacks
		mov [main_colour], 0
		mov [border_colour], 0

		mov cx, 3 ; black top 3 pieces
		blackJPiece_1_topLoop:
			call drawsquare
			add [x_coordinate], ax ; move to next
			loop blackJPiece_1_topLoop

		sub [x_coordinate], ax
		add [y_coordinate], ax ; bottom square position
		call drawsquare ; black bottom square

		pop ax
		pop cx
		pop [y_coordinate]
		pop [x_coordinate]
		ret
endp blackJPiece_1

proc drawJPiece_2
		push [x_coordinate]
		push [y_coordinate]
		push cx
		push ax

		mov ax, [square_size] ; mov square size to a register
		
		; OO 
		; O  
		; O
		
		mov [light_colour], 9h ; blues
		mov [main_colour], 0d0h
		mov [border_colour], 40h

		add [x_coordinate], ax ; right square position
		call drawsquare

		sub [x_coordinate], ax ; left squares position
		mov cx, 3 ; draw left 3 pieces
		drawJPiece_2_leftLoop:
			call drawsquare
			add [y_coordinate], ax ; move to next
			loop drawJPiece_2_leftLoop

		pop ax
		pop cx
		pop [y_coordinate]
		pop [x_coordinate]
		ret
endp drawJPiece_2

proc blackJPiece_2
		push [x_coordinate]
		push [y_coordinate]
		push cx
		push ax

		mov ax, [square_size] ; mov square size to a register
		
		; OO 
		; O  
		; O
		
		mov [light_colour], 0 ; blacks
		mov [main_colour], 0
		mov [border_colour], 0

		add [x_coordinate], ax ; right square position
		call drawsquare

		sub [x_coordinate], ax ; left squares position
		mov cx, 3 ; black left 3 pieces
		blackJPiece_2_leftLoop:
			call drawsquare
			add [y_coordinate], ax ; move to next
			loop blackJPiece_2_leftLoop

		pop ax
		pop cx
		pop [y_coordinate]
		pop [x_coordinate]
		ret
endp blackJPiece_2

proc drawJPiece_3
		push [x_coordinate]
		push [y_coordinate]
		push cx
		push ax

		mov ax, [square_size] ; mov square size to a register
		
		; 
		; O  
		; OOO
		
		mov [light_colour], 9h ; blues
		mov [main_colour], 0d0h
		mov [border_colour], 40h

		add [y_coordinate], ax ; top square position
		call drawsquare ; draw top square

		add [y_coordinate], ax ; top square position
		mov cx, 3 ; draw bottom 3 pieces
		drawJPiece_3_bottomLoop:
			call drawsquare
			add [x_coordinate], ax ; move to next
			loop drawJPiece_3_bottomLoop

		pop ax
		pop cx
		pop [y_coordinate]
		pop [x_coordinate]
		ret
endp drawJPiece_3

proc blackJPiece_3
		push [x_coordinate]
		push [y_coordinate]
		push cx
		push ax

		mov ax, [square_size] ; mov square size to a register
		
		; 
		; O  
		; OOO
		
		mov [light_colour], 0 ; blacks
		mov [main_colour], 0
		mov [border_colour], 0

		add [y_coordinate], ax ; top square position
		call drawsquare ; black top square

		add [y_coordinate], ax ; top square position
		mov cx, 3 ; black bottom 3 pieces
		blackJPiece_3_bottomLoop:
			call drawsquare
			add [x_coordinate], ax ; move to next
			loop blackJPiece_3_bottomLoop

		pop ax
		pop cx
		pop [y_coordinate]
		pop [x_coordinate]
		ret
endp blackJPiece_3

proc drawJPiece_4
		push [x_coordinate]
		push [y_coordinate]
		push cx
		push ax

		mov ax, [square_size] ; mov square size to a register
		
		;   O
		;   O
		;  OO
		
		mov [light_colour], 9h ; blues
		mov [main_colour], 0d0h
		mov [border_colour], 40h

		add [x_coordinate], ax ; right squares position
		add [x_coordinate], ax
		mov cx, 3 ; draw right 3 pieces
		drawJPiece_4_rightLoop:
			call drawsquare
			add [y_coordinate], ax ; move to next
			loop drawJPiece_4_rightLoop

		sub [y_coordinate], ax ; left square position
		sub [x_coordinate], ax
		call drawsquare

		pop ax
		pop cx
		pop [y_coordinate]
		pop [x_coordinate]
		ret
endp drawJPiece_4

proc blackJPiece_4
		push [x_coordinate]
		push [y_coordinate]
		push cx
		push ax

		mov ax, [square_size] ; mov square size to a register
		
		;   O
		;   O
		;  OO
		
		mov [light_colour], 0 ; blacks
		mov [main_colour], 0
		mov [border_colour], 0

		add [x_coordinate], ax ; right squares position
		add [x_coordinate], ax
		mov cx, 3 ; black right 3 pieces
		blackJPiece_4_rightLoop:
			call drawsquare
			add [y_coordinate], ax ; move to next
			loop blackJPiece_4_rightLoop

		sub [y_coordinate], ax ; left square position
		sub [x_coordinate], ax
		call drawsquare

		pop ax
		pop cx
		pop [y_coordinate]
		pop [x_coordinate]
		ret
endp blackJPiece_4

proc drawLPiece_1
		push [x_coordinate]
		push [y_coordinate]
		push cx
		push ax

		mov ax, [square_size] ; mov square size to a register
		
		; OOO
		; O  
		
		mov [light_colour], 77h ; orange
		mov [main_colour], 27h
		mov [border_colour], 15h

		add [y_coordinate], ax 
		call drawsquare ; draw bottom square

		sub [y_coordinate], ax
		mov cx, 3 ; draw top 3 pieces
		drawLPiece_1_topLoop:
			call drawsquare
			add [x_coordinate], ax ; move to next
			loop drawLPiece_1_topLoop

		pop ax
		pop cx
		pop [y_coordinate]
		pop [x_coordinate]
		ret
endp drawLPiece_1

proc blackLPiece_1
		push [x_coordinate]
		push [y_coordinate]
		push cx
		push ax

		mov ax, [square_size] ; mov square size to a register
		
		; OOO
		; O  
		
		mov [light_colour], 0 ; black
		mov [main_colour], 0
		mov [border_colour], 0

		add [y_coordinate], ax 
		call drawsquare ; black bottom square

		sub [y_coordinate], ax
		mov cx, 3 ; black top 3 pieces
		blackLPiece_1_topLoop:
			call drawsquare
			add [x_coordinate], ax ; move to next
			loop blackLPiece_1_topLoop

		pop ax
		pop cx
		pop [y_coordinate]
		pop [x_coordinate]
		ret
endp blackLPiece_1

proc drawLPiece_2
		push [x_coordinate]
		push [y_coordinate]
		push cx
		push ax

		mov ax, [square_size] ; mov square size to a register
		
		; O
		; O  
		; OO
		
		mov [light_colour], 77h ; orange
		mov [main_colour], 27h
		mov [border_colour], 15h

		mov cx, 3 ; draw left 3 pieces
		drawLPiece_2_leftLoop:
			call drawsquare
			add [y_coordinate], ax ; move to next
			loop drawLPiece_2_leftLoop

		sub [y_coordinate], ax
		add [x_coordinate], ax 
		call drawsquare ; draw bottom square

		pop ax
		pop cx
		pop [y_coordinate]
		pop [x_coordinate]
		ret
endp drawLPiece_2

proc blackLPiece_2
		push [x_coordinate]
		push [y_coordinate]
		push cx
		push ax

		mov ax, [square_size] ; mov square size to a register
		
		; O
		; O  
		; OO
		
		mov [light_colour], 0 ; black
		mov [main_colour], 0
		mov [border_colour], 0

		mov cx, 3 ; black left 3 pieces
		blackLPiece_2_leftLoop:
			call drawsquare
			add [y_coordinate], ax ; move to next
			loop blackLPiece_2_leftLoop

		sub [y_coordinate], ax
		add [x_coordinate], ax 
		call drawsquare ; black bottom square

		pop ax
		pop cx
		pop [y_coordinate]
		pop [x_coordinate]
		ret
endp blackLPiece_2

proc drawLPiece_3
		push [x_coordinate]
		push [y_coordinate]
		push cx
		push ax

		mov ax, [square_size] ; mov square size to a register
		
		;  
		;   O
		; OOO
		
		mov [light_colour], 77h ; orange
		mov [main_colour], 27h
		mov [border_colour], 15h

		add [y_coordinate], ax
		add [y_coordinate], ax
		mov cx, 3 ; draw bottom 3 pieces
		drawLPiece_3_bottomLoop:
			call drawsquare
			add [x_coordinate], ax ; move to next
			loop drawLPiece_3_bottomLoop

		sub [y_coordinate], ax 
		sub [x_coordinate], ax
		call drawsquare ; draw bottom square

		pop ax
		pop cx
		pop [y_coordinate]
		pop [x_coordinate]
		ret
endp drawLPiece_3

proc blackLPiece_3
		push [x_coordinate]
		push [y_coordinate]
		push cx
		push ax

		mov ax, [square_size] ; mov square size to a register
		
		;  
		;   O
		; OOO
		
		mov [light_colour], 0 ; black
		mov [main_colour], 0
		mov [border_colour], 0

		add [y_coordinate], ax
		add [y_coordinate], ax
		mov cx, 3 ; black bottom 3 pieces
		blackLPiece_3_bottomLoop:
			call drawsquare
			add [x_coordinate], ax ; move to next
			loop blackLPiece_3_bottomLoop

		sub [y_coordinate], ax 
		sub [x_coordinate], ax
		call drawsquare ; black bottom square

		pop ax
		pop cx
		pop [y_coordinate]
		pop [x_coordinate]
		ret
endp blackLPiece_3

proc drawLPiece_4
		push [x_coordinate]
		push [y_coordinate]
		push cx
		push ax

		mov ax, [square_size] ; mov square size to a register
		
		;  OO
		;   O
		;   O
		
		mov [light_colour], 77h ; orange
		mov [main_colour], 27h
		mov [border_colour], 15h
	
		add [x_coordinate], ax
		call drawsquare ; draw bottom square

		add [x_coordinate], ax
		mov cx, 3 ; draw right 4 pieces
		drawLPiece_4_rightLoop:
			call drawsquare
			add [y_coordinate], ax ; move to next
			loop drawLPiece_4_rightLoop

		pop ax
		pop cx
		pop [y_coordinate]
		pop [x_coordinate]
		ret
endp drawLPiece_4

proc blackLPiece_4
		push [x_coordinate]
		push [y_coordinate]
		push cx
		push ax

		mov ax, [square_size] ; mov square size to a register
		
		;  OO
		;   O
		;   O
		
		mov [light_colour], 0 ; black
		mov [main_colour], 0
		mov [border_colour], 0
	
		add [x_coordinate], ax
		call drawsquare ; black bottom square

		add [x_coordinate], ax
		mov cx, 3 ; draw right 4 pieces
		blackLPiece_4_rightLoop:
			call drawsquare
			add [y_coordinate], ax ; move to next
			loop blackLPiece_4_rightLoop

		pop ax
		pop cx
		pop [y_coordinate]
		pop [x_coordinate]
		ret
endp blackLPiece_4

proc drawIPiece_1
		push [x_coordinate]
		push [y_coordinate]
		push cx
		push ax
		
		;  
		; OOOO
		
		mov [light_colour], 0ffh ; cyan
		mov [main_colour], 0feh
		mov [border_colour], 6h
		
		mov ax, [square_size] ; mov square size to a register

		add [y_coordinate], ax
		mov cx, 4 ; draw line
		drawIPiece_1_bottomLoop:
			call drawsquare
			add [x_coordinate], ax ; move to next
			loop drawIPiece_1_bottomLoop

		pop ax
		pop cx
		pop [y_coordinate]
		pop [x_coordinate]
		ret
endp drawIPiece_1

proc blackIPiece_1
		push [x_coordinate]
		push [y_coordinate]
		push cx
		push ax
		
		;  
		; OOOO
		
		mov [light_colour], 0 ; black
		mov [main_colour], 0
		mov [border_colour], 0
		
		mov ax, [square_size] ; mov square size to a register

		add [y_coordinate], ax
		mov cx, 4 ; black line
		blackIPiece_1_bottomLoop:
			call drawsquare
			add [x_coordinate], ax ; move to next
			loop blackIPiece_1_bottomLoop

		pop ax
		pop cx
		pop [y_coordinate]
		pop [x_coordinate]
		ret
endp blackIPiece_1

proc drawIPiece_2
		push [x_coordinate]
		push [y_coordinate]
		push cx
		push ax
		
		; O
		; O
		; O
		; O
		
		mov [light_colour], 0ffh ; cyan
		mov [main_colour], 0feh
		mov [border_colour], 6h
		
		mov ax, [square_size] ; mov square size to a register

		add [x_coordinate], ax
		mov cx, 4 ; draw line
		drawIPiece_2_leftLoop:
			call drawsquare
			add [y_coordinate], ax ; move to next
			loop drawIPiece_2_leftLoop

		pop ax
		pop cx
		pop [y_coordinate]
		pop [x_coordinate]
		ret
endp drawIPiece_2

proc blackIPiece_2
		push [x_coordinate]
		push [y_coordinate]
		push cx
		push ax
		
		; O
		; O
		; O
		; O
		
		mov [light_colour], 0 ; black
		mov [main_colour], 0
		mov [border_colour], 0
		
		mov ax, [square_size] ; mov square size to a register

		add [x_coordinate], ax
		mov cx, 4 ; black line
		blackIPiece_2_leftLoop:
			call drawsquare
			add [y_coordinate], ax ; move to next
			loop blackIPiece_2_leftLoop

		pop ax
		pop cx
		pop [y_coordinate]
		pop [x_coordinate]
		ret
endp blackIPiece_2

proc drawIPiece_3
		push [x_coordinate]
		push [y_coordinate]
		push cx
		push ax
		
		;  
		;  
		; OOOO
		
		mov [light_colour], 0ffh ; cyan
		mov [main_colour], 0feh
		mov [border_colour], 6h
		
		mov ax, [square_size] ; mov square size to a register

		add [y_coordinate], ax
		add [y_coordinate], ax
		mov cx, 4 ; draw line
		drawIPiece_3_bottomLoop:
			call drawsquare
			add [x_coordinate], ax ; move to next
			loop drawIPiece_3_bottomLoop

		pop ax
		pop cx
		pop [y_coordinate]
		pop [x_coordinate]
		ret
endp drawIPiece_3

proc drawSPiece_1
		push [x_coordinate]
		push [y_coordinate]
		push ax
		
		;  OO
		; OO 
		
		mov [light_colour], 0bdh ; greens
		mov [main_colour], 38h
		mov [border_colour], 22h
		
		mov ax, [square_size] ; mov square size to a register

		add [y_coordinate], ax
		call drawsquare
		add [x_coordinate], ax
		call drawsquare
		sub [y_coordinate], ax
		call drawsquare
		add [x_coordinate], ax
		call drawsquare

		pop ax
		pop [y_coordinate]
		pop [x_coordinate]
		ret
endp drawSPiece_1

proc blackSPiece_1
		push [x_coordinate]
		push [y_coordinate]
		push ax
		
		;  OO
		; OO 
		
		mov [light_colour], 0h ; black
		mov [main_colour], 0h
		mov [border_colour], 0h
		
		mov ax, [square_size] ; mov square size to a register

		add [y_coordinate], ax
		call drawsquare
		add [x_coordinate], ax
		call drawsquare
		sub [y_coordinate], ax
		call drawsquare
		add [x_coordinate], ax
		call drawsquare

		pop ax
		pop [y_coordinate]
		pop [x_coordinate]
		ret
endp blackSPiece_1

proc drawSPiece_2
		push [x_coordinate]
		push [y_coordinate]
		push ax
		
		; O  
		; OO 
		;  O 
		
		mov [light_colour], 0bdh ; greens
		mov [main_colour], 38h
		mov [border_colour], 22h
		
		mov ax, [square_size] ; mov square size to a register

		call drawsquare
		add [y_coordinate], ax
		call drawsquare
		add [x_coordinate], ax
		call drawsquare
		add [y_coordinate], ax
		call drawsquare

		pop ax
		pop [y_coordinate]
		pop [x_coordinate]
		ret
endp drawSPiece_2

proc blackSPiece_2
		push [x_coordinate]
		push [y_coordinate]
		push ax
		
		; O  
		; OO 
		;  O 
		
		mov [light_colour], 0h ; black
		mov [main_colour], 0h
		mov [border_colour], 0h
		
		mov ax, [square_size] ; mov square size to a register

		call drawsquare
		add [y_coordinate], ax
		call drawsquare
		add [x_coordinate], ax
		call drawsquare
		add [y_coordinate], ax
		call drawsquare

		pop ax
		pop [y_coordinate]
		pop [x_coordinate]
		ret
endp blackSPiece_2

proc drawZPiece_1
		push [x_coordinate]
		push [y_coordinate]
		push ax
		
		; OO
		;  OO 
		
		mov [light_colour], 5fh ; reds
		mov [main_colour], 0f9h
		mov [border_colour], 01h
		
		mov ax, [square_size] ; mov square size to a register

		call drawsquare
		add [x_coordinate], ax
		call drawsquare
		add [y_coordinate], ax
		call drawsquare
		add [x_coordinate], ax
		call drawsquare

		pop ax
		pop [y_coordinate]
		pop [x_coordinate]
		ret
endp drawZPiece_1

proc blackZPiece_1
		push [x_coordinate]
		push [y_coordinate]
		push ax
		
		; OO
		;  OO 
		
		mov [light_colour], 0h ; blacks
		mov [main_colour], 0h
		mov [border_colour], 0h
		
		mov ax, [square_size] ; mov square size to a register

		call drawsquare
		add [x_coordinate], ax
		call drawsquare
		add [y_coordinate], ax
		call drawsquare
		add [x_coordinate], ax
		call drawsquare

		pop ax
		pop [y_coordinate]
		pop [x_coordinate]
		ret
endp blackZPiece_1

proc drawZPiece_2
		push [x_coordinate]
		push [y_coordinate]
		push ax
		
		;  O 
		; OO 
		; O  
		
		mov [light_colour], 5fh ; reds
		mov [main_colour], 0f9h
		mov [border_colour], 01h
		
		mov ax, [square_size] ; mov square size to a register

		add [x_coordinate], ax
		call drawsquare
		add [y_coordinate], ax
		call drawsquare
		sub [x_coordinate], ax
		call drawsquare
		add [y_coordinate], ax
		call drawsquare

		pop ax
		pop [y_coordinate]
		pop [x_coordinate]
		ret
endp drawZPiece_2

proc blackZPiece_2
		push [x_coordinate]
		push [y_coordinate]
		push ax
		
		;  O 
		; OO 
		; O  
		
		mov [light_colour], 0h ; reds
		mov [main_colour], 0h
		mov [border_colour], 0h
		
		mov ax, [square_size] ; mov square size to a register

		add [x_coordinate], ax
		call drawsquare
		add [y_coordinate], ax
		call drawsquare
		sub [x_coordinate], ax
		call drawsquare
		add [y_coordinate], ax
		call drawsquare

		pop ax
		pop [y_coordinate]
		pop [x_coordinate]
		ret
endp blackZPiece_2

; _________logicals_________

; random
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

proc generate_last_7_queue
	; an official tetris random generator mechanism 
	; needs to load the queue every time with all of the 7 tetreminos
	; in a random order
	; this procedure does it
	mov [min_queue_last_7], 14
	mov bx, offset queue
	mov si, 14
	mov cx, 7

	reset_last_7_loop: ; 100 is not an avaliable piece, so setting every spot we
					   ; want to change to 100 will let us know which spot we
					   ; already changed
		mov [bx+si], 100
		add si, 2
		loop reset_last_7_loop

	mov ax, 0
	mov cx, 7
	generate_last_7_loop:
		mov [top_limit], cx ; generate a random location on the list
		call randomnum
		mov dl, [rand_num]
		add dl, [rand_num] 
		add dl, [min_queue_last_7]; the piece is a word, so si is doubled
		mov dh, 0 ; now dx holds the position the position it wants to put a piece in

		mov si, dx
		check_if_spot_valid: ; check if the spot wasn't already taken 
			cmp [bx+si], 6
			ja generate_last_7_set ; when the spot is valid, continue

		; if spot isnt valid:
			add si, 2 ; try the one bove
			cmp si, 28
			jb check_if_spot_valid ; if dx is still in range 14-27 check again
			mov dl, [min_queue_last_7] ; if it isn't start from the beginnig
			mov dh, 0
			jmp check_if_spot_valid

		generate_last_7_set:
		
		mov [bx+si], ax ; when the spot is avaliable, put a piece in it
		inc ax ; next piece

		cmp [rand_num], 0 ; if the chosen spot is the lowest avaliable spot, change the minimum to the next spot
		je generate_last_7_change_min

		loop generate_last_7_loop

		ret

		generate_last_7_change_min:
			add [min_queue_last_7], 2
			
			loop generate_last_7_loop

	ret
endp generate_last_7_queue

; movment
proc rotate_left
		push ax
		push [x_coordinate]
		push [y_coordinate]
		cmp [current_piece], 0 ; if t-piece
		je rotate_left_t
		cmp [current_piece], 1 ; if o-piece
		je rotate_left_o
		cmp [current_piece], 2 ; if j-piece
		je rotate_left_j
		cmp [current_piece], 3 ; if l-piece
		je rotate_left_l
		cmp [current_piece], 4 ; if i-piece
		je rotate_left_i
		cmp [current_piece], 5 ; if s-piece
		je rotate_left_s
		cmp [current_piece], 6 ; if z-piece
		je rotate_left_z
		jmp rotate_left_end

	rotate_left_o: ; o-piece
		call drawopiece
		jmp rotate_left_end ; o-piece has only 1 rotation

	rotate_left_z: ; z-piece
		inc [current_piece_rotation] ; next position
		cmp [current_piece_rotation], 4 ; make it return to 1 after 2
		jna rotate_left_z_draw ; make it return to 1 after 4
		mov [current_piece_rotation], 1 ; make it return to 1 after 2

	rotate_left_z_draw: ; draw s-piece
		mov ax, [square_size] ; move square size to a register (used for checking )

		cmp [current_piece_rotation], 1 ; rotate to first position
		je rotate_left_z_draw_1
		cmp [current_piece_rotation], 2 ; rotate to second positon
		je rotate_left_z_draw_2
		cmp [current_piece_rotation], 3 ; rotate to third position
		je rotate_left_z_draw_3
		cmp [current_piece_rotation], 4 ; rotate to fourth position
		je rotate_left_z_draw_4
		jmp rotate_left_end

	rotate_left_z_draw_1:
		call readpixel
		cmp [pixelcolour], 0 ; if the square that wasn't occupied is already occupied, don't rotate #1
		jne rotate_left_fail

		add [x_coordinate], ax
		call readpixel
		cmp [pixelcolour], 0 ; if the square that wasn't occupied is already occupied, don't rotate #2
		jne rotate_left_fail

		sub [x_coordinate], ax ; return to cursor's position

		add [x_coordinate], ax
		call blackZPiece_2 ; delete fourth position
		sub [x_coordinate], ax
		call drawzPiece_1 ; draw first position
		jmp rotate_left_end

	rotate_left_z_draw_2:
		add [y_coordinate], ax 
		call readpixel
		cmp [pixelcolour], 0 ; if the square that wasn't occupied is already occupied, don't rotate #1
		jne rotate_left_fail

		add [y_coordinate], ax 
		call readpixel
		cmp [pixelcolour], 0 ; if the square that wasn't occupied is already occupied, don't rotate #2
		jne rotate_left_fail

		sub [y_coordinate], ax ; return to cursor's position
		sub [y_coordinate], ax 

		call blackZPiece_1 ; delete fourth position
		call drawzPiece_2 ; draw first position
		jmp rotate_left_end

	rotate_left_z_draw_3:
		add [y_coordinate], ax 
		add [y_coordinate], ax 
		add [x_coordinate], ax 
		call readpixel
		cmp [pixelcolour], 0 ; if the square that wasn't occupied is already occupied, don't rotate #1
		jne rotate_left_fail

		add [x_coordinate], ax 
		call readpixel
		cmp [pixelcolour], 0 ; if the square that wasn't occupied is already occupied, don't rotate #2
		jne rotate_left_fail

		sub [y_coordinate], ax ; return to cursor's position
		sub [y_coordinate], ax 
		sub [x_coordinate], ax 
		sub [x_coordinate], ax 

		call blackZPiece_2 ; delete first position
		add [y_coordinate], ax
		call drawzPiece_1 ; draw second position
		sub [y_coordinate], ax
		jmp rotate_left_end

	rotate_left_z_draw_4:
		add [x_coordinate], ax 
		add [x_coordinate], ax 
		call readpixel
		cmp [pixelcolour], 0 ; if the square that wasn't occupied is already occupied, don't rotate #1
		jne rotate_left_fail

		add [y_coordinate], ax 
		call readpixel
		cmp [pixelcolour], 0 ; if the square that wasn't occupied is already occupied, don't rotate #2
		jne rotate_left_fail

		sub [y_coordinate], ax ; return to cursor's position
		sub [x_coordinate], ax 
		sub [x_coordinate], ax 

		add [y_coordinate], ax
		call blackZPiece_1 ; delete third position
		sub [y_coordinate], ax
		add [x_coordinate], ax
		call drawzPiece_2 ; draw fourth position
		sub [x_coordinate], ax
		jmp rotate_left_end

	rotate_left_s: ; s-piece
		inc [current_piece_rotation] ; next position
		cmp [current_piece_rotation], 4 ; make it return to 1 after 2
		jna rotate_left_s_draw ; make it return to 1 after 4
		mov [current_piece_rotation], 1 ; make it return to 1 after 2

	rotate_left_s_draw: ; draw s-piece
		mov ax, [square_size] ; move square size to a register (used for checking )

		cmp [current_piece_rotation], 1 ; rotate to first position
		je rotate_left_s_draw_1
		cmp [current_piece_rotation], 2 ; rotate to second positon
		je rotate_left_s_draw_2
		cmp [current_piece_rotation], 3 ; rotate to third position
		je rotate_left_s_draw_3
		cmp [current_piece_rotation], 4 ; rotate to fourth position
		je rotate_left_s_draw_4
		jmp rotate_left_end

	rotate_left_s_draw_1:
		add [y_coordinate], ax
		call readpixel
		cmp [pixelcolour], 0 ; if the square that wasn't occupied is already occupied, don't rotate #1
		jne rotate_left_fail

		add [x_coordinate], ax
		add [x_coordinate], ax
		sub [y_coordinate], ax
		call readpixel
		cmp [pixelcolour], 0 ; if the square that wasn't occupied is already occupied, don't rotate #2
		jne rotate_left_fail

		sub [x_coordinate], ax ; return to cursor's position
		sub [x_coordinate], ax

		add [x_coordinate], ax
		call blackSPiece_2 ; delete fourth position
		sub [x_coordinate], ax
		call drawSPiece_1 ; draw first position
		jmp rotate_left_end

	rotate_left_s_draw_2:
		call readpixel
		cmp [pixelcolour], 0 ; if the square that wasn't occupied is already occupied, don't rotate #1
		jne rotate_left_fail

		add [x_coordinate], ax
		add [y_coordinate], ax
		add [y_coordinate], ax
		call readpixel
		cmp [pixelcolour], 0 ; if the square that wasn't occupied is already occupied, don't rotate #2
		jne rotate_left_fail

		sub [x_coordinate], ax ; return to cursor's position
		sub [y_coordinate], ax
		sub [y_coordinate], ax

		call blackSPiece_1 ; delete first position
		call drawSPiece_2 ; draw second position
		jmp rotate_left_end

	rotate_left_s_draw_3:
		add [y_coordinate], ax
		add [y_coordinate], ax
		call readpixel
		cmp [pixelcolour], 0 ; if the square that wasn't occupied is already occupied, don't rotate #1
		jne rotate_left_fail

		add [x_coordinate], ax
		add [x_coordinate], ax
		sub [y_coordinate], ax
		call readpixel
		cmp [pixelcolour], 0 ; if the square that wasn't occupied is already occupied, don't rotate #2
		jne rotate_left_fail

		sub [x_coordinate], ax ; return to cursor's position
		sub [x_coordinate], ax
		sub [y_coordinate], ax

		call blackSPiece_2 ; delete second position
		add [y_coordinate], ax
		call drawSPiece_1 ; draw third position
		sub [y_coordinate], ax
		jmp rotate_left_end

	rotate_left_s_draw_4:
		add [x_coordinate], ax
		call readpixel
		cmp [pixelcolour], 0 ; if the square that wasn't occupied is already occupied, don't rotate #1
		jne rotate_left_fail

		add [x_coordinate], ax
		add [y_coordinate], ax
		add [y_coordinate], ax
		call readpixel
		cmp [pixelcolour], 0 ; if the square that wasn't occupied is already occupied, don't rotate #2
		jne rotate_left_fail

		sub [x_coordinate], ax ; return to cursor's position
		sub [x_coordinate], ax
		sub [y_coordinate], ax
		sub [y_coordinate], ax

		add [y_coordinate], ax
		call blackSPiece_1 ; delete third position
		sub [y_coordinate], ax
		add [x_coordinate], ax
		call drawSPiece_2 ; draw fourth position
		sub [x_coordinate], ax
		jmp rotate_left_end
		
	rotate_left_i: ; i-piece
		inc [current_piece_rotation] ; next position
		cmp [current_piece_rotation], 4 ; make it return to 1 after 2
		jna rotate_left_i_draw ; make it return to 1 after 4
		mov [current_piece_rotation], 1 ; make it return to 1 after 2

	rotate_left_i_draw: ; draw i-piece
		mov ax, [square_size] ; move square size to a register (used for checking )

		cmp [current_piece_rotation], 1 ; rotate to first position
		je rotate_left_i_draw_1
		cmp [current_piece_rotation], 2 ; rotate to second positon
		je rotate_left_i_draw_2
		cmp [current_piece_rotation], 3 ; rotate to third position
		je rotate_left_i_draw_3
		cmp [current_piece_rotation], 4 ; rotate to fourth position
		je rotate_left_i_draw_4
		jmp rotate_left_end

	rotate_left_i_draw_1:
		add [y_coordinate], ax
		call readpixel
		cmp [pixelcolour], 0 ; if the square that wasn't occupied is already occupied, don't rotate #1
		jne rotate_left_fail

		add [x_coordinate], ax
		call readpixel
		cmp [pixelcolour], 0 ; if the square that wasn't occupied is already occupied, don't rotate #2
		jne rotate_left_fail

		add [x_coordinate], ax
		add [x_coordinate], ax
		call readpixel
		cmp [pixelcolour], 0 ; if the square that wasn't occupied is already occupied, don't rotate #3
		jne rotate_left_fail

		sub [y_coordinate], ax ; return to cursor's position
		sub [x_coordinate], ax
		sub [x_coordinate], ax
		sub [x_coordinate], ax

		add [x_coordinate], ax
		call blackipiece_2 ; delete fourth position
		sub [x_coordinate], ax
		call drawipiece_1 ; draw first position
		jmp rotate_left_end

	rotate_left_i_draw_2:
		add [x_coordinate], ax
		call readpixel
		cmp [pixelcolour], 0 ; if the square that wasn't occupied is already occupied, don't rotate #1
		jne rotate_left_fail

		add [y_coordinate], ax
		add [y_coordinate], ax
		call readpixel
		cmp [pixelcolour], 0 ; if the square that wasn't occupied is already occupied, don't rotate #2
		jne rotate_left_fail

		add [y_coordinate], ax
		call readpixel
		cmp [pixelcolour], 0 ; if the square that wasn't occupied is already occupied, don't rotate #3
		jne rotate_left_fail

		sub [x_coordinate], ax ; return to cursor's position
		sub [y_coordinate], ax
		sub [y_coordinate], ax
		sub [y_coordinate], ax

		call blackipiece_1 ; delete first position
		call drawipiece_2 ; draw second position
		jmp rotate_left_end

	rotate_left_i_draw_3:
		add [y_coordinate], ax
		add [y_coordinate], ax
		call readpixel
		cmp [pixelcolour], 0 ; if the square that wasn't occupied is already occupied, don't rotate #1
		jne rotate_left_fail

		add [x_coordinate], ax
		add [x_coordinate], ax
		call readpixel
		cmp [pixelcolour], 0 ; if the square that wasn't occupied is already occupied, don't rotate #2
		jne rotate_left_fail

		add [x_coordinate], ax
		call readpixel
		cmp [pixelcolour], 0 ; if the square that wasn't occupied is already occupied, don't rotate #3
		jne rotate_left_fail

		sub [x_coordinate], ax ; return to cursor's position
		sub [x_coordinate], ax
		sub [x_coordinate], ax
		sub [y_coordinate], ax
		sub [y_coordinate], ax

		call blackipiece_2 ; delete second position
		add [y_coordinate], ax
		call drawipiece_1 ; draw third position
		sub [y_coordinate], ax
		jmp rotate_left_end

	rotate_left_i_draw_4:
		add [x_coordinate], ax
		add [x_coordinate], ax
		call readpixel
		cmp [pixelcolour], 0 ; if the square that wasn't occupied is already occupied, don't rotate #1
		jne rotate_left_fail

		add [y_coordinate], ax
		call readpixel
		cmp [pixelcolour], 0 ; if the square that wasn't occupied is already occupied, don't rotate #2
		jne rotate_left_fail

		add [y_coordinate], ax
		add [y_coordinate], ax
		call readpixel
		cmp [pixelcolour], 0 ; if the square that wasn't occupied is already occupied, don't rotate #3
		jne rotate_left_fail

		sub [x_coordinate], ax ; return to cursor's position
		sub [x_coordinate], ax
		sub [y_coordinate], ax
		sub [y_coordinate], ax
		sub [y_coordinate], ax

		add [y_coordinate], ax
		call blackipiece_1 ; delete third position
		sub [y_coordinate], ax
		add [x_coordinate], ax
		call drawipiece_2 ; draw fourth position
		sub [x_coordinate], ax
		jmp rotate_left_end

	rotate_left_l: ; l-piece
		inc [current_piece_rotation] ; next position
		cmp [current_piece_rotation], 5 ; make it return to 1 after 4
		jne rotate_left_l_draw ; make it return to 1 after 4
		mov [current_piece_rotation], 1 ; make it return to 1 after 4

	rotate_left_l_draw: ; draw l-piece
		mov ax, [square_size] ; move square size to a register (used for checking )

		cmp [current_piece_rotation], 1 ; rotate to first position
		je rotate_left_l_draw_1
		cmp [current_piece_rotation], 2 ; rotate to second positon
		je rotate_left_l_draw_2
		cmp [current_piece_rotation], 3 ; rotate to third positon
		je rotate_left_l_draw_3
		cmp [current_piece_rotation], 4 ; rotate to 4rth positon
		je rotate_left_l_draw_4
		jmp rotate_left_end

	rotate_left_l_draw_1:
		call readpixel
		cmp [pixelcolour], 0 ; if the square that wasn't occupied is already occupied, don't rotate #1
		jne rotate_left_fail

		add [y_coordinate], ax
		call readpixel
		cmp [pixelcolour], 0 ; if the square that wasn't occupied is already occupied, don't rotate #2
		jne rotate_left_fail

		sub [y_coordinate], ax ; return to cursor's position

		call blacklpiece_4 ; delete fourth position
		call drawlpiece_1 ; draw first position
		jmp rotate_left_end

	rotate_left_l_draw_2:
		add [y_coordinate], ax
		add [y_coordinate], ax
		call readpixel
		cmp [pixelcolour], 0 ; if the square that wasn't occupied is already occupied, don't rotate #1
		jne rotate_left_fail

		add [x_coordinate], ax
		call readpixel
		cmp [pixelcolour], 0 ; if the square that wasn't occupied is already occupied, don't rotate #2
		jne rotate_left_fail

		sub [y_coordinate], ax ; return to cursor's position
		sub [y_coordinate], ax
		sub [x_coordinate], ax

		call blacklpiece_1 ; delete fourth position
		call drawlpiece_2 ; draw first position
		jmp rotate_left_end

	rotate_left_l_draw_3:
		add [y_coordinate], ax
		add [y_coordinate], ax
		add [x_coordinate], ax
		add [x_coordinate], ax
		call readpixel
		cmp [pixelcolour], 0 ; if the square that wasn't occupied is already occupied, don't rotate #1
		jne rotate_left_fail

		sub [y_coordinate], ax
		call readpixel
		cmp [pixelcolour], 0 ; if the square that wasn't occupied is already occupied, don't rotate #2
		jne rotate_left_fail

		sub [y_coordinate], ax ; return to cursor's position
		sub [x_coordinate], ax
		sub [x_coordinate], ax

		call blacklpiece_2 ; delete fourth position
		call drawlpiece_3 ; draw first position
		jmp rotate_left_end

	rotate_left_l_draw_4:
		add [x_coordinate], ax
		call readpixel
		cmp [pixelcolour], 0 ; if the square that wasn't occupied is already occupied, don't rotate #1
		jne rotate_left_fail

		add [x_coordinate], ax
		call readpixel
		cmp [pixelcolour], 0 ; if the square that wasn't occupied is already occupied, don't rotate #2
		jne rotate_left_fail

		sub [x_coordinate], ax ; return to cursor's position
		sub [x_coordinate], ax

		call blacklpiece_3 ; delete fourth position
		call drawlpiece_4 ; draw first position
		jmp rotate_left_end

	rotate_left_j: ; j-piece
		inc [current_piece_rotation] ; next position
		cmp [current_piece_rotation], 5 ; make it return to 1 after 4
		jne rotate_left_j_draw ; make it return to 1 after 4
		mov [current_piece_rotation], 1 ; make it return to 1 after 4

	rotate_left_j_draw: ; draw t-piece
		mov ax, [square_size] ; move square size to a register (used for checking )

		cmp [current_piece_rotation], 1 ; rotate to first position
		je rotate_left_j_draw_1
		cmp [current_piece_rotation], 2 ; rotate to second positon
		je rotate_left_j_draw_2
		cmp [current_piece_rotation], 3 ; rotate to third positon
		je rotate_left_j_draw_3
		cmp [current_piece_rotation], 4 ; rotate to 4rth positon
		je rotate_left_j_draw_4
		jmp rotate_left_end

	rotate_left_j_draw_1: ; rotate to first position
		call readpixel
		cmp [pixelcolour], 0 ; if the square that wasn't occupied is already occupied, don't rotate #1
		jne rotate_left_fail

		add [x_coordinate], ax
		call readpixel
		cmp [pixelcolour], 0 ; if the square that wasn't occupied is already occupied, don't rotate #2
		jne rotate_left_fail

		sub [x_coordinate], ax ; return to cursor's position

		call blackjpiece_4 ; delete fourth position
		call drawjpiece_1 ; draw first position
		jmp rotate_left_end

	rotate_left_j_draw_2: ; rotate to first position
		add [y_coordinate], ax
		call readpixel
		cmp [pixelcolour], 0 ; if the square that wasn't occupied is already occupied, don't rotate #1
		jne rotate_left_fail

		add [y_coordinate], ax
		call readpixel
		cmp [pixelcolour], 0 ; if the square that wasn't occupied is already occupied, don't rotate #2
		jne rotate_left_fail

		sub [y_coordinate], ax ; return to cursor's position
		sub [y_coordinate], ax

		call blackjpiece_1 ; delete fourth position
		call drawjpiece_2 ; draw first position
		jmp rotate_left_end

	rotate_left_j_draw_3: ; rotate to first position
		add [y_coordinate], ax
		add [y_coordinate], ax
		add [x_coordinate], ax
		call readpixel
		cmp [pixelcolour], 0 ; if the square that wasn't occupied is already occupied, don't rotate #1
		jne rotate_left_fail

		add [x_coordinate], ax
		call readpixel
		cmp [pixelcolour], 0 ; if the square that wasn't occupied is already occupied, don't rotate #2
		jne rotate_left_fail

		sub [y_coordinate], ax ; return to cursor's position
		sub [y_coordinate], ax
		sub [x_coordinate], ax
		sub [x_coordinate], ax

		call blackjpiece_2 ; delete fourth position
		call drawjpiece_3 ; draw first position
		jmp rotate_left_end

	rotate_left_j_draw_4: ; rotate to first position
		add [x_coordinate], ax
		add [x_coordinate], ax
		call readpixel
		cmp [pixelcolour], 0 ; if the square that wasn't occupied is already occupied, don't rotate #1
		jne rotate_left_fail

		add [y_coordinate], ax
		call readpixel
		cmp [pixelcolour], 0 ; if the square that wasn't occupied is already occupied, don't rotate #2
		jne rotate_left_fail

		sub [y_coordinate], ax ; return to cursor's position
		sub [x_coordinate], ax
		sub [x_coordinate], ax

		call blackjpiece_3 ; delete fourth position
		call drawjpiece_4 ; draw first position
		jmp rotate_left_end
		
	rotate_left_t: ; t-piece
		inc [current_piece_rotation] ; next position
		cmp [current_piece_rotation], 5 ; make it return to 1 after 4
		jne rotate_left_t_draw ; make it return to 1 after 4
		mov [current_piece_rotation], 1 ; make it return to 1 after 4

	rotate_left_t_draw: ; draw j-piece
		mov ax, [square_size] ; move square size to a register (used for checking)

		cmp [current_piece_rotation], 1 ; rotate to first position
		je rotate_left_t_draw_1
		cmp [current_piece_rotation], 2 ; rotate to second positon
		je rotate_left_t_draw_2
		cmp [current_piece_rotation], 3 ; rotate to third positon
		je rotate_left_t_draw_3
		cmp [current_piece_rotation], 4 ; rotate to 4rth positon
		je rotate_left_t_draw_4
		jmp rotate_left_end

	rotate_left_t_draw_1: ; rotate to first position 
		add [y_coordinate], ax
		call readpixel
		cmp [pixelcolour], 0 ; if the square that wasn't occupied is already occupied, don't rotate
		jne rotate_left_fail
		sub [y_coordinate], ax

		call blacktpiece_4 ; delete fourth position
		call drawtpiece_1 ; draw first position
		jmp rotate_left_end

	rotate_left_t_draw_2: ; rotate to second position
		add [y_coordinate], ax
		add [y_coordinate], ax
		add [x_coordinate], ax
		call readpixel
		cmp [pixelcolour], 0 ; if the square that wasn't occupied is already occupied, don't rotate
		jne rotate_left_fail
		sub [x_coordinate], ax
		sub [y_coordinate], ax
		sub [y_coordinate], ax

		call blacktpiece_1 ; delete first position
		call drawtpiece_2 ; draw second position
		jmp rotate_left_end

	rotate_left_t_draw_3: ; rotate to third position
		add [x_coordinate], ax
		add [x_coordinate], ax
		add [y_coordinate], ax
		call readpixel
		cmp [pixelcolour], 0 ; if the square that wasn't occupied is already occupied, don't rotate
		jne rotate_left_fail
		sub [y_coordinate], ax
		sub [x_coordinate], ax
		sub [x_coordinate], ax

		call blacktpiece_2 ; delete second position
		call drawtpiece_3 ; draw third position
		jmp rotate_left_end

	rotate_left_t_draw_4: ; rotate to fourth position
		add [x_coordinate], ax
		call readpixel
		cmp [pixelcolour], 0 ; if the square that wasn't occupied is already occupied, don't rotate
		jne rotate_left_fail
		sub [x_coordinate], ax

		call blacktpiece_3 ; delete third position
		call drawtpiece_4 ; draw fourth position
		jmp rotate_left_end
		
	rotate_left_fail:
		cmp [current_piece_rotation], 1
		je rotate_left_fail_1
		dec [current_piece_rotation]
		jmp rotate_left_end

	rotate_left_fail_1:
		mov [current_piece_rotation], 4

	rotate_left_end:
		pop [y_coordinate]
		pop [x_coordinate]
		pop ax
		ret
endp rotate_left

proc rotate_right
		push ax
		push [x_coordinate]
		push [y_coordinate]
		cmp [current_piece], 0 ; if t-piece
		je rotate_right_t
		cmp [current_piece], 1 ; if o-piece
		je rotate_right_o
		cmp [current_piece], 2 ; if j-piece
		je rotate_right_j
		cmp [current_piece], 3 ; if l-piece
		je rotate_right_l
		cmp [current_piece], 4 ; if i-piece
		je rotate_right_i
		cmp [current_piece], 5 ; if s-piece
		je rotate_right_s
		cmp [current_piece], 6 ; if z-piece
		je rotate_right_z
		jmp rotate_right_end

	rotate_right_o: ; o-piece
		call drawopiece
		jmp rotate_right_end ; o-piece has only 1 rotation

	rotate_right_z: ; s-piece
		dec [current_piece_rotation] ; next position
		cmp [current_piece_rotation], 1 ; make it return to 1 after 2
		jnb rotate_right_z_draw ; make it return to 1 after 4
		mov [current_piece_rotation], 4 ; make it return to 1 after 2

	rotate_right_z_draw: ; draw s-piece
		mov ax, [square_size] ; move square size to a register (used for checking )

		cmp [current_piece_rotation], 1 ; rotate to first position
		je rotate_right_z_draw_1
		cmp [current_piece_rotation], 2 ; rotate to second positon
		je rotate_right_z_draw_2
		cmp [current_piece_rotation], 3 ; rotate to third positon
		je rotate_right_z_draw_3
		cmp [current_piece_rotation], 4 ; rotate to fourth positon
		je rotate_right_z_draw_4
		jmp rotate_right_end

	rotate_right_z_draw_1:
		call readpixel
		cmp [pixelcolour], 0 ; if the square that wasn't occupied is already occupied, don't rotate #1
		jne rotate_right_fail

		add [x_coordinate], ax
		add [x_coordinate], ax
		add [y_coordinate], ax
		call readpixel
		cmp [pixelcolour], 0 ; if the square that wasn't occupied is already occupied, don't rotate #2
		jne rotate_right_fail

		sub [x_coordinate], ax ; return to cursor's position
		sub [x_coordinate], ax
		sub [y_coordinate], ax

		call blackzPiece_2 ; delete second position
		call drawzPiece_1 ; draw first position
		jmp rotate_right_end

	rotate_right_z_draw_2:
		add [y_coordinate], ax
		add [y_coordinate], ax
		call readpixel
		cmp [pixelcolour], 0 ; if the square that wasn't occupied is already occupied, don't rotate #1
		jne rotate_right_fail

		sub [y_coordinate], ax
		sub [y_coordinate], ax
		add [x_coordinate], ax
		call readpixel
		cmp [pixelcolour], 0 ; if the square that wasn't occupied is already occupied, don't rotate #2
		jne rotate_right_fail

		sub [x_coordinate], ax ; return to cursor's position

		add [y_coordinate], ax
		call blackzPiece_1 ; delete third position
		sub [y_coordinate], ax
		call drawzPiece_2 ; draw second position
		jmp rotate_right_end

	rotate_right_z_draw_3:
		add [y_coordinate], ax
		call readpixel
		cmp [pixelcolour], 0 ; if the square that wasn't occupied is already occupied, don't rotate #1
		jne rotate_right_fail

		add [y_coordinate], ax
		add [x_coordinate], ax
		add [x_coordinate], ax
		call readpixel
		cmp [pixelcolour], 0 ; if the square that wasn't occupied is already occupied, don't rotate #2
		jne rotate_right_fail

		sub [x_coordinate], ax ; return to cursor's position
		sub [x_coordinate], ax
		sub [y_coordinate], ax
		sub [y_coordinate], ax

		add [x_coordinate], ax
		call blackzPiece_2 ; delete fourth position
		sub [x_coordinate], ax
		add [y_coordinate], ax
		call drawzPiece_1 ; draw third position
		sub [y_coordinate], ax
		jmp rotate_right_end

	rotate_right_z_draw_4:
		add [x_coordinate], ax
		add [x_coordinate], ax
		call readpixel
		cmp [pixelcolour], 0 ; if the square that wasn't occupied is already occupied, don't rotate #1
		jne rotate_right_fail

		sub [x_coordinate], ax
		add [y_coordinate], ax
		add [y_coordinate], ax
		call readpixel
		cmp [pixelcolour], 0 ; if the square that wasn't occupied is already occupied, don't rotate #2
		jne rotate_right_fail

		sub [x_coordinate], ax ; return to cursor's position
		sub [y_coordinate], ax
		sub [y_coordinate], ax

		call blackzPiece_1 ; delete first position
		add [x_coordinate], ax
		call drawzPiece_2 ; draw fourth position
		sub [x_coordinate], ax
		jmp rotate_right_end

	rotate_right_s: ; s-piece
		dec [current_piece_rotation] ; next position
		cmp [current_piece_rotation], 1 ; make it return to 1 after 2
		jnb rotate_right_s_draw ; make it return to 1 after 4
		mov [current_piece_rotation], 4 ; make it return to 1 after 2

	rotate_right_s_draw: ; draw s-piece
		mov ax, [square_size] ; move square size to a register (used for checking )

		cmp [current_piece_rotation], 1 ; rotate to first position
		je rotate_right_s_draw_1
		cmp [current_piece_rotation], 2 ; rotate to second positon
		je rotate_right_s_draw_2
		cmp [current_piece_rotation], 3 ; rotate to third positon
		je rotate_right_s_draw_3
		cmp [current_piece_rotation], 4 ; rotate to fourth positon
		je rotate_right_s_draw_4
		jmp rotate_right_end

	rotate_right_s_draw_1:
		add [x_coordinate], ax
		call readpixel
		cmp [pixelcolour], 0 ; if the square that wasn't occupied is already occupied, don't rotate #1
		jne rotate_right_fail

		add [x_coordinate], ax
		call readpixel
		cmp [pixelcolour], 0 ; if the square that wasn't occupied is already occupied, don't rotate #2
		jne rotate_right_fail

		sub [x_coordinate], ax ; return to cursor's position
		sub [x_coordinate], ax

		call blackSPiece_2 ; delete second position
		call drawSPiece_1 ; draw first position
		jmp rotate_right_end

	rotate_right_s_draw_2:
		call readpixel
		cmp [pixelcolour], 0 ; if the square that wasn't occupied is already occupied, don't rotate #1
		jne rotate_right_fail

		add [y_coordinate], ax
		call readpixel
		cmp [pixelcolour], 0 ; if the square that wasn't occupied is already occupied, don't rotate #2
		jne rotate_right_fail

		sub [y_coordinate], ax ; return to cursor's position

		add [y_coordinate], ax
		call blackSPiece_1 ; delete third position
		sub [y_coordinate], ax
		call drawSPiece_2 ; draw second position
		jmp rotate_right_end

	rotate_right_s_draw_3:
		add [y_coordinate], ax
		add [y_coordinate], ax
		call readpixel
		cmp [pixelcolour], 0 ; if the square that wasn't occupied is already occupied, don't rotate #1
		jne rotate_right_fail

		add [x_coordinate], ax
		call readpixel
		cmp [pixelcolour], 0 ; if the square that wasn't occupied is already occupied, don't rotate #2
		jne rotate_right_fail

		sub [x_coordinate], ax ; return to cursor's position
		sub [y_coordinate], ax
		sub [y_coordinate], ax

		add [x_coordinate], ax
		call blackSPiece_2 ; delete fourth position
		sub [x_coordinate], ax
		add [y_coordinate], ax
		call drawSPiece_1 ; draw third position
		sub [y_coordinate], ax
		jmp rotate_right_end

	rotate_right_s_draw_4:
		add [y_coordinate], ax
		add [x_coordinate], ax
		add [x_coordinate], ax
		call readpixel
		cmp [pixelcolour], 0 ; if the square that wasn't occupied is already occupied, don't rotate #1
		jne rotate_right_fail

		add [y_coordinate], ax
		call readpixel
		cmp [pixelcolour], 0 ; if the square that wasn't occupied is already occupied, don't rotate #2
		jne rotate_right_fail

		sub [x_coordinate], ax ; return to cursor's position
		sub [x_coordinate], ax
		sub [y_coordinate], ax
		sub [y_coordinate], ax

		call blackSPiece_1 ; delete fourth position
		add [x_coordinate], ax
		call drawSPiece_2 ; draw third position
		sub [x_coordinate], ax
		jmp rotate_right_end

	rotate_right_i: ; i-piece
		dec [current_piece_rotation] ; next position
		cmp [current_piece_rotation], 1 ; make it return to 1 after 2
		jnb rotate_right_i_draw ; make it return to 1 after 4
		mov [current_piece_rotation], 4 ; make it return to 1 after 2

	rotate_right_i_draw: ; draw i-piece
		mov ax, [square_size] ; move square size to a register (used for checking )

		cmp [current_piece_rotation], 1 ; rotate to first position
		je rotate_right_i_draw_1
		cmp [current_piece_rotation], 2 ; rotate to second positon
		je rotate_right_i_draw_2
		cmp [current_piece_rotation], 3 ; rotate to third positon
		je rotate_right_i_draw_3
		cmp [current_piece_rotation], 4 ; rotate to fourth positon
		je rotate_right_i_draw_4
		jmp rotate_right_end

	rotate_right_i_draw_1:
		call readpixel
		cmp [pixelcolour], 0 ; if the square that wasn't occupied is already occupied, don't rotate #1
		jne rotate_right_fail

		add [x_coordinate], ax
		add [x_coordinate], ax
		call readpixel
		cmp [pixelcolour], 0 ; if the square that wasn't occupied is already occupied, don't rotate #2
		jne rotate_right_fail

		add [x_coordinate], ax
		call readpixel
		cmp [pixelcolour], 0 ; if the square that wasn't occupied is already occupied, don't rotate #3
		jne rotate_right_fail

		sub [x_coordinate], ax ; return to cursor's position
		sub [x_coordinate], ax
		sub [x_coordinate], ax

		call blackipiece_2 ; delete second position
		call drawipiece_1 ; draw first position
		jmp rotate_right_end

	rotate_right_i_draw_2:
		call readpixel
		cmp [pixelcolour], 0 ; if the square that wasn't occupied is already occupied, don't rotate #1
		jne rotate_right_fail

		add [y_coordinate], ax
		call readpixel
		cmp [pixelcolour], 0 ; if the square that wasn't occupied is already occupied, don't rotate #2
		jne rotate_right_fail

		add [y_coordinate], ax
		add [y_coordinate], ax
		call readpixel
		cmp [pixelcolour], 0 ; if the square that wasn't occupied is already occupied, don't rotate #3
		jne rotate_right_fail

		sub [y_coordinate], ax ; return to cursor's position
		sub [y_coordinate], ax
		sub [y_coordinate], ax

		add [y_coordinate], ax
		call blackipiece_1 ; delete third position
		sub [y_coordinate], ax
		call drawipiece_2 ; draw second position
		jmp rotate_right_end

	rotate_right_i_draw_3:
		add [y_coordinate], ax
		add [y_coordinate], ax
		call readpixel
		cmp [pixelcolour], 0 ; if the square that wasn't occupied is already occupied, don't rotate #1
		jne rotate_right_fail

		add [x_coordinate], ax
		call readpixel
		cmp [pixelcolour], 0 ; if the square that wasn't occupied is already occupied, don't rotate #2
		jne rotate_right_fail

		add [x_coordinate], ax
		add [x_coordinate], ax
		call readpixel
		cmp [pixelcolour], 0 ; if the square that wasn't occupied is already occupied, don't rotate #3
		jne rotate_right_fail

		sub [y_coordinate], ax ; return to cursor's position
		sub [y_coordinate], ax
		sub [x_coordinate], ax
		sub [x_coordinate], ax
		sub [x_coordinate], ax

		add [x_coordinate], ax
		call blackipiece_2 ; delete fourth position
		sub [x_coordinate], ax
		add [y_coordinate], ax
		call drawipiece_1 ; draw third position
		sub [y_coordinate], ax
		jmp rotate_right_end

	rotate_right_i_draw_4:
		add [x_coordinate], ax
		add [x_coordinate], ax
		call readpixel
		cmp [pixelcolour], 0 ; if the square that wasn't occupied is already occupied, don't rotate #1
		jne rotate_right_fail

		add [y_coordinate], ax
		add [y_coordinate], ax
		call readpixel
		cmp [pixelcolour], 0 ; if the square that wasn't occupied is already occupied, don't rotate #2
		jne rotate_right_fail

		add [y_coordinate], ax
		call readpixel
		cmp [pixelcolour], 0 ; if the square that wasn't occupied is already occupied, don't rotate #3
		jne rotate_right_fail

		sub [y_coordinate], ax ; return to cursor's position
		sub [y_coordinate], ax
		sub [y_coordinate], ax
		sub [x_coordinate], ax
		sub [x_coordinate], ax

		call blackipiece_1 ; delete first position
		add [x_coordinate], ax
		call drawipiece_2 ; draw fourth position
		sub [x_coordinate], ax
		jmp rotate_right_end

	rotate_right_l: ; l-piece
		dec [current_piece_rotation] ; previouse position
		cmp [current_piece_rotation], 0 ; make it return to 4 after 1
		jne rotate_right_l_draw ; make it return to 4 after 1
		mov [current_piece_rotation], 4 ; make it return to 4 after 1

	rotate_right_l_draw: ; draw l-piece
		mov ax, [square_size] ; move square size to a register (used for checking )

		cmp [current_piece_rotation], 1 ; rotate to first position
		je rotate_right_l_draw_1
		cmp [current_piece_rotation], 2 ; rotate to second positon
		je rotate_right_l_draw_2
		cmp [current_piece_rotation], 3 ; rotate to third positon
		je rotate_right_l_draw_3
		cmp [current_piece_rotation], 4 ; rotate to 4rth positon
		je rotate_right_l_draw_4
		jmp rotate_right_fail

	rotate_right_l_draw_1:
		add [x_coordinate], ax
		call readpixel
		cmp [pixelcolour], 0 ; if the square that wasn't occupied is already occupied, don't rotate #1
		jne rotate_right_fail

		add [x_coordinate], ax
		call readpixel
		cmp [pixelcolour], 0 ; if the square that wasn't occupied is already occupied, don't rotate #2
		jne rotate_right_fail

		sub [x_coordinate], ax ; return to cursor's position
		sub [x_coordinate], ax

		call blacklpiece_2 ; delete fourth position
		call drawlpiece_1 ; draw first position
		jmp rotate_right_end

	rotate_right_l_draw_2:
		call readpixel
		cmp [pixelcolour], 0 ; if the square that wasn't occupied is already occupied, don't rotate #1
		jne rotate_right_fail

		add [y_coordinate], ax
		call readpixel
		cmp [pixelcolour], 0 ; if the square that wasn't occupied is already occupied, don't rotate #2
		jne rotate_right_fail

		sub [y_coordinate], ax ; return to cursor's position

		call blacklpiece_3 ; delete fourth position
		call drawlpiece_2 ; draw first position
		jmp rotate_right_end

	rotate_right_l_draw_3:
		add [y_coordinate], ax
		add [y_coordinate], ax
		call readpixel
		cmp [pixelcolour], 0 ; if the square that wasn't occupied is already occupied, don't rotate #1
		jne rotate_right_fail

		add [x_coordinate], ax
		call readpixel
		cmp [pixelcolour], 0 ; if the square that wasn't occupied is already occupied, don't rotate #2
		jne rotate_right_fail

		sub [y_coordinate], ax ; return to cursor's position
		sub [y_coordinate], ax
		sub [x_coordinate], ax

		call blacklpiece_4 ; delete fourth position
		call drawlpiece_3 ; draw first position
		jmp rotate_right_end

	rotate_right_l_draw_4:
		add [y_coordinate], ax
		add [y_coordinate], ax
		add [x_coordinate], ax
		add [x_coordinate], ax
		call readpixel
		cmp [pixelcolour], 0 ; if the square that wasn't occupied is already occupied, don't rotate #1
		jne rotate_right_fail

		sub [y_coordinate], ax
		call readpixel
		cmp [pixelcolour], 0 ; if the square that wasn't occupied is already occupied, don't rotate #2
		jne rotate_right_fail

		sub [y_coordinate], ax ; return to cursor's position
		sub [x_coordinate], ax
		sub [x_coordinate], ax

		call blacklpiece_1 ; delete fourth position
		call drawlpiece_4 ; draw first position
		jmp rotate_right_end

	rotate_right_j: ; j-piece
		dec [current_piece_rotation] ; previouse position
		cmp [current_piece_rotation], 0 ; make it return to 4 after 1
		jne rotate_right_j_draw ; make it return to 4 after 1
		mov [current_piece_rotation], 4 ; make it return to 4 after 1

	rotate_right_j_draw: ; draw j-piece
		mov ax, [square_size] ; move square size to a register (used for checking )

		cmp [current_piece_rotation], 1 ; rotate to first position
		je rotate_right_j_draw_1
		cmp [current_piece_rotation], 2 ; rotate to second positon
		je rotate_right_j_draw_2
		cmp [current_piece_rotation], 3 ; rotate to third positon
		je rotate_right_j_draw_3
		cmp [current_piece_rotation], 4 ; rotate to 4rth positon
		je rotate_right_j_draw_4
		jmp rotate_right_fail

	rotate_right_j_draw_1:
		add [x_coordinate], ax
		add [x_coordinate], ax
		call readpixel
		cmp [pixelcolour], 0 ; if the square that wasn't occupied is already occupied, don't rotate #1
		jne rotate_right_fail

		add [y_coordinate], ax
		call readpixel
		cmp [pixelcolour], 0 ; if the square that wasn't occupied is already occupied, don't rotate #2
		jne rotate_right_fail

		sub [y_coordinate], ax ; return to cursor's position
		sub [x_coordinate], ax
		sub [x_coordinate], ax

		call blackjpiece_2 ; delete fourth position
		call drawjpiece_1 ; draw first position
		jmp rotate_right_end

	rotate_right_j_draw_2:
		call readpixel
		cmp [pixelcolour], 0 ; if the square that wasn't occupied is already occupied, don't rotate #1
		jne rotate_right_fail

		add [x_coordinate], ax
		call readpixel
		cmp [pixelcolour], 0 ; if the square that wasn't occupied is already occupied, don't rotate #2
		jne rotate_right_fail

		sub [x_coordinate], ax ; return to cursor's position

		call blackjpiece_3 ; delete fourth position
		call drawjpiece_2 ; draw first position
		jmp rotate_right_end

	rotate_right_j_draw_3:
		add [y_coordinate], ax
		call readpixel
		cmp [pixelcolour], 0 ; if the square that wasn't occupied is already occupied, don't rotate #1
		jne rotate_right_fail

		add [y_coordinate], ax
		call readpixel
		cmp [pixelcolour], 0 ; if the square that wasn't occupied is already occupied, don't rotate #2
		jne rotate_right_fail

		sub [y_coordinate], ax ; return to cursor's position
		sub [y_coordinate], ax

		call blackjpiece_4 ; delete fourth position
		call drawjpiece_3 ; draw first position
		jmp rotate_right_end

	rotate_right_j_draw_4:
		add [y_coordinate], ax
		add [y_coordinate], ax
		add [x_coordinate], ax
		call readpixel
		cmp [pixelcolour], 0 ; if the square that wasn't occupied is already occupied, don't rotate #1
		jne rotate_right_fail

		add [x_coordinate], ax
		call readpixel
		cmp [pixelcolour], 0 ; if the square that wasn't occupied is already occupied, don't rotate #2
		jne rotate_right_fail

		sub [y_coordinate], ax ; return to cursor's position
		sub [y_coordinate], ax
		sub [x_coordinate], ax
		sub [x_coordinate], ax

		call blackjpiece_1 ; delete fourth position
		call drawjpiece_4 ; draw first position
		jmp rotate_right_end
		
	rotate_right_t: ; t-piece
		dec [current_piece_rotation] ; previouse position
		cmp [current_piece_rotation], 0 ; make it return to 4 after 1
		jne rotate_right_t_draw ; make it return to 4 after 1
		mov [current_piece_rotation], 4 ; make it return to 4 after 1

	rotate_right_t_draw: ; draw t-piece
		mov ax, [square_size] ; move square size to a register (used for checking )

		cmp [current_piece_rotation], 1 ; rotate to first position
		je rotate_right_t_draw_1
		cmp [current_piece_rotation], 2 ; rotate to second positon
		je rotate_right_t_draw_2
		cmp [current_piece_rotation], 3 ; rotate to third positon
		je rotate_right_t_draw_3
		cmp [current_piece_rotation], 4 ; rotate to 4rth positon
		je rotate_right_t_draw_4
		jmp rotate_right_fail

	rotate_right_t_draw_1: ; rotate to first position ;y+1
		add [y_coordinate], ax
		add [x_coordinate], ax
		add [x_coordinate], ax
		call readpixel
		cmp [pixelcolour], 0 ; if the square that wasn't occupied is already occupied, don't rotate
		jne rotate_right_fail
		sub [y_coordinate], ax
		sub [x_coordinate], ax
		sub [x_coordinate], ax

		call blacktpiece_2 ; delete second position
		call drawtpiece_1 ; draw first position
		jmp rotate_right_end

	rotate_right_t_draw_2: ; rotate to second position
		add [x_coordinate], ax
		call readpixel
		cmp [pixelcolour], 0 ; if the square that wasn't occupied is already occupied, don't rotate
		jne rotate_right_fail
		sub [x_coordinate], ax

		call blacktpiece_3 ; delete third position
		call drawtpiece_2 ; draw second position
		jmp rotate_right_end

	rotate_right_t_draw_3: ; rotate to third position
		add [y_coordinate], ax
		call readpixel
		cmp [pixelcolour], 0 ; if the square that wasn't occupied is already occupied, don't rotate
		jne rotate_right_fail
		sub [y_coordinate], ax

		call blacktpiece_4 ; delete fourth position
		call drawtpiece_3 ; draw third position
		jmp rotate_right_end

	rotate_right_t_draw_4: ; rotate to fourth position
		add [x_coordinate], ax
		add [y_coordinate], ax
		add [y_coordinate], ax
		call readpixel
		cmp [pixelcolour], 0 ; if the square that wasn't occupied is already occupied, don't rotate
		jne rotate_right_fail
		sub [x_coordinate], ax
		sub [y_coordinate], ax
		sub [y_coordinate], ax

		call blacktpiece_1 ; delete first position
		call drawtpiece_4 ; draw fourth position
		jmp rotate_right_end
		
	rotate_right_fail:
		cmp [current_piece_rotation], 4
		je rotate_right_fail_1
		inc [current_piece_rotation]
		jmp rotate_right_end

	rotate_right_fail_1:
		mov [current_piece_rotation], 1

	rotate_right_end:
		pop [y_coordinate]
		pop [x_coordinate]
		pop ax
		ret
endp rotate_right

proc move_left
		push ax
		push [y_coordinate]
		push [x_coordinate]
		
		mov ax, [square_size] ; square size in a register

		cmp [current_piece], 0
		je move_left_t ; if t-piece
		cmp [current_piece], 1
		je move_left_o ; if o-piece
		cmp [current_piece], 2
		je move_left_j ; if j-piece
		cmp [current_piece], 3
		je move_left_l ; if l-piece
		cmp [current_piece], 4
		je move_left_i ; if i-piece
		cmp [current_piece], 5
		je move_left_s ; if s-piece
		cmp [current_piece], 6
		je move_left_z ; if z-piece
		jmp move_left_end

	move_left_o:
		call readpixel
		cmp [pixelcolour], 0 ; don't move left if it's blocked - row 1
		jne move_left_end

		add [y_coordinate], ax
		call readpixel
		cmp [pixelcolour], 0 ; don't move left if it's blocked - row 2
		jne move_left_end

		sub [y_coordinate], ax ; return to cursor position

		pop [x_coordinate] ; momenteraly pop x_coordinate in order to permenantly change it

		call blackopiece ; erase piece
		sub [x_coordinate], ax
		call drawopiece ; redraw it one square left

		push [x_coordinate] ; push x_coordinate back before jumping to the end to not mess up the pop at the end
		jmp move_left_end

	move_left_z:
		cmp [current_piece_rotation], 1 ; different actions based on rotation
		je move_left_z_1
		cmp [current_piece_rotation], 2
		je move_left_z_2
		cmp [current_piece_rotation], 3
		je move_left_z_3
		cmp [current_piece_rotation], 4
		je move_left_z_4
		jmp move_left_end

	move_left_z_1:
		sub [x_coordinate], ax
		call readpixel
		cmp [pixelcolour], 0 ; don't move left if it's blocked - row 1
		jne move_left_end

		add [x_coordinate], ax
		add [y_coordinate], ax
		call readpixel
		cmp [pixelcolour], 0 ; don't move left if it's blocked - row 2
		jne move_left_end

		sub [x_coordinate], ax ; return to cursor's position
		sub [y_coordinate], ax

		pop [x_coordinate] ; momenteraly pop x_coordinate in order to permenantly change it
		
		call blackZPiece_1 ; erase piece
		sub [x_coordinate], ax
		call drawZPiece_1 ; redraw it one square left

		push [x_coordinate] ; push x_coordinate back before jumping to the end to not mess up the pop at the end
		jmp move_left_end

	move_left_z_2:
		call readpixel
		cmp [pixelcolour], 0 ; don't move left if it's blocked - row 1
		jne move_left_end

		sub [x_coordinate], ax
		add [y_coordinate], ax
		call readpixel
		cmp [pixelcolour], 0 ; don't move left if it's blocked - row 2
		jne move_left_end

		add [y_coordinate], ax
		call readpixel
		cmp [pixelcolour], 0 ; don't move left if it's blocked - row 3
		jne move_left_end

		add [x_coordinate], ax ; return to cursor's position
		sub [y_coordinate], ax
		sub [y_coordinate], ax

		pop [x_coordinate] ; momenteraly pop x_coordinate in order to permenantly change it
		
		call blackZPiece_2 ; erase piece
		sub [x_coordinate], ax
		call drawZPiece_2 ; redraw it one square left

		push [x_coordinate] ; push x_coordinate back before jumping to the end to not mess up the pop at the end
		jmp move_left_end

	move_left_z_3:
		add [y_coordinate], ax
		sub [x_coordinate], ax
		call readpixel
		cmp [pixelcolour], 0 ; don't move left if it's blocked - row 2
		jne move_left_end

		add [x_coordinate], ax
		add [y_coordinate], ax
		call readpixel
		cmp [pixelcolour], 0 ; don't move left if it's blocked - row 3
		jne move_left_end

		sub [x_coordinate], ax ; return to cursor's position
		sub [y_coordinate], ax
		sub [y_coordinate], ax

		pop [x_coordinate] ; momenteraly pop x_coordinate in order to permenantly change it
		add [y_coordinate], ax
		call blackZPiece_1 ; erase piece
		sub [x_coordinate], ax
		call drawZPiece_1 ; redraw it one square left
		sub [y_coordinate], ax

		push [x_coordinate] ; push x_coordinate back before jumping to the end to not mess up the pop at the end
		jmp move_left_end

	move_left_z_4:
		add [x_coordinate], ax
		call readpixel
		cmp [pixelcolour], 0 ; don't move left if it's blocked - row 1
		jne move_left_end

		sub [x_coordinate], ax
		add [y_coordinate], ax
		call readpixel
		cmp [pixelcolour], 0 ; don't move left if it's blocked - row 2
		jne move_left_end

		add [y_coordinate], ax
		call readpixel
		cmp [pixelcolour], 0 ; don't move left if it's blocked - row 3
		jne move_left_end

		sub [y_coordinate], ax ; return to cursor's position
		sub [y_coordinate], ax

		pop [x_coordinate] ; momenteraly pop x_coordinate in order to permenantly change it
		
		add [x_coordinate], ax
		call blackZPiece_2 ; erase piece
		sub [x_coordinate], ax
		call drawZPiece_2 ; redraw it one square left
		sub [x_coordinate], ax

		push [x_coordinate] ; push x_coordinate back before jumping to the end to not mess up the pop at the end
		jmp move_left_end

	move_left_s:
		cmp [current_piece_rotation], 1 ; different actions based on rotation
		je move_left_s_1
		cmp [current_piece_rotation], 2
		je move_left_s_2
		cmp [current_piece_rotation], 3
		je move_left_s_3
		cmp [current_piece_rotation], 4
		je move_left_s_4
		jmp move_left_end

	move_left_s_1:
		call readpixel
		cmp [pixelcolour], 0 ; don't move left if it's blocked - row 1
		jne move_left_end

		sub [x_coordinate], ax
		add [y_coordinate], ax
		call readpixel
		cmp [pixelcolour], 0 ; don't move left if it's blocked - row 2
		jne move_left_end

		add [x_coordinate], ax ; return to cursor's position
		sub [y_coordinate], ax

		pop [x_coordinate] ; momenteraly pop x_coordinate in order to permenantly change it
		
		call blackSPiece_1 ; erase piece
		sub [x_coordinate], ax
		call drawSPiece_1 ; redraw it one square left

		push [x_coordinate] ; push x_coordinate back before jumping to the end to not mess up the pop at the end
		jmp move_left_end

	move_left_s_2:
		sub [x_coordinate], ax
		call readpixel
		cmp [pixelcolour], 0 ; don't move left if it's blocked - row 1
		jne move_left_end

		add [y_coordinate], ax
		call readpixel
		cmp [pixelcolour], 0 ; don't move left if it's blocked - row 2
		jne move_left_end

		add [y_coordinate], ax
		add [x_coordinate], ax
		call readpixel
		cmp [pixelcolour], 0 ; don't move left if it's blocked - row 3
		jne move_left_end

		sub [y_coordinate], ax ; return to cursor's position
		sub [y_coordinate], ax

		pop [x_coordinate] ; momenteraly pop x_coordinate in order to permenantly change it
		
		call blackSPiece_2 ; erase piece
		sub [x_coordinate], ax
		call drawSPiece_2 ; redraw it one square left

		push [x_coordinate] ; push x_coordinate back before jumping to the end to not mess up the pop at the end
		jmp move_left_end

	move_left_s_3:
		add [y_coordinate], ax
		call readpixel
		cmp [pixelcolour], 0 ; don't move left if it's blocked - row 1
		jne move_left_end

		sub [x_coordinate], ax
		add [y_coordinate], ax
		call readpixel
		cmp [pixelcolour], 0 ; don't move left if it's blocked - row 2
		jne move_left_end

		sub [y_coordinate], ax ; return to cursor's position
		sub [y_coordinate], ax
		add [x_coordinate], ax

		pop [x_coordinate] ; momenteraly pop x_coordinate in order to permenantly change it
		
		add [y_coordinate], ax
		call blackSPiece_1 ; erase piece
		sub [x_coordinate], ax
		call drawSPiece_1 ; redraw it one square left
		sub [y_coordinate], ax

		push [x_coordinate] ; push x_coordinate back before jumping to the end to not mess up the pop at the end
		jmp move_left_end

	move_left_s_4:
		call readpixel
		cmp [pixelcolour], 0 ; don't move left if it's blocked - row 1
		jne move_left_end

		add [y_coordinate], ax
		call readpixel
		cmp [pixelcolour], 0 ; don't move left if it's blocked - row 2
		jne move_left_end

		add [y_coordinate], ax
		add [x_coordinate], ax
		call readpixel
		cmp [pixelcolour], 0 ; don't move left if it's blocked - row 2
		jne move_left_end

		sub [y_coordinate], ax ; return to cursor's position
		sub [y_coordinate], ax
		sub [x_coordinate], ax

		pop [x_coordinate] ; momenteraly pop x_coordinate in order to permenantly change it
		
		add [x_coordinate], ax
		call blackSPiece_2 ; erase piece
		sub [x_coordinate], ax
		call drawSPiece_2 ; redraw it one square left
		sub [x_coordinate], ax

		push [x_coordinate] ; push x_coordinate back before jumping to the end to not mess up the pop at the end
		jmp move_left_end

	move_left_i:
		cmp [current_piece_rotation], 1 ; different actions based on rotation
		je move_left_i_1
		cmp [current_piece_rotation], 2
		je move_left_i_2
		cmp [current_piece_rotation], 3
		je move_left_i_3
		cmp [current_piece_rotation], 4
		je move_left_i_4
		jmp move_left_end

	move_left_i_1:
		sub [x_coordinate], ax
		add [y_coordinate], ax
		call readpixel
		cmp [pixelcolour], 0 ; don't move left if it's blocked - row 2
		jne move_left_end

		add [x_coordinate], ax ; return to cursor's position
		sub [y_coordinate], ax

		pop [x_coordinate] ; momenteraly pop x_coordinate in order to permenantly change it
		
		call blackipiece_1 ; erase piece
		sub [x_coordinate], ax
		call drawipiece_1 ; redraw it one square left

		push [x_coordinate] ; push x_coordinate back before jumping to the end to not mess up the pop at the end
		jmp move_left_end

	move_left_i_2:
		call readpixel
		cmp [pixelcolour], 0 ; don't move left if it's blocked - row 1
		jne move_left_end

		add [y_coordinate], ax
		call readpixel
		cmp [pixelcolour], 0 ; don't move left if it's blocked - row 2
		jne move_left_end
		
		add [y_coordinate], ax
		call readpixel
		cmp [pixelcolour], 0 ; don't move left if it's blocked - row 3
		jne move_left_end

		add [y_coordinate], ax
		call readpixel
		cmp [pixelcolour], 0 ; don't move left if it's blocked - row 4
		jne move_left_end

		sub [y_coordinate], ax ; return to cursor's position
		sub [y_coordinate], ax
		sub [y_coordinate], ax

		pop [x_coordinate] ; momenteraly pop x_coordinate in order to permenantly change it
		
		call blackipiece_2 ; erase piece
		sub [x_coordinate], ax
		call drawipiece_2 ; redraw it one square left

		push [x_coordinate] ; push x_coordinate back before jumping to the end to not mess up the pop at the end
		jmp move_left_end

	move_left_i_3:
		sub [x_coordinate], ax
		add [y_coordinate], ax
		add [y_coordinate], ax
		call readpixel
		cmp [pixelcolour], 0 ; don't move left if it's blocked - row 2
		jne move_left_end

		add [x_coordinate], ax ; return to cursor's position
		sub [y_coordinate], ax
		sub [y_coordinate], ax

		pop [x_coordinate] ; momenteraly pop x_coordinate in order to permenantly change it
		
		add [y_coordinate], ax
		call blackipiece_1 ; erase piece
		sub [x_coordinate], ax
		call drawipiece_1 ; redraw it one square left
		sub [y_coordinate], ax

		push [x_coordinate] ; push x_coordinate back before jumping to the end to not mess up the pop at the end
		jmp move_left_end

	move_left_i_4:
		add [x_coordinate], ax
		call readpixel
		cmp [pixelcolour], 0 ; don't move left if it's blocked - row 1
		jne move_left_end

		add [y_coordinate], ax
		call readpixel
		cmp [pixelcolour], 0 ; don't move left if it's blocked - row 2
		jne move_left_end
		
		add [y_coordinate], ax
		call readpixel
		cmp [pixelcolour], 0 ; don't move left if it's blocked - row 3
		jne move_left_end

		add [y_coordinate], ax
		call readpixel
		cmp [pixelcolour], 0 ; don't move left if it's blocked - row 4
		jne move_left_end

		sub [y_coordinate], ax ; return to cursor's position
		sub [y_coordinate], ax
		sub [y_coordinate], ax
		sub [x_coordinate], ax

		pop [x_coordinate] ; momenteraly pop x_coordinate in order to permenantly change it
		
		add [x_coordinate], ax
		call blackipiece_2 ; erase piece
		sub [x_coordinate], ax
		call drawipiece_2 ; redraw it one square left
		sub [x_coordinate], ax

		push [x_coordinate] ; push x_coordinate back before jumping to the end to not mess up the pop at the end
		jmp move_left_end

	move_left_l:
		cmp [current_piece_rotation], 1 ; different actions based on rotation
		je move_left_l_1
		cmp [current_piece_rotation], 2
		je move_left_l_2
		cmp [current_piece_rotation], 3
		je move_left_l_3
		cmp [current_piece_rotation], 4
		je move_left_l_4
		jmp move_left_end

	move_left_l_1:
		sub [x_coordinate], ax
		call readpixel
		cmp [pixelcolour], 0 ; don't move left if it's blocked - row 1
		jne move_left_end
		
		add [y_coordinate], ax
		call readpixel
		cmp [pixelcolour], 0 ; don't move left if it's blocked - row 2
		jne move_left_end

		; l-piece 1st position has no third row so there's no point in checking it

		sub [y_coordinate], ax ; return to cursor's position
		add [x_coordinate], ax

		pop [x_coordinate] ; momenteraly pop x_coordinate in order to permenantly change it
		
		call blacklpiece_1 ; erase piece
		sub [x_coordinate], ax
		call drawlpiece_1 ; redraw it one square left

		push [x_coordinate] ; push x_coordinate back before jumping to the end to not mess up the pop at the end
		jmp move_left_end

	move_left_l_2:
		sub [x_coordinate], ax
		call readpixel
		cmp [pixelcolour], 0 ; don't move left if it's blocked - row 1
		jne move_left_end
		
		add [y_coordinate], ax
		call readpixel
		cmp [pixelcolour], 0 ; don't move left if it's blocked - row 2
		jne move_left_end

		add [y_coordinate], ax
		call readpixel
		cmp [pixelcolour], 0 ; don't move left if it's blocked - row 3
		jne move_left_end

		sub [y_coordinate], ax ; return to cursor's position
		sub [y_coordinate], ax
		add [x_coordinate], ax

		pop [x_coordinate] ; momenteraly pop x_coordinate in order to permenantly change it
		
		call blacklpiece_2 ; erase piece
		sub [x_coordinate], ax
		call drawlpiece_2 ; redraw it one square left

		push [x_coordinate] ; push x_coordinate back before jumping to the end to not mess up the pop at the end
		jmp move_left_end

	move_left_l_3:
		; l-piece 1st position has no first row so there's no point in checking it
		
		add [y_coordinate], ax
		add [x_coordinate], ax
		call readpixel
		cmp [pixelcolour], 0 ; don't move left if it's blocked - row 2
		jne move_left_end

		sub [x_coordinate], ax
		sub [x_coordinate], ax
		add [y_coordinate], ax
		call readpixel
		cmp [pixelcolour], 0 ; don't move left if it's blocked - row 3
		jne move_left_end

		sub [y_coordinate], ax ; return to cursor's position
		sub [y_coordinate], ax
		add [x_coordinate], ax

		pop [x_coordinate] ; momenteraly pop x_coordinate in order to permenantly change it
		
		call blacklpiece_3 ; erase piece
		sub [x_coordinate], ax
		call drawlpiece_3 ; redraw it one square left

		push [x_coordinate] ; push x_coordinate back before jumping to the end to not mess up the pop at the end
		jmp move_left_end

	move_left_l_4:
		call readpixel
		cmp [pixelcolour], 0 ; don't move left if it's blocked - row 1
		jne move_left_end

		add [y_coordinate], ax
		add [x_coordinate], ax
		call readpixel
		cmp [pixelcolour], 0 ; don't move left if it's blocked - row 2
		jne move_left_end

		add [y_coordinate], ax
		call readpixel
		cmp [pixelcolour], 0 ; don't move left if it's blocked - row 3
		jne move_left_end

		sub [y_coordinate], ax ; return to cursor's position
		sub [y_coordinate], ax
		sub [x_coordinate], ax

		pop [x_coordinate] ; momenteraly pop x_coordinate in order to permenantly change it
		
		call blacklpiece_4 ; erase piece
		sub [x_coordinate], ax
		call drawlpiece_4 ; redraw it one square left

		push [x_coordinate] ; push x_coordinate back before jumping to the end to not mess up the pop at the end
		jmp move_left_end

	move_left_j:
		cmp [current_piece_rotation], 1 ; different actions based on rotation
		je move_left_j_1
		cmp [current_piece_rotation], 2
		je move_left_j_2
		cmp [current_piece_rotation], 3
		je move_left_j_3
		cmp [current_piece_rotation], 4
		je move_left_j_4
		jmp move_left_end

	move_left_j_1:
		sub [x_coordinate], ax
		call readpixel
		cmp [pixelcolour], 0 ; don't move left if it's blocked - row 1
		jne move_left_end
		
		add [y_coordinate], ax
		add [x_coordinate], ax
		add [x_coordinate], ax
		call readpixel
		cmp [pixelcolour], 0 ; don't move left if it's blocked - row 2
		jne move_left_end

		; j-piece 1st position has no third row so there's no point in checking it

		sub [x_coordinate], ax ; return to cursor's position
		sub [y_coordinate], ax

		pop [x_coordinate] ; momenteraly pop x_coordinate in order to permenantly change it
		
		call blackjpiece_1 ; erase piece
		sub [x_coordinate], ax
		call drawjpiece_1 ; redraw it one square left

		push [x_coordinate] ; push x_coordinate back before jumping to the end to not mess up the pop at the end
		jmp move_left_end

	move_left_j_2:
		sub [x_coordinate], ax
		call readpixel
		cmp [pixelcolour], 0 ; don't move left if it's blocked - row 1
		jne move_left_end
		
		add [y_coordinate], ax
		call readpixel
		cmp [pixelcolour], 0 ; don't move left if it's blocked - row 2
		jne move_left_end

		add [y_coordinate], ax
		call readpixel
		cmp [pixelcolour], 0 ; don't move left if it's blocked - row 3
		jne move_left_end

		sub [y_coordinate], ax ; return to cursor position
		sub [y_coordinate], ax
		add [x_coordinate], ax

		pop [x_coordinate] ; momenteraly pop x_coordinate in order to permenantly change it
		
		call blackjpiece_2 ; erase piece
		sub [x_coordinate], ax
		call drawjpiece_2 ; redraw it one square left

		push [x_coordinate] ; push x_coordinate back before jumping to the end to not mess up the pop at the end
		jmp move_left_end

	move_left_j_3:
		; j-piece 1st position has no first row so there's no point in checking it

		add [y_coordinate], ax
		sub [x_coordinate], ax
		call readpixel
		cmp [pixelcolour], 0 ; don't move left if it's blocked - row 2
		jne move_left_end
		
		add [y_coordinate], ax
		call readpixel
		cmp [pixelcolour], 0 ; don't move left if it's blocked - row 3
		jne move_left_end

		sub [y_coordinate], ax ; return to cursor position
		sub [y_coordinate], ax ; return to cursor position
		add [x_coordinate], ax

		pop [x_coordinate] ; momenteraly pop x_coordinate in order to permenantly change it
		
		call blackjpiece_3 ; erase piece
		sub [x_coordinate], ax
		call drawjpiece_3 ; redraw it one square left

		push [x_coordinate] ; push x_coordinate back before jumping to the end to not mess up the pop at the end
		jmp move_left_end

	move_left_j_4:
		add [x_coordinate], ax
		call readpixel
		cmp [pixelcolour], 0 ; don't move left if it's blocked - row 1
		jne move_left_end
		
		add [y_coordinate], ax
		call readpixel
		cmp [pixelcolour], 0 ; don't move left if it's blocked - row 2
		jne move_left_end

		sub [x_coordinate], ax
		add [y_coordinate], ax
		call readpixel
		cmp [pixelcolour], 0 ; don't move left if it's blocked - row 2
		jne move_left_end

		sub [y_coordinate], ax ; return to cursor position
		sub [y_coordinate], ax

		pop [x_coordinate] ; momenteraly pop x_coordinate in order to permenantly change it
		
		call blackjpiece_4 ; erase piece
		sub [x_coordinate], ax
		call drawjpiece_4 ; redraw it one square left

		push [x_coordinate] ; push x_coordinate back before jumping to the end to not mess up the pop at the end
		jmp move_left_end

	move_left_t:
		cmp [current_piece_rotation], 1 ; different actions based on rotation
		je move_left_t_1
		cmp [current_piece_rotation], 2
		je move_left_t_2
		cmp [current_piece_rotation], 3
		je move_left_t_3
		cmp [current_piece_rotation], 4
		je move_left_t_4
		jmp move_left_end

	move_left_t_1:
		call readpixel
		cmp [pixelcolour], 0 ; don't move left if it's blocked - row 1
		jne move_left_end

		sub [x_coordinate], ax
		add [y_coordinate], ax
		call readpixel
		cmp [pixelcolour], 0 ; don't move left if it's blocked - row 2
		jne move_left_end

		; t-piece 1st position has no first row so there's no point in checking it

		sub [y_coordinate], ax ; return to cursor position
		add [x_coordinate], ax

		pop [x_coordinate] ; momenteraly pop x_coordinate in order to permenantly change it

		call blacktpiece_1 ; erase piece
		sub [x_coordinate], ax
		call drawtpiece_1 ; redraw it one square left

		push [x_coordinate] ; push x_coordinate back before jumping to the end to not mess up the pop at the end
		jmp move_left_end

	move_left_t_2:
		call readpixel
		cmp [pixelcolour], 0 ; don't move left if it's blocked - row 1
		jne move_left_end

		sub [x_coordinate], ax
		add [y_coordinate], ax
		call readpixel
		cmp [pixelcolour], 0 ; don't move left if it's blocked - row 2
		jne move_left_end
		add [x_coordinate], ax

		add [y_coordinate], ax
		call readpixel
		cmp [pixelcolour], 0 ; don't move left if it's blocked - row 3
		jne move_left_end

		sub [y_coordinate], ax ; return to cursor position
		sub [y_coordinate], ax

		pop [x_coordinate] ; momenteraly pop x_coordinate in order to permenantly change it

		call blacktpiece_2 ; erase piece
		sub [x_coordinate], ax
		call drawtpiece_2 ; redraw it one square left

		push [x_coordinate] ; push x_coordinate back before jumping to the end to not mess up the pop at the end

		jmp move_left_end

	move_left_t_3:
		; t-piece 3rd position has no first row so there's no point in checking it

		sub [x_coordinate], ax
		add [y_coordinate], ax
		call readpixel
		cmp [pixelcolour], 0 ; don't move left if it's blocked - row 2
		jne move_left_end
		add [x_coordinate], ax

		add [y_coordinate], ax
		call readpixel
		cmp [pixelcolour], 0 ; don't move left if it's blocked - row 3
		jne move_left_end

		sub [y_coordinate], ax ; return to cursor position
		sub [y_coordinate], ax

		pop [x_coordinate] ; momenteraly pop x_coordinate in order to permenantly change it

		call blacktpiece_3 ; erase piece
		sub [x_coordinate], ax
		call drawtpiece_3 ; redraw it one square left

		push [x_coordinate] ; push x_coordinate back before jumping to the end to not mess up the pop at the end

		jmp move_left_end

	move_left_t_4:
		call readpixel
		cmp [pixelcolour], 0 ; don't move left if it's blocked - row 1
		jne move_left_end

		add [y_coordinate], ax
		call readpixel
		cmp [pixelcolour], 0 ; don't move left if it's blocked - row 2
		jne move_left_end

		add [y_coordinate], ax
		call readpixel
		cmp [pixelcolour], 0 ; don't move left if it's blocked - row 3
		jne move_left_end
		
		sub [y_coordinate], ax ; return to cursor position
		sub [y_coordinate], ax

		pop [x_coordinate] ; momenteraly pop x_coordinate in order to permenantly change it

		call blacktpiece_4 ; erase piece
		sub [x_coordinate], ax
		call drawtpiece_4 ; redraw it one square left

		push [x_coordinate] ; push x_coordinate back before jumping to the end to not mess up the pop at the end
		jmp move_left_end

	move_left_end:
		pop [x_coordinate]
		pop [y_coordinate]
		pop ax
		ret
endp move_left

proc move_right
		push ax
		push [y_coordinate]
		push [x_coordinate]
		
		mov ax, [square_size] ; square size in a register

		cmp [current_piece], 0
		je move_right_t ; t-piece
		cmp [current_piece], 1
		je move_right_o ; o-piece
		cmp [current_piece], 2
		je move_right_j ; j-piece
		cmp [current_piece], 3
		je move_right_l ; l-piece
		cmp [current_piece], 4
		je move_right_i ; i-piece
		cmp [current_piece], 5
		je move_right_s ; s-piece
		cmp [current_piece], 6
		je move_right_z ; z-piece
		jmp move_right_end

	move_right_o:
		add [x_coordinate], ax
		add [x_coordinate], ax
		add [x_coordinate], ax
		call readpixel
		cmp [pixelcolour], 0 ; don't move right if it's blocked - row 1
		jne move_right_end

		add [y_coordinate], ax
		call readpixel
		cmp [pixelcolour], 0 ; don't move right if it's blocked - row 2
		jne move_right_end

		sub [y_coordinate], ax ; return to cursor position
		sub [x_coordinate], ax
		sub [x_coordinate], ax
		sub [x_coordinate], ax

		pop [x_coordinate] ; momenteraly pop x_coordinate in order to permenantly change it

		call blackopiece ; erase piece
		add [x_coordinate], ax
		call drawopiece ; redraw it one square right

		push [x_coordinate] ; push x_coordinate back before jumping to the end to not mess up the pop at the end
		jmp move_right_end

		move_right_z:
		cmp [current_piece_rotation], 1
		je move_right_z_1
		cmp [current_piece_rotation], 2
		je move_right_z_2
		cmp [current_piece_rotation], 3
		je move_right_z_3
		cmp [current_piece_rotation], 4
		je move_right_z_4
		jmp move_right_end

	move_right_z_1:
		add [x_coordinate], ax
		add [x_coordinate], ax
		call readpixel
		cmp [pixelcolour], 0 ; don't move right if it's blocked - row 1
		jne move_right_end

		add [x_coordinate], ax
		add [y_coordinate], ax
		call readpixel
		cmp [pixelcolour], 0 ; don't move right if it's blocked - row 2
		jne move_right_end

		sub [y_coordinate], ax ; return to cursor position
		sub [x_coordinate], ax
		sub [x_coordinate], ax
		sub [x_coordinate], ax

		pop [x_coordinate] ; momenteraly pop x_coordinate in order to permenantly change it

		call blackzPiece_1 ; erase piece
		add [x_coordinate], ax
		call drawzPiece_1 ; redraw it one square right

		push [x_coordinate] ; push x_coordinate back before jumping to the end to not mess up the pop at the end
		jmp move_right_end

	move_right_z_2:
		add [x_coordinate], ax
		add [x_coordinate], ax
		call readpixel
		cmp [pixelcolour], 0 ; don't move right if it's blocked - row 1
		jne move_right_end

		add [y_coordinate], ax
		call readpixel
		cmp [pixelcolour], 0 ; don't move right if it's blocked - row 2
		jne move_right_end

		add [y_coordinate], ax
		sub [x_coordinate], ax
		call readpixel
		cmp [pixelcolour], 0 ; don't move right if it's blocked - row 2
		jne move_right_end

		sub [y_coordinate], ax ; return to cursor position
		sub [y_coordinate], ax
		sub [x_coordinate], ax

		pop [x_coordinate] ; momenteraly pop x_coordinate in order to permenantly change it

		call blackzPiece_2 ; erase piece
		add [x_coordinate], ax
		call drawzPiece_2 ; redraw it one square right

		push [x_coordinate] ; push x_coordinate back before jumping to the end to not mess up the pop at the end
		jmp move_right_end

	move_right_z_3:
		add [y_coordinate], ax
		add [x_coordinate], ax
		add [x_coordinate], ax
		call readpixel
		cmp [pixelcolour], 0 ; don't move right if it's blocked - row 1
		jne move_right_end

		add [x_coordinate], ax
		add [y_coordinate], ax
		call readpixel
		cmp [pixelcolour], 0 ; don't move right if it's blocked - row 2
		jne move_right_end

		sub [y_coordinate], ax ; return to cursor position
		sub [x_coordinate], ax
		sub [x_coordinate], ax
		sub [x_coordinate], ax

		pop [x_coordinate] ; momenteraly pop x_coordinate in order to permenantly change it

		call blackzPiece_1 ; erase piece
		add [x_coordinate], ax
		call drawzPiece_1 ; redraw it one square right

		push [x_coordinate] ; push x_coordinate back before jumping to the end to not mess up the pop at the end
		sub [y_coordinate], ax
		jmp move_right_end

	move_right_z_4:
		add [x_coordinate], ax
		add [x_coordinate], ax
		add [x_coordinate], ax
		call readpixel
		cmp [pixelcolour], 0 ; don't move right if it's blocked - row 1
		jne move_right_end

		add [y_coordinate], ax
		call readpixel
		cmp [pixelcolour], 0 ; don't move right if it's blocked - row 2
		jne move_right_end

		add [y_coordinate], ax
		sub [x_coordinate], ax
		call readpixel
		cmp [pixelcolour], 0 ; don't move right if it's blocked - row 2
		jne move_right_end

		sub [y_coordinate], ax ; return to cursor position
		sub [y_coordinate], ax
		sub [x_coordinate], ax

		pop [x_coordinate] ; momenteraly pop x_coordinate in order to permenantly change it

		add [x_coordinate], ax
		call blackzPiece_2 ; erase piece
		add [x_coordinate], ax
		call drawzPiece_2 ; redraw it one square right
		sub [x_coordinate], ax

		push [x_coordinate] ; push x_coordinate back before jumping to the end to not mess up the pop at the end
		jmp move_right_end

	move_right_s:
		cmp [current_piece_rotation], 1
		je move_right_s_1
		cmp [current_piece_rotation], 2
		je move_right_s_2
		cmp [current_piece_rotation], 3
		je move_right_s_3
		cmp [current_piece_rotation], 4
		je move_right_s_4
		jmp move_right_end

	move_right_s_1:
		add [x_coordinate], ax
		add [x_coordinate], ax
		add [x_coordinate], ax
		call readpixel
		cmp [pixelcolour], 0 ; don't move right if it's blocked - row 1
		jne move_right_end

		sub [x_coordinate], ax
		add [y_coordinate], ax
		call readpixel
		cmp [pixelcolour], 0 ; don't move right if it's blocked - row 2
		jne move_right_end

		sub [y_coordinate], ax ; return to cursor position
		sub [x_coordinate], ax
		sub [x_coordinate], ax

		pop [x_coordinate] ; momenteraly pop x_coordinate in order to permenantly change it

		call blackSPiece_1 ; erase piece
		add [x_coordinate], ax
		call drawSPiece_1 ; redraw it one square right

		push [x_coordinate] ; push x_coordinate back before jumping to the end to not mess up the pop at the end
		jmp move_right_end

	move_right_s_2:
		add [x_coordinate], ax
		call readpixel
		cmp [pixelcolour], 0 ; don't move right if it's blocked - row 1
		jne move_right_end

		add [x_coordinate], ax
		add [y_coordinate], ax
		call readpixel
		cmp [pixelcolour], 0 ; don't move right if it's blocked - row 2
		jne move_right_end

		add [y_coordinate], ax
		call readpixel
		cmp [pixelcolour], 0 ; don't move right if it's blocked - row 3
		jne move_right_end

		sub [y_coordinate], ax ; return to cursor position
		sub [y_coordinate], ax
		sub [x_coordinate], ax
		sub [x_coordinate], ax

		pop [x_coordinate] ; momenteraly pop x_coordinate in order to permenantly change it

		call blackSPiece_2 ; erase piece
		add [x_coordinate], ax
		call drawSPiece_2 ; redraw it one square right

		push [x_coordinate] ; push x_coordinate back before jumping to the end to not mess up the pop at the end
		jmp move_right_end

	move_right_s_3:
		add [y_coordinate], ax
		add [x_coordinate], ax
		add [x_coordinate], ax
		add [x_coordinate], ax
		call readpixel
		cmp [pixelcolour], 0 ; don't move right if it's blocked - row 2
		jne move_right_end

		sub [x_coordinate], ax
		add [y_coordinate], ax
		call readpixel
		cmp [pixelcolour], 0 ; don't move right if it's blocked - row 3
		jne move_right_end

		sub [y_coordinate], ax ; return to cursor position
		sub [y_coordinate], ax
		sub [x_coordinate], ax
		sub [x_coordinate], ax

		pop [x_coordinate] ; momenteraly pop x_coordinate in order to permenantly change it

		add [y_coordinate], ax
		call blackSPiece_1 ; erase piece
		add [x_coordinate], ax
		call drawSPiece_1 ; redraw it one square right
		sub [y_coordinate], ax

		push [x_coordinate] ; push x_coordinate back before jumping to the end to not mess up the pop at the end
		jmp move_right_end

	move_right_s_4:
		add [x_coordinate], ax
		add [x_coordinate], ax
		call readpixel
		cmp [pixelcolour], 0 ; don't move right if it's blocked - row 1
		jne move_right_end

		add [x_coordinate], ax
		add [y_coordinate], ax
		call readpixel
		cmp [pixelcolour], 0 ; don't move right if it's blocked - row 2
		jne move_right_end

		add [y_coordinate], ax
		call readpixel
		cmp [pixelcolour], 0 ; don't move right if it's blocked - row 3
		jne move_right_end

		sub [y_coordinate], ax ; return to cursor position
		sub [y_coordinate], ax
		sub [x_coordinate], ax
		sub [x_coordinate], ax

		pop [x_coordinate] ; momenteraly pop x_coordinate in order to permenantly change it

		add [x_coordinate], ax
		call blackSPiece_2 ; erase piece
		add [x_coordinate], ax
		call drawSPiece_2 ; redraw it one square right
		sub [x_coordinate], ax

		push [x_coordinate] ; push x_coordinate back before jumping to the end to not mess up the pop at the end
		jmp move_right_end

	move_right_i:
		cmp [current_piece_rotation], 1
		je move_right_i_1
		cmp [current_piece_rotation], 2
		je move_right_i_2
		cmp [current_piece_rotation], 3
		je move_right_i_3
		cmp [current_piece_rotation], 4
		je move_right_i_4
		jmp move_right_end

	move_right_i_1:
		add [y_coordinate], ax
		add [x_coordinate], ax
		add [x_coordinate], ax
		add [x_coordinate], ax
		add [x_coordinate], ax
		call readpixel
		cmp [pixelcolour], 0 ; don't move right if it's blocked - row 2
		jne move_right_end

		sub [y_coordinate], ax ; return to cursor position
		sub [x_coordinate], ax
		sub [x_coordinate], ax
		sub [x_coordinate], ax
		sub [x_coordinate], ax

		pop [x_coordinate] ; momenteraly pop x_coordinate in order to permenantly change it

		call blackipiece_1 ; erase piece
		add [x_coordinate], ax
		call drawipiece_1 ; redraw it one square right

		push [x_coordinate] ; push x_coordinate back before jumping to the end to not mess up the pop at the end
		jmp move_right_end

	move_right_i_2:
		add [x_coordinate], ax
		add [x_coordinate], ax
		call readpixel
		cmp [pixelcolour], 0 ; don't move right if it's blocked - row 1
		jne move_right_end

		add [y_coordinate], ax
		call readpixel
		cmp [pixelcolour], 0 ; don't move right if it's blocked - row 2
		jne move_right_end

		add [y_coordinate], ax
		call readpixel
		cmp [pixelcolour], 0 ; don't move right if it's blocked - row 3
		jne move_right_end
		
		add [y_coordinate], ax
		call readpixel
		cmp [pixelcolour], 0 ; don't move right if it's blocked - row 4
		jne move_right_end

		sub [x_coordinate], ax ; return to cursor position
		sub [x_coordinate], ax
		sub [y_coordinate], ax
		sub [y_coordinate], ax
		sub [y_coordinate], ax

		pop [x_coordinate] ; momenteraly pop x_coordinate in order to permenantly change it

		call blackipiece_2 ; erase piece
		add [x_coordinate], ax
		call drawipiece_2 ; redraw it one square right

		push [x_coordinate] ; push x_coordinate back before jumping to the end to not mess up the pop at the end
		jmp move_right_end

	move_right_i_3:
		add [y_coordinate], ax
		add [y_coordinate], ax
		add [x_coordinate], ax
		add [x_coordinate], ax
		add [x_coordinate], ax
		add [x_coordinate], ax
		call readpixel
		cmp [pixelcolour], 0 ; don't move right if it's blocked - row 2
		jne move_right_end

		sub [y_coordinate], ax ; return to cursor position
		sub [y_coordinate], ax
		sub [x_coordinate], ax
		sub [x_coordinate], ax
		sub [x_coordinate], ax
		sub [x_coordinate], ax

		pop [x_coordinate] ; momenteraly pop x_coordinate in order to permenantly change it

		add [y_coordinate], ax
		call blackipiece_1 ; erase piece
		add [x_coordinate], ax
		call drawipiece_1 ; redraw it one square right
		sub [y_coordinate], ax

		push [x_coordinate] ; push x_coordinate back before jumping to the end to not mess up the pop at the end
		jmp move_right_end

	move_right_i_4:
		add [x_coordinate], ax
		add [x_coordinate], ax
		add [x_coordinate], ax
		call readpixel
		cmp [pixelcolour], 0 ; don't move right if it's blocked - row 1
		jne move_right_end

		add [y_coordinate], ax
		call readpixel
		cmp [pixelcolour], 0 ; don't move right if it's blocked - row 2
		jne move_right_end

		add [y_coordinate], ax
		call readpixel
		cmp [pixelcolour], 0 ; don't move right if it's blocked - row 3
		jne move_right_end
		
		add [y_coordinate], ax
		call readpixel
		cmp [pixelcolour], 0 ; don't move right if it's blocked - row 4
		jne move_right_end

		sub [x_coordinate], ax ; return to cursor position
		sub [x_coordinate], ax
		sub [x_coordinate], ax
		sub [y_coordinate], ax
		sub [y_coordinate], ax
		sub [y_coordinate], ax

		pop [x_coordinate] ; momenteraly pop x_coordinate in order to permenantly change it

		add [x_coordinate], ax
		call blackipiece_2 ; erase piece
		add [x_coordinate], ax
		call drawipiece_2 ; redraw it one square right
		sub [x_coordinate], ax

		push [x_coordinate] ; push x_coordinate back before jumping to the end to not mess up the pop at the end
		jmp move_right_end

	move_right_l:
		cmp [current_piece_rotation], 1
		je move_right_l_1
		cmp [current_piece_rotation], 2
		je move_right_l_2
		cmp [current_piece_rotation], 3
		je move_right_l_3
		cmp [current_piece_rotation], 4
		je move_right_l_4
		jmp move_right_end

	move_right_l_1:
		add [x_coordinate], ax
		add [x_coordinate], ax
		add [x_coordinate], ax
		call readpixel
		cmp [pixelcolour], 0 ; don't move right if it's blocked - row 1
		jne move_right_end

		add [y_coordinate], ax
		sub [x_coordinate], ax
		sub [x_coordinate], ax
		call readpixel
		cmp [pixelcolour], 0 ; don't move right if it's blocked - row 2
		jne move_right_end

		; l-piece 1st position has no first row so there's no point in checking it

		sub [y_coordinate], ax ; return to cursor position
		sub [x_coordinate], ax

		pop [x_coordinate] ; momenteraly pop x_coordinate in order to permenantly change it

		call blacklpiece_1 ; erase piece
		add [x_coordinate], ax
		call drawlpiece_1 ; redraw it one square right

		push [x_coordinate] ; push x_coordinate back before jumping to the end to not mess up the pop at the end
		jmp move_right_end

	move_right_l_2:
		add [x_coordinate], ax
		call readpixel
		cmp [pixelcolour], 0 ; don't move right if it's blocked - row 1
		jne move_right_end

		add [y_coordinate], ax
		call readpixel
		cmp [pixelcolour], 0 ; don't move right if it's blocked - row 2
		jne move_right_end

		add [y_coordinate], ax
		add [x_coordinate], ax
		call readpixel
		cmp [pixelcolour], 0 ; don't move right if it's blocked - row 3
		jne move_right_end

		sub [y_coordinate], ax ; return to cursor position
		sub [y_coordinate], ax
		sub [x_coordinate], ax
		sub [x_coordinate], ax

		pop [x_coordinate] ; momenteraly pop x_coordinate in order to permenantly change it

		call blacklpiece_2 ; erase piece
		add [x_coordinate], ax
		call drawlpiece_2 ; redraw it one square right

		push [x_coordinate] ; push x_coordinate back before jumping to the end to not mess up the pop at the end
		jmp move_right_end

	move_right_l_3:
		; l-piece 3rd position has no first row so there's no point in checking it

		add [y_coordinate], ax
		add [x_coordinate], ax
		add [x_coordinate], ax
		add [x_coordinate], ax
		call readpixel
		cmp [pixelcolour], 0 ; don't move right if it's blocked - row 2
		jne move_right_end

		add [y_coordinate], ax
		call readpixel
		cmp [pixelcolour], 0 ; don't move right if it's blocked - row 3
		jne move_right_end

		sub [y_coordinate], ax ; return to cursor position
		sub [y_coordinate], ax
		sub [x_coordinate], ax
		sub [x_coordinate], ax
		sub [x_coordinate], ax

		pop [x_coordinate] ; momenteraly pop x_coordinate in order to permenantly change it

		call blacklpiece_3 ; erase piece
		add [x_coordinate], ax
		call drawlpiece_3 ; redraw it one square right

		push [x_coordinate] ; push x_coordinate back before jumping to the end to not mess up the pop at the end
		jmp move_right_end

	move_right_l_4:
		add [x_coordinate], ax
		add [x_coordinate], ax
		add [x_coordinate], ax
		call readpixel
		cmp [pixelcolour], 0 ; don't move right if it's blocked - row 1
		jne move_right_end

		add [y_coordinate], ax
		call readpixel
		cmp [pixelcolour], 0 ; don't move right if it's blocked - row 2
		jne move_right_end

		add [y_coordinate], ax
		call readpixel
		cmp [pixelcolour], 0 ; don't move right if it's blocked - row 3
		jne move_right_end

		sub [y_coordinate], ax ; return to cursor position
		sub [y_coordinate], ax
		sub [x_coordinate], ax
		sub [x_coordinate], ax
		sub [x_coordinate], ax

		pop [x_coordinate] ; momenteraly pop x_coordinate in order to permenantly change it

		call blacklpiece_4 ; erase piece
		add [x_coordinate], ax
		call drawlpiece_4 ; redraw it one square right

		push [x_coordinate] ; push x_coordinate back before jumping to the end to not mess up the pop at the end
		jmp move_right_end

	move_right_j:
		cmp [current_piece_rotation], 1
		je move_right_j_1
		cmp [current_piece_rotation], 2
		je move_right_j_2
		cmp [current_piece_rotation], 3
		je move_right_j_3
		cmp [current_piece_rotation], 4
		je move_right_j_4
		jmp move_right_end

	move_right_j_1:
		add [x_coordinate], ax
		add [x_coordinate], ax
		add [x_coordinate], ax
		call readpixel
		cmp [pixelcolour], 0 ; don't move right if it's blocked - row 1
		jne move_right_end

		add [y_coordinate], ax
		call readpixel
		cmp [pixelcolour], 0 ; don't move right if it's blocked - row 2
		jne move_right_end

		; j-piece 1st position has no first row so there's no point in checking it

		sub [y_coordinate], ax ; return to cursor position
		sub [x_coordinate], ax
		sub [x_coordinate], ax
		sub [x_coordinate], ax

		pop [x_coordinate] ; momenteraly pop x_coordinate in order to permenantly change it

		call blackjpiece_1 ; erase piece
		add [x_coordinate], ax
		call drawjpiece_1 ; redraw it one square right

		push [x_coordinate] ; push x_coordinate back before jumping to the end to not mess up the pop at the end
		jmp move_right_end

	move_right_j_2:
		add [x_coordinate], ax
		add [x_coordinate], ax
		call readpixel
		cmp [pixelcolour], 0 ; don't move right if it's blocked - row 1
		jne move_right_end

		add [y_coordinate], ax
		sub [x_coordinate], ax
		call readpixel
		cmp [pixelcolour], 0 ; don't move right if it's blocked - row 2
		jne move_right_end

		add [y_coordinate], ax
		call readpixel
		cmp [pixelcolour], 0 ; don't move right if it's blocked - row 3
		jne move_right_end

		sub [y_coordinate], ax ; return to cursor position
		sub [y_coordinate], ax
		sub [x_coordinate], ax

		pop [x_coordinate] ; momenteraly pop x_coordinate in order to permenantly change it

		call blackjpiece_2 ; erase piece
		add [x_coordinate], ax
		call drawjpiece_2 ; redraw it one square right

		push [x_coordinate] ; push x_coordinate back before jumping to the end to not mess up the pop at the end
		jmp move_right_end

	move_right_j_3:
		; j-piece 3rd position doesn't have a first row so there's no point in checking it

		add [y_coordinate], ax
		add [x_coordinate], ax
		call readpixel
		cmp [pixelcolour], 0 ; don't move right if it's blocked - row 2
		jne move_right_end

		add [y_coordinate], ax
		add [x_coordinate], ax
		add [x_coordinate], ax
		call readpixel
		cmp [pixelcolour], 0 ; don't move right if it's blocked - row 3
		jne move_right_end

		sub [y_coordinate], ax ; return to cursor position
		sub [y_coordinate], ax ; return to cursor position
		sub [x_coordinate], ax
		sub [x_coordinate], ax
		sub [x_coordinate], ax

		pop [x_coordinate] ; momenteraly pop x_coordinate in order to permenantly change it

		call blackjpiece_3 ; erase piece
		add [x_coordinate], ax
		call drawjpiece_3 ; redraw it one square right

		push [x_coordinate] ; push x_coordinate back before jumping to the end to not mess up the pop at the end
		jmp move_right_end

	move_right_j_4:
		add [x_coordinate], ax
		add [x_coordinate], ax
		add [x_coordinate], ax
		call readpixel
		cmp [pixelcolour], 0 ; don't move right if it's blocked - row 1
		jne move_right_end

		add [y_coordinate], ax
		call readpixel
		cmp [pixelcolour], 0 ; don't move right if it's blocked - row 2
		jne move_right_end

		add [y_coordinate], ax
		call readpixel
		cmp [pixelcolour], 0 ; don't move right if it's blocked - row 3
		jne move_right_end

		sub [y_coordinate], ax ; return to cursor position
		sub [y_coordinate], ax ; return to cursor position
		sub [x_coordinate], ax
		sub [x_coordinate], ax
		sub [x_coordinate], ax

		pop [x_coordinate] ; momenteraly pop x_coordinate in order to permenantly change it

		call blackjpiece_4 ; erase piece
		add [x_coordinate], ax
		call drawjpiece_4 ; redraw it one square right

		push [x_coordinate] ; push x_coordinate back before jumping to the end to not mess up the pop at the end
		jmp move_right_end

	move_right_t:
		cmp [current_piece_rotation], 1
		je move_right_t_1
		cmp [current_piece_rotation], 2
		je move_right_t_2
		cmp [current_piece_rotation], 3
		je move_right_t_3
		cmp [current_piece_rotation], 4
		je move_right_t_4
		jmp move_right_end

	move_right_t_1:
		add [x_coordinate], ax
		add [x_coordinate], ax
		call readpixel
		cmp [pixelcolour], 0 ; don't move right if it's blocked - row 1
		jne move_right_end

		add [x_coordinate], ax
		add [y_coordinate], ax
		call readpixel
		cmp [pixelcolour], 0 ; don't move right if it's blocked - row 2
		jne move_right_end

		; t-piece 1st position has no first row so there's no point in checking it

		sub [y_coordinate], ax ; return to cursor position
		sub [x_coordinate], ax
		sub [x_coordinate], ax
		sub [x_coordinate], ax

		pop [x_coordinate] ; momenteraly pop x_coordinate in order to permenantly change it

		call blacktpiece_1 ; erase piece
		add [x_coordinate], ax
		call drawtpiece_1 ; redraw it one square right

		push [x_coordinate] ; push x_coordinate back before jumping to the end to not mess up the pop at the end
		jmp move_right_end

	move_right_t_2:
		add [x_coordinate], ax
		add [x_coordinate], ax
		call readpixel
		cmp [pixelcolour], 0 ; don't move right if it's blocked - row 1
		jne move_right_end

		add [y_coordinate], ax
		call readpixel
		cmp [pixelcolour], 0 ; don't move right if it's blocked - row 2
		jne move_right_end

		add [y_coordinate], ax
		call readpixel
		cmp [pixelcolour], 0 ; don't move right if it's blocked - row 3
		jne move_right_end

		sub [y_coordinate], ax ; return to cursor position
		sub [y_coordinate], ax
		sub [x_coordinate], ax
		sub [x_coordinate], ax

		pop [x_coordinate] ; momenteraly pop x_coordinate in order to permenantly change it

		call blacktpiece_2 ; erase piece
		add [x_coordinate], ax
		call drawtpiece_2 ; redraw it one square right

		push [x_coordinate] ; push x_coordinate back before jumping to the end to not mess up the pop at the end

		jmp move_right_end

	move_right_t_3:
		; t-piece 3rd position has no first row so there's no point in checking it

		add [y_coordinate], ax
		add [x_coordinate], ax
		add [x_coordinate], ax
		add [x_coordinate], ax
		call readpixel
		cmp [pixelcolour], 0 ; don't move right if it's blocked - row 2
		jne move_right_end
		sub [x_coordinate], ax

		add [y_coordinate], ax
		call readpixel
		cmp [pixelcolour], 0 ; don't move right if it's blocked - row 3
		jne move_right_end

		sub [y_coordinate], ax ; return to cursor position
		sub [y_coordinate], ax
		sub [x_coordinate], ax
		sub [x_coordinate], ax

		pop [x_coordinate] ; momenteraly pop x_coordinate in order to permenantly change it

		call blacktpiece_3 ; erase piece
		add [x_coordinate], ax
		call drawtpiece_3 ; redraw it one square right

		push [x_coordinate] ; push x_coordinate back before jumping to the end to not mess up the pop at the end

		jmp move_right_end

	move_right_t_4:
		add [x_coordinate], ax
		add [x_coordinate], ax
		call readpixel
		cmp [pixelcolour], 0 ; don't move right if it's blocked - row 1
		jne move_right_end

		add [x_coordinate], ax
		add [y_coordinate], ax
		call readpixel
		cmp [pixelcolour], 0 ; don't move right if it's blocked - row 2
		jne move_right_end

		add [y_coordinate], ax
		sub [x_coordinate], ax
		call readpixel
		cmp [pixelcolour], 0 ; don't move right if it's blocked - row 3
		jne move_right_end
		
		sub [y_coordinate], ax ; return to cursor position
		sub [y_coordinate], ax
		sub [x_coordinate], ax
		sub [x_coordinate], ax

		pop [x_coordinate] ; momenteraly pop x_coordinate in order to permenantly change it

		call blacktpiece_4 ; erase piece
		add [x_coordinate], ax
		call drawtpiece_4 ; redraw it one square right

		push [x_coordinate] ; push x_coordinate back before jumping to the end to not mess up the pop at the end
		jmp move_right_end

	move_right_end:
		pop [x_coordinate]
		pop [y_coordinate]
		pop ax
		ret
endp move_right

proc move_down
		push ax
		push [x_coordinate]
		push [y_coordinate]
		
		mov ax, [square_size] ; square size in a register

		cmp [current_piece], 0
		je move_down_t ; if t-piece
		cmp [current_piece], 1
		je move_down_o ; if o-piece
		cmp [current_piece], 2
		je move_down_j ; if j-piece
		cmp [current_piece], 3
		je move_down_l ; if l-piece
		cmp [current_piece], 4
		je move_down_i ; if i-piece
		cmp [current_piece], 5
		je move_down_s ; if s-piece
		cmp [current_piece], 6
		je move_down_z ; if z-piece
		jmp move_down_end

	move_down_o:
		add [y_coordinate], ax
		add [y_coordinate], ax
		add [x_coordinate], ax
		call readpixel
		cmp [pixelcolour], 0 ; don't move down if it's blocked - column 1
		jne move_down_fail

		add [x_coordinate], ax
		call readpixel
		cmp [pixelcolour], 0 ; don't move down if it's blocked - column 1
		jne move_down_fail

		sub [y_coordinate], ax ; return to cursor position
		sub [y_coordinate], ax
		sub [x_coordinate], ax
		sub [x_coordinate], ax

		pop [y_coordinate] ; momenteraly pop y_coordinate in order to permenantly change it

		call blackopiece ; erase piece
		add [y_coordinate], ax
		call drawopiece ; redraw it one square down

		push [y_coordinate] ; push y_coordinate back before jumping to the end to not mess up the pop at the end
		jmp move_down_end

	move_down_z:
		cmp [current_piece_rotation], 1 ; every rotation falls down differently
		je move_down_z_1
		cmp [current_piece_rotation], 2
		je move_down_z_2
		cmp [current_piece_rotation], 3
		je move_down_z_3
		cmp [current_piece_rotation], 4
		je move_down_z_4
		jmp move_down_end

	move_down_z_1:
		add [y_coordinate], ax
		call readpixel
		cmp [pixelcolour], 0 ; don't move down if it's blocked - column 1
		jne move_down_fail
		
		add [x_coordinate], ax
		add [y_coordinate], ax
		call readpixel
		cmp [pixelcolour], 0 ; don't move down if it's blocked - column 2
		jne move_down_fail

		add [x_coordinate], ax
		call readpixel
		cmp [pixelcolour], 0 ; don't move down if it's blocked - column 3
		jne move_down_fail

		sub [x_coordinate], ax ; return to cursor position
		sub [x_coordinate], ax
		sub [y_coordinate], ax
		sub [y_coordinate], ax

		pop [y_coordinate] ; momenteraly pop y_coordinate in order to permenantly change it

		call blackzPiece_1 ; erase piece
		add [y_coordinate], ax
		call drawzPiece_1 ; redraw it one square down

		push [y_coordinate] ; push y_coordinate back before jumping to the end to not mess up the pop at the end
		jmp move_down_end

	move_down_z_2:
		add [y_coordinate], ax
		add [y_coordinate], ax
		add [y_coordinate], ax
		call readpixel
		cmp [pixelcolour], 0 ; don't move down if it's blocked - column 1
		jne move_down_fail
		
		add [x_coordinate], ax
		sub [y_coordinate], ax
		call readpixel
		cmp [pixelcolour], 0 ; don't move down if it's blocked - column 2
		jne move_down_fail

		sub [x_coordinate], ax ; return to cursor position
		sub [y_coordinate], ax
		sub [y_coordinate], ax

		pop [y_coordinate] ; momenteraly pop y_coordinate in order to permenantly change it

		call blackzPiece_2 ; erase piece
		add [y_coordinate], ax
		call drawzPiece_2 ; redraw it one square down

		push [y_coordinate] ; push y_coordinate back before jumping to the end to not mess up the pop at the end
		jmp move_down_end

	move_down_z_3:
		add [y_coordinate], ax
		add [y_coordinate], ax
		call readpixel
		cmp [pixelcolour], 0 ; don't move down if it's blocked - column 1
		jne move_down_fail
		
		add [x_coordinate], ax
		add [y_coordinate], ax
		call readpixel
		cmp [pixelcolour], 0 ; don't move down if it's blocked - column 2
		jne move_down_fail

		add [x_coordinate], ax
		call readpixel
		cmp [pixelcolour], 0 ; don't move down if it's blocked - column 3
		jne move_down_fail

		sub [x_coordinate], ax ; return to cursor position
		sub [x_coordinate], ax
		sub [y_coordinate], ax
		sub [y_coordinate], ax

		pop [y_coordinate] ; momenteraly pop y_coordinate in order to permenantly change it

		add [y_coordinate], ax
		call blackzPiece_1 ; erase piece
		add [y_coordinate], ax
		call drawzPiece_1 ; redraw it one square down
		sub [y_coordinate], ax

		push [y_coordinate] ; push y_coordinate back before jumping to the end to not mess up the pop at the end
		jmp move_down_end

	move_down_z_4:
		add [x_coordinate], ax
		add [y_coordinate], ax
		add [y_coordinate], ax
		add [y_coordinate], ax
		call readpixel
		cmp [pixelcolour], 0 ; don't move down if it's blocked - column 1
		jne move_down_fail
		
		add [x_coordinate], ax
		sub [y_coordinate], ax
		call readpixel
		cmp [pixelcolour], 0 ; don't move down if it's blocked - column 2
		jne move_down_fail

		sub [x_coordinate], ax ; return to cursor position
		sub [y_coordinate], ax
		sub [y_coordinate], ax

		pop [y_coordinate] ; momenteraly pop y_coordinate in order to permenantly change it

		call blackzPiece_2 ; erase piece
		add [y_coordinate], ax
		call drawzPiece_2 ; redraw it one square down

		push [y_coordinate] ; push y_coordinate back before jumping to the end to not mess up the pop at the end
		sub [x_coordinate], ax
		jmp move_down_end

	move_down_s:
		cmp [current_piece_rotation], 1 ; every rotation falls down differently
		je move_down_s_1
		cmp [current_piece_rotation], 2
		je move_down_s_2
		cmp [current_piece_rotation], 3
		je move_down_s_3
		cmp [current_piece_rotation], 4
		je move_down_s_4
		jmp move_down_end

	move_down_s_1:
		add [y_coordinate], ax
		add [y_coordinate], ax
		call readpixel
		cmp [pixelcolour], 0 ; don't move down if it's blocked - column 1
		jne move_down_fail
		
		add [x_coordinate], ax
		call readpixel
		cmp [pixelcolour], 0 ; don't move down if it's blocked - column 2
		jne move_down_fail

		add [x_coordinate], ax
		sub [y_coordinate], ax
		call readpixel
		cmp [pixelcolour], 0 ; don't move down if it's blocked - column 3
		jne move_down_fail

		sub [x_coordinate], ax ; return to cursor position
		sub [x_coordinate], ax
		sub [y_coordinate], ax

		pop [y_coordinate] ; momenteraly pop y_coordinate in order to permenantly change it

		call blackSPiece_1 ; erase piece
		add [y_coordinate], ax
		call drawSPiece_1 ; redraw it one square down

		push [y_coordinate] ; push y_coordinate back before jumping to the end to not mess up the pop at the end
		jmp move_down_end

	move_down_s_2:
		add [y_coordinate], ax
		add [y_coordinate], ax
		call readpixel
		cmp [pixelcolour], 0 ; don't move down if it's blocked - column 1
		jne move_down_fail
		
		add [x_coordinate], ax
		add [y_coordinate], ax
		call readpixel
		cmp [pixelcolour], 0 ; don't move down if it's blocked - column 2
		jne move_down_fail

		sub [x_coordinate], ax ; return to cursor position
		sub [y_coordinate], ax
		sub [y_coordinate], ax
		sub [y_coordinate], ax

		pop [y_coordinate] ; momenteraly pop y_coordinate in order to permenantly change it

		call blackSPiece_2 ; erase piece
		add [y_coordinate], ax
		call drawSPiece_2 ; redraw it one square down

		push [y_coordinate] ; push y_coordinate back before jumping to the end to not mess up the pop at the end
		jmp move_down_end

	move_down_s_3:
		add [y_coordinate], ax
		add [y_coordinate], ax
		add [y_coordinate], ax
		call readpixel
		cmp [pixelcolour], 0 ; don't move down if it's blocked - column 1
		jne move_down_fail
		
		add [x_coordinate], ax
		call readpixel
		cmp [pixelcolour], 0 ; don't move down if it's blocked - column 2
		jne move_down_fail

		add [x_coordinate], ax
		sub [y_coordinate], ax
		call readpixel
		cmp [pixelcolour], 0 ; don't move down if it's blocked - column 3
		jne move_down_fail

		sub [x_coordinate], ax ; return to cursor position
		sub [x_coordinate], ax
		sub [y_coordinate], ax
		sub [y_coordinate], ax

		pop [y_coordinate] ; momenteraly pop y_coordinate in order to permenantly change it

		add [y_coordinate], ax
		call blackSPiece_1 ; erase piece
		add [y_coordinate], ax
		call drawSPiece_1 ; redraw it one square down
		sub [y_coordinate], ax

		push [y_coordinate] ; push y_coordinate back before jumping to the end to not mess up the pop at the end
		jmp move_down_end

	move_down_s_4:
		add [y_coordinate], ax
		add [y_coordinate], ax
		add [x_coordinate], ax
		call readpixel
		cmp [pixelcolour], 0 ; don't move down if it's blocked - column 1
		jne move_down_fail
		
		add [x_coordinate], ax
		add [y_coordinate], ax
		call readpixel
		cmp [pixelcolour], 0 ; don't move down if it's blocked - column 2
		jne move_down_fail

		sub [x_coordinate], ax ; return to cursor position
		sub [x_coordinate], ax
		sub [y_coordinate], ax
		sub [y_coordinate], ax
		sub [y_coordinate], ax

		pop [y_coordinate] ; momenteraly pop y_coordinate in order to permenantly change it

		add [x_coordinate], ax
		call blackSPiece_2 ; erase piece
		add [y_coordinate], ax
		call drawSPiece_2 ; redraw it one square down
		sub [x_coordinate], ax

		push [y_coordinate] ; push y_coordinate back before jumping to the end to not mess up the pop at the end
		jmp move_down_end

	move_down_i:
		cmp [current_piece_rotation], 1 ; every rotation falls down differently
		je move_down_i_1
		cmp [current_piece_rotation], 2
		je move_down_i_2
		cmp [current_piece_rotation], 3
		je move_down_i_3
		cmp [current_piece_rotation], 4
		je move_down_i_4
		jmp move_down_end

	move_down_i_1:
		add [y_coordinate], ax
		add [y_coordinate], ax
		call readpixel
		cmp [pixelcolour], 0 ; don't move down if it's blocked - column 1
		jne move_down_fail
		
		add [x_coordinate], ax
		call readpixel
		cmp [pixelcolour], 0 ; don't move down if it's blocked - column 2
		jne move_down_fail

		add [x_coordinate], ax
		call readpixel
		cmp [pixelcolour], 0 ; don't move down if it's blocked - column 3
		jne move_down_fail

		add [x_coordinate], ax
		call readpixel
		cmp [pixelcolour], 0 ; don't move down if it's blocked - column 4
		jne move_down_fail

		sub [x_coordinate], ax ; return to cursor position
		sub [x_coordinate], ax
		sub [x_coordinate], ax
		sub [y_coordinate], ax
		sub [y_coordinate], ax

		pop [y_coordinate] ; momenteraly pop y_coordinate in order to permenantly change it

		call blackipiece_1 ; erase piece
		add [y_coordinate], ax
		call drawipiece_1 ; redraw it one square down

		push [y_coordinate] ; push y_coordinate back before jumping to the end to not mess up the pop at the end
		jmp move_down_end

	move_down_i_2:
		add [x_coordinate], ax
		add [y_coordinate], ax
		add [y_coordinate], ax
		add [y_coordinate], ax
		add [y_coordinate], ax
		call readpixel
		cmp [pixelcolour], 0 ; don't move down if it's blocked - column 1
		jne move_down_fail

		sub [x_coordinate], ax ; return to cursor position
		sub [y_coordinate], ax
		sub [y_coordinate], ax
		sub [y_coordinate], ax

		pop [y_coordinate] ; momenteraly pop y_coordinate in order to permenantly change it

		call blackipiece_2 ; erase piece
		add [y_coordinate], ax
		call drawipiece_2 ; redraw it one square down

		push [y_coordinate] ; push y_coordinate back before jumping to the end to not mess up the pop at the end
		jmp move_down_end

	move_down_i_3:
		add [y_coordinate], ax
		add [y_coordinate], ax
		add [y_coordinate], ax
		call readpixel
		cmp [pixelcolour], 0 ; don't move down if it's blocked - column 1
		jne move_down_fail
		
		add [x_coordinate], ax
		call readpixel
		cmp [pixelcolour], 0 ; don't move down if it's blocked - column 2
		jne move_down_fail

		add [x_coordinate], ax
		call readpixel
		cmp [pixelcolour], 0 ; don't move down if it's blocked - column 3
		jne move_down_fail

		add [x_coordinate], ax
		call readpixel
		cmp [pixelcolour], 0 ; don't move down if it's blocked - column 4
		jne move_down_fail

		sub [x_coordinate], ax ; return to cursor position
		sub [x_coordinate], ax
		sub [x_coordinate], ax
		sub [y_coordinate], ax
		sub [y_coordinate], ax
		sub [y_coordinate], ax

		pop [y_coordinate] ; momenteraly pop y_coordinate in order to permenantly change it

		add [y_coordinate], ax
		call blackipiece_1 ; erase piece
		add [y_coordinate], ax
		call drawipiece_1 ; redraw it one square down
		sub [y_coordinate], ax

		push [y_coordinate] ; push y_coordinate back before jumping to the end to not mess up the pop at the end
		jmp move_down_end

	move_down_i_4:
		add [x_coordinate], ax
		add [x_coordinate], ax
		add [y_coordinate], ax
		add [y_coordinate], ax
		add [y_coordinate], ax
		add [y_coordinate], ax
		call readpixel
		cmp [pixelcolour], 0 ; don't move down if it's blocked - column 1
		jne move_down_fail

		sub [x_coordinate], ax ; return to cursor position
		sub [x_coordinate], ax
		sub [y_coordinate], ax
		sub [y_coordinate], ax
		sub [y_coordinate], ax

		pop [y_coordinate] ; momenteraly pop y_coordinate in order to permenantly change it

		add [x_coordinate], ax
		call blackipiece_2 ; erase piece
		add [y_coordinate], ax
		call drawipiece_2 ; redraw it one square down
		sub [x_coordinate], ax

		push [y_coordinate] ; push y_coordinate back before jumping to the end to not mess up the pop at the end
		jmp move_down_end

	move_down_l:
		cmp [current_piece_rotation], 1 ; every rotation falls down differently
		je move_down_l_1
		cmp [current_piece_rotation], 2
		je move_down_l_2
		cmp [current_piece_rotation], 3
		je move_down_l_3
		cmp [current_piece_rotation], 4
		je move_down_l_4
		jmp move_down_end

	move_down_l_1:
		add [y_coordinate], ax
		add [y_coordinate], ax
		call readpixel
		cmp [pixelcolour], 0 ; don't move down if it's blocked - column 1
		jne move_down_fail
		
		add [x_coordinate], ax
		sub [y_coordinate], ax
		call readpixel
		cmp [pixelcolour], 0 ; don't move down if it's blocked - column 2
		jne move_down_fail

		add [x_coordinate], ax
		call readpixel
		cmp [pixelcolour], 0 ; don't move down if it's blocked - column 3
		jne move_down_fail

		sub [x_coordinate], ax ; return to cursor position
		sub [x_coordinate], ax
		sub [y_coordinate], ax
		sub [y_coordinate], ax

		pop [y_coordinate] ; momenteraly pop y_coordinate in order to permenantly change it

		call blacklpiece_1 ; erase piece
		add [y_coordinate], ax
		call drawlpiece_1 ; redraw it one square down

		push [y_coordinate] ; push y_coordinate back before jumping to the end to not mess up the pop at the end
		jmp move_down_end

	move_down_l_2:
		add [y_coordinate], ax
		add [y_coordinate], ax
		add [y_coordinate], ax
		call readpixel
		cmp [pixelcolour], 0 ; don't move down if it's blocked - column 1
		jne move_down_fail
		
		add [x_coordinate], ax
		call readpixel
		cmp [pixelcolour], 0 ; don't move down if it's blocked - column 2
		jne move_down_fail

		; j-piece 2nd position doesn't have a 3rd column so there's no point in checking it

		sub [x_coordinate], ax ; return to cursor position
		sub [y_coordinate], ax
		sub [y_coordinate], ax
		sub [y_coordinate], ax

		pop [y_coordinate] ; momenteraly pop y_coordinate in order to permenantly change it

		call blacklpiece_2 ; erase piece
		add [y_coordinate], ax
		call drawlpiece_2 ; redraw it one square down

		push [y_coordinate] ; push y_coordinate back before jumping to the end to not mess up the pop at the end
		jmp move_down_end

	move_down_l_3:
		add [y_coordinate], ax
		add [y_coordinate], ax
		add [y_coordinate], ax
		call readpixel
		cmp [pixelcolour], 0 ; don't move down if it's blocked - column 1
		jne move_down_fail
		
		add [x_coordinate], ax
		call readpixel
		cmp [pixelcolour], 0 ; don't move down if it's blocked - column 2
		jne move_down_fail

		add [x_coordinate], ax
		call readpixel
		cmp [pixelcolour], 0 ; don't move down if it's blocked - column 2
		jne move_down_fail

		sub [x_coordinate], ax ; return to cursor position
		sub [x_coordinate], ax
		sub [y_coordinate], ax
		sub [y_coordinate], ax
		sub [y_coordinate], ax

		pop [y_coordinate] ; momenteraly pop y_coordinate in order to permenantly change it

		call blacklpiece_3 ; erase piece
		add [y_coordinate], ax
		call drawlpiece_3 ; redraw it one square down

		push [y_coordinate] ; push y_coordinate back before jumping to the end to not mess up the pop at the end
		jmp move_down_end

	move_down_l_4:
		; l-piece 4th position doesn't have a 1st column so there's no point in checking it
		
		add [y_coordinate], ax
		add [x_coordinate], ax
		call readpixel
		cmp [pixelcolour], 0 ; don't move down if it's blocked - column 2
		jne move_down_fail

		add [y_coordinate], ax
		add [y_coordinate], ax
		add [x_coordinate], ax
		call readpixel
		cmp [pixelcolour], 0 ; don't move down if it's blocked - column 2
		jne move_down_fail

		sub [x_coordinate], ax ; return to cursor position
		sub [x_coordinate], ax
		sub [y_coordinate], ax
		sub [y_coordinate], ax
		sub [y_coordinate], ax

		pop [y_coordinate] ; momenteraly pop y_coordinate in order to permenantly change it

		call blacklpiece_4 ; erase piece
		add [y_coordinate], ax
		call drawlpiece_4 ; redraw it one square down

		push [y_coordinate] ; push y_coordinate back before jumping to the end to not mess up the pop at the end
		jmp move_down_end

	move_down_j:
		cmp [current_piece_rotation], 1 ; every rotation falls down differently
		je move_down_j_1
		cmp [current_piece_rotation], 2
		je move_down_j_2
		cmp [current_piece_rotation], 3
		je move_down_j_3
		cmp [current_piece_rotation], 4
		je move_down_j_4
		jmp move_down_end

	move_down_j_1:
		add [y_coordinate], ax
		call readpixel
		cmp [pixelcolour], 0 ; don't move down if it's blocked - column 1
		jne move_down_fail
		
		add [x_coordinate], ax
		call readpixel
		cmp [pixelcolour], 0 ; don't move down if it's blocked - column 2
		jne move_down_fail

		add [x_coordinate], ax
		add [y_coordinate], ax
		call readpixel
		cmp [pixelcolour], 0 ; don't move down if it's blocked - column 3
		jne move_down_fail

		sub [x_coordinate], ax ; return to cursor position
		sub [x_coordinate], ax
		sub [y_coordinate], ax
		sub [y_coordinate], ax

		pop [y_coordinate] ; momenteraly pop y_coordinate in order to permenantly change it

		call blackjpiece_1 ; erase piece
		add [y_coordinate], ax
		call drawjpiece_1 ; redraw it one square down

		push [y_coordinate] ; push y_coordinate back before jumping to the end to not mess up the pop at the end
		jmp move_down_end
		
	move_down_j_2:
		add [y_coordinate], ax
		add [y_coordinate], ax
		add [y_coordinate], ax
		call readpixel
		cmp [pixelcolour], 0 ; don't move down if it's blocked - column 1
		jne move_down_fail
		
		add [x_coordinate], ax
		sub [y_coordinate], ax
		sub [y_coordinate], ax
		call readpixel
		cmp [pixelcolour], 0 ; don't move down if it's blocked - column 2
		jne move_down_fail

		; j-piece 2nd position doesn't have a 3rd column so there's no point in checking it

		sub [x_coordinate], ax ; return to cursor position
		sub [y_coordinate], ax

		pop [y_coordinate] ; momenteraly pop y_coordinate in order to permenantly change it

		call blackjpiece_2 ; erase piece
		add [y_coordinate], ax
		call drawjpiece_2 ; redraw it one square down

		push [y_coordinate] ; push y_coordinate back before jumping to the end to not mess up the pop at the end
		jmp move_down_end

	move_down_j_3:
		add [y_coordinate], ax
		add [y_coordinate], ax
		add [y_coordinate], ax
		call readpixel
		cmp [pixelcolour], 0 ; don't move down if it's blocked - column 1
		jne move_down_fail
		
		add [x_coordinate], ax
		call readpixel
		cmp [pixelcolour], 0 ; don't move down if it's blocked - column 2
		jne move_down_fail

		add [x_coordinate], ax
		call readpixel
		cmp [pixelcolour], 0 ; don't move down if it's blocked - column 3
		jne move_down_fail

		sub [x_coordinate], ax ; return to cursor position
		sub [x_coordinate], ax
		sub [y_coordinate], ax
		sub [y_coordinate], ax
		sub [y_coordinate], ax

		pop [y_coordinate] ; momenteraly pop y_coordinate in order to permenantly change it

		call blackjpiece_3 ; erase piece
		add [y_coordinate], ax
		call drawjpiece_3 ; redraw it one square down

		push [y_coordinate] ; push y_coordinate back before jumping to the end to not mess up the pop at the end
		jmp move_down_end

	move_down_j_4:
		; j-piece 4nd position doesn't have a 1st column so there's no point in checking it
		
		add [y_coordinate], ax
		add [y_coordinate], ax
		add [y_coordinate], ax
		add [x_coordinate], ax
		call readpixel
		cmp [pixelcolour], 0 ; don't move down if it's blocked - column 2
		jne move_down_fail

		add [x_coordinate], ax
		call readpixel
		cmp [pixelcolour], 0 ; don't move down if it's blocked - column 3
		jne move_down_fail

		sub [x_coordinate], ax ; return to cursor position
		sub [x_coordinate], ax
		sub [y_coordinate], ax
		sub [y_coordinate], ax
		sub [y_coordinate], ax

		pop [y_coordinate] ; momenteraly pop y_coordinate in order to permenantly change it

		call blackjpiece_4 ; erase piece
		add [y_coordinate], ax
		call drawjpiece_4 ; redraw it one square down

		push [y_coordinate] ; push y_coordinate back before jumping to the end to not mess up the pop at the end
		jmp move_down_end

	move_down_t:
		cmp [current_piece_rotation], 1 ; every rotation falls down differently
		je move_down_t_1
		cmp [current_piece_rotation], 2
		je move_down_t_2
		cmp [current_piece_rotation], 3
		je move_down_t_3
		cmp [current_piece_rotation], 4
		je move_down_t_4
		jmp move_down_end

	move_down_t_1:
		add [y_coordinate], ax
		add [y_coordinate], ax
		call readpixel
		cmp [pixelcolour], 0 ; don't move down if it's blocked - column 1
		jne move_down_fail
		
		add [x_coordinate], ax
		call readpixel
		cmp [pixelcolour], 0 ; don't move down if it's blocked - column 2
		jne move_down_fail

		add [x_coordinate], ax
		call readpixel
		cmp [pixelcolour], 0 ; don't move down if it's blocked - column 3
		jne move_down_fail

		sub [x_coordinate], ax ; return to cursor position
		sub [x_coordinate], ax
		sub [y_coordinate], ax
		sub [y_coordinate], ax

		pop [y_coordinate] ; momenteraly pop y_coordinate in order to permenantly change it

		call blacktpiece_1 ; erase piece
		add [y_coordinate], ax
		call drawtpiece_1 ; redraw it one square down

		push [y_coordinate] ; push y_coordinate back before jumping to the end to not mess up the pop at the end
		jmp move_down_end

	move_down_t_2:
		add [y_coordinate], ax
		add [y_coordinate], ax
		call readpixel
		cmp [pixelcolour], 0 ; don't move down if it's blocked - column 1
		jne move_down_fail

		add [y_coordinate], ax
		add [x_coordinate], ax
		call readpixel
		cmp [pixelcolour], 0 ; don't move down if it's blocked - column 2
		jne move_down_fail

		; t-piece 2nd position doesn't have a 3rc column so there's nothing to check there

		sub [y_coordinate], ax ; return to cursor position
		sub [y_coordinate], ax
		sub [y_coordinate], ax
		sub [x_coordinate], ax

		pop [y_coordinate] ; momenteraly pop y_coordinate in order to permenantly change it

		call blacktpiece_2 ; erase piece
		add [y_coordinate], ax
		call drawtpiece_2 ; redraw it one square down

		push [y_coordinate] ; push y_coordinate back before jumping to the end to not mess up the pop at the end

		jmp move_down_end

	move_down_t_3:
		add [y_coordinate], ax
		add [y_coordinate], ax
		call readpixel
		cmp [pixelcolour], 0 ; don't move down if it's blocked - column 1
		jne move_down_fail

		add [y_coordinate], ax
		add [x_coordinate], ax
		call readpixel
		cmp [pixelcolour], 0 ; don't move down if it's blocked - column 2
		jne move_down_fail

		sub [y_coordinate], ax
		add [x_coordinate], ax
		call readpixel
		cmp [pixelcolour], 0 ; don't move down if it's blocked - column 3
		jne move_down_fail

		sub [y_coordinate], ax ; return to cursor position
		sub [y_coordinate], ax
		sub [x_coordinate], ax
		sub [x_coordinate], ax

		pop [y_coordinate] ; momenteraly pop y_coordinate in order to permenantly change it

		call blacktpiece_3 ; erase piece
		add [y_coordinate], ax
		call drawtpiece_3 ; redraw it one square down

		push [y_coordinate] ; push y_coordinate back before jumping to the end to not mess up the pop at the end

		jmp move_down_end

	move_down_t_4:
		; t-piece 2nd position doesn't have a 3rc column so there's nothing to check there

		add [y_coordinate], ax
		add [y_coordinate], ax
		add [y_coordinate], ax
		add [x_coordinate], ax
		call readpixel
		cmp [pixelcolour], 0 ; don't move down if it's blocked - column 2
		jne move_down_fail

		sub [y_coordinate], ax
		add [x_coordinate], ax
		call readpixel
		cmp [pixelcolour], 0 ; don't move down if it's blocked - column 3
		jne move_down_fail

		sub [y_coordinate], ax ; return to cursor position
		sub [y_coordinate], ax
		sub [x_coordinate], ax
		sub [x_coordinate], ax

		pop [y_coordinate] ; momenteraly pop y_coordinate in order to permenantly change it

		call blacktpiece_4 ; erase piece
		add [y_coordinate], ax
		call drawtpiece_4 ; redraw it one square down

		push [y_coordinate] ; push y_coordinate back before jumping to the end to not mess up the pop at the end
		jmp move_down_end

	move_down_fail:
		mov [move_down_failed], 1


	move_down_end:
		pop [y_coordinate]
		pop [x_coordinate]
		pop ax
		ret
endp move_down

proc generate_piece
	cmp [current_piece], 0 ; 0 = t-piece, 1 = o-piece, 2 = j-piece, 3 = l-piece, 4 = i-piece, 5 = s-piece, 6 = z-piece
	je generate_t
	cmp [current_piece], 1
	je generate_o
	cmp [current_piece], 2
	je generate_j
	cmp [current_piece], 3
	je generate_l
	cmp [current_piece], 4
	je generate_i
	cmp [current_piece], 5
	je generate_s
	cmp [current_piece], 6
	je generate_z
	ret

	generate_t:
		call drawtpiece_1 
		ret
	generate_o:
		call drawopiece 
		ret
	generate_j:
		call drawjpiece_1 
		ret
	generate_l:
		call drawlpiece_1 
		ret
	generate_i:
		call drawipiece_1 
		ret
	generate_s:
		call drawspiece_1 
		ret
	generate_z:
		call drawzpiece_1 
		ret
	
	ret
endp generate_piece

proc destroy_piece
	cmp [current_piece], 0 ; 0 = t-piece, 1 = o-piece, 2 = j-piece, 3 = l-piece, 4 = i-piece, 5 = s-piece, 6 = z-piece
	je destroy_t
	cmp [current_piece], 1
	je destroy_o
	cmp [current_piece], 2
	je destroy_j
	cmp [current_piece], 3
	je destroy_l
	cmp [current_piece], 4
	je destroy_i
	cmp [current_piece], 5
	je destroy_s
	cmp [current_piece], 6
	je destroy_z
	ret

	destroy_t:
		cmp [current_piece_rotation], 1 
		je destroy_t_1
		cmp [current_piece_rotation], 2 
		je destroy_t_2
		cmp [current_piece_rotation], 3 
		je destroy_t_3
		cmp [current_piece_rotation], 4 
		je destroy_t_4
		ret
		destroy_t_1:
			call blacktpiece_1
			ret
		destroy_t_2:
			call blacktpiece_2
			ret
		destroy_t_3:
			call blacktpiece_3
			ret
		destroy_t_4:
			call blacktpiece_4
			ret
	
	destroy_o:
		call blackopiece 
		ret
	destroy_j:
		cmp [current_piece_rotation], 1 
		je destroy_j_1
		cmp [current_piece_rotation], 2 
		je destroy_j_2
		cmp [current_piece_rotation], 3 
		je destroy_j_3
		cmp [current_piece_rotation], 4 
		je destroy_j_4
		ret
		destroy_j_1:
			call blackjpiece_1
			ret
		destroy_j_2:
			call blackjpiece_2
			ret
		destroy_j_3:
			call blackjpiece_3
			ret
		destroy_j_4:
			call blackjpiece_4
			ret
	
	destroy_l:
		cmp [current_piece_rotation], 1 
		je destroy_l_1
		cmp [current_piece_rotation], 2 
		je destroy_l_2
		cmp [current_piece_rotation], 3 
		je destroy_l_3
		cmp [current_piece_rotation], 4 
		je destroy_l_4
		ret
		destroy_l_1:
			call blacklpiece_1
			ret
		destroy_l_2:
			call blacklpiece_2
			ret
		destroy_l_3:
			call blacklpiece_3
			ret
		destroy_l_4:
			call blacklpiece_4
			ret
	
	destroy_i:
		push ax
		mov ax, [square_size]
		cmp [current_piece_rotation], 1 
		je destroy_i_1
		cmp [current_piece_rotation], 2 
		je destroy_i_2
		cmp [current_piece_rotation], 3 
		je destroy_i_3
		cmp [current_piece_rotation], 4 
		je destroy_i_4
		ret
		destroy_i_1:
			call blackipiece_1
			pop ax
			ret
		destroy_i_2:
			call blackipiece_2
			pop ax
			ret
		destroy_i_3:
			push ax
			mov ax, [square_size]
			add [y_coordinate], ax
			call blackipiece_1
			sub [y_coordinate], ax
			pop ax
			ret
		destroy_i_4:
			add [x_coordinate], ax
			call blackipiece_2
			sub [x_coordinate], ax
			pop ax
			ret
	
	destroy_s:
		push ax
		mov ax, [square_size]
		cmp [current_piece_rotation], 1 
		je destroy_s_1
		cmp [current_piece_rotation], 2 
		je destroy_s_2
		cmp [current_piece_rotation], 3 
		je destroy_s_3
		cmp [current_piece_rotation], 4 
		je destroy_s_4
		ret
		destroy_s_1:
			call blackspiece_1
			pop ax
			ret
		destroy_s_2:
			call blackspiece_2
			pop ax
			ret
		destroy_s_3:
			add [y_coordinate], ax
			call blackspiece_1
			sub [y_coordinate], ax
			pop ax
			ret
		destroy_s_4:
			add [x_coordinate], ax
			call blackspiece_2
			sub [x_coordinate], ax
			pop ax
			ret
	
	destroy_z:
		push ax
		mov ax, [square_size]
		cmp [current_piece_rotation], 1 
		je destroy_z_1
		cmp [current_piece_rotation], 2 
		je destroy_z_2
		cmp [current_piece_rotation], 3 
		je destroy_z_3
		cmp [current_piece_rotation], 4 
		je destroy_z_4
		ret
		destroy_z_1:
			call blackzpiece_1
			pop ax
			ret
		destroy_z_2:
			call blackzpiece_2
			pop ax
			ret
		destroy_z_3:
			add [y_coordinate], ax
			call blackzpiece_1
			sub [y_coordinate], ax
			pop ax
			ret
		destroy_z_4:
			add [x_coordinate], ax
			call blackzpiece_2
			sub [x_coordinate], ax
			pop ax
			ret
endp destroy_piece

proc move_down_lines
		pusha
		mov ax, [square_size] ; square size as a register
		mov cx, 10
	move_down_lines_columns:
		push cx

		push [y_coordinate]
		mov cx, 21
		sub cx, [line] ; for every line after 
	move_down_lines_move_down_squares:
		sub [y_coordinate], ax
		call readpixel
		cmp [pixelcolour], 0
		je move_down_lines_move_down_square_black
		cmp [pixelcolour], 0efh
		je move_down_lines_move_down_square_purple
		cmp [pixelcolour], 0bfh
		je move_down_lines_move_down_square_yellow
		cmp [pixelcolour], 9h
		je move_down_lines_move_down_square_blue
		cmp [pixelcolour], 77h
		je move_down_lines_move_down_square_orange
		cmp [pixelcolour], 0ffh
		je move_down_lines_move_down_square_cyan
		cmp [pixelcolour], 5fh
		je move_down_lines_move_down_square_red
		cmp [pixelcolour], 0bdh
		je move_down_lines_move_down_square_green
		jmp move_down_lines_move_down_squares_loopend

	move_down_lines_move_down_square_black:
		add [y_coordinate], ax ; a square down

		mov [light_colour], 0 ; black
		mov [main_colour], 0
		mov [border_colour], 0
		call drawSquare ; black current square

		sub [y_coordinate], ax ; return back

		jmp move_down_lines_move_down_squares_loopEnd

	move_down_lines_move_down_square_yellow:
		mov [light_colour], 0 ; black
		mov [main_colour], 0
		mov [border_colour], 0
		call drawSquare ; black current square

		add [y_coordinate], ax ; a square down

		mov [main_colour], 37h ; orangish yellow
		mov [light_colour], 0bfh ; light yellow
		mov [border_colour], 5dh ; brown

		call drawsquare; redraw it a square down

		sub [y_coordinate], ax ; return back

		jmp move_down_lines_move_down_squares_loopEnd

	move_down_lines_move_down_square_purple:
		mov [light_colour], 0 ; black
		mov [main_colour], 0
		mov [border_colour], 0
		call drawSquare ; black current square

		add [y_coordinate], ax ; a square down

		mov [light_colour], 0efh
		mov [main_colour], 0deh
		mov [border_colour], 83h

		call drawsquare; redraw it a square down

		sub [y_coordinate], ax ; return back

		jmp move_down_lines_move_down_squares_loopEnd

	move_down_lines_move_down_square_blue:
		mov [light_colour], 0 ; black
		mov [main_colour], 0
		mov [border_colour], 0
		call drawSquare ; black current square

		add [y_coordinate], ax ; a square down

		mov [light_colour], 9h ; blues
		mov [main_colour], 0d0h
		mov [border_colour], 40h

		call drawsquare; redraw it a square down

		sub [y_coordinate], ax ; return back

		jmp move_down_lines_move_down_squares_loopEnd

	move_down_lines_move_down_square_orange:
		mov [light_colour], 0 ; black
		mov [main_colour], 0
		mov [border_colour], 0
		call drawSquare ; black current square

		add [y_coordinate], ax ; a square down

		mov [light_colour], 77h ; orange
		mov [main_colour], 27h
		mov [border_colour], 15h

		call drawsquare; redraw it a square down

		sub [y_coordinate], ax ; return back

		jmp move_down_lines_move_down_squares_loopEnd

	move_down_lines_move_down_square_cyan:
		mov [light_colour], 0 ; black
		mov [main_colour], 0
		mov [border_colour], 0
		call drawSquare ; black current square

		add [y_coordinate], ax ; a square down

		mov [light_colour], 0ffh ; cyan
		mov [main_colour], 0feh
		mov [border_colour], 6h

		call drawsquare; redraw it a square down

		sub [y_coordinate], ax ; return back

		jmp move_down_lines_move_down_squares_loopEnd

	move_down_lines_move_down_square_green:
		mov [light_colour], 0 ; black
		mov [main_colour], 0
		mov [border_colour], 0
		call drawSquare ; black current square

		add [y_coordinate], ax ; a square down

		mov [light_colour], 0bdh ; greens
		mov [main_colour], 38h
		mov [border_colour], 22h

		call drawsquare; redraw it a square down

		sub [y_coordinate], ax ; return back

		jmp move_down_lines_move_down_squares_loopEnd

	move_down_lines_move_down_square_red:
		mov [light_colour], 0 ; black
		mov [main_colour], 0
		mov [border_colour], 0
		call drawSquare ; black current square

		add [y_coordinate], ax ; a square down

		mov [light_colour], 5fh ; reds
		mov [main_colour], 0f9h
		mov [border_colour], 01h

		call drawsquare; redraw it a square down

		sub [y_coordinate], ax ; return back

		jmp move_down_lines_move_down_squares_loopEnd

	move_down_lines_move_down_squares_loopEnd:
		loop move_down_lines_move_down_squares
		pop [y_coordinate]

		pop cx
		add [x_coordinate], ax
		loop move_down_lines_columns
		popa
		ret
endp move_down_lines

; utilities
proc is_game_over
		push [x_coordinate]
		push [y_coordinate]
		push ax

		mov ax, [square_size]
		mov [y_coordinate], 17 ; reset variables
		mov [x_coordinate], 144

		mov cx, 4
	is_game_over_loop:
		call readpixel
		cmp [pixelcolour], 0
		jne is_game_over_true
		
		add [y_coordinate], ax
		call readpixel
		cmp [pixelcolour], 0
		jne is_game_over_true

		sub [y_coordinate], ax
		add [x_coordinate], ax
		loop is_game_over_loop

		jmp is_game_over_end

	is_game_over_true:
		mov [game_over], 1

	is_game_over_end:
		pop ax
		pop [y_coordinate]
		pop [x_coordinate]
		ret
endp is_game_over

proc draw_queue_thumblnails
		pusha
		push [current_piece]
		mov [x_coordinate], 250
		mov [y_coordinate], 27
		mov bx, offset queue

		mov si, 0
		mov cx, 5
	draw_queue_thumbnails_loop:
		push [bx+si]
		pop [current_piece]

		mov [x_coordinate], 250
		cmp [current_piece], 1
		je draw_queue_thumbnail_io
		cmp [current_piece], 4
		je draw_queue_thumbnail_io

		draw_queue_thumbnail:
		call generate_piece
		add [y_coordinate], 34
		add si, 2
		loop draw_queue_thumbnails_loop

		jmp draw_queue_thumbnails_end
		draw_queue_thumbnail_io:
			sub [x_coordinate], 4
			jmp draw_queue_thumbnail

	draw_queue_thumbnails_end:
		pop [current_piece]
		popa
		ret
endp draw_queue_thumblnails

proc erase_queue_thumblnails
		pusha
		push [current_piece]
		mov [x_coordinate], 250
		mov [y_coordinate], 27
		mov bx, offset queue

		mov si, 0
		mov cx, 5
	erase_queue_thumbnails_loop:
		push [bx+si]
		pop [current_piece]
		mov [current_piece_rotation], 1

		mov [x_coordinate], 250
		cmp [current_piece], 1
		je erase_queue_thumbnail_io
		cmp [current_piece], 4
		je erase_queue_thumbnail_io

		erase_queue_thumbnail:
		call destroy_piece
		add [y_coordinate], 34
		add si, 2
		loop erase_queue_thumbnails_loop

		jmp erase_queue_thumbnails_end
		erase_queue_thumbnail_io:
			sub [x_coordinate], 4
			jmp erase_queue_thumbnail

	erase_queue_thumbnails_end:
		pop [current_piece]
		popa
		ret
endp erase_queue_thumblnails

proc draw_held_piece_thumbnail
		pusha
		push [current_piece]
		mov [y_coordinate], 38
		
		push [held_piece]
		pop [current_piece]

		cmp [current_piece], 1
		je draw_held_piece_thumbnail_io
		cmp [current_piece], 4
		je draw_held_piece_thumbnail_io

		mov [x_coordinate], 46
		call generate_piece
		pop [current_piece]
		popa
		ret

		draw_held_piece_thumbnail_io:
			mov [x_coordinate], 42
			call generate_piece
			pop [current_piece]
			popa
			ret
endp draw_held_piece_thumbnail

proc black_held_piece_thumbnail
		pusha
		push [current_piece]
		mov [y_coordinate], 38
		
		push [held_piece]
		pop [current_piece]

		cmp [current_piece], 1
		je black_held_piece_thumbnail_io
		cmp [current_piece], 4
		je black_held_piece_thumbnail_io

		mov [x_coordinate], 46 ; regular thumbnail position
		mov [current_piece_rotation], 1
		call destroy_piece
		pop [current_piece]
		popa
		ret

		black_held_piece_thumbnail_io: ; i and o thumbnail position
			mov [x_coordinate], 42
			mov [current_piece_rotation], 1
			call destroy_piece
			pop [current_piece]
			popa
			ret
endp black_held_piece_thumbnail

proc draw_score
	pusha

	mov bx, offset score
	mov dx, offset score
	mov si, 0
	mov cx, 10
	draw_score_add_loop:
		mov al, '0'
		add [bx+si], al
		inc si
		loop draw_score_add_loop

	call print_text

	mov si, 0
	mov cx, 10
	draw_score_sub_loop:
		mov al, '0'
		sub [bx+si], al
		inc si
		loop draw_score_sub_loop
	popa
	ret
endp draw_score

proc inc_score_first_digit
	pusha
	mov bx, offset score
	mov si, 9
	mov cx, 10
	inc_digit_1:
		inc [bx+si]
		mov dl, 9
		cmp [bx+si], dl
		ja digit_overflow_1
		popa
		ret
	digit_overflow_1:
		mov dl, 0
		mov [bx+si], dl
		dec si
		loop inc_digit_1
	popa
	ret
endp inc_score_first_digit

proc inc_score_second_digit
	pusha
	mov bx, offset score
	mov si, 8
	mov cx, 9
	inc_digit_2:
		inc [bx+si]
		mov dl, 9
		cmp [bx+si], dl
		ja digit_overflow_2
		popa
		ret
	digit_overflow_2:
		mov dl, 0
		mov [bx+si], dl
		dec si
		loop inc_digit_2
	popa
	ret
endp inc_score_second_digit

proc inc_score_third_digit
	pusha
	mov bx, offset score
	mov si, 7
	mov cx, 8
	inc_digit_3:
		inc [bx+si]
		mov dl, 9
		cmp [bx+si], dl
		ja digit_overflow_3
		popa
		ret
	digit_overflow_3:
		mov dl, 0
		mov [bx+si], dl
		dec si
		loop inc_digit_3
	popa
	ret
endp inc_score_third_digit

proc draw_level
	pusha

	mov bx, offset level
	mov dx, offset level
	mov si, 0
	mov cx, 2
	draw_level_add_loop:
		mov al, '0'
		add [bx+si], al
		inc si
		loop draw_level_add_loop

	call print_text

	mov si, 0
	mov cx, 2
	draw_level_sub_loop:
		mov al, '0'
		sub [bx+si], al
		inc si
		loop draw_level_sub_loop
	popa
	ret
endp draw_level

proc calculate_level
	pusha
	mov bx, offset level
	cmp [lines_cleared], 5
	jb level_0
	cmp [lines_cleared], 10
	jb level_1
	cmp [lines_cleared], 15
	jb level_2
	cmp [lines_cleared], 20
	jb level_3
	cmp [lines_cleared], 30
	jb level_4
	cmp [lines_cleared], 40
	jb level_5
	cmp [lines_cleared], 50
	jb level_6
	cmp [lines_cleared], 60
	jb level_7
	cmp [lines_cleared], 70
	jb level_8
	cmp [lines_cleared], 80
	jb level_9
	cmp [lines_cleared], 100
	jb level_10
	cmp [lines_cleared], 120
	jb level_11
	cmp [lines_cleared], 140
	jb level_12
	cmp [lines_cleared], 160
	jb level_13
	cmp [lines_cleared], 180
	jb level_14
	cmp [lines_cleared], 200
	jb level_15
	cmp [lines_cleared], 240
	jb level_16
	cmp [lines_cleared], 280
	jb level_17
	cmp [lines_cleared], 330
	jb level_18
	cmp [lines_cleared], 400
	jb level_19
	cmp [lines_cleared], 500
	jb level_20

	jmp level_21
	

	level_0:
		mov [level_num], 0
		mov al, 0
		mov [bx+1], al
		mov al, 0
		mov [bx+0], al
		mov [default_speed], 0ffffh
		popa
		ret
	level_1:
		mov [level_num], 1
		mov al, 1
		mov [bx+1], al
		mov al, 0
		mov [bx+0], al
		mov [default_speed], 0e000h
		popa
		ret
	level_2:
		mov [level_num], 2
		mov al, 2
		mov [bx+1], al
		mov al, 0
		mov [bx+0], al
		mov [default_speed], 0d000h
		popa
		ret
	level_3:
		mov [level_num], 3
		mov al, 3
		mov [bx+1], al
		mov al, 0
		mov [bx+0], al
		mov [default_speed], 0c000h
		popa
		ret
	level_4:
		mov [level_num], 4
		mov al, 4
		mov [bx+1], al
		mov al, 0
		mov [bx+0], al
		mov [default_speed], 0b000h
		popa
		ret
	level_5:
		mov [level_num], 5
		mov al, 5
		mov [bx+1], al
		mov al, 0
		mov [bx+0], al
		mov [default_speed], 0afffh
		popa
		ret
	level_6:
		mov [level_num], 6
		mov al, 6
		mov [bx+1], al
		mov al, 0
		mov [bx+0], al
		mov [default_speed], 09800h
		popa
		ret
	level_7:
		mov [level_num], 7
		mov al, 7
		mov [bx+1], al
		mov al, 0
		mov [bx+0], al
		mov [default_speed], 09000h
		popa
		ret
	level_8:
		mov [level_num], 8
		mov al, 8
		mov [bx+1], al
		mov al, 0
		mov [bx+0], al
		mov [default_speed], 08800h
		popa
		ret
	level_9:
		mov [level_num], 9
		mov al, 9
		mov [bx+1], al
		mov al, 0
		mov [bx+0], al
		mov [default_speed], 08000h
		popa
		ret
	level_10:
		mov [level_num], 10
		mov al, 0
		mov [bx+1], al
		mov al, 1
		mov [bx+0], al
		mov [default_speed], 07800h
		popa
		ret
	level_11:
		mov [level_num], 11
		mov al, 1
		mov [bx+1], al
		mov al, 1
		mov [bx+0], al
		mov [default_speed], 07000h
		popa
		ret
	level_12:
		mov [level_num], 12
		mov al, 2
		mov [bx+1], al
		mov al, 1
		mov [bx+0], al
		mov [default_speed], 06000h
		popa
		ret
	level_13:
		mov [level_num], 13
		mov al, 3
		mov [bx+1], al
		mov al, 1
		mov [bx+0], al
		mov [default_speed], 05000h
		popa
		ret
	level_14:
		mov [level_num], 14
		mov al, 4
		mov [bx+1], al
		mov al, 1
		mov [bx+0], al
		mov [default_speed], 04000h
		popa
		ret
	level_15:
		mov [level_num], 15
		mov al, 5
		mov [bx+1], al
		mov al, 1
		mov [bx+0], al
		mov [default_speed], 03000h
		popa
		ret
	level_16:
		mov [level_num], 16
		mov al, 6
		mov [bx+1], al
		mov al, 1
		mov [bx+0], al
		mov [default_speed], 02000h
		popa
		ret
	level_17:
		mov [level_num], 17
		mov al, 7
		mov [bx+1], al
		mov al, 1
		mov [bx+0], al
		mov [default_speed], 01000h
		popa
		ret
	level_18:
		mov [level_num], 18
		mov al, 8
		mov [bx+1], al
		mov al, 1
		mov [bx+0], al
		mov [default_speed], 800h
		popa
		ret
	level_19:
		mov [level_num], 19
		mov al, 9
		mov [bx+1], al
		mov al, 1
		mov [bx+0], al
		mov [default_speed], 750h
		popa
		ret
	level_20:
		mov [level_num], 20
		mov al, 0
		mov [bx+1], al
		mov al, 2
		mov [bx+0], al
		mov [default_speed], 400h
		popa
		ret
	level_21:
		mov [level_num], 21
		mov al, 1
		mov [bx+1], al
		mov al, 2
		mov [bx+0], al
		mov [default_speed], 200h
		popa
		ret
endp calculate_level

proc draw_cleared_lines
	pusha

	mov bx, offset lines_cleared_printable
	mov dx, offset lines_cleared_printable
	mov si, 0
	mov cx, 3
	draw_cleared_lines_add_loop:
		mov al, '0'
		add [bx+si], al
		inc si
		loop draw_cleared_lines_add_loop

	call print_text

	mov si, 0
	mov cx, 3
	draw_cleared_lines_sub_loop:
		mov al, '0'
		sub [bx+si], al
		inc si
		loop draw_cleared_lines_sub_loop
	popa
	ret
endp draw_cleared_lines

proc inc_cleared_lines
	pusha
	mov bx, offset lines_cleared_printable
	mov si, 2
	mov cx, 3
	inc_digit_cleared_lines:
		inc [bx+si]
		mov dl, 9
		cmp [bx+si], dl
		ja digit_overflow_cleared_lines
		popa
		ret
	digit_overflow_cleared_lines:
		mov dl, 0
		mov [bx+si], dl
		dec si
		loop inc_digit_cleared_lines
	popa
	ret
endp inc_cleared_lines

start:
mov ax, @data
mov ds, ax

;start screen:
	call entergraphicmode

	mov cx, offset filename2 ; print screen
	mov [filename], cx
    call OpenFile
    call ReadHeader
    call ReadPalette
    call CopyPal
    call CopyBitmap
	
	call waitforkeypress

	cmp [pressedkey], '1'
	je level_1_start
	cmp [pressedkey], '2'
	je level_2_start
	cmp [pressedkey], '3'
	je level_3_start
	cmp [pressedkey], '4'
	je level_4_start
	cmp [pressedkey], '5'
	je level_5_start
	cmp [pressedkey], '6'
	je level_6_start
	cmp [pressedkey], '7'
	je level_7_start
	cmp [pressedkey], '8'
	je level_8_start
	cmp [pressedkey], '9'
	je level_9_start
	jmp game_start

	level_1_start:
		mov [lines_cleared], 5
		jmp game_start
	level_2_start:
		mov [lines_cleared], 10
		jmp game_start
	level_3_start:
		mov [lines_cleared], 15
		jmp game_start
	level_4_start:
		mov [lines_cleared], 20
		jmp game_start
	level_5_start:
		mov [lines_cleared], 30
		jmp game_start
	level_6_start:
		mov [lines_cleared], 40
		jmp game_start
	level_7_start:
		mov [lines_cleared], 50
		jmp game_start
	level_8_start:
		mov [lines_cleared], 60
		jmp game_start
	level_9_start:
		mov [lines_cleared], 70
		jmp game_start

game_start:

    call entergraphicmode

	call initializerandom

	; initialize queue

	call generate_last_7_queue

	mov bx, offset queue
	mov cx, 7
	initial_move_queue_7_spots:
		push cx

		mov si, 2
		mov cx, 13
		initial_move_queue_loop:
			push [bx+si]
			sub si, 2
			pop [bx+si]
			add si, 4
			loop initial_move_queue_loop
		
		pop cx
		loop initial_move_queue_7_spots

	call generate_last_7_queue

	mov [queue_iteration], 0

	; Process BMP file

	mov cx, offset filename1 
	mov [filename], cx

    call OpenFile
    call ReadHeader
    call ReadPalette
    call CopyPal
    call CopyBitmap

	push 3 ;x coordinate
	push 15 ;y coordinate
	call cursor_location
	call draw_score

	push 11 ;x coordinate
	push 13 ;y coordinate
	call cursor_location
	call draw_level

	push 10 ;x coordinate
	push 17 ;y coordinate
	call cursor_location
	call draw_cleared_lines

mainGameLoop:
	; reset hard variables (so mechanisms like hold won't reset them)
	mov [held_this_turn], 0
	mov [lines_cleared_this_turn], 0

	; this code segment checks each row and if every square in it isn't empty (not black) if it is, this segment empties the row
	mov [x_coordinate], 120
	mov [y_coordinate], 17
	mov ax, [square_size] ; square size as a register

	mov cx, 21 ; for each row
	clearing_row_mechanism:
			push cx

			mov cx, 10 ; for every column in this row
		check_row_for_full:
			call readpixel 
			cmp [pixelcolour], 0 ; check each square if it's empty
			je finished_clearing_row_mechanism ; if a square is empty, finish without clearing the row and move on to the next one
			add [x_coordinate], ax
			loop check_row_for_full
			; reaches here only if the whole row isn't empty
			mov [x_coordinate], 120 ; reset x coord
			mov [main_colour], 0 ; black
			mov [light_colour], 0
			mov [border_colour], 0
			mov cx, 10 ; for 10 squares
			empty_row_columns:
				call drawsquare ; clear the square
				add [x_coordinate], ax
				loop empty_row_columns
			pop [line] ; get the line number to line from the stack
			push [line]
			mov [x_coordinate], 120 ; reset x coord
			call move_down_lines
			inc [lines_cleared_this_turn]
			inc [lines_cleared]
			call inc_cleared_lines
		finished_clearing_row_mechanism:
			mov [x_coordinate], 120 ; reset x coord
			add [y_coordinate], ax ; next row
			pop cx
		loop clearing_row_mechanism

		push 10 ;x coordinate
		push 17 ;y coordinate
		call cursor_location
		call draw_cleared_lines

		call calculate_level

		push 11 ;x coordinate
		push 13 ;y coordinate
		call cursor_location
		call draw_level

		; clearing lines-based score mechanism:
		cmp [lines_cleared_this_turn], 1
		je cleared_1_rows
		cmp [lines_cleared_this_turn], 2
		je cleared_2_rows
		cmp [lines_cleared_this_turn], 3
		je cleared_3_rows
		cmp [lines_cleared_this_turn], 4
		je cleared_4_rows
		jmp next_piece ; if didn't clear (or bugged)

		cleared_1_rows:
			mov ax, 4
			mov cl, [level_num]
			mov ch, 0
			inc cx
			mul cx
			mov cx, ax
			cleared_1_rows_score_loop:
				call inc_score_second_digit
				loop cleared_1_rows_score_loop

			push 3 ;x coordinate
			push 15 ;y coordinate
			call cursor_location
			call draw_score
			jmp next_piece

		cleared_2_rows:
			mov ax, 1
			mov cl, [level_num]
			mov ch, 0
			inc cx
			mul cx
			mov cx, ax
			cleared_2_rows_score_loop:
				call inc_score_third_digit
				loop cleared_2_rows_score_loop

			push 3 ;x coordinate
			push 15 ;y coordinate
			call cursor_location
			call draw_score
			jmp next_piece
		cleared_3_rows:
			mov ax, 3
			mov cl, [level_num]
			mov ch, 0
			inc cx
			mul cx
			mov cx, ax
			cleared_3_rows_score_loop:
				call inc_score_third_digit
				loop cleared_3_rows_score_loop

			push 3 ;x coordinate
			push 15 ;y coordinate
			call cursor_location
			call draw_score
			jmp next_piece
		cleared_4_rows:
			mov ax, 12
			mov cl, [level_num]
			mov ch, 0
			inc cx
			mul cx
			mov cx, ax
			cleared_4_rows_score_loop:
				call inc_score_third_digit
				loop cleared_4_rows_score_loop

			push 3 ;x coordinate
			push 15 ;y coordinate
			call cursor_location
			call draw_score
			jmp next_piece

	next_piece:
			call erase_queue_thumblnails

			mov bx, offset queue
			mov si, 0
			push [bx+si]
			pop [current_piece]
			mov si, 2
			mov cx, 13
		move_queue_loop:
			push [bx+si]
			sub si, 2
			pop [bx+si]
			add si, 4
			loop move_queue_loop

			inc [queue_iteration]
			cmp [queue_iteration], 7
			jb reset_vars
			
			call generate_last_7_queue
			mov [queue_iteration], 0

	reset_vars:
		call draw_queue_thumblnails

		mov [y_coordinate], 17 ; reset variables
		mov [x_coordinate], 144
		mov [move_down_failed], 0
		mov [current_piece_rotation], 1
		push [default_speed]
		pop [move_down_speed]
		mov [up_key_pressed], 0
		mov [game_over], 0
		call is_game_over
		cmp [game_over], 1
		je end_game
		call generate_piece ; spawn next piece

	falling_piece_loop:
		mov cx, 20 ; loop 20 times in order to have 20 chances to move in a block-length fall
		check_keyboard_loop:
			; check if thre is a charcter to read
			cmp [up_key_pressed], 1
			je fast_dropping ; up key means shooting it down, so just keeping on moving down until it reaches the next piece
			push [default_speed]
			pop [move_down_speed] ; slow down (for down key)
			mov [pressedkey], 0
			mov ah, 1h
			int 16h
			jz addDelay ; if no key was pressed, add delay
			
			; waits for character
			call waitforkeypress

			; was down key pressed? - speed up
			cmp ah, 50h
			je speed_up


			; was up key pressed? - super speed up
			cmp ah, 48h
			je skip_down
			
			; check if user asks to quit
			cmp [pressedkey], 27 ; esc to quit
			je end_game

			; Was right Key Pressed? - move right
			cmp ah, 4dh
			je rightKey

			; Was left Key Pressed? - move left
			cmp	ah, 4bh
			je leftKey

			; was a pressed? - rotate left
			cmp [pressedkey], 'a' 
			je leftRotation
			cmp [pressedkey], 'A' 
			je leftRotation

			; was a pressed? - rotate right
			cmp [pressedkey], 'd' 
			je rightRotation
			cmp [pressedkey], 'D' 
			je rightRotation

			; was space pressed? - hold
			cmp [pressedkey], ' ' 
			je hold

			jmp addDelay ; a wrong key is like no key at all

			rightKey:
				call move_right
				jmp addDelay

			leftKey:
				call move_left
				jmp addDelay

			speed_up:
				mov [move_down_speed], 0
				; flush type ahead buffer status
				jmp fast_dropping

			skip_down:
				mov [move_down_speed], 0
				mov [up_key_pressed], 1
				; flush type ahead buffer status
				mov ah, 0Ch
				mov al, 00h
				int 21h
				jmp fast_dropping

			leftRotation:
				call rotate_left
				; flush type ahead buffer status
				mov ah, 0Ch
				mov al, 00h
				int 21h
				jmp addDelay

			rightRotation:
				call rotate_right
				; flush type ahead buffer status
				mov ah, 0Ch
				mov al, 00h
				int 21h
				jmp addDelay

			hold:
				cmp [held_this_turn], 1
				je addDelay
				call destroy_piece
				cmp [held_piece], 6
				ja hold_first_piece
				jmp hold_new_piece

			fast_dropping:
				call inc_score_first_digit
				push 3 ;x coordinate
				push 15 ;y coordinate
				call cursor_location
				call draw_score
				mov cx, 1

			addDelay: 
				call delay ; add delay

			loop check_keyboard_loop ; do it 20 times before continuing

		call move_down ; after 20 times, move it one down
		
		cmp [move_down_failed], 1
		je maingameloop ; if move down failed, it means the piece reached the end
		
		jmp falling_piece_loop

	hold_first_piece:
		mov [held_this_turn], 1
		push [current_piece]
		pop [held_piece]
		call draw_held_piece_thumbnail
		jmp next_piece
		
	hold_new_piece:
		mov [held_this_turn], 1
		call black_held_piece_thumbnail
		push [current_piece]
		push [held_piece]
		pop [current_piece]
		pop [held_piece]
		call draw_held_piece_thumbnail
		jmp reset_vars
	
	
end_game:
	mov [move_down_speed], 0ffffh
	call delay

	call entergraphicmode

	mov cx, offset filename3 ; print screen
	mov [filename], cx
    call OpenFile
    call ReadHeader
    call ReadPalette
    call CopyPal
    call CopyBitmap

	push 15 ;x coordinate
	push 17 ;y coordinate
	call cursor_location
	call draw_score

	push 23 ;x coordinate
	push 15 ;y coordinate
	call cursor_location
	call draw_level

	push 22 ;x coordinate
	push 19 ;y coordinate
	call cursor_location
	call draw_cleared_lines

	call waitforkeypress

	;text mode
	mov al, 03h 
	mov ah, 0
	int 10h
exit:
mov ax, 4c00h
int 21h
END start
