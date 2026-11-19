// Linked at the unused __TEXT tail of the exact source image.
// All added entries use direct branches; no forged authenticated pointers.
.text
.p2align 2
// runtime resolver thunk. d0-d7 and Swift self are preserved through dlsym.
_resolve:
 pacibsp
 sub sp, sp, #240
 stp x29,x30,[sp,#0]
 stp x0,x1,[sp,#16]
 stp x2,x3,[sp,#32]
 stp x4,x5,[sp,#48]
 stp x6,x7,[sp,#64]
 str x8,[sp,#80]
 stp q0,q1,[sp,#96]
 stp q2,q3,[sp,#128]
 stp q4,q5,[sp,#160]
 stp q6,q7,[sp,#192]
 mov x0,#-2
 mov x1,x16
 bl _dlsym
 mov x16,x0
 ldp q0,q1,[sp,#96]
 ldp q2,q3,[sp,#128]
 ldp q4,q5,[sp,#160]
 ldp q6,q7,[sp,#192]
 ldr x8,[sp,#80]
 ldp x6,x7,[sp,#64]
 ldp x4,x5,[sp,#48]
 ldp x2,x3,[sp,#32]
 ldp x0,x1,[sp,#16]
 ldp x29,x30,[sp,#0]
 add sp,sp,#240
 autibsp
 braaz x16
.org 0x100
_classify:
 mov x0,x20
 adr x16,Lclassify
 b _resolve
Lclassify: .asciz "STHClassify"
.org 0x140
_setup:
 adr x16,Lsetup
 b _resolve
Lsetup: .asciz "STHSetup"
.org 0x180
_update:
 adr x16,Lupdate
 b _resolve
Lupdate: .asciz "STHUpdate"
.org 0x1c0
_end:
 adr x16,Lend
 b _resolve
Lend: .asciz "STHEnd"
.org 0x200
_long:
 mov x0,x20
 adr x16,Llong
 b _resolve
Llong: .asciz "STHLong"
.org 0x240
_tap:
 mov x1,x0
 mov x0,x20
 adr x16,Ltap
 b _resolve
Ltap: .asciz "STHTap"
// One-instruction trampolines preserve original PAC prologues.
.org 0x300
_orig_setup:
 pacibsp
 b _original_setup_plus4
.org 0x310
_orig_update:
 pacibsp
 b _original_update_plus4
.org 0x320
_orig_end:
 pacibsp
 b _original_end_plus4
.org 0x330
_orig_long:
 pacibsp
 b _original_long_plus4
.org 0x340
_orig_tap:
 pacibsp
 b _original_tap_plus4

// Original keyboard closures run inside Stheno's existing SwiftUI spring.
.org 0x380
_keyboard_show:
 adr x16,Lkeyboard_show
 b _resolve
Lkeyboard_show: .asciz "STHKeyboardShow"
.org 0x3c0
_keyboard_hide:
 adr x16,Lkeyboard_hide
 b _resolve
Lkeyboard_hide: .asciz "STHKeyboardHide"
.org 0x400
_orig_keyboard_show:
 pacibsp
 b _original_keyboard_show_plus4
.org 0x410
_orig_keyboard_hide:
 b _original_keyboard_hide_target

// Every newly presented model starts with the same defaults as bottom-right reset.
.org 0x440
_present:
 mov x0,x20
 adr x16,Lpresent
 b _resolve
Lpresent: .asciz "STHFirstPresentation"
.org 0x480
_orig_present:
 pacibsp
 b _original_present_plus4
