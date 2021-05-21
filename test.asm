
proc generate_last_7_queue
	; the official tetris random generator mechanism 
	; needs to load the queue every time with all of the 7 tetreminos
	; in a random order
	; this procedure does it
	mov bx, offset queue
	mov si, 14
	mov cx, 7

	reset_last_7_loop: ; 100 is not an avaliable spot, so 
		mov [bx+si], 100
		add si, 2
		loop reset_last_7_loop

	mov cx, 7
	generate_last_7_loop:
		mov [top_limit], cx ; generate a random location on the list
		call randomnum
		mov dl, [rand_num]
		mov dh, 0

		mov si, 0
		mov bx, offset used_spots
		push cx
		mov cx, 7
		check_if_spot_valid: ; check if the spot wasn't already taken 
			cmp [bx+si], dx 
			je if_spot_isnt_valid ; if the spot is already used
			add si, 2
			loop check_if_spot_valid
		
		jmp generate_last_7_set ; when the spot is valid, continue

		if_spot_isnt_valid:
			mov cx, 7
			mov si, 0

			inc dx
			cmp dl 7
			jnb check_if_spot_valid ; if dx is still in range 0-6 check again
			mov dx, 0 ; if it isn't start from the beginnig and
			jmp  check_if_spot_valid

		generate_last_7_set:

			

		mov si, dl
		add si, dl
		add si, 14

		loop generate_last_7_loop
	ret
endp generate_last_7_queue