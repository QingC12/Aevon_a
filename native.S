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
begin STHNativeCloseFlick
 mov x20, x0
 target 0x507bc
 finish

// ReflectManager's orientation getter, using the same key paths as native long press.
.globl _STHNativeOrientation
_STHNativeOrientation:
 pacibsp
 sub sp, sp, #64
 stp x29, x30, [sp, #48]
 add x29, sp, #48
 stp x19, x20, [sp, #16]
 stp x21, x22, [sp, #32]
 mov x20, x0
 adrp x22, _sth_core_base@PAGE
 ldr x22, [x22, _sth_core_base@PAGEOFF]
 add x0, x22, #0xb6, lsl #12
 add x0, x0, #0x808
 target 0xb091c
 mov x19, x0
 add x0, x22, #0xb6, lsl #12
 add x0, x0, #0x830
 target 0xb091c
 mov x21, x0
 mov x8, sp
 mov x0, x20
 mov x1, x19
 mov x2, x21
 target 0xaeecc
 mov x0, x19
 target 0xb0a0c
 mov x0, x21
 target 0xb0a0c
 ldr x0, [sp]
 ldp x19, x20, [sp, #16]
 ldp x21, x22, [sp, #32]
 ldp x29, x30, [sp, #48]
 add sp, sp, #64
 retab

begin STHNativeRotate
 mov x20, x0
 mov x0, x1
 mov x1, #1
 // The native window animation takes the same orientation as the scene update.
 stp x0, xzr, [sp, #-16]!
 target 0x42b94
 ldp x0, xzr, [sp], #16
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
