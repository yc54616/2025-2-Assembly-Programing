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
CANVAS_SEG      equ 0x3000  ; 캔버스 데이터 세그먼트

SCREEN_WIDTH    equ 319
SCREEN_HEIGHT   equ 199
SCREEN_PITCH    equ 320      ; 한 줄에 실제 픽셀 수(320)

CANVAS_WIDTH    equ 310    ; window_width(312) - 좌우 테두리 1px * 2
CANVAS_HEIGHT   equ 166    ; window_height(180) - title_bar(12) - 상/하 테두리(2)

PAINT_COLOR      equ 0x00     ; 기본 색(검정) - 초기값
CANVAS_BG_COLOR  equ 0x0F     ; 배경(흰색)

PALETTE_COUNT       equ 4
PALETTE_CELL_SIZE   equ 8
PALETTE_STEP        equ 10     ; 셀(8px) + 간격(2px)

paint_color:    db PAINT_COLOR

; --- 그리기 모드 정의 ---
DRAW_MODE_PEN      equ 0
DRAW_MODE_LINE     equ 1
DRAW_MODE_RECT     equ 2
; DRAW_MODE_CIRCLE   equ 3        ; (알고리즘 설명만)
DRAW_MODE_ELLIPSE  equ 4        ; (알고리즘 설명만)
DRAW_MODE_ERASER   equ 5        ; [추가] 지우개 모드

current_draw_mode: db DRAW_MODE_PEN   ; 기본은 펜

; --- 도형 시작/끝점 & 상태 ---
shape_pending: db 0        ; 0: 없음, 1: 시작점 저장됨
shape_start_x: dw 0
shape_start_y: dw 0
shape_end_x:   dw 0
shape_end_y:   dw 0

; --- 선(Bresenham)용 임시 변수 ---
line_dx:   dw 0
line_dy:   dw 0
line_sx:   dw 0
line_sy:   dw 0
line_err:  dw 0
line_e2:   dw 0
line_x1:   dw 0
line_y1:   dw 0

; --- 사각형 계산용 임시 변수 ---
rect_x0: dw 0
rect_y0: dw 0
rect_x1: dw 0
rect_y1: dw 0

; 팔레트에 표시할 색들 (순서대로)
palette_colors:
    db 0x00, 0x04, 0x02, 0x01   ; 검정, 빨강, 초록, 파랑

; 각 팔레트 셀의 X 오프셋 (window_x 기준)
; window_x + 4, 14, 24, 34에 놓인다고 보면 됨
palette_x_offsets:
    db 4, 14, 24, 34

; --- 창(Window) 관련 변수 ---
window_x:       dw 4          ; 왼쪽에서 약간만 띄움
window_y:       dw 4          ; 위쪽에서 약간만 띄움
window_width:   dw 312        ; 폭 많이 키움 (0..319 중 4~315 사용)
window_height:  dw 180        ; 높이 많이 키움 (아래 taskbar 위까지)
title_bar_height: dw 12       ; 그대로
window_title:   db "Hyungwaha OS", 0x00
is_window_open: db 0

; 닫기 버튼
close_btn_size: dw 8
close_btn_off_x: dw 2      ; 오른쪽 테두리로부터 여백 2px
close_btn_off_y: dw 2      ; 위쪽 여백 그대로

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
    call check_keyboard_tool     
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
; [키보드 입력] 
;   '1': 펜, '2': 직선, '3': 사각형
;   '5': 원, '0': 지우개
; ---------------------------------------------------------
check_keyboard_tool:
    push ax
    push bx

    mov ah, 01h
    int 16h
    jz .no_key

    mov ah, 00h
    int 16h

    cmp al, '1'
    je .mode_pen
    cmp al, '2'
    je .mode_line
    cmp al, '3'
    je .mode_rect
    cmp al, '0'         ; [추가] 지우개
    je .mode_eraser

    jmp .no_key

