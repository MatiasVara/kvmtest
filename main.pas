uses BaseUnix, Linux;

Type
  kvm_userspace_memory_region = record
  slot: DWORD;
  flags: DWORD;
  guest_phys_addr: QWORD;
  memory_size: QWORD;
  userspace_addr: QWORD;  
end;

const
  KVM_EXIT_IO_IN = 0;
  KVM_EXIT_IO_OUT = 1;
  SYNC_REGS_SIZE_BYTES = 2048;
  KVM_GET_API_VERSION = $AE00;
  KVM_RUN_A = $AE80;
  KVM_GET_VCPU_MMAP_SIZE = $AE04;
  KVM_CREATE_VM = $AE01;
  KVM_SET_USER_MEMORY_REGION = $4020ae46;
  KVM_CREATE_VCPU = $AE41;
  KVM_GET_SREGS = $8138ae83;
  KVM_SET_SREGS = $4138ae84;
  KVM_NR_INTERRUPTS = 256;
  KVM_GET_REGS = $8090ae81;
  KVM_SET_REGS = $4090ae82;
  KVM_EXIT_HLT = 5;
  KVM_EXIT_MMIO = 6;
  KVM_EXIT_IO = 2;

type
  // KVM_EXIT_UNKNOWN
  kvm_run_hw = record
    hardware_exit_reason: QWORD;
  end;
		
  // KVM_EXIT_FAIL_ENTRY
  kvm_run_fail_entry = record
    hardware_entry_failure_reason: QWORD;
	  cpu: DWORD;
  end;
		
  // KVM_EXIT_EXCEPTION
  kvm_run_ex = record
    exception: DWORD;
	  error_code: DWORD;
  end;
		
  // KVM_EXIT_IO
  kvm_run_exit_io = record
    direction: Byte;
	  size: Byte;
	  port: WORD;
	  count: DWORD;
	  data_offset: QWORD;
  end;
  
  // KVM_EXIT_MMIO
  kvm_run_mmio = record
    phys_addr: QWORD;
	  data: array[0..7] of Byte;
	  len: DWORD;
	  is_write: Byte;
  end;
  
  // KVM_EXIT_INTERNAL_ERROR
  kvm_run_internal = record
    suberror: DWORD;
	  ndata: DWORD;
	  data: array[0..15] of QWORD;
  end;
  
  kvm_run = record
	  // in 
	  request_interrupt_window: Byte;
	  immediate_exit: Byte;
	  padding1: array[0..5] of Byte;

	  // out
	  exit_reason: DWORD;
 	  ready_for_interrupt_injection: Byte;
	  if_flag: Byte;
	  flags: WORD;

	  // in (pre_kvm_run), out (post_kvm_run)
	  cr8: QWORD;
	  apic_base: QWORD;

	  // this contain the union structure
	  padding_exit: array[0..255] of Char;

	  kvm_valid_regs: QWORD;
	  kvm_dirty_regs: QWORD;
	  padding: array[0..SYNC_REGS_SIZE_BYTES-1] of Char;
  end;

  kvm_segment = record
    base: QWORD;
    limit: DWORD;
    selector: WORD;
    tp: Byte;
    present, dpl, db, s, l, g, avl: Byte;
    unusable: Byte;
    padding: Byte;
  end;

  kvm_dtable = record 
    base: QWORD;
    limit: WORD;
    padding: array[0..2] of WORD;
  end;

  kvm_sregs = record
    cs, ds, es, fs, gs, ss: kvm_segment;
    tr, ldt: kvm_segment;
    gdt, idt: kvm_dtable;
    cr0, cr2, cr3, cr4, cr8: QWORD;
    efer: QWORD;
    apic_base: QWORD;
    interrupt_bitmap: array[0..((KVM_NR_INTERRUPTS + 63) div 64)-1] of QWORD;
  end;

  kvm_regs = record
    rax, rbx, rcx, rdx: QWORD;
    rsi, rdi, rsp, rbp: QWORD;
    r8,  r9,  r10, r11: QWORD;
    r12, r13, r14, r15: QWORD;
    rip, rflags: QWORD;
  end;

const
  GUEST_ADDR_START = 0;
  GUEST_ADDR_MEM_SIZE = $1000;

var
  kvm, vmfd, vcpufd: CInt;
  ret: LongInt;
  mem: PChar;
  region: kvm_userspace_memory_region;
  mmap_size: QWORD;
  run: ^kvm_run;
  sregs: kvm_sregs;
  regs: kvm_regs;
  code: array[0..11] of Byte = (
        $ba, $f8, $03, // mov $0x3f8, %dx 
        $0, $d8,       // add %bl, %al 
        $04, Byte('0'),      // add $'0', %al 
        $ee,           // out %al, (%dx) 
        $b0, Byte('1'),      // mov $'\n', %al
        $ee,           // out %al, (%dx)
        $f4           // hlt
    );
  p: PChar = @code[0];

