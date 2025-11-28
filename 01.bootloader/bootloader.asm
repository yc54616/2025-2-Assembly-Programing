; 01.bootloader/bootloader.asm
; 기능: 디스크 리셋 추가, 디버그 메시지 출력
bits 16
org 0x0000

jmp 0x07C0:start

start:
    mov ax, 0x07C0
    mov ds, ax
    mov es, ax
    
    ; [중요] BIOS가 넘겨준 부팅 드라이브 번호(DL) 저장
    ; USB는 보통 0x80 (HDD 인식)으로 넘어옵니다.
    mov [boot_drive], dl

    ; 스택 초기화
    mov ax, 0x7000
    mov ss, ax
    mov sp, 0xFFFE

    ; [디버그] 화면에 'S' (Start) 출력 -> 부트로더 진입 확인용
    mov ah, 0x0E
    mov al, 'S'
    int 0x10

    ; 1. 디스크 시스템 초기화 (Reset Disk System)
    ; 실기에서는 이걸 안 하면 읽기 실패하는 경우가 많음
    mov ah, 0x00
    mov dl, [boot_drive]
    int 0x13
    jc .DISK_ERROR      ; 실패시 에러로 점프

.READ_KERNEL:
    ; [디버그] 'L' (Loading) 출력
    mov ah, 0x0E
    mov al, 'L'
    int 0x10

    ; 커널 로드 (15 섹터)
    mov ah, 0x02
    mov al, 15          ; 읽을 섹터 수
    mov ch, 0           ; 실린더 0
    mov cl, 2           ; 섹터 2 (1부터 시작하므로 2번부터)
    mov dh, 0           ; 헤드 0
    mov dl, [boot_drive]; 드라이브 번호
    
    ; 저장할 메모리 위치 (ES:BX = 0x07E0:0x0000)
    mov bx, 0x07E0
    mov es, bx
    mov bx, 0x0000
    
    int 0x13
    jc .RETRY           ; 실패시 재시도

    ; [디버그] 'G' (Go) 출력 -> 읽기 성공 확인용
    mov ah, 0x0E
    mov al, 'G'
    int 0x10

    jmp .BOOT_KERNEL

.RETRY:
    ; 재시도 로직 (디스크 리셋 후 다시 시도)
    dec byte [retry_count]
    jz .DISK_ERROR      ; 카운트 0 되면 에러

    ; 재시도 전 리셋 한번 더
    mov ah, 0x00
    mov dl, [boot_drive]
    int 0x13
    
    jmp .READ_KERNEL

.BOOT_KERNEL:
    jmp 0x07E0:0x0000

.DISK_ERROR:
    ; 에러 발생시 'E' 출력 하고 멈춤
    mov ah, 0x0E
    mov al, 'E'
    int 10h
    jmp $

boot_drive:     db 0
retry_count:    db 5

times 510 - ($ - $$) db 0
dw 0xAA55
