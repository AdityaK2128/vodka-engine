#!/usr/bin/env python3
"""ntdll: Restore the TEB GS base before resuming from the macOS SIGSYS handler.

Games that make Windows system calls directly (copy protection such as Forza Horizon 6's)
reach sigsys_handler() on macOS 14+. init_handler() switches GSBASE to the pthread TSD so
Unix code can run, and every other handler switches it back with leave_handler() before
returning to Windows code. sigsys_handler() did not, then resumed at
__wine_syscall_dispatcher_prolog_end, which reads the TEB through %gs:0x30. It got the
pthread TSD instead, and crashed reading pthread_teb at 0x320 of a NULL TEB, so the call
failed with STATUS_ACCESS_VIOLATION.

Usage: 0001-ntdll-macos-sigsys-restore-teb.py <wine source>
"""
import re
import sys

path = f"{sys.argv[1]}/dlls/ntdll/unix/signal_x86_64.c"
src = open(path, encoding="utf-8").read()

start = src.index("static void sigsys_handler")
end = src.index("\n}\n", start)
body = src[start:end]
if "leave_handler" in body:
    print("sigsys_handler already restores the TEB")
    sys.exit(0)

resume = re.search(r"\n([ \t]*)RIP_sig\(\s*(\w+)\s*\)\s*=\s*\(ULONG64\)__wine_syscall_dispatcher_prolog_end_ptr;", body)
if not resume:
    sys.exit("sigsys_handler: couldn't find where it resumes the dispatcher")
indent, context = resume.group(1), resume.group(2)

# leave_handler() takes (sigcontext) in Wine 11.0 and (sigcontext, thread data) later.
signature = re.search(r"static inline void leave_handler\(([^)]*)\)", src)
if not signature:
    sys.exit("leave_handler() not found")
arguments = context
if "," in signature.group(1):
    data = re.search(r"(\w+)\s*=\s*init_handler\(", body)
    if not data:
        sys.exit("sigsys_handler: couldn't find its thread data")
    arguments = f"{context}, {data.group(1)}"

call = f"\n{indent}leave_handler( {arguments} );"
body = body[:resume.start()] + call + body[resume.start():]
open(path, "w", encoding="utf-8").write(src[:start] + body + src[end:])
print(f"Patched sigsys_handler: leave_handler( {arguments} ) before resuming")
