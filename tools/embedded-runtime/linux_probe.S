/* Standalone Linux/AArch64 guest. No libc, Android linker or Termux paths. */
.section .text
.global _start
_start:
    mov x0, #1
    adr x1, message
    mov x2, #18
    mov x8, #64
    svc #0
    mov x0, #0
    mov x8, #93
    svc #0
message:
    .ascii "AI_LINUX_GUEST_V1\n"
