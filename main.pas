// main.pas
//
// This program demostrates the use of the KVM API to create and run a VM.
//
// Copyright (c) 2021 Matias Vara <matiasevara@gmail.com>
// All Rights Reserved
//
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program.  If not, see <http://www.gnu.org/licenses/>.
//
program main;

{$asmmode intel}
{$mode delphi}
{$MACRO ON}

uses BaseUnix, Linux, Kvm, sysutils;

const
  GUEST_ADDR_START = 0;
  GUEST_ADDR_MEM_SIZE = $200000;
  guestinitialregs : kvm_regs = (
    rsp : GUEST_ADDR_MEM_SIZE;
    rip : GUEST_ADDR_START;
    rflags : 2;
  );

procedure LoadBinary(filemem: PChar; path: AnsiString);
var
  Buf : Array[1..2048] of byte;
  FBinary: File;
  ReadCount: LongInt;
begin
  Assign(FBinary, path);
  Reset(FBinary, 1);
  Repeat
    BlockRead (FBinary, Buf, Sizeof(Buf), ReadCount);
    move(Buf, filemem^, ReadCount);
    Inc(filemem, ReadCount);
  Until (ReadCount = 0);
  Close(FBinary);
end;

var
  ret: LongInt;
  mem: PChar;
  guest: VM;
  guestVCPU: VCPU;
  exit_reason: LongInt;
  region: kvm_userspace_memory_region;
  regs: kvm_regs;
  ioexit: PKvmRunExitIO;
  value: ^QWORD;
begin
  If not KvmInit then
  begin
    WriteLn('Unable to open /dev/kvm');
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

  LoadBinary(mem, Paramstr(1));

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

  // vm is limited to one vcpu
  guestvcpu.vm := @guest;
  if not CreateVCPU(guest.vmfd, @guestvcpu) then
    Exit;

  // configure system registers
  if not ConfigureSregs(@guestvcpu) then
    Exit;

  // configure general purpose registers
  if not ConfigureRegs(@guestvcpu, @guestinitialregs) then
    Exit;

  while true do
  begin
    if not RunVCPU(@guestvcpu, exit_reason) then
    begin
      WriteLn('KVM_RUN');
      Break;
    end;
    if exit_reason = KVM_EXIT_HLT then
    begin
      WriteLn('HLT!');
      ret := GetRegisters(@guestvcpu, @regs);
      if ret = -1 then
      begin
        WriteLn('KVM_SET_REGS');
        Break;
      end;
      WriteLn('Halt instruction, rax: 0x', IntToHex(regs.rax, 4), ', rbx: 0x', IntToHex(regs.rbx, 4));
      Break;
    end else if exit_reason = KVM_EXIT_MMIO then
    begin
      continue;
    end else if exit_reason = KVM_EXIT_IO then
    begin
      ioexit := PKvmRunExitIO(@guestvcpu.run.padding_exit[0]);
      value := Pointer(PtrUInt(guestvcpu.run) + ioexit.data_offset);
      WriteLn('IO: port: 0x', IntToHex(ioexit.port, 4), ', value: 0x', IntToHex(value^, 4));
      continue;
    end else
    begin
      WriteLn('exit_reason: ', exit_reason);
      Break;
    end;
  end;

  fpClose(kvmfd);
end.
