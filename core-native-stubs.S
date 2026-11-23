// Tail jumps leave LR, SP, Swift self/context and arguments unchanged.
// Only the ABI scratch register x16 is used; PAC starts in the core body.
.text
.p2align 2
.globl _STHNativeMinimized
_STHNativeMinimized:
 adrp x16, _sth_core_base@PAGE
 ldr x16, [x16, _sth_core_base@PAGEOFF]
 add x16, x16, #0xda, lsl #12
 add x16, x16, #0x600
 br x16
.globl _STHNativeSetMinimized
_STHNativeSetMinimized:
 adrp x16, _sth_core_base@PAGE
 ldr x16, [x16, _sth_core_base@PAGEOFF]
 add x16, x16, #0xda, lsl #12
 add x16, x16, #0x690
 br x16
.globl _STHNativeClassify
_STHNativeClassify:
 adrp x16, _sth_core_base@PAGE
 ldr x16, [x16, _sth_core_base@PAGEOFF]
 add x16, x16, #0xda, lsl #12
 add x16, x16, #0x710
 br x16
.globl _STHNativeTranslation
_STHNativeTranslation:
 adrp x16, _sth_core_base@PAGE
 ldr x16, [x16, _sth_core_base@PAGEOFF]
 add x16, x16, #0xda, lsl #12
 add x16, x16, #0x734
 br x16
.globl _STHNativeMove
_STHNativeMove:
 adrp x16, _sth_core_base@PAGE
 ldr x16, [x16, _sth_core_base@PAGEOFF]
 add x16, x16, #0xda, lsl #12
 add x16, x16, #0x758
 br x16
.globl _STHNativeRect
_STHNativeRect:
 adrp x16, _sth_core_base@PAGE
 ldr x16, [x16, _sth_core_base@PAGEOFF]
 add x16, x16, #0xda, lsl #12
 add x16, x16, #0x77c
 br x16
.globl _STHNativeReset
_STHNativeReset:
 adrp x16, _sth_core_base@PAGE
 ldr x16, [x16, _sth_core_base@PAGEOFF]
 add x16, x16, #0xda, lsl #12
 add x16, x16, #0x7a0
 br x16
.globl _STHNativeDock
_STHNativeDock:
 adrp x16, _sth_core_base@PAGE
 ldr x16, [x16, _sth_core_base@PAGEOFF]
 add x16, x16, #0xda, lsl #12
 add x16, x16, #0x89c
 br x16
.globl _STHNativeOrientation
_STHNativeOrientation:
 adrp x16, _sth_core_base@PAGE
 ldr x16, [x16, _sth_core_base@PAGEOFF]
 add x16, x16, #0xda, lsl #12
 add x16, x16, #0x93c
 br x16
.globl _STHNativeSetup
_STHNativeSetup:
 adrp x16, _sth_core_base@PAGE
 ldr x16, [x16, _sth_core_base@PAGEOFF]
 add x16, x16, #0xda, lsl #12
 add x16, x16, #0x9c0
 br x16
.globl _STHNativeUpdate
_STHNativeUpdate:
 adrp x16, _sth_core_base@PAGE
 ldr x16, [x16, _sth_core_base@PAGEOFF]
 add x16, x16, #0xda, lsl #12
 add x16, x16, #0x9e0
 br x16
.globl _STHNativeEnd
_STHNativeEnd:
 adrp x16, _sth_core_base@PAGE
 ldr x16, [x16, _sth_core_base@PAGEOFF]
 add x16, x16, #0xda, lsl #12
 add x16, x16, #0xa00
 br x16
.globl _STHNativeLong
_STHNativeLong:
 adrp x16, _sth_core_base@PAGE
 ldr x16, [x16, _sth_core_base@PAGEOFF]
 add x16, x16, #0xda, lsl #12
 add x16, x16, #0xa20
 br x16
.globl _STHNativeTap
_STHNativeTap:
 adrp x16, _sth_core_base@PAGE
 ldr x16, [x16, _sth_core_base@PAGEOFF]
 add x16, x16, #0xda, lsl #12
 add x16, x16, #0xa44
 br x16
.globl _STHNativeGetScale
_STHNativeGetScale:
 adrp x16, _sth_core_base@PAGE
 ldr x16, [x16, _sth_core_base@PAGEOFF]
 add x16, x16, #0xda, lsl #12
 add x16, x16, #0xa6c
 br x16
.globl _STHNativeGetOffset
_STHNativeGetOffset:
 adrp x16, _sth_core_base@PAGE
 ldr x16, [x16, _sth_core_base@PAGEOFF]
 add x16, x16, #0xda, lsl #12
 add x16, x16, #0xa90
 br x16
.globl _STHNativeSetViewportGeometry
_STHNativeSetViewportGeometry:
 adrp x16, _sth_core_base@PAGE
 ldr x16, [x16, _sth_core_base@PAGEOFF]
 add x16, x16, #0xda, lsl #12
 add x16, x16, #0xab4
 br x16
.globl _STHNativeCopyBundleID
_STHNativeCopyBundleID:
 adrp x16, _sth_core_base@PAGE
 ldr x16, [x16, _sth_core_base@PAGEOFF]
 add x16, x16, #0xda, lsl #12
 add x16, x16, #0xaf8
 br x16
.globl _STHNativeRefreshGeometry
_STHNativeRefreshGeometry:
 adrp x16, _sth_core_base@PAGE
 ldr x16, [x16, _sth_core_base@PAGEOFF]
 add x16, x16, #0xda, lsl #12
 add x16, x16, #0xb1c
 br x16
.globl _STHNativePresent
_STHNativePresent:
 adrp x16, _sth_core_base@PAGE
 ldr x16, [x16, _sth_core_base@PAGEOFF]
 add x16, x16, #0xda, lsl #12
 add x16, x16, #0xb40
 br x16
.globl _STHNativeInitialSize
_STHNativeInitialSize:
 adrp x16, _sth_core_base@PAGE
 ldr x16, [x16, _sth_core_base@PAGEOFF]
 add x16, x16, #0xda, lsl #12
 add x16, x16, #0xb64
 br x16
