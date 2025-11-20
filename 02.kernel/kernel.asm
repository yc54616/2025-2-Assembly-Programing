; 02.kernel/kernel.asm
; 기능: 더블 버퍼링, 드래그, 작업 표시줄, 앱 실행, 창 닫기, 시계(KST), **전원 끄기(OFF)**
bits 16
org 0x0000

    jmp start_kernel

; ---------------------------------------------------------
; [상수 및 변수 설정]
; ---------------------------------------------------------
BUFFER_SEG      equ 0x2000
VIDEO_SEG       equ 0xA000
SCREEN_WIDTH    equ 319
SCREEN_HEIGHT   equ 199

; --- 창(Window) 관련 변수 ---
window_x:       dw 100
window_y:       dw 80
window_width:   dw 140
window_height:  dw 80
title_bar_height: dw 12
window_title:   db "Hyeongwaha OS", 0x00
is_window_open: db 0

; 닫기 버튼
close_btn_size: dw 8
close_btn_off_x: dw 130
close_btn_off_y: dw 2

; --- 작업 표시줄 관련 변수 ---
taskbar_height: dw 14
taskbar_color:  db 0x18     ; Dark Grey

; 1. 앱 실행 버튼
btn_x:          dw 4
btn_y:          dw 188
btn_w:          dw 36
btn_h:          dw 10
btn_color:      db 0x07     ; Light Grey
btn_title:      db "App", 0x00

; 2. [추가] 전원 끄기 버튼 (시계 왼쪽)
off_btn_x:      dw 210      ; 시계(250)보다 왼쪽
off_btn_y:      dw 188
off_btn_w:      dw 30
off_btn_h:      dw 10
off_btn_color:  db 0x28     ; Red (강렬한 색)
off_btn_title:  db "OFF", 0x00

; 시계 관련
time_str:       db "00:00:00", 0x00
clock_x:        dw 250
clock_y:        dw 190

; --- 색상 정의 ---
border_color:   db 0x08
title_bar_color:db 0x09
content_color:  db 0x0F
bg_color:       db 0x00
font_color:     db 0x0F
close_btn_color:db 0x28     ; Red
clock_color:    db 0x0F     ; White

; --- 마우스 상태 ---
mouse_x:        dw 160
mouse_y:        dw 100
mouse_btn_left: db 0
mouse_btn_last: db 0
is_dragging:    db 0
drag_offset_x:  dw 0
drag_offset_y:  dw 0
needs_redraw:   dw 1

; --- PS/2 ---
m_cycle:        db 0
m_byte1:        db 0
m_byte2:        db 0
m_byte3:        db 0

; ---------------------------------------------------------
; [커서 비트맵]
; ---------------------------------------------------------
cursor_bitmap:
    dw 1000000000000000b
    dw 1100000000000000b
    dw 1110000000000000b
    dw 1111000000000000b
    dw 1111100000000000b
    dw 1111110000000000b
    dw 1111111000000000b
    dw 1111111100000000b
    dw 1111111110000000b
    dw 1111111111000000b
    dw 1111110000000000b
    dw 1110110000000000b
    dw 1100110000000000b
    dw 1000011000000000b
    dw 0000011000000000b
    dw 0000001100000000b

; ---------------------------------------------------------
; [커널 진입점]
; ---------------------------------------------------------
start_kernel:
    mov ax, 0x07E0
    mov ds, ax
    mov es, ax
    mov ss, ax
    mov sp, 0xFFFE
    mov bp, sp

    cli
    mov ax, 0x0013
    int 0x10
    call ps2_init

.main_loop:
    call update_system_time
    mov word [needs_redraw], 1

    in al, 0x64
    test al, 0x01
    jz .draw_step
    in al, 0x60
    call parse_ps2_packet

.draw_step:
    cmp word [needs_redraw], 1
    jne .next_loop

    call clear_screen
    call draw_taskbar

    cmp byte [is_window_open], 1
    jne .skip_window
    call draw_window
