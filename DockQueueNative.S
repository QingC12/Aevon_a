.text
.p2align 2
.macro callcore address
 adrp x9,_sth_action_core_base@PAGE
 ldr x9,[x9,_sth_action_core_base@PAGEOFF]
 movz x10,#(\address & 65535)
 movk x10,#((\address >> 16) & 65535),lsl #16
 add x9,x9,x10
 blr x9
.endm
.macro enter name
.globl _\name
_\name:
 pacibsp
 stp x20,x21,[sp,#-32]!
 stp x29,x30,[sp,#16]
 add x29,sp,#16
.endm
.macro leave
 ldp x29,x30,[sp,#16]
 ldp x20,x21,[sp],#32
 retab
.endm
.macro keypaths first,second
 callcore 0xb091c
 str x0,[sp,#16]
 adrp x9,_sth_action_core_base@PAGE
 ldr x9,[x9,_sth_action_core_base@PAGEOFF]
 movz x10,#(\second & 65535)
 movk x10,#((\second >> 16) & 65535),lsl #16
 add x0,x9,x10
 callcore 0xb091c
 str x0,[sp,#24]
.endm
.macro pair first,second
 adrp x9,_sth_action_core_base@PAGE
 ldr x9,[x9,_sth_action_core_base@PAGEOFF]
 movz x10,#(\first & 65535)
 movk x10,#((\first >> 16) & 65535),lsl #16
 add x0,x9,x10
 keypaths \first,\second
.endm
.macro releasepaths
 ldr x0,[sp,#16]
 callcore 0xb0a0c
 ldr x0,[sp,#24]
 callcore 0xb0a0c
.endm
enter STHDockNativeOrientation
 sub sp,sp,#48
 stp x19,x20,[sp]
 stp x21,x22,[sp,#16]
 mov x20,x0
 adrp x22,_sth_action_core_base@PAGE
 ldr x22,[x22,_sth_action_core_base@PAGEOFF]
 add x0,x22,#0xb6,lsl #12
 add x0,x0,#0x808
 callcore 0xb091c
 mov x19,x0
 add x0,x22,#0xb6,lsl #12
 add x0,x0,#0x830
 callcore 0xb091c
 mov x21,x0
 add x8,sp,#32
 mov x0,x20
 mov x1,x19
 mov x2,x21
 callcore 0xaeecc
 mov x0,x19
 callcore 0xb0a0c
 mov x0,x21
 callcore 0xb0a0c
 ldr x0,[sp,#32]
 ldp x21,x22,[sp,#16]
 ldp x19,x20,[sp]
 add sp,sp,#48
 leave
enter STHDockNativeMinimized
 sub sp,sp,#32
 mov x20,x0
 pair 0xb6898,0xb68c0
 mov x0,x20
 ldp x1,x2,[sp,#16]
 mov x8,sp
 callcore 0xaeecc
 releasepaths
 ldrb w0,[sp]
 add sp,sp,#32
 leave
enter STHDockNativeOffset
 sub sp,sp,#32
 mov x20,x0
 pair 0xbb030,0xbb058
 mov x0,x20
 ldp x1,x2,[sp,#16]
 mov x8,sp
 callcore 0xaeecc
 releasepaths
 ldp d0,d1,[sp]
 add sp,sp,#32
 leave
enter STHDockNativeSetOffset
 sub sp,sp,#32
 mov x20,x0
 stp d0,d1,[sp]
 pair 0xbb030,0xbb058
 mov x0,x20
 callcore 0xb0a2c
 mov x0,sp
 mov x1,x20
 ldp x2,x3,[sp,#16]
 callcore 0xaeedc
 add sp,sp,#32
 leave
enter STHDockNativeRect
 mov x20,x0
 callcore 0x3dde4
 leave
enter STHDockCopyFloating
 sub sp,sp,#32
 adrp x9,_sth_action_core_base@PAGE
 ldr x9,[x9,_sth_action_core_base@PAGEOFF]
 cbz x9,Lnone
 add x10,x9,#0xe9,lsl #12
 ldr x10,[x10,#0x5c0]
 cmn x10,#1
 b.ne Lnone
 add x9,x9,#0xf7,lsl #12
 ldr x20,[x9,#0xb10]
 cbz x20,Lnone
 pair 0xb3d20,0xb3d48
 mov x0,x20
 ldp x1,x2,[sp,#16]
 mov x8,sp
 callcore 0xaeecc
 releasepaths
 ldr x0,[sp]
 b Ldone
Lnone:
 mov x0,#0
Ldone:
 add sp,sp,#32
 leave
enter STHDockNativeAnimate
 sub sp,sp,#16
 callcore 0x51454
 fmov d1,#0.25
 fdiv d0,d1,d0
 str d0,[sp]
 callcore 0x51454
 fmov d1,d0
 ldr d0,[sp]
 fmov d2,xzr
 callcore 0xafb5c
 str x0,[sp]
 adr x16,Lreflow
 mov x17,#0x720f
 pacia x16,x17
 mov x1,x16
 mov x2,#0
 adrp x9,_sth_action_core_base@PAGE
 ldr x9,[x9,_sth_action_core_base@PAGEOFF]
 add x9,x9,#0xdd,lsl #12
 ldr x3,[x9,#0x510]
 add x3,x3,#8
 mov x21,#0
 callcore 0xaf19c
 ldr x0,[sp]
 callcore 0xb0a0c
 add sp,sp,#16
 leave
Lreflow:
 pacibsp
 stp x29,x30,[sp,#-16]!
 mov x29,sp
 bl _STHDockReflow
 ldp x29,x30,[sp],#16
 retab
