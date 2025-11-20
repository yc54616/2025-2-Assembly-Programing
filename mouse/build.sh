#!/bin/bash
rm -f floppy.img 01.bootloader/bootloader.bin 02.kernel/kernel.bin

nasm -f bin 01.bootloader/bootloader.asm -o 01.bootloader/bootloader.bin
nasm -f bin 02.kernel/kernel.asm -o 02.kernel/kernel.bin

cat 01.bootloader/bootloader.bin 02.kernel/kernel.bin > floppy.img

echo "Build Complete."
