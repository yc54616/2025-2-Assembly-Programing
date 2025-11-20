#!/bin/bash

# 이 스크립트는 오래된 파일을 지우고,
# 부트로더와 커널을 다시 컴파일한 후,
# floppy.img로 합칩니다.

# 1. 이전 빌드 파일 삭제
echo "Cleaning old files..."
rm -f floppy.img
rm -f 01.bootloader/bootloader.bin
rm -f 02.kernel/kernel.bin

# 2. 부트로더 컴파일
echo "Compiling bootloader..."
nasm -f bin 01.bootloader/bootloader.asm -o 01.bootloader/bootloader.bin

# 3. 커널 컴파일
echo "Compiling kernel..."
nasm -f bin 02.kernel/kernel.asm -o 02.kernel/kernel.bin

# 4. 컴파일 성공 확인
if [ ! -f 01.bootloader/bootloader.bin ]; then
    echo "ERROR: Bootloader compilation failed!"
    exit 1
fi

if [ ! -f 02.kernel/kernel.bin ]; then
    echo "ERROR: Kernel compilation failed!"
    exit 1
fi

# 5. floppy.img로 합치기
echo "Creating floppy image..."
cat 01.bootloader/bootloader.bin 02.kernel/kernel.bin > floppy.img

echo "Build complete!"
echo "---"
echo "File sizes:"
ls -l 01.bootloader/bootloader.bin 02.kernel/kernel.bin floppy.img
echo "---"
