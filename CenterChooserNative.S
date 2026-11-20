// Two independent builds: core trampolines, or the chooser dylib's Swift ABI getter.
.text
.p2align 2
#ifdef STH_CENTER_CORE_PATCH
// Linked into the exact core at 0xda000. Each replaced instruction was PACIBSP.
// The originals are void; x0 is a borrowed UIKit pan, x20 is Swift self.
.macro hook original, phase
 pacibsp
 stp x29,x30,[sp,#-48]!
 mov x29,sp
 stp x0,x20,[sp,#16]
 str x21,[sp,#32]
 .if \phase == 2
  // Snapshot before the native terminal path clears selected/scale. Do not veto it.
  bl Lsymbol
  str x0,[sp,#40]
  cbz x0,1f
  mov x16,x0
  ldp x1,x0,[sp,#16]
  mov w2,#2
  blraaz x16
1:
  ldp x0,x20,[sp,#16]
  ldr x21,[sp,#32]
 .endif
 bl \original
 .if \phase == 2
  ldr x0,[sp,#40]
 .else
  bl Lsymbol
 .endif
 cbz x0,2f
 mov x16,x0
 ldp x1,x0,[sp,#16]
 .if \phase == 2
  mov w2,#3
 .else
  mov w2,#\phase
 .endif
 blraaz x16
2:
 ldp x29,x30,[sp],#48
 retab
.endm

 hook Lbegin, 0
 .org 0x80
 hook Lchange, 1
 .org 0x100
 hook Lfinish, 2
 .org 0x180
Lbegin:
 pacibsp
 b _STHCenterCoreBeginPlus4
Lchange:
 pacibsp
 b _STHCenterCoreChangePlus4
Lfinish:
 pacibsp
 b _STHCenterCoreFinishPlus4
Lsymbol:
 mov x0,#-2 // RTLD_DEFAULT on Darwin.
 adr x1,LpanName
 b _STHCenterCoreDlsym
LpanName:
 .asciz "STHCenterRingPan"
 .p2align 2
#else
// int64_t STHCenterRingSelected(void *ring); caller validates singleton and image.
.globl _STHCenterRingSelected
_STHCenterRingSelected:
 pacibsp
 stp x20,x21,[sp,#-32]!
 stp x29,x30,[sp,#16]
 add x29,sp,#16
 mov x20,x0
 mov x21,#0
 adrp x9,_sth_action_core_base@PAGE
 ldr x9,[x9,_sth_action_core_base@PAGEOFF]
 movz x10,#0x3f98
 movk x10,#5,lsl #16
 add x9,x9,x10
 blr x9
 ldp x29,x30,[sp,#16]
 ldp x20,x21,[sp],#32
 retab

.macro cc_call address
 adrp x9,_sth_action_core_base@PAGE
 ldr x9,[x9,_sth_action_core_base@PAGEOFF]
 movz x10,#(\address & 65535)
 movk x10,#((\address >> 16) & 65535),lsl #16
 add x9,x9,x10
 blr x9
.endm
.globl _STHCenterRunAnimation
_STHCenterRunAnimation:
 pacibsp
 sub sp,sp,#64
 stp x20,x21,[sp,#32]
 stp x29,x30,[sp,#48]
 add x29,sp,#48
 str x0,[sp]
 cbnz w1,LcenterEase
 cc_call 0x51454
 fmov d1,#0.25
 fdiv d0,d1,d0
 str d0,[sp,#8]
 cc_call 0x51454
 fmov d1,d0
 ldr d0,[sp,#8]
 fmov d2,xzr
 cc_call 0xafb5c
 b LcenterAnimate
LcenterEase:
 movz x9,#0x3333
 movk x9,#0x3333,lsl #16
 movk x9,#0x3333,lsl #32
 movk x9,#0x3fc3,lsl #48
 fmov d0,x9
 cc_call 0xafb4c
LcenterAnimate:
 str x0,[sp,#16]
 adr x16,LcenterUpdate
 mov x17,#0x720f
 pacia x16,x17
 mov x1,x16
 ldr x2,[sp]
 adrp x9,_sth_action_core_base@PAGE
 ldr x9,[x9,_sth_action_core_base@PAGEOFF]
 add x9,x9,#0xdd,lsl #12
 ldr x3,[x9,#0x510]
 add x3,x3,#8
 mov x21,#0
 cc_call 0xaf19c
 ldr x0,[sp,#16]
 cc_call 0xb0a0c
 ldp x29,x30,[sp,#48]
 ldp x20,x21,[sp,#32]
 add sp,sp,#64
 retab
LcenterUpdate:
 pacibsp
 stp x29,x30,[sp,#-16]!
 mov x29,sp
 mov x0,x20
 bl _STHCenterInvokeBlock
 ldp x29,x30,[sp],#16
 retab
#endif
