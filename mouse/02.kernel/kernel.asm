; 02.kernel/kernel.asm (v.Analyzer - 마우스 신호 분석기)
bits 16
org 0x0000

start_kernel:
    ; 1. 세그먼트 초기화
    mov ax, 0x07E0
    mov ds, ax
    mov es, ax
    mov ss, ax
    mov sp, 0xFFFE
    mov bp, sp

    ; [안전 장치] 인터럽트 끄기 (IDT 없이 IRQ 발생하면 다운됨)
    cli 

    ; 2. 텍스트 모드 (로그 확인용)
    mov ax, 0x0003
    int 0x10

    ; 진단 시작 메시지
    mov si, msg_start
    call print_string

    ; 3. PS/2 마우스 초기화 (하드웨어 직접 제어)
    call ps2_init

    ; 초기화 완료 메시지
    mov si, msg_ready
    call print_string

.analyze_loop:
    ; 4. 데이터가 들어왔는지 확인 (Polling)
    in al, 0x64
    test al, 0x01   ; Output Buffer Full?
    jz .analyze_loop

    ; 5. 데이터 읽기
    in al, 0x60
    
    ; 읽은 값을 화면에 16진수로 출력
    call print_hex
    
    ; 공백 추가
    mov al, ' '
    call print_char

    jmp .analyze_loop

; ---------------------------------------------------------
; PS/2 초기화 루틴 (복잡한 과정 생략하고 핵심만 수행)
; ---------------------------------------------------------
ps2_init:
    ; 1. 마우스 포트 활성화 (0xA8)
    call wait_write
    mov al, 0xA8
    out 0x64, al

    ; 2. 데이터 리포팅 켜기 (0xD4 -> 0xF4)
    call wait_write
    mov al, 0xD4
    out 0x64, al
    call wait_write
    mov al, 0xF4
    out 0x60, al

    ; ACK(0xFA) 응답 대기 및 출력
    call wait_read
    in al, 0x60
    
    push ax
    mov si, msg_ack
    call print_string
    pop ax
    call print_hex ; 응답 코드 출력 (FA가 나와야 정상)
    
    mov al, 0x0D ; 줄바꿈
    call print_char
    mov al, 0x0A
    call print_char

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

; ---------------------------------------------------------
; 출력 함수들
; ---------------------------------------------------------
print_string:
    mov ah, 0x0E
.loop:
    lodsb
    cmp al, 0
    je .done
    int 0x10
    jmp .loop
.done:
    ret

print_char:
    mov ah, 0x0E
    int 0x10
    ret

print_hex:
    push ax
    push bx
    mov bl, al      ; 원본 저장

    ; 상위 4비트
    shr al, 4
    call .digit
    
    ; 하위 4비트
    mov al, bl
    and al, 0x0F
    call .digit

    pop bx
    pop ax
    ret

.digit:
    add al, '0'
    cmp al, '9'
    jle .p
    add al, 7
.p:
    mov ah, 0x0E
    int 0x10
    ret

; ---------------------------------------------------------
; 메시지
; ---------------------------------------------------------
msg_start: db "--- Mouse Signal Analyzer ---", 0x0D, 0x0A, 0
msg_ack:   db "Init Response: ", 0
msg_ready: db 0x0D, 0x0A, "Ready! Move or Click Mouse...", 0x0D, 0x0A, 0

times (512 * 4) - ($ - $$) db 0