.mode_pen:
    mov byte [current_draw_mode], DRAW_MODE_PEN
    jmp .no_key
.mode_line:
    mov byte [current_draw_mode], DRAW_MODE_LINE
    jmp .no_key
.mode_rect:
    mov byte [current_draw_mode], DRAW_MODE_RECT
    jmp .no_key
.mode_eraser:           ; [추가]
    mov byte [current_draw_mode], DRAW_MODE_ERASER
    jmp .no_key

.no_key:
    pop bx
    pop ax
    ret

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
; [시간 관련 함수] 수정됨
; 기능: 복잡한 연산 없이 BIOS 시간을 그대로 가져와서 출력
; ---------------------------------------------------------
update_system_time:
    ; 1. BIOS로 시간 읽기 (RTC)
    mov ah, 0x02
    int 0x1A            ; 반환값 -> CH:시, CL:분, DH:초 (모두 BCD 포맷)

    ; 2. 시 (Hour) 출력
    mov al, ch          ; 시 (예: 오후 1시면 0x13)
    mov di, time_str    ; 문자열 버퍼 포인터
    call bcd_to_ascii   ; 변환해서 저장

    ; 3. 분 (Minute) 출력
    mov al, cl          ; 분
    add di, 3           ; "HH:" 다음 위치인 'MM' 자리로 이동
    call bcd_to_ascii

    ; 4. 초 (Second) 출력
    mov al, dh          ; 초
    add di, 3           ; "MM:" 다음 위치인 'SS' 자리로 이동
    call bcd_to_ascii
    
    ret

; ---------------------------------------------------------
; [BCD to ASCII 변환 함수]
; 입력: AL (BCD 값, 예: 0x59)
; 출력: [DI] 위치에 아스키 코드 2글자 기록 ('5', '9')
; ---------------------------------------------------------
bcd_to_ascii:
    push ax
    push bx
    
    ; 첫 번째 자리 (10의 자리) 처리
    mov bl, al          ; AL 값 백업 (예: 0x59)
    shr al, 4           ; 오른쪽으로 4비트 밀기 (0x59 -> 0x05)
    add al, '0'         ; 숫자를 문자로 ('0' 더하기)
    mov [di], al        ; 화면 버퍼에 기록

    ; 두 번째 자리 (1의 자리) 처리
    mov al, bl          ; 백업해둔 원래 값 복구 (0x59)
    and al, 0x0F        ; 하위 4비트만 남기기 (0x59 -> 0x09)
    add al, '0'         ; 숫자를 문자로
    mov [di+1], al      ; 다음 칸에 기록
    
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
; [캔버스 픽셀 찍기]
;   입력:
;       AX = canvas_y (0..CANVAS_HEIGHT-1)
;       BX = canvas_x (0..CANVAS_WIDTH-1)
;   동작:
;       범위 체크 후 CANVAS_SEG 메모리에 paint_color로 1픽셀 기록
; ---------------------------------------------------------
app_plot_pixel:
    push dx
    push di
    push es
    push ax
    push bx

    ; x 범위 체크
    cmp bx, 0
    jl  .done
    cmp bx, CANVAS_WIDTH
    jge .done

    ; y 범위 체크
    cmp ax, 0
    jl  .done
    cmp ax, CANVAS_HEIGHT
    jge .done

    ; offset = y * CANVAS_WIDTH + x
    mov dx, CANVAS_WIDTH
    mul dx                  ; DX:AX = AX * DX (y * width)
    add ax, bx              ; AX = offset
    mov di, ax

    mov ax, CANVAS_SEG
    mov es, ax
    mov al, [paint_color]
    mov [es:di], al

.done:
    pop bx
    pop ax
    pop es
    pop di
    pop dx
    ret
