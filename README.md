# Kvmtest
This is a simple example to demostrate the use of KVM API to manipulate VMs from freepascal

# How to build the example
To build the example, you have just to run `./build.sh`. You are going to get something like:
```bash
IO: port: 0x0010, value: 0x0000
IO: port: 0x0010, value: 0x0001
IO: port: 0x0010, value: 0x0002
IO: port: 0x0010, value: 0x0003
IO: port: 0x0010, value: 0x0004
HLT!
Halt instruction, rax: 0x0005, rbx: 0x0002
```
This output corresponds with the following assembly:
```assembly
start:
  mov rax, 0
loop:
  out $10, ax // this triggers a VMEXIT
  inc ax
  cmp ax, 5
  jne loop
  hlt  // this triggers a VMEXIT
```

# Bibliography
https://github.com/soulxu/kvmsample

https://github.com/dpw/kvm-hello-world/blob/master/kvm-hello-world.c

https://prog.world/kvm-host-in-a-couple-of-lines-of-code/

https://www.freepascal.org/docs-html/rtl/baseunix/fpioctl.html

https://github.com/torvalds/linux/blob/master/include/uapi/linux/kvm.h