.skip_window:

    call draw_arrow_cursor
    call copy_buffer_to_screen
    mov word [needs_redraw], 0

.next_loop:
    jmp .main_loop

; ---------------------------------------------------------
; [시스템 종료 로직 (APM)]
; ---------------------------------------------------------
shutdown_system:
    ; APM Connect
    mov ax, 0x5301
    xor bx, bx
    int 0x15

    ; APM Enable Power Management
    mov ax, 0x5308
    mov bx, 0x0001
    mov cx, 0x0001
    int 0x15

    ; APM Set Power State (OFF)
    mov ax, 0x5307
    mov bx, 0x0001
    mov cx, 0x0003
    int 0x15

    ; 실패 시 무한 루프 (hlt)
    cli
    hlt
    jmp $

; ---------------------------------------------------------
; [시간 관련 함수 (KST +9, Modulo)]
; ---------------------------------------------------------
update_system_time:
    mov ah, 0x02
    int 0x1A
    ; Hour
    mov al, ch
    mov ah, al
    and al, 0x0F
    shr ah, 4
    mov bl, 10
    xchg al, ah
    mul bl
    add al, ah
    add al, 9
    xor ah, ah
    mov bl, 24
    div bl
    mov al, ah
    mov ah, 0
    mov bl, 10
    div bl
    shl al, 4
    or al, ah
    mov di, time_str
    call bcd_to_ascii
    ; Min
    mov al, cl
    mov di, time_str
    add di, 3
    call bcd_to_ascii
    ; Sec
    mov al, dh
    mov di, time_str
    add di, 6
    call bcd_to_ascii
    ret

bcd_to_ascii:
    push ax
    push bx
    mov bl, al
    shr al, 4
    add al, '0'
    mov [di], al
    mov al, bl
    and al, 0x0F
    add al, '0'
    mov [di+1], al
    pop bx
    pop ax
    ret

; ---------------------------------------------------------
; [화면 전송]
; ---------------------------------------------------------
copy_buffer_to_screen:
    push es
    push ds
    push si
    push di
    push cx
    push ax
    mov ax, BUFFER_SEG
    mov ds, ax
    xor si, si
    mov ax, VIDEO_SEG
    mov es, ax
    xor di, di
    cld
    mov cx, 32000
    rep movsw
    pop ax
    pop cx
    pop di
    pop si
    pop ds
    pop es
    ret

; ---------------------------------------------------------
; [이벤트 로직]
; ---------------------------------------------------------
handle_drag_logic:
    cmp byte [mouse_btn_left], 1
    je .btn_down
    mov byte [is_dragging], 0
    mov byte [mouse_btn_last], 0
    ret
.btn_down:
    cmp byte [is_dragging], 1
    je .move_logic
    cmp byte [mouse_btn_last], 0
    jne .update_history

    ; 1. 전원 끄기 버튼 확인 (최우선)
    call is_in_off_btn
    cmp ax, 1
    jne .check_app_btn
    jmp shutdown_system   ; 전원 끄기로 점프

.check_app_btn:
    ; 2. 앱 버튼 확인
    call is_in_taskbar_btn
    cmp ax, 1
    jne .check_window_click
    mov byte [is_window_open], 1
    mov word [needs_redraw], 1
    jmp .update_history

.check_window_click:
    cmp byte [is_window_open], 0
    je .update_history
    ; 3. 닫기 버튼 확인
    call is_in_close_btn
    cmp ax, 1
    jne .check_drag
    mov byte [is_window_open], 0
    mov word [needs_redraw], 1
    jmp .update_history

.check_drag:
    ; 4. 드래그 확인
    call is_in_titlebar
    cmp ax, 1
    jne .update_history
    mov byte [is_dragging], 1
    mov ax, [mouse_x]
    sub ax, [window_x]
    mov [drag_offset_x], ax
    mov ax, [mouse_y]
    sub ax, [window_y]
    mov [drag_offset_y], ax
    jmp .update_history