; ---------------------------------------------------------
; [이벤트 로직]
; ---------------------------------------------------------
handle_drag_logic:
    ; [추가] 그림판 입력 처리 호출 (드래그 확인 전에 체크)
    call app_handle_input
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
    ; [수정] 이미 열려있으면 초기화하지 않고, 닫혀있을 때만 열고 초기화
    cmp byte [is_window_open], 1
    je .update_history
    
    mov byte [is_window_open], 1
    call app_init           ; [추가] 앱 열릴 때 캔버스 초기화
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
    ; btn_x = window_x + window_width - close_btn_size - close_btn_off_x
    mov ax, [window_x]
    add ax, [window_width]
    sub ax, [close_btn_size]
    sub ax, [close_btn_off_x]     ; AX = btn_x

    ; X 범위 체크: [btn_x, btn_x + close_btn_size)
    mov dx, ax                    ; DX = btn_x
    cmp [mouse_x], dx
    jl .ret_false_close
    add dx, [close_btn_size]
    cmp [mouse_x], dx
    jge .ret_false_close

    ; Y 범위 체크: [window_y + off_y, window_y + off_y + close_btn_size)
    mov ax, [window_y]
    add ax, [close_btn_off_y]     ; AX = btn_y
    mov dx, ax                    ; DX = btn_y
    cmp [mouse_y], dx
    jl .ret_false_close
    add dx, [close_btn_size]
    cmp [mouse_y], dx
    jge .ret_false_close

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

    ; 창 외곽 테두리
    push word [border_color]
    push word [window_height]
    push word [window_width]
    push word [window_y]
    push word [window_x]
    call draw_rect_param
    add sp, 10

    ; 타이틀바
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

    ; 내용 영역(흰색 배경)
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

    ; 타이틀 문자열
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

    ; --- 닫기 버튼 사각형 그리기 (우측 상단) ---
    ; btn_x = window_x + window_width - close_btn_size - close_btn_off_x
    mov ax, [window_x]
    add ax, [window_width]
    sub ax, [close_btn_size]
    sub ax, [close_btn_off_x]     ; 오른쪽에서 여백만큼 안쪽
    mov dx, ax                    ; DX = btn_x

    mov bx, [window_y]
    add bx, [close_btn_off_y]     ; btn_y

    push word [close_btn_color]
    push word [close_btn_size]
    push word [close_btn_size]
    push bx                       ; y
    push dx                       ; x
    call draw_rect_param
    add sp, 10

    ; --- 그림판 캔버스 내용 그리기 ---
    call app_draw_content

    ; --- 'X' 문자 그리기 (버튼 안쪽에)
    mov ax, dx                    ; btn_x
    ; add ax, 2                     ; 약간 안쪽으로
    mov bx, [window_y]
    add bx, [close_btn_off_y]
    ; add bx, 1                     ; 세로로도 약간 내림

    push word 0x0F
    push str_x
    push bx
    push ax
    call draw_string_param
    add sp, 8

    ; ============================================
    ; 5번: 색상 팔레트 그리기 (내용 영역 상단 왼쪽)
    ; ============================================
    push ax
    push bx
    push cx
    push dx
    push si

    mov cx, PALETTE_COUNT         ; 색 개수 (예: 4)
    xor si, si                    ; 인덱스 0..3

.palette_draw_loop:
    ; 색값 읽기
    mov bx, palette_colors
    mov dl, [bx+si]               ; DL = 색상
    xor dh, dh                    ; DX = color (word)

    ; x = window_x + palette_x_offsets[si]
    mov bx, palette_x_offsets
    mov al, [bx+si]
    xor ah, ah
    add ax, [window_x]            ; AX = x

    ; y = window_y + title_bar_height + 2
    mov bx, [window_y]
    add bx, [title_bar_height]
    add bx, 2                     ; BX = y

    ; 작은 사각형으로 팔레트 셀 그리기
    push dx                       ; color
    push word PALETTE_CELL_SIZE   ; height
    push word PALETTE_CELL_SIZE   ; width
    push bx                       ; y
    push ax                       ; x
    call draw_rect_param
    add sp, 10

    inc si
    loop .palette_draw_loop

    pop si
    pop dx
    pop cx
    pop bx
    pop ax
    ; ============================================

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

