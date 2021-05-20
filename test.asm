proc generate_last_7_queue
	mov bx, offset queue
	mov si, 14
	mov cx, 7
	reset_last_7_loop:
		mov [bx+si], 100
		add si, 2
		loop reset_last_7_loop

	mov cx, 7
	generate_last_7_loop:
		mov [top_limit], cx
		call randomnum
		mov dl, [rand_num]
		mov dh, 0

		mov si, 0
		mov bx, offset used_spots
		push cx
		mov cx, 7
		check_if_spot_valid:
			cmp [bx+si], dx
			je if_spot_isnt_valid
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

		mov

		loop generate_last_7_loop
	ret
endp generate_last_7_queue