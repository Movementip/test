"""Run Android 1.4.7's actual x86_64 body cipher in Unicorn (no credentials).

Usage: python verify_apk_bnit.py /path/to/apktool-lane/lib/x86_64/libbnit.so
Requires unicorn. Only libc allocation/copy and ndk string append are stubbed;
the cipher instructions and initial state are executed from the APK binary.
"""
import struct
import sys
import hashlib
from pathlib import Path
from unicorn import Uc, UC_ARCH_X86, UC_MODE_64, UC_HOOK_CODE
from unicorn.x86_const import *

uc = Uc(UC_ARCH_X86, UC_MODE_64)
binary = Path(sys.argv[1]).read_bytes()
assert hashlib.sha256(binary).hexdigest() == "a98b250f3b17e5a7ab9eab193f06adc1c162dd0ddaf24e00e2cc87beda7e316e", "Expected Lane Android 1.4.7 x86_64 libbnit.so"
uc.mem_map(0, 0x20000)
uc.mem_write(0, binary)
uc.mem_map(0x200000, 0x100000)
uc.mem_map(0x900000, 0x10000)
uc.mem_map(0xf00000, 0x1000)
heap = 0x200000


def alloc(size):
    global heap
    address = heap
    heap += (size + 31) & ~15
    return address


def q(address):
    return struct.unpack("<Q", uc.mem_read(address, 8))[0]


def native_string(data, target=None):
    address = target or alloc(24)
    pointer = alloc(len(data) + 1)
    uc.mem_write(pointer, data + b"\0")
    uc.mem_write(address, struct.pack("<QQQ", (len(data) + 16) | 1, len(data), pointer))
    return address


def string_bytes(address):
    first = uc.mem_read(address, 1)[0]
    if first & 1:
        return bytes(uc.mem_read(q(address + 16), q(address + 8)))
    return bytes(uc.mem_read(address + 1, first >> 1))


def hook(machine, address, size, data):
    rdi, rsi, rdx = [machine.reg_read(r) for r in (UC_X86_REG_RDI, UC_X86_REG_RSI, UC_X86_REG_RDX)]
    if address == 0xd8f0:  # operator new
        result = alloc(rdi)
    elif address in (0xdbc0, 0xdb50):  # memcpy / memmove
        machine.mem_write(rdi, bytes(machine.mem_read(rsi, rdx)))
        result = rdi
    elif address == 0xdaa0:  # ndk basic_string::append
        native_string(string_bytes(rdi) + bytes(machine.mem_read(rsi, rdx)), rdi)
        result = rdi
    elif address == 0xda80:  # operator delete
        result = 0
    else:
        return
    stack = machine.reg_read(UC_X86_REG_RSP)
    machine.reg_write(UC_X86_REG_RAX, result)
    machine.reg_write(UC_X86_REG_RSP, stack + 8)
    machine.reg_write(UC_X86_REG_RIP, q(stack))


uc.hook_add(UC_HOOK_CODE, hook)
body = b'["track-1","track-2"]'
nonce = b"00112233445566778899aabbccddeeff"
timestamp = b"1700000000123"
out = alloc(24)
pointer = alloc(len(body))
uc.mem_write(pointer, body)
values = (out, pointer, len(body), native_string(nonce), native_string(timestamp),
          native_string(b"SqperSzvbntKmv_CbnngeThis_12303!"))
for register, value in zip((UC_X86_REG_RDI, UC_X86_REG_RSI, UC_X86_REG_RDX,
                            UC_X86_REG_RCX, UC_X86_REG_R8, UC_X86_REG_R9), values):
    uc.reg_write(register, value)
uc.reg_write(UC_X86_REG_RSP, 0x90fff0)
uc.mem_write(0x90fff0, struct.pack("<Q", 0xf00000))
uc.emu_start(0xc760, 0xf00000, count=1000000)
print(bytes(uc.mem_read(q(out), q(out + 8) - q(out))).hex())
