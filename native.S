// ABI bridges recovered for this exact Stheno arm64e image.
.text
.p2align 2
.macro begin name
.globl _\name
_\name:
 pacibsp
 stp x20, x21, [sp, #-32]!
 stp x29, x30, [sp, #16]
 add x29, sp, #16
.endm
.macro target value
 adrp x9, _sth_core_base@PAGE
 ldr x9, [x9, _sth_core_base@PAGEOFF]
 movz x10, #(\value & 65535)
 movk x10, #((\value >> 16) & 65535), lsl #16
 add x9, x9, x10
 blr x9
.endm
.macro finish
 ldp x29, x30, [sp, #16]
 ldp x20, x21, [sp], #32
 retab
.endm
begin STHNativeClassify
 mov x20, x0
 target 0xd7980
 finish
begin STHNativeTranslation
 mov x20, x0
 target 0xaf02c
 finish
begin STHNativeMove
 mov x20,x0
 target 0x9d450
 finish
begin STHNativeRect
 mov x20, x0
 target 0x3dde4
 finish
begin STHNativeScale
 mov x20, x0
 target 0x9cadc
 finish
begin STHNativeSetScale
 mov x20, x0
 target 0x9d0ec
 finish
.globl _STHNativeReset
_STHNativeReset:
 pacibsp
 sub sp,sp,#96
 stp x20,x21,[sp,#0]
 stp x29,x30,[sp,#16]
 add x29,sp,#16
 mov x20,x0
 str x0,[sp,#64]
 // ReflectManager initializer stores (.8, 1, 1, .8) at 0x443b4.
 movz x9,#0x999a
 movk x9,#0x9999,lsl #16
 movk x9,#0x9999,lsl #32
 movk x9,#0x3fe9,lsl #48
 fmov d0,x9
 fmov d1,#1.0
 stp d0,d1,[sp,#32]
 stp d1,d0,[sp,#48]
 add x0,sp,#32
 add x1,sp,#64
 target 0x9e770
 mov x0,x20
 target 0x44950
 ldp x29,x30,[sp,#16]
 ldp x20,x21,[sp,#0]
 add sp,sp,#96
 retab
begin STHNativeDock
 target 0x447d4
 finish
begin STHNativeRotate
 mov x20, x0
 mov x0, #3
 mov x1, #1
 target 0x42b94
 mov x0, #3
 mov x1, x20
 target 0x45740
 finish
begin STHNativeSetup
 target 0xd9300
 finish
begin STHNativeUpdate
 target 0xd9310
 finish
begin STHNativeEnd
 target 0xd9320
 finish
begin STHNativeLong
 mov x20, x0
 target 0xd9330
 finish
begin STHNativeTap
 mov x20, x0
 mov x0, x1
 target 0xd9340
 finish