.move_logic:
    mov ax, [mouse_x]
    sub ax, [drag_offset_x]
    cmp ax, 0
    jge .chk_r
    mov ax, 0
    mov [window_x], ax
    add ax, [drag_offset_x]
    mov [mouse_x], ax
    jmp .calc_y
.chk_r:
    mov bx, SCREEN_WIDTH
    sub bx, [window_width]
    cmp ax, bx
    jle .set_x
    mov ax, bx
    mov [window_x], ax
    add ax, [drag_offset_x]
    mov [mouse_x], ax
    jmp .calc_y
.set_x:
    mov [window_x], ax
.calc_y:
    mov ax, [mouse_y]
    sub ax, [drag_offset_y]
    cmp ax, 0
    jge .chk_b
    mov ax, 0
    mov [window_y], ax
    add ax, [drag_offset_y]
    mov [mouse_y], ax
    jmp .finish_move
.chk_b:
    mov bx, SCREEN_HEIGHT
    sub bx, [taskbar_height]
    sub bx, [window_height]
    cmp ax, bx
    jle .set_y
    mov ax, bx
    mov [window_y], ax
    add ax, [drag_offset_y]
    mov [mouse_y], ax
    jmp .finish_move
.set_y:
    mov [window_y], ax
.finish_move:
    mov word [needs_redraw], 1
.update_history:
    mov al, [mouse_btn_left]
    mov [mouse_btn_last], al
    ret

; --- 충돌 체크 함수들 ---
is_in_off_btn:          ; [추가] 전원 버튼 충돌 체크
    mov ax, [mouse_x]
    cmp ax, [off_btn_x]
    jl .ret_false_off
    mov cx, [off_btn_x]
    add cx, [off_btn_w]
    cmp ax, cx
    jg .ret_false_off
    mov ax, [mouse_y]
    cmp ax, [off_btn_y]
    jl .ret_false_off
    mov cx, [off_btn_y]
    add cx, [off_btn_h]
    cmp ax, cx
    jg .ret_false_off
    mov ax, 1
    ret
.ret_false_off:
    xor ax, ax
    ret

is_in_close_btn:
    mov ax, [window_x]
    add ax, [close_btn_off_x]
    cmp [mouse_x], ax
    jl .ret_false_close
    add ax, [close_btn_size]
    cmp [mouse_x], ax
    jg .ret_false_close
    mov ax, [window_y]
    add ax, [close_btn_off_y]
    cmp [mouse_y], ax
    jl .ret_false_close
    add ax, [close_btn_size]
    cmp [mouse_y], ax
    jg .ret_false_close
    mov ax, 1
    ret
.ret_false_close:
    xor ax, ax
    ret

is_in_titlebar:
    mov ax, [mouse_x]
    cmp ax, [window_x]
    jl .ret_false
    mov cx, [window_x]
    add cx, [window_width]
    cmp ax, cx
    jg .ret_false
    mov ax, [mouse_y]
    cmp ax, [window_y]
    jl .ret_false
    mov cx, [window_y]
    add cx, [title_bar_height]
    cmp ax, cx
    jg .ret_false
    mov ax, 1
    ret
.ret_false:
    xor ax, ax
    ret

is_in_taskbar_btn:
    mov ax, [mouse_x]
    cmp ax, [btn_x]
    jl .ret_false_btn
    mov cx, [btn_x]
    add cx, [btn_w]
    cmp ax, cx
    jg .ret_false_btn
    mov ax, [mouse_y]
    cmp ax, [btn_y]
    jl .ret_false_btn
    mov cx, [btn_y]
    add cx, [btn_h]
    cmp ax, cx
    jg .ret_false_btn
    mov ax, 1
    ret
.ret_false_btn:
    xor ax, ax
    ret

