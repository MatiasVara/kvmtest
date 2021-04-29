program main;

uses BaseUnix, Linux, Kvm;

const
  GUEST_ADDR_START = 0;
  GUEST_ADDR_MEM_SIZE = $200000;

var
  kvmfd, vmfd, vcpufd: CInt;
  ret: LongInt;
  mem,filemem: PChar;
  region: kvm_userspace_memory_region;
  mmap_size: QWORD;
  run: ^kvm_run;
  sregs: kvm_sregs;
  regs: kvm_regs;
  Buf : Array[1..2048] of byte;
  Readed: LongInt;
  FBinary: File;

begin 
  kvmfd := fpOpen('/dev/kvm', O_RdWr or O_CLOEXEC);
  if kvmfd < 0 then
  begin
    WriteLn('Error!');
    Exit;
  end;
  ret := fpIOCtl(kvmfd, KVM_GET_API_VERSION, nil);
  if ret = -1 then
  begin
    WriteLn('KVM_GET_API_VERSION');
    fpClose(kvmfd);
    Exit;
  end;

  if ret <> 12 then
  begin
    WriteLn('KVM_GET_API_VERSION ', ret, ', expected 12');
    fpClose(kvmfd);
    Exit;
  end;

  vmfd := fpIOCtl(kvmfd, KVM_CREATE_VM, nil);

  if vmfd = -1 then
  begin
    WriteLn('KVM_CREATE_VM');
    fpClose(kvmfd);
    Exit;
  end;

  // Allocate one aligned page of guest memory to hold the code.
  mem := fpmmap(nil, GUEST_ADDR_MEM_SIZE, PROT_READ or PROT_WRITE, MAP_SHARED or MAP_ANONYMOUS, -1, 0);
  if mem = nil then
  begin
    WriteLn('Allocating memory');
    fpClose(kvmfd);
    Exit;
  end;
  
  // read binary from file an put it in memory
  Assign(FBinary, Paramstr(1));
  Reset(FBinary, 1);
  filemem := mem;
  Repeat
    BlockRead (FBinary, Buf, Sizeof(Buf), Readed);
    move(Buf, filemem^, Readed); 
    Inc(filemem, Readed);
  Until (Readed = 0);
  Close(FBinary);
  
  region.slot := 0;
  region.guest_phys_addr := GUEST_ADDR_START;
  region.memory_size := GUEST_ADDR_MEM_SIZE;
  region.userspace_addr := QWORD(mem);

  ret := fpIOCtl(vmfd, KVM_SET_USER_MEMORY_REGION, @region);
  if ret = -1 then
  begin
    WriteLn('KVM_SET_USER_MEMORY_REGION');
    fpClose(kvmfd);
    Exit;
  end;

  vcpufd := fpIOCtl(vmfd, KVM_CREATE_VCPU, nil);
  if vcpufd = -1 then
  begin
    WriteLn('KVM_CREATE_VCPU');
    fpClose(kvmfd);
    Exit;
  end;
  
  // Map the shared kvm_run structure and following data
  ret := fpIOCtl(kvmfd, KVM_GET_VCPU_MMAP_SIZE, nil);
  if ret = -1 then
  begin
    WriteLn('KVM_GET_VCPU_MMAP_SIZE');
    fpClose(kvmfd);
    Exit;
  end;  
  mmap_size := ret;
  if mmap_size < sizeof(run^) then
  begin
    WriteLn('KVM_GET_VCPU_MMAP_SIZE unexpectedly small');
    fpClose(kvmfd);
    Exit;
  end;
  run := fpmmap(nil, mmap_size, PROT_READ or PROT_WRITE, MAP_SHARED, vcpufd, 0);
  if run = nil then
  begin
    WriteLn('mmap run');
    fpClose(kvmfd);
    Exit;
  end;

  // Initialize CS to point at 0, via a read-modify-write of sregs
  ret := fpIOCtl(vcpufd, KVM_GET_SREGS, @sregs);
  if ret = -1 then
  begin
    WriteLn('KVM_GET_SREGS');
    fpClose(kvmfd);
    Exit;
  end;

  // set lognmode
  setup_longmode(mem, @sregs);
  
  ret := fpIOCtl(vcpufd, KVM_SET_SREGS, @sregs);
  if ret = -1 then
  begin
    WriteLn('KVM_SET_SREGS');
    fpClose(kvmfd);
    Exit;
  end;
 
  fillChar(pchar(@regs)^, sizeof(regs), 0);

  regs.rip := GUEST_ADDR_START;
  regs.rax := 2;
  regs.rbx := 2;
  regs.rflags := 2;
  regs.rsp := GUEST_ADDR_MEM_SIZE;

  ret := fpIOCtl(vcpufd, KVM_SET_REGS, @regs);
  if ret = -1 then
  begin
    WriteLn('KVM_SET_REGS');
    fpClose(kvmfd);
    Exit;
  end;
  
  // loop until VMEXIT
  while true do
  begin
    ret := fpIOCtl(vcpufd, KVM_RUN_A, nil);
    if ret = -1 then
    begin
      WriteLn('KVM_RUN');
      fpClose(kvmfd);
      Exit;
    end;
    if run^.exit_reason = KVM_EXIT_HLT then
    begin
      WriteLn('HLT!');  
      ret := fpIOCtl(vcpufd, KVM_GET_REGS, @regs);
      if ret = -1 then
      begin
        WriteLn('KVM_SET_REGS');
        Break;
      end;
      WriteLn('Halt instruction, rax: ', regs.rax, ', rbx: ', regs.rbx);
      Break;
    end else if run^.exit_reason = KVM_EXIT_MMIO then
    begin
      continue;
    end else if run^.exit_reason = KVM_EXIT_IO then
    begin
      WriteLn('IO!');
      continue;
    end else
    begin
      WriteLn('exit_reason: ', run^.exit_reason);
      Break;
    end; 
  end;

  fpClose(kvmfd);
end.