; ---------------------------------------------------------
; [커서 그리기] 흰색 커서 + 검은 테두리
;   - draw_cursor_at()을 여러 번 호출해서
;     테두리(검정) 4방향 + 중앙(흰색)을 그림
; ---------------------------------------------------------
draw_arrow_cursor:
    push bp
    mov bp, sp

    ; 1) 테두리 색: 검정 (0x00)
    ; 왼쪽 (x-1, y)
    mov ax, [mouse_x]
    dec ax
    mov dx, [mouse_y]
    push word 0x00          ; color = black
    push dx                 ; base_y
    push ax                 ; base_x
    call draw_cursor_at
    add sp, 6

    ; 오른쪽 (x+1, y)
    mov ax, [mouse_x]
    inc ax
    mov dx, [mouse_y]
    push word 0x00
    push dx
    push ax
    call draw_cursor_at
    add sp, 6

    ; 위 (x, y-1)
    mov ax, [mouse_x]
    mov dx, [mouse_y]
    dec dx
    push word 0x00
    push dx
    push ax
    call draw_cursor_at
    add sp, 6

    ; 아래 (x, y+1)
    mov ax, [mouse_x]
    mov dx, [mouse_y]
    inc dx
    push word 0x00
    push dx
    push ax
    call draw_cursor_at
    add sp, 6

    ; 2) 가운데 커서: 흰색 (0x0F)
    mov ax, [mouse_x]
    mov dx, [mouse_y]
    push word 0x0F          ; color = white
    push dx
    push ax
    call draw_cursor_at
    add sp, 6

    pop bp
    ret
; ---------------------------------------------------------
; [헬퍼] draw_cursor_at
;   인자 (stack):
;     [bp+4]  = base_x (word)
;     [bp+6]  = base_y (word)
;     [bp+8]  = color  (byte, word로 푸시됨)
;   역할:
;     cursor_bitmap(16x16)을 (base_x, base_y)에 color로 그림
;     화면 밖으로 나가는 부분은 안전하게 클리핑
; ---------------------------------------------------------
draw_cursor_at:
    push bp
    mov bp, sp

    push ax
    push bx
    push cx
    push dx
    push si
    push di
    push es

    ; 화면 버퍼 세그먼트 설정
    mov ax, BUFFER_SEG
    mov es, ax

    ; 커서 비트맵 시작 주소
    mov si, cursor_bitmap

    ; 현재 y = base_y
    mov dx, [bp+6]
    mov cx, 16              ; 총 16줄

.row_loop:
    ; --- 세로 클리핑 ---
    cmp dx, 0
    jl .row_next            ; 화면 위쪽(음수) → 이 줄 스킵
    cmp dx, SCREEN_HEIGHT
    jge .row_next           ; 화면 아래쪽 넘으면 스킵

    ; 이 줄은 화면 안에 있으니, 픽셀 단위 루프 진행
    push cx                 ; 바깥 루프 카운트 보존

    mov bx, [si]            ; 현재 줄의 16비트 패턴
    mov cx, 16              ; 가로 16픽셀
    mov di, [bp+4]          ; x = base_x

.pixel_loop:
    test bx, 0x8000
    jz .skip_pixel

    ; --- 가로 클리핑 ---
    cmp di, 0
    jl  .skip_pixel2
    cmp di, SCREEN_WIDTH
    jg  .skip_pixel2

    ; 여기까지 왔으면 (di, dx)가 화면 안
    ; 오프셋 = y*320 + x
    push ax
    push dx
    push bx

    mov ax, dx
    mov bx, ax
    shl ax, 8
    shl bx, 6
    add ax, bx              ; ax = y*320
    add ax, di              ; ax = y*320 + x
    mov bx, ax

    mov al, byte [bp+8]     ; color
    mov [es:bx], al

    pop bx
    pop dx
    pop ax