; ---------------------------------------------------------
; [그리기 함수들]
; ---------------------------------------------------------
draw_window:
    push bp
    mov bp, sp
    push word [border_color]
    push word [window_height]
    push word [window_width]
    push word [window_y]
    push word [window_x]
    call draw_rect_param
    add sp, 10
    mov ax, [window_x]
    inc ax
    mov bx, [window_y]
    inc bx
    mov cx, [window_width]
    sub cx, 2
    push word [title_bar_color]
    push word [title_bar_height]
    push cx
    push bx
    push ax
    call draw_rect_param
    add sp, 10
    mov ax, [window_x]
    inc ax
    mov bx, [window_y]
    add bx, [title_bar_height]
    mov cx, [window_width]
    sub cx, 2
    mov dx, [window_height]
    sub dx, [title_bar_height]
    sub dx, 2
    push word [content_color]
    push dx
    push cx
    push bx
    push ax
    call draw_rect_param
    add sp, 10
    mov ax, [window_x]
    add ax, 4
    mov bx, [window_y]
    add bx, 2
    push word [font_color]
    push window_title
    push bx
    push ax
    call draw_string_param
    add sp, 8
    mov ax, [window_x]
    add ax, [close_btn_off_x]
    mov bx, [window_y]
    add bx, [close_btn_off_y]
    push word [close_btn_color]
    push word [close_btn_size]
    push word [close_btn_size]
    push bx
    push ax
    call draw_rect_param
    add sp, 10
    mov ax, [window_x]
    add ax, [close_btn_off_x]
    mov bx, [window_y]
    add bx, [close_btn_off_y]
    push word 0x0F
    push str_x
    push bx
    push ax
    call draw_string_param
    add sp, 8
    pop bp
    ret

draw_taskbar:
    push bp
    mov bp, sp
    ; 배경
    mov ax, SCREEN_HEIGHT
    sub ax, [taskbar_height]
    push word [taskbar_color]
    push word [taskbar_height]
    push word SCREEN_WIDTH
    push ax
    push word 0
    call draw_rect_param
    add sp, 10
    ; 앱 버튼
    push word [btn_color]
    push word [btn_h]
    push word [btn_w]
    push word [btn_y]
    push word [btn_x]
    call draw_rect_param
    add sp, 10
    mov ax, [btn_x]
    add ax, 6
    mov bx, [btn_y]
    add bx, 2
    push word 0x00
    push btn_title
    push bx
    push ax
    call draw_string_param
    add sp, 8
    
    ; [추가] 전원 끄기 버튼
    push word [off_btn_color]
    push word [off_btn_h]
    push word [off_btn_w]
    push word [off_btn_y]
    push word [off_btn_x]
    call draw_rect_param
    add sp, 10

    ; "OFF" 텍스트
    mov ax, [off_btn_x]
    add ax, 4   ; 텍스트 패딩
    mov bx, [off_btn_y]
    add bx, 2
    push word 0x0F ; White Text
    push off_btn_title
    push bx
    push ax
    call draw_string_param
    add sp, 8

    ; 시계
    push word [clock_color]
    push time_str
    push word [clock_y]
    push word [clock_x]
    call draw_string_param
    add sp, 8
    pop bp
    ret

clear_screen:
    push es
    push di
    push cx
    push ax
    mov ax, BUFFER_SEG
    mov es, ax
    xor di, di
    mov cx, 320*200
    mov al, [bg_color]
    rep stosb
    pop ax
    pop cx
    pop di
    pop es
    ret

draw_rect_param:
    push bp
    mov bp, sp
    push ax
    push bx
    push cx
    push si
    push di
    push es
    mov bx, BUFFER_SEG
    mov es, bx
    mov cx, [bp+10]
    mov si, [bp+6]
