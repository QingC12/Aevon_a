.text
.p2align 2
.macro event original
 pacibsp
 stp x20,x21,[sp,#-48]!
 stp x29,x30,[sp,#32]
 add x29,sp,#32
 bl \original
 mov x0,#-2
 adr x1,Lname
 bl _STHDockCoreDlsym
 cbz x0,1f
 mov x16,x0
 blraaz x16
1:
 ldp x29,x30,[sp,#32]
 ldp x20,x21,[sp],#48
 retab
.endm
event Lminimize
.org 0x80
event Lrestore
.org 0x100
event Lgeometry
.org 0x180
Lminimize:
 pacibsp
 b _STHDockMinimizePlus4
Lrestore:
 pacibsp
 b _STHDockRestorePlus4
Lgeometry:
 pacibsp
 b _STHDockGeometryPlus4
Lname:
 .asciz "STHDockReflow"
.p2align 2
