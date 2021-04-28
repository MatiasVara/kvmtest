nasm guest.s -o guest.o -f elf64
ld -T guest.ld guest.o -o guest.img
./main guest.img 