begin 
  kvm := fpOpen('/dev/kvm', O_RdWr or O_CLOEXEC);
  if kvm < 0 then
  begin
    WriteLn('Error!');
    Exit;
  end;
  ret := fpIOCtl(kvm, KVM_GET_API_VERSION, nil);
  if ret = -1 then
  begin
    WriteLn('KVM_GET_API_VERSION');
    fpClose(kvm);
    Exit;
  end;

  if ret <> 12 then
  begin
    WriteLn('KVM_GET_API_VERSION ', ret, ', expected 12');
    fpClose(kvm);
    Exit;
  end;

  vmfd := fpIOCtl(kvm, KVM_CREATE_VM, nil);

  if vmfd = -1 then
  begin
    WriteLn('KVM_CREATE_VM');
    fpClose(kvm);
    Exit;
  end;

  // Allocate one aligned page of guest memory to hold the code.
  mem := fpmmap(nil, GUEST_ADDR_MEM_SIZE, PROT_READ or PROT_WRITE, MAP_SHARED or MAP_ANONYMOUS, -1, 0);
  if mem = nil then
  begin
    WriteLn('Allocating memory');
    fpClose(kvm);
    Exit;
  end;
  move(p^, mem^, sizeof(code)); 
  
  region.slot := 0;
  region.guest_phys_addr := GUEST_ADDR_START;
  region.memory_size := GUEST_ADDR_MEM_SIZE;
  region.userspace_addr := QWORD(mem);

  ret := fpIOCtl(vmfd, KVM_SET_USER_MEMORY_REGION, @region);
  if ret = -1 then
  begin
    WriteLn('KVM_SET_USER_MEMORY_REGION');
    fpClose(kvm);
    Exit;
  end;

  vcpufd := fpIOCtl(vmfd, KVM_CREATE_VCPU, nil);
  if vcpufd = -1 then
  begin
    WriteLn('KVM_CREATE_VCPU');
    fpClose(kvm);
    Exit;
  end;
  
  // Map the shared kvm_run structure and following data
  ret := fpIOCtl(kvm, KVM_GET_VCPU_MMAP_SIZE, nil);
  if ret = -1 then
  begin
    WriteLn('KVM_GET_VCPU_MMAP_SIZE');
    fpClose(kvm);
    Exit;
  end;  
  mmap_size := ret;
  if mmap_size < sizeof(run^) then
  begin
    WriteLn('KVM_GET_VCPU_MMAP_SIZE unexpectedly small');
    fpClose(kvm);
    Exit;
  end;
  run := fpmmap(nil, mmap_size, PROT_READ or PROT_WRITE, MAP_SHARED, vcpufd, 0);
  if run = nil then
  begin
    WriteLn('mmap run');
    fpClose(kvm);
    Exit;
  end;

  // TODO: here switch to long mode
  
  // Initialize CS to point at 0, via a read-modify-write of sregs
  ret := fpIOCtl(vcpufd, KVM_GET_SREGS, @sregs);
  if ret = -1 then
  begin
    WriteLn('KVM_GET_SREGS');
    fpClose(kvm);
    Exit;
  end;
  sregs.cs.base := 0;
  sregs.cs.selector := 0;
  ret := fpIOCtl(vcpufd, KVM_SET_SREGS, @sregs);
  if ret = -1 then
  begin
    WriteLn('KVM_SET_SREGS');
    fpClose(kvm);
    Exit;
  end;
  
  // Initialize registers: instruction pointer for our code, addends, and
  // initial flags required by x86 architecture
  regs.rip := GUEST_ADDR_START;
  regs.rax := 2;
  regs.rbx := 2;
  regs.rflags := 2;
  ret := fpIOCtl(vcpufd, KVM_SET_REGS, @regs);
  if ret = -1 then
  begin
    WriteLn('KVM_SET_REGS');
    fpClose(kvm);
    Exit;
  end;
  
  // loop until VMEXIT
  while true do
  begin
    ret := fpIOCtl(vcpufd, KVM_RUN_A, nil);
    if ret = -1 then
    begin
      WriteLn('KVM_RUN');
      fpClose(kvm);
      Exit;
    end;
    if run^.exit_reason = KVM_EXIT_HLT then
    begin
      WriteLn('HLT!');
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

  fpClose(kvm);
end.