.skip_pixel2:
.skip_pixel:
    shl bx, 1               ; 다음 비트
    inc di                  ; x++
    dec cx
    jnz .pixel_loop

    pop cx                  ; 바깥 루프 카운트 복원

.row_next:
    add si, 2               ; 다음 비트맵 줄
    inc dx                  ; y++
    loop .row_loop

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
; [헬퍼] canvas_from_mouse
;   입력:  [mouse_x], [mouse_y], [window_x], [window_y], [title_bar_height]
;   출력:
;       CF = 0이면 캔버스 안에 있음
;           AX = canvas_y (0 .. CANVAS_HEIGHT-1)
;           BX = canvas_x (0 .. CANVAS_WIDTH-1)
;       CF = 1이면 캔버스 밖
; ---------------------------------------------------------
canvas_from_mouse:
    push dx

    ; X 방향: mouse_x - window_x - 1(왼쪽 테두리)
    mov ax, [mouse_x]
    sub ax, [window_x]
    sub ax, 1                       ; 왼쪽 테두리 1px

    cmp ax, 0
    jl  .outside
    cmp ax, CANVAS_WIDTH
    jge .outside
    mov bx, ax                      ; BX = canvas_x

    ; Y 방향: mouse_y - window_y - title_bar_height
    mov ax, [mouse_y]
    sub ax, [window_y]
    sub ax, [title_bar_height]

    cmp ax, 0
    jl  .outside
    cmp ax, CANVAS_HEIGHT
    jge .outside

    ; 여기까지 왔으면 (BX, AX)가 유효한 캔버스 좌표
    clc                             ; CF=0 (inside)
    pop dx
    ret

.outside:
    stc                             ; CF=1 (outside)
    pop dx
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
; [앱 초기화] 캔버스 메모리를 흰색으로 채움
; ---------------------------------------------------------
app_init:
    push ax
    push cx
    push di
    push es

    mov ax, CANVAS_SEG
    mov es, ax
    xor di, di
    mov cx, CANVAS_WIDTH * CANVAS_HEIGHT   ; 138 * 66 = 9108 바이트
    mov al, CANVAS_BG_COLOR                ; 흰색
    rep stosb

    pop es
    pop di
    pop cx
    pop ax
    ret

; ---------------------------------------------------------
; [앱 입력 처리]
; ---------------------------------------------------------
app_handle_input:
    cmp byte [is_window_open], 1
    jne .end

    mov bl, [mouse_btn_last]
    mov bh, [mouse_btn_left]

    ; 1) 팔레트 클릭
    cmp bh, 1
    jne .after_palette
    call app_check_palette_click
    cmp ax, 1
    je .end
.after_palette:

    ; 2) 펜 또는 지우개 (연속 그리기)
    mov al, [current_draw_mode]
    cmp al, DRAW_MODE_PEN
    je .continuous_draw
    cmp al, DRAW_MODE_ERASER
    je .continuous_draw
    jmp .shape_mode

.continuous_draw:
    cmp bh, 1
    jne .end

    call canvas_from_mouse
    jc   .end
    ; 현재 AX=canvas_y, BX=canvas_x

    cmp byte [current_draw_mode], DRAW_MODE_ERASER
    je .do_eraser_big    ; [수정] 큰 지우개 로직으로 점프

    ; [일반 펜]
    call app_plot_pixel
    jmp .pen_finish

.do_eraser_big:
    ; -----------------------------------------------------
    ; [지우개 확대 로직] 9x9 크기 정사각형 (중심 기준 -4 ~ +4)
    ; -----------------------------------------------------
    push ax
    push bx
    push cx
    push dx
    push si
    push di
    push word [paint_color]      ; 기존 색상 백업

    mov byte [paint_color], 0x0F ; 흰색 설정

    mov cx, bx  ; CX = 중심 X
    mov dx, ax  ; DX = 중심 Y

    ; Y 루프: -4 ~ +4
    mov si, -8
