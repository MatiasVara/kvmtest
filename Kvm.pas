Unit Kvm;



interface

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

  PDE64_PRESENT = 1;
  PDE64_RW = 1 shl 1;
  PDE64_USER = 1 shl 2;
  PDE64_PS = 1 shl 7;
  CR0_PE = 1;
  CR0_MP = 1 shl 1;
  CR0_ET = 1 shl 4;
  CR0_NE = 1 shl 5;
  CR0_WP = 1 shl 16;
  CR0_AM = 1 shl 18;
  CR0_PG = 1 shl 31;
  EFER_LME = 1 shl 8;
  EFER_LMA = 1 shl 10;
  CR4_PAE = 1 shl 5;

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

  pkvm_sregs = ^kvm_sregs;
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


procedure setup_longmode(mem: Pointer; sregs: pkvm_sregs);

implementation

procedure setup_longmode(mem: Pointer; sregs: pkvm_sregs);
var
  pml4, pdpt, pd: ^QWORD;
  seg: kvm_segment;
begin
  pml4 := Pointer(PtrUInt(mem)+$2000);
  pdpt := Pointer(PtrUInt(mem)+$3000);
  pd := Pointer(PtrUInt(mem)+$4000);
  
  pml4[0] := PDE64_PRESENT or PDE64_RW or PDE64_USER or $3000;
  pdpt[0] := PDE64_PRESENT or PDE64_RW or PDE64_USER or $4000;
  pd[0] := PDE64_PRESENT or PDE64_RW or PDE64_USER or PDE64_PS;

  // this supposes that we start at 0
  sregs^.cr3 := $2000;
  sregs^.cr4 := CR4_PAE;
  sregs^.cr0 := CR0_PE or CR0_MP or CR0_ET or CR0_NE or CR0_WP or CR0_AM or CR0_PG;
  sregs^.efer := EFER_LME or EFER_LMA;

  seg.base := 0;
  seg.limit := $ffffffff;
  seg.selector := 1 shl 3;
  seg.present := 1;
  seg.tp := 11;
  seg.dpl := 0;
  seg.db := 0;
  seg.s := 1;
  seg.l := 1;
  seg.g := 1;

  sregs^.cs := seg;
  
  seg.tp := 3;
  seg.selector := 2 shl 3;
  sregs^.ds := seg;
  sregs^.fs := seg;
  sregs^.gs := seg;
  sregs^.ss := seg;
end;

initialization


end.
