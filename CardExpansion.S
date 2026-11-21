// Scope non-oscillating animation to the floating card's scale and offset.
// Native keyboard delivery and all ring animations keep their original spring.
.text
.p2align 2
.macro card_call address
 adrp x9,_sth_action_core_base@PAGE
 ldr x9,[x9,_sth_action_core_base@PAGEOFF]
 movz x10,#(\address & 65535)
 movk x10,#((\address >> 16) & 65535),lsl #16
 add x9,x9,x10
 blr x9
.endm
.globl _STHCardRunExpansion
_STHCardRunExpansion:
 pacibsp
 sub sp,sp,#64
 stp x20,x21,[sp,#32]
 stp x29,x30,[sp,#48]
 add x29,sp,#48
 str x0,[sp]
 // Read the same native speed once for a consistent response/damping pair.
 card_call 0x51454
 fmov d1,#0.25
 fdiv d2,d1,d0
 fmov d1,#1.0
 fmaxnm d1,d0,d1
 fmov d0,d2
 fmov d2,xzr
 card_call 0xafb5c
 str x0,[sp,#16]
 adr x16,LcardExpansionUpdate
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
 card_call 0xaf19c
 ldr x0,[sp,#16]
 card_call 0xb0a0c
 ldp x29,x30,[sp,#48]
 ldp x20,x21,[sp,#32]
 add sp,sp,#64
 retab
LcardExpansionUpdate:
 pacibsp
 stp x29,x30,[sp,#-16]!
 mov x29,sp
 mov x0,x20
 bl _STHCenterInvokeBlock
 ldp x29,x30,[sp],#16
 retab