.er_loop_y:
    cmp si, 8
    jg .er_done

    ; X 루프: -4 ~ +4
    mov di, -8
.er_loop_x:
    cmp di, 8
    jg .er_next_y

    ; 그릴 좌표 계산: BX = center_x + di, AX = center_y + si
    mov bx, cx
    add bx, di
    mov ax, dx
    add ax, si

    call app_plot_pixel ; 픽셀 찍기 (범위 벗어나면 함수 내부에서 무시됨)

    inc di
    jmp .er_loop_x

.er_next_y:
    inc si
    jmp .er_loop_y

.er_done:
    pop word [paint_color]       ; 색상 복구
    pop di
    pop si
    pop dx
    pop cx
    pop bx
    pop ax
    ; -----------------------------------------------------

.pen_finish:
    mov word [needs_redraw], 1
    jmp .end

.shape_mode:
    ; (1) 시작점
    cmp bl, 0
    jne .check_release
    cmp bh, 1
    jne .check_release

    call canvas_from_mouse
    jc   .end
    mov [shape_start_y], ax
    mov [shape_start_x], bx
    mov byte [shape_pending], 1
    jmp .end

.check_release:
    ; (2) 끝점
    cmp bl, 1
    jne .end
    cmp bh, 0
    jne .end

    cmp byte [shape_pending], 1
    jne .end

    call canvas_from_mouse
    jc   .cancel_shape
    mov [shape_end_y], ax
    mov [shape_end_x], bx

    mov al, [current_draw_mode]
    cmp al, DRAW_MODE_LINE
    je  .do_line
    cmp al, DRAW_MODE_RECT
    je  .do_rect
    ; cmp al, DRAW_MODE_CIRCLE  <-- 삭제
    ; je  .do_circle            <-- 삭제
    jmp .finish_shape

.do_line:
    call draw_line_shape
    jmp .finish_shape
.do_rect:
    call draw_rect_shape
    jmp .finish_shape
; .do_circle:                   <-- 삭제
;    call draw_circle_shape     <-- 삭제
;    jmp .finish_shape          <-- 삭제

.cancel_shape:
    jmp .finish_shape

.finish_shape:
    mov byte [shape_pending], 0
    mov word [needs_redraw], 1
.end:
    ret

; ---------------------------------------------------------
; [팔레트 클릭 처리]
;   - 마우스가 팔레트 영역 안을 클릭했으면 paint_color 변경
;   - AX = 1 : 팔레트 클릭 처리함
;   - AX = 0 : 팔레트 영역 아님
; ---------------------------------------------------------
app_check_palette_click:
    push bx
    push cx
    push dx

    ; local_y = mouse_y - window_y - title_bar_height - 2
    mov bx, [mouse_y]
    sub bx, [window_y]
    sub bx, [title_bar_height]
    sub bx, 2                ; 제목줄 아래로 조금 내림

    cmp bx, 0
    jl  .no_hit
    cmp bx, PALETTE_CELL_SIZE
    jge .no_hit              ; 세로 범위 벗어남

    ; local_x = mouse_x - window_x - 4
    mov dx, [mouse_x]
    sub dx, [window_x]
    sub dx, 4

    cmp dx, 0
    jl  .no_hit

    ; 한 셀 폭 + 간격 = PALETTE_STEP (10)
    ; idx = local_x / 10, pos_in_step = local_x % 10
    mov ax, dx
    mov bl, PALETTE_STEP
    xor ah, ah
    div bl                   ; AL=idx, AH=remainder

    cmp al, PALETTE_COUNT
    jge .no_hit              ; 팔레트 개수 초과
    cmp ah, PALETTE_CELL_SIZE
    jge .no_hit              ; 간격 부분(셀 사이) 클릭

    ; 여기까지 오면 AL = 팔레트 인덱스 (0..3)
    ; paint_color = palette_colors[AL]
    push si

    xor bx, bx
    mov bl, al               ; BX = idx
    mov si, palette_colors
    add si, bx
    mov al, [si]
    mov [paint_color], al

    pop si

    mov word [needs_redraw], 1
    mov ax, 1                ; 처리함
    jmp .done

