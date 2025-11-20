; 01.bootloader/bootloader.asm
bits 16
org 0x0000

jmp 0x07C0:start

start:
    mov ax, 0x07C0
    mov ds, ax
    mov es, ax
    mov [boot_drive], dl

    mov ax, 0x7000
    mov ss, ax
    mov sp, 0xFFFE

.READ_LOOP:
    mov ah, 0x00
    mov dl, [boot_drive]
    int 0x13
    jc .RETRY_CHECK

    ; [수정] 커널 크기가 커졌으므로 15섹터를 로드합니다.
    mov ah, 0x02
    mov al, 15          ; 4 -> 15 로 변경 (넉넉하게 잡음)
    mov ch, 0
    mov cl, 2
    mov dh, 0
    mov dl, [boot_drive]
    mov bx, 0x07E0
    mov es, bx
    mov bx, 0x0000
    int 0x13
    jnc .BOOT_KERNEL

.RETRY_CHECK:
    dec byte [retry_count]
    jz .DISK_ERROR
    jmp .READ_LOOP

.BOOT_KERNEL:
    jmp 0x07E0:0x0000

.DISK_ERROR:
    mov ah, 0x0E
    mov al, 'E'
    int 10h
    jmp $

boot_drive:     db 0
retry_count:    db 5

times 510 - ($ - $$) db 0
dw 0xAA55
