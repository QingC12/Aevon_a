// System-action bridges for the exact pinned Stheno arm64e core. Existing
// native.S stays byte-identical; these calls do not touch geometry/gestures.
.text
.p2align 2
.macro begin name
.globl _\name
_\name:
 pacibsp
 stp x20,x21,[sp,#-32]!
 stp x29,x30,[sp,#16]
 add x29,sp,#16
.endm
.macro target value
 adrp x9,_sth_action_core_base@PAGE
 ldr x9,[x9,_sth_action_core_base@PAGEOFF]
 movz x10,#(\value & 65535)
 movk x10,#((\value >> 16) & 65535),lsl #16
 add x9,x9,x10
 blr x9
.endm
.macro finish
 ldp x29,x30,[sp,#16]
 ldp x20,x21,[sp],#32
 retab
.endm
// Swift String -> retained NSString*, borrowed words input.
begin STHSystemCopySwiftString
 ldp x0,x1,[x0]
 target 0xafccc
 finish
// NSString* -> owned Swift String words; output pointer is NOT an ObjC object.
begin STHSystemMakeSwiftString
 sub sp,sp,#16
 str x1,[sp]
 target 0xafcec
 ldr x8,[sp]
 stp x0,x1,[x8]
 add sp,sp,#16
 finish
// (isUnique,capacity,growForAppend,ownedSource) -> owned Array<Stheno.App>.
// Native specialized COW allocator retains Strings and consumes source +1.
begin STHSystemGrowApps
 target 0x47710
 finish
// Borrowed ReflectManager self +0x30 contains its original id:String.
begin STHSystemCopyModelIdentifier
 ldp x0,x1,[x0,#0x30]
 target 0xafccc
 finish

// Collapse only the initialized ring, not any floating App window.
begin STHSystemActionDismissRingNative
 adrp x9,_sth_action_core_base@PAGE
 ldr x9,[x9,_sth_action_core_base@PAGEOFF]
 cbz x9,LNoRing
 add x10,x9,#0xe9,lsl #12
 ldr x10,[x10,#0x5a0]
 cmn x10,#1
 b.ne LNoRing
 add x9,x9,#0xf7,lsl #12
 ldr x20,[x9,#0xaf0]
 cbz x20,LNoRing
 mov x21,#0
 target 0x59870
 mov w0,#1
 b LRingDone
LNoRing:
 mov w0,#0
LRingDone:
 finish

// Hide the transient quick-setting overlay using its real Published setter.
// Does not mutate saved prefs or dismiss unrelated application windows.
begin STHSystemActionHideQuickSettingNative
 sub sp,sp,#16
 adrp x9,_sth_action_core_base@PAGE
 ldr x9,[x9,_sth_action_core_base@PAGEOFF]
 cbz x9,LNoQuickSetting
 add x10,x9,#0xe9,lsl #12
 ldr x10,[x10,#0x5a8]
 cmn x10,#1
 b.ne LNoQuickSetting
 add x9,x9,#0xf7,lsl #12
 ldr x20,[x9,#0xaf8]
 cbz x20,LNoQuickSetting
 mov x21,#0
 target 0xe050
 cbz w0,LNoQuickSetting
 strb wzr,[sp]
 str x20,[sp,#8]
 mov x0,sp
 add x1,sp,#8
 mov x2,#0
 mov x3,#0
 target 0x25448
 mov w0,#1
 b LQuickSettingDone
LNoQuickSetting:
 mov w0,#0
LQuickSettingDone:
 add sp,sp,#16
 finish