.no_hit:
    xor ax, ax               ; 처리 안 함

.done:
    pop dx
    pop cx
    pop bx
    ret
; ---------------------------------------------------------
; [앱 그리기] 캔버스 메모리를 화면 버퍼(BUFFER_SEG)에 복사
;   - 캔버스 (0..CANVAS_WIDTH-1, 0..CANVAS_HEIGHT-1)를
;   - 화면상의 (window_x+1, window_y+title_bar_height)에 맞춰 그림
; ---------------------------------------------------------
app_draw_content:
    push ax
    push bx
    push cx
    push dx
    push si
    push di
    push ds
    push es

    ; -----------------------------------------------------
    ; 1) 커널 DS 상태에서 화면 버퍼 내 시작 위치 계산
    ;    y0 = window_y + title_bar_height
    ;    x0 = window_x + 1
    ;    offset = y0 * SCREEN_PITCH + x0
    ; -----------------------------------------------------
    mov ax, [window_y]
    add ax, [title_bar_height]        ; y0
    mov bx, SCREEN_PITCH              ; 320
    mul bx                            ; AX = y0 * 320

    mov bx, [window_x]
    add bx, 1                         ; x0
    add ax, bx                        ; AX = y0*320 + x0
    mov di, ax                        ; DI = 화면 버퍼 오프셋

    ; -----------------------------------------------------
    ; 2) 세그먼트 설정: DS=CANVAS_SEG, ES=BUFFER_SEG
    ; -----------------------------------------------------
    mov ax, CANVAS_SEG
    mov ds, ax
    xor si, si                        ; 캔버스 시작 (offset 0)

    mov ax, BUFFER_SEG
    mov es, ax

    ; -----------------------------------------------------
    ; 3) 줄 단위로 캔버스 → 화면 버퍼 복사
    ; -----------------------------------------------------
    mov cx, CANVAS_HEIGHT             ; 바깥 루프: 줄 수

.y_loop:
    push cx                           ; 바깥 루프 카운터 보존

    mov cx, CANVAS_WIDTH              ; 한 줄 폭
    rep movsb                         ; DS:SI(캔버스) → ES:DI(화면)

    pop cx                            ; 줄 수 복원

    ; rep movsb 후:
    ;   SI = SI + CANVAS_WIDTH
    ;   DI = DI + CANVAS_WIDTH
    ; 다음 줄 시작 = DI + (SCREEN_PITCH - CANVAS_WIDTH)
    add di, SCREEN_PITCH - CANVAS_WIDTH

    loop .y_loop

    pop es
    pop ds
    pop di
    pop si
    pop dx
    pop cx
    pop bx
    pop ax
    ret
; ---------------------------------------------------------
; [선 그리기] Bresenham 알고리즘
;   입력: shape_start_x/Y, shape_end_x/Y (캔버스 좌표)
;   출력: 캔버스에 현재 paint_color로 선을 그림
; ---------------------------------------------------------
draw_line_shape:
    push ax
    push bx
    push cx
    push dx
    push si
    push di

    ; x0, y0, x1, y1 로 가져오기
    mov si, [shape_start_x]   ; SI = x0
    mov di, [shape_start_y]   ; DI = y0
    mov ax, [shape_end_x]     ; AX = x1
    mov bx, [shape_end_y]     ; BX = y1

    mov [line_x1], ax
    mov [line_y1], bx

    ; dx = |x1 - x0|
    mov dx, ax
    sub dx, si                ; dx = x1 - x0
    mov word [line_sx], 1
    cmp dx, 0
    jge .dx_ok
    neg dx
    mov word [line_sx], -1