.y_loop:
    push cx
    mov bx, si
    mov di, si
    shl bx, 8
    shl di, 6
    add di, bx
    add di, [bp+4]
    mov ax, [bp+12]
    mov cx, [bp+8]
    rep stosb
    pop cx
    inc si
    loop .y_loop
    pop es
    pop di
    pop si
    pop cx
    pop bx
    pop ax
    pop bp
    ret

draw_string_param:
    push bp
    mov bp, sp
    push si
    mov si, [bp+8]
    mov bx, [bp+4]
    mov dx, [bp+6]
.loop:
    mov al, [ds:si]
    cmp al, 0
    je .end
    push word [bp+10]
    push ax
    push dx
    push bx
    call draw_char_param
    add sp, 8
    add bx, 8
    inc si
    jmp .loop
.end:
    pop si
    pop bp
    ret

draw_char_param:
    push bp
    mov bp, sp
    push ax
    push bx
    push cx
    push dx
    push si
    push di
    push es
    mov bx, BUFFER_SEG
    mov es, bx
    xor ax, ax
    mov al, [bp+8]
    sub al, 32
    shl ax, 3
    add ax, font_data
    mov si, ax
    mov ax, [bp+10]
    mov bh, al
    mov dx, [bp+6]
    mov cx, 8
.row:
    push cx
    mov bl, [ds:si]
    mov ax, dx
    mov di, ax
    shl ax, 8
    shl di, 6
    add di, ax
    add di, [bp+4]
    mov ch, 8
.pix:
    test bl, 0x80
    jz .skip
    mov [es:di], bh
.skip:
    shl bl, 1
    inc di
    dec ch
    jnz .pix
    inc si
    inc dx
    pop cx
    loop .row
    pop es
    pop di
    pop si
    pop dx
    pop cx
    pop bx
    pop ax
    pop bp
    ret

draw_arrow_cursor:
    push bp
    mov bp, sp
    push ax
    push bx
    push cx
    push dx
    push si
    push di
    push es
    mov ax, BUFFER_SEG 
    mov es, ax
    mov si, cursor_bitmap
    mov dx, [mouse_y]
    mov cx, 16
.row_loop:
    cmp dx, SCREEN_HEIGHT
    jge .end_draw
    mov bx, [si]
    push cx
    mov cx, 16
    mov di, [mouse_x]
.pixel_loop:
    test bx, 0x8000
    jz .skip_pixel
    cmp di, 0
    jl .skip_pixel
    cmp di, SCREEN_WIDTH
    jge .skip_pixel
    push bx
    push dx
    mov ax, dx
    mov bx, ax
    shl ax, 8
    shl bx, 6
    add ax, bx
    add ax, di
    mov bx, ax
    mov byte [es:bx], 0x0F
    pop dx
    pop bx
.skip_pixel:
    shl bx, 1
    inc di
    dec cx
    jnz .pixel_loop
    pop cx
    add si, 2
    inc dx
    loop .row_loop
.end_draw:
    pop es
    pop di
    pop si
    pop dx
    pop cx
    pop bx
    pop ax
    pop bp
    ret

; ---------------------------------------------------------
; [PS/2]
; ---------------------------------------------------------
ps2_init:
    call wait_write
    mov al, 0xA8
    out 0x64, al
    call wait_write
    mov al, 0xD4
    out 0x64, al
    call wait_write
    mov al, 0xF4
    out 0x60, al
    call wait_read
    in al, 0x60
    ret
wait_write:
    in al, 0x64
    test al, 0x02
    jnz wait_write
    ret
wait_read:
    in al, 0x64
    test al, 0x01
    jz wait_read
    ret
parse_ps2_packet:
    mov dl, al
    mov al, [m_cycle]
    cmp al, 0
    je .b1
    cmp al, 1
    je .b2
    cmp al, 2
    je .b3
    mov byte [m_cycle], 0
    ret
.b1:
    test dl, 0x08
    jz .reset
    mov [m_byte1], dl
    inc byte [m_cycle]
    ret
.b2:
    mov [m_byte2], dl
    inc byte [m_cycle]
    ret
