[BITS 64]
start:
  mov rax, 0
loop:
  out $10, ax
  inc ax
  cmp ax, 5
  jne loop
  hlt
