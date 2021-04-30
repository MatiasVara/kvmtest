program main;

uses BaseUnix, Linux, Kvm;

{$asmmode intel}
{$mode delphi} // required for FPC to understand the Delphi pascal syntax and symbols (ie: Result)
{$MACRO ON}
const
  GUEST_ADDR_START = 0;
  GUEST_ADDR_MEM_SIZE = $200000;

var
  ret: LongInt;
  filemem, mem: PChar;
  run: ^kvm_run;
  Buf : Array[1..2048] of byte;
  Readed: LongInt;
  FBinary: File;
  guest: VM;
  guestVCPU: VCPU;
  exit_reason: LongInt;
  region: kvm_userspace_memory_region;
  regs: kvm_regs;
begin

  // initialize Kvm file descriptor
  If not KvmInit then
  begin
    Exit;
  end;
  guest.vmfd := CreateVM();
  if guest.vmfd = -1 then
  begin
    WriteLn('Error at CREATE_VM');
    Exit;
  end;

  // allocate one aligned page of guest memory to hold the code.
  mem := fpmmap(nil, GUEST_ADDR_MEM_SIZE, PROT_READ or PROT_WRITE, MAP_SHARED or MAP_ANONYMOUS, -1, 0);
  if mem = nil then
  begin
    WriteLn('Error at Allocating memory');
    Exit;
  end;
  guest.mem := mem;

  // read binary from file and put it in memory
  Assign(FBinary, Paramstr(1));
  Reset(FBinary, 1);
  filemem := mem;
  Repeat
    BlockRead (FBinary, Buf, Sizeof(Buf), Readed);
    move(Buf, filemem^, Readed);
    Inc(filemem, Readed);
  Until (Readed = 0);
  Close(FBinary);

  // set user memory region
  region.slot := 0;
  region.guest_phys_addr := GUEST_ADDR_START;
  region.memory_size := GUEST_ADDR_MEM_SIZE;
  region.userspace_addr := QWORD(mem);
  ret := SetUserMemoryRegion(guest.vmfd, @region);
  if ret = -1 then
  begin
    WriteLn('Error at KVM_SET_USER_MEMORY_REGION');
    Exit;
  end;

  guestvcpu.vm := @guest;

  if not CreateVCPU(guest.vmfd, @guestvcpu) then
    Exit;

  if not ConfigureSregs(@guestvcpu) then
    Exit;

  fillChar(pchar(@regs)^, sizeof(regs), 0);
  regs.rip := GUEST_ADDR_START;
  regs.rax := 2;
  regs.rbx := 2;
  regs.rflags := 2;
  regs.rsp := GUEST_ADDR_MEM_SIZE;
  if not ConfigureRegs(@guestvcpu, @regs) then
    Exit;

  while true do
  begin
    if not RunVCPU(@guestvcpu, exit_reason) then
    begin
      WriteLn('KVM_RUN');
      Exit;
    end;
    if exit_reason = KVM_EXIT_HLT then
    begin
      WriteLn('HLT!');
      ret := fpIOCtl(guestvcpu.vcpufd, KVM_GET_REGS, @regs);
      if ret = -1 then
      begin
        WriteLn('KVM_SET_REGS');
        Break;
      end;
      WriteLn('Halt instruction, rax: ', regs.rax, ', rbx: ', regs.rbx);
      Break;
    end else if exit_reason = KVM_EXIT_MMIO then
    begin
      continue;
    end else if exit_reason = KVM_EXIT_IO then
    begin
      WriteLn('IO!');
      continue;
    end else
    begin
      WriteLn('exit_reason: ', exit_reason);
      Break;
    end;
  end;

  fpClose(kvmfd);
end.