.dx_ok:
    mov [line_dx], dx         ; line_dx = |dx|

    ; dy = |y1 - y0|
    mov dx, bx
    sub dx, di                ; dy = y1 - y0
    mov word [line_sy], 1
    cmp dx, 0
    jge .dy_ok
    neg dx
    mov word [line_sy], -1
.dy_ok:
    ; dy_neg = -|dy|
    neg dx
    mov [line_dy], dx         ; line_dy = dy_neg (<=0)

    ; err = dx + dy_neg
    mov ax, [line_dx]
    add ax, [line_dy]
    mov [line_err], ax

.line_loop:
    ; 점 찍기: (si=x0, di=y0)
    mov bx, si
    mov ax, di
    call app_plot_pixel

    ; x0==x1 && y0==y1 이면 종료
    cmp si, [line_x1]
    jne .cont
    cmp di, [line_y1]
    jne .cont
    jmp .done

.cont:
    ; e2 = 2 * err
    mov ax, [line_err]
    shl ax, 1
    mov [line_e2], ax

    ; if (e2 >= dy_neg) { err += dy_neg; x0 += sx; }
    mov dx, [line_dy]
    cmp ax, dx                ; e2 < dy_neg 이면 스킵
    jl  .skip_x
    add [line_err], dx
    mov ax, [line_sx]
    add si, ax
.skip_x:

    ; if (e2 <= dx_abs) { err += dx_abs; y0 += sy; }
    mov ax, [line_e2]
    mov dx, [line_dx]
    cmp ax, dx
    jg  .skip_y               ; e2 > dx_abs 이면 스킵
    add [line_err], dx
    mov ax, [line_sy]
    add di, ax
.skip_y:

    jmp .line_loop

.done:
    pop di
    pop si
    pop dx
    pop cx
    pop bx
    pop ax
    ret
; ---------------------------------------------------------
; [사각형 그리기] 테두리만 그림
;   입력: shape_start_x/Y, shape_end_x/Y
; ---------------------------------------------------------
draw_rect_shape:
    push ax
    push bx
    push cx
    push dx

    ; x0 = min(start_x, end_x), x1 = max(...)
    mov ax, [shape_start_x]
    mov bx, [shape_end_x]
    cmp ax, bx
    jle .x_ok
    xchg ax, bx
.x_ok:
    mov [rect_x0], ax
    mov [rect_x1], bx

    ; y0 = min(start_y, end_y), y1 = max(...)
    mov ax, [shape_start_y]
    mov bx, [shape_end_y]
    cmp ax, bx
    jle .y_ok
    xchg ax, bx
.y_ok:
    mov [rect_y0], ax
    mov [rect_y1], bx

    ; -------------------------
    ; 윗변/아랫변 (수평선)
    ; -------------------------
    mov bx, [rect_x0]
.horiz_loop:
    mov ax, [rect_y0]
    call app_plot_pixel        ; 윗변

    mov ax, [rect_y1]
    call app_plot_pixel        ; 아랫변

    inc bx
    cmp bx, [rect_x1]
    jle .horiz_loop

    ; -------------------------
    ; 좌우 변 (수직선) - 양 끝은 이미 그렸으니 y0+1 ~ y1-1
    ; -------------------------
    mov ax, [rect_y0]
    inc ax                     ; y = y0 + 1

.vert_loop:
    cmp ax, [rect_y1]
    jge .done_rect

    mov bx, [rect_x0]
    call app_plot_pixel        ; 왼쪽 변

    mov bx, [rect_x1]
    call app_plot_pixel        ; 오른쪽 변

    inc ax
    jmp .vert_loop

.done_rect:
    pop dx
    pop cx
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