.b3:
    mov [m_byte3], dl
    mov byte [m_cycle], 0
    call update_mouse_position
    ret
.reset:
    mov byte [m_cycle], 0
    ret
update_mouse_position:
    push ax
    push bx
    xor ax, ax
    mov al, [m_byte2]
    cbw
    sar ax, 1
    add [mouse_x], ax
    xor ax, ax
    mov al, [m_byte3]
    cbw
    sar ax, 1
    sub [mouse_y], ax
    cmp word [mouse_x], 0
    jge .cx
    mov word [mouse_x], 0
    jmp .cy
.cx:
    cmp word [mouse_x], 319
    jle .cy
    mov word [mouse_x], 319
.cy:
    cmp word [mouse_y], 0
    jge .cy1
    mov word [mouse_y], 0
    jmp .btn
.cy1:
    cmp word [mouse_y], 199
    jle .btn
    mov word [mouse_y], 199
.btn:
    mov al, [m_byte1]
    and al, 0x01
    mov [mouse_btn_left], al
    call handle_drag_logic
    mov word [needs_redraw], 1
    pop bx
    pop ax
    ret

; ---------------------------------------------------------
; [데이터]
; ---------------------------------------------------------
str_x:  db "X", 0x00

font_data:
    db 0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00 ; ' '
    db 0x18,0x3C,0x3C,0x18,0x18,0x00,0x18,0x00 ; '!'
    db 0x66,0x66,0x24,0x00,0x00,0x00,0x00,0x00 ; '"'
    db 0x00,0x6C,0xFE,0x6C,0xFE,0x6C,0x00,0x00 ; '#'
    db 0x18,0x3E,0x60,0x3C,0x06,0x7C,0x18,0x00 ; '$'
    db 0x00,0x63,0x66,0x0C,0x18,0x66,0x63,0x00 ; '%'
    db 0x1C,0x36,0x1C,0x38,0x6D,0x66,0x3B,0x00 ; '&'
    db 0x18,0x18,0x30,0x00,0x00,0x00,0x00,0x00 ; '''
    db 0x0C,0x18,0x30,0x60,0x60,0x30,0x18,0x0C ; '('
    db 0x60,0x30,0x18,0x0C,0x0C,0x18,0x30,0x60 ; ')'
    db 0x00,0x00,0x66,0x3C,0xFF,0x3C,0x66,0x00 ; '*'
    db 0x00,0x00,0x18,0x18,0x7E,0x18,0x18,0x00 ; '+'
    db 0x00,0x00,0x00,0x00,0x00,0x30,0x18,0x30 ; ','
    db 0x00,0x00,0x00,0x00,0x7E,0x00,0x00,0x00 ; '-'
    db 0x00,0x00,0x00,0x00,0x00,0x00,0x18,0x18 ; '.'
    db 0x00,0x06,0x0C,0x18,0x30,0x60,0x40,0x00 ; '/'
    db 0x3C,0x66,0x6E,0x76,0x7E,0x66,0x3C,0x00 ; '0'
    db 0x18,0x38,0x18,0x18,0x18,0x18,0x7E,0x00 ; '1'
    db 0x3C,0x66,0x06,0x0C,0x18,0x30,0x7E,0x00 ; '2'
    db 0x3C,0x66,0x06,0x1C,0x06,0x66,0x3C,0x00 ; '3'
    db 0x0C,0x1C,0x3C,0x6C,0xFE,0x0C,0x0C,0x00 ; '4'
    db 0x7E,0x60,0x7C,0x06,0x06,0x66,0x3C,0x00 ; '5'
    db 0x3C,0x60,0x60,0x7C,0x66,0x66,0x3C,0x00 ; '6'
    db 0x7E,0x66,0x06,0x0C,0x18,0x18,0x18,0x00 ; '7'
    db 0x3C,0x66,0x66,0x3C,0x66,0x66,0x3C,0x00 ; '8'
    db 0x3C,0x66,0x66,0x3E,0x06,0x0C,0x38,0x00 ; '9'
    db 0x00,0x00,0x18,0x18,0x00,0x00,0x18,0x18 ; ':'
    db 0x00,0x00,0x30,0x18,0x00,0x00,0x30,0x18 ; ';'
    db 0x0C,0x18,0x30,0x60,0x30,0x18,0x0C,0x00 ; '<'
    db 0x00,0x00,0x3C,0x00,0x3C,0x00,0x00,0x00 ; '='
    db 0x60,0x30,0x18,0x0C,0x18,0x30,0x60,0x00 ; '>'
    db 0x3C,0x66,0x06,0x0C,0x18,0x00,0x18,0x00 ; '?'
    db 0x3C,0x66,0x6E,0x6A,0x6E,0x60,0x3C,0x00 ; '@'
    db 0x18,0x3C,0x66,0x66,0x7E,0x66,0x66,0x00 ; 'A'
    db 0x7C,0x66,0x66,0x7C,0x66,0x66,0x7C,0x00 ; 'B'
    db 0x3C,0x66,0x60,0x60,0x60,0x66,0x3C,0x00 ; 'C'
    db 0x78,0x6C,0x66,0x66,0x66,0x6C,0x78,0x00 ; 'D'
    db 0x7E,0x60,0x60,0x7C,0x60,0x60,0x7E,0x00 ; 'E'
    db 0x7E,0x60,0x60,0x7C,0x60,0x60,0x60,0x00 ; 'F'
    db 0x3C,0x66,0x60,0x60,0x6E,0x66,0x3C,0x00 ; 'G'
    db 0x66,0x66,0x66,0x7E,0x66,0x66,0x66,0x00 ; 'H'
    db 0x3C,0x18,0x18,0x18,0x18,0x18,0x3C,0x00 ; 'I'
    db 0x0E,0x06,0x06,0x06,0x06,0x66,0x3C,0x00 ; 'J'
    db 0x66,0x6C,0x78,0x70,0x78,0x6C,0x66,0x00 ; 'K'
    db 0x60,0x60,0x60,0x60,0x60,0x60,0x7E,0x00 ; 'L'
    db 0xC6,0xEE,0xFE,0xD6,0xC6,0xC6,0xC6,0x00 ; 'M'
    db 0xC6,0xE6,0xF6,0xDE,0xCE,0xC6,0xC6,0x00 ; 'N'
    db 0x3C,0x66,0xC6,0xC6,0xC6,0x66,0x3C,0x00 ; 'O'
    db 0x7C,0x66,0x66,0x7C,0x60,0x60,0x60,0x00 ; 'P'
    db 0x3C,0x66,0xC6,0xC6,0xD6,0x76,0x3E,0x00 ; 'Q'
    db 0x7C,0x66,0x66,0x7C,0x78,0x6C,0x66,0x00 ; 'R'
    db 0x3C,0x66,0x60,0x3C,0x06,0x66,0x3C,0x00 ; 'S'
    db 0x7E,0x18,0x18,0x18,0x18,0x18,0x18,0x00 ; 'T'
    db 0x66,0x66,0x66,0x66,0x66,0x66,0x7E,0x00 ; 'U'
    db 0x66,0x66,0x66,0x66,0x66,0x3C,0x18,0x00 ; 'V'
    db 0xC6,0xC6,0xC6,0xD6,0xFE,0xEE,0xC6,0x00 ; 'W'
    db 0x66,0x66,0x3C,0x18,0x3C,0x66,0x66,0x00 ; 'X'
    db 0x66,0x66,0x66,0x3C,0x18,0x18,0x18,0x00 ; 'Y'
    db 0x7E,0x06,0x0C,0x18,0x30,0x60,0x7E,0x00 ; 'Z'
    db 0x3C,0x30,0x30,0x30,0x30,0x30,0x3C,0x00 ; '['
    db 0x00,0x40,0x60,0x30,0x18,0x0C,0x06,0x00 ; '\'
    db 0x3C,0x0C,0x0C,0x0C,0x0C,0x0C,0x3C,0x00 ; ']'
    db 0x24,0x66,0x3C,0x18,0x00,0x00,0x00,0x00 ; '^'
    db 0x00,0x00,0x00,0x00,0x00,0x00,0x00,0xFE ; '_'
    db 0x30,0x18,0x0C,0x00,0x00,0x00,0x00,0x00 ; '`'
    db 0x00,0x00,0x00,0x3C,0x06,0x3E,0x66,0x3E ; 'a'
    db 0x60,0x60,0x60,0x7C,0x66,0x66,0x7C,0x00 ; 'b'
    db 0x00,0x00,0x00,0x3C,0x60,0x60,0x60,0x3C ; 'c'
    db 0x06,0x06,0x06,0x3E,0x66,0x66,0x3E,0x00 ; 'd'
    db 0x00,0x00,0x00,0x3C,0x66,0x7E,0x60,0x3C ; 'e'
    db 0x0C,0x18,0x7E,0x18,0x18,0x18,0x18,0x00 ; 'f'
    db 0x00,0x00,0x3E,0x66,0x66,0x3E,0x06,0x7C ; 'g'
    db 0x60,0x60,0x60,0x7C,0x66,0x66,0x66,0x00 ; 'h'
    db 0x18,0x00,0x38,0x18,0x18,0x18,0x3C,0x00 ; 'i'
    db 0x06,0x00,0x0E,0x06,0x06,0x66,0x3C,0x00 ; 'j'
    db 0x60,0x60,0x6C,0x78,0x70,0x78,0x6C,0x00 ; 'k'
    db 0x18,0x18,0x18,0x18,0x18,0x18,0x3C,0x00 ; 'l'
    db 0x00,0x00,0xCC,0xFE,0xD6,0xD6,0xC6,0x00 ; 'm'
    db 0x00,0x00,0x00,0x7C,0x66,0x66,0x66,0x00 ; 'n'
    db 0x00,0x00,0x00,0x3C,0x66,0x66,0x66,0x3C ; 'o'
    db 0x00,0x00,0x00,0x7C,0x66,0x66,0x7C,0x60 ; 'p'
    db 0x00,0x00,0x00,0x3E,0x66,0x66,0x3E,0x06 ; 'q'
    db 0x00,0x00,0x00,0x7C,0x66,0x60,0x60,0x00 ; 'r'
    db 0x00,0x00,0x00,0x3C,0x60,0x3C,0x06,0x7C ; 's'
    db 0x18,0x18,0x7E,0x18,0x18,0x18,0x0C,0x00 ; 't'
    db 0x00,0x00,0x00,0x66,0x66,0x66,0x3E,0x00 ; 'u'
    db 0x00,0x00,0x00,0x66,0x66,0x3C,0x18,0x00 ; 'v'
    db 0x00,0x00,0xC6,0xD6,0xFE,0xEE,0xC6,0x00 ; 'w'
    db 0x00,0x00,0x00,0x66,0x3C,0x18,0x3C,0x66 ; 'x'
    db 0x00,0x00,0x00,0x66,0x66,0x3E,0x06,0x7C ; 'y'
    db 0x00,0x00,0x00,0x7E,0x0C,0x18,0x30,0x7E ; 'z'
    db 0x0C,0x18,0x18,0x30,0x18,0x18,0x0C,0x00 ; '{'
    db 0x18,0x18,0x18,0x00,0x18,0x18,0x18,0x00 ; '|'
    db 0x60,0x30,0x30,0x18,0x30,0x30,0x60,0x00 ; '}'
    db 0x00,0x3B,0x6E,0x00,0x00,0x00,0x00,0x00 ; '~'

times (512 * 15) - ($ - $$) db 0
