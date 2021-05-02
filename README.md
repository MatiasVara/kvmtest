# Kvmtest
This sample demonstrates KVM API to manage VMs from FreePascal. This work has been mainly inspired by the article at [1].

# Requirements
A Linux host with KVM. Also you need to install freepascal and nasm.

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
This output corresponds with the following assembly code:
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
[1] https://lwn.net/Articles/658511/

[2] https://github.com/soulxu/kvmsample

[3] https://github.com/dpw/kvm-hello-world/blob/master/kvm-hello-world.c

[4] https://prog.world/kvm-host-in-a-couple-of-lines-of-code/

[5] https://www.freepascal.org/docs-html/rtl/baseunix/fpioctl.html

[6] https://github.com/torvalds/linux/blob/master/include/uapi/linux/kvm.h
