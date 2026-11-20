// STATIC RESEARCH ONLY. Additive bridge for the exact 2.0.16 arm64e core
// inherited by the proposed 2.0.17 chooser. Not wired into production.
// Resolve/gate _sth_action_core_base exactly as SystemActionRuntime.m does.
.text
.p2align 2
.macro enter name
.globl _\name
_\name:
 pacibsp
 stp x20,x21,[sp,#-32]!
 stp x29,x30,[sp,#16]
 add x29,sp,#16
.endm
.macro callcore value
 adrp x9,_sth_action_core_base@PAGE
 ldr x9,[x9,_sth_action_core_base@PAGEOFF]
 movz x10,#(\value & 65535)
 movk x10,#((\value >> 16) & 65535),lsl #16
 add x9,x9,x10
 blr x9
.endm
.macro leave
 ldp x29,x30,[sp,#16]
 ldp x20,x21,[sp],#32
 retab
.endm

// C: void *STHChooserBuildManagerConsumed(uintptr_t word0, uintptr_t word1);
// Consumes ONE owned Swift String; returns ONE owned ReflectManager.
// Do not release word1 after this call: native 4e284 consumes it.
enter STHChooserBuildManagerConsumed
 mov x21,#0
 callcore 0x4e024
 leave

// C: void STHChooserReleaseSwift(void *ownedSwiftObject);
enter STHChooserReleaseSwift
 callcore 0xb0a0c
 leave

// C: void STHChooserReleaseArray(void *ownedArray);
enter STHChooserReleaseArray
 callcore 0xb07fc
 leave

enter STHChooserClearMinimized
 sub sp,sp,#32
 mov x20,x0
 adrp x9,_sth_action_core_base@PAGE
 ldr x9,[x9,_sth_action_core_base@PAGEOFF]
 add x0,x9,#0xb6,lsl #12
 add x0,x0,#0x898
 callcore 0xb091c
 str x0,[sp,#16]
 adrp x9,_sth_action_core_base@PAGE
 ldr x9,[x9,_sth_action_core_base@PAGEOFF]
 add x0,x9,#0xb6,lsl #12
 add x0,x0,#0x8c0
 callcore 0xb091c
 str x0,[sp,#24]
 strb wzr,[sp]
 mov x0,sp
 mov x1,x20
 ldp x2,x3,[sp,#16]
 mov x21,#0
 callcore 0xaeedc
 ldr x0,[sp,#16]
 callcore 0xb0a0c
 ldr x0,[sp,#24]
 callcore 0xb0a0c
 add sp,sp,#32
 leave

// C: void STHChooserOpenModelAnimated(void *borrowedReflectManager);
// Synchronous withAnimation, NOT a retained/asynchronous custom closure.
// Reuses ORIGINAL thunk 65af4 -> 58944 -> ReflectEnv -> patched 47e8.
// The caller must keep its +1 model alive until this function returns.
enter STHChooserOpenModelAnimated
 sub sp,sp,#32
 str x0,[sp]
 bl _STHChooserClearMinimized
 mov x21,#0
 callcore 0x51454
 // Original selected-launch response = 0.3 / native animation setting.
 mov x8,#0x3333333333333333
 movk x8,#0x3fd3,lsl #48
 fmov d1,x8
 fdiv d0,d1,d0
 str d0,[sp,#8]
 callcore 0x51454
 fmov d1,d0
 ldr d0,[sp,#8]
 fmov d2,xzr
 callcore 0xafb5c
 str x0,[sp,#16]
 adrp x9,_sth_action_core_base@PAGE
 ldr x9,[x9,_sth_action_core_base@PAGEOFF]
 movz x10,#0x5af4
 movk x10,#0x6,lsl #16
 add x16,x9,x10
 mov x17,#0x720f
 pacia x16,x17
 mov x1,x16
 ldr x2,[sp]
 add x9,x9,#0xdd,lsl #12
 ldr x3,[x9,#0x510]
 add x3,x3,#8
 mov x21,#0
 callcore 0xaf19c
 ldr x0,[sp,#16]
 callcore 0xb0a0c
 add sp,sp,#32
 leave

// C: int STHChooserCopyCatalogs(void *ownedArraysOut[2]);
// Output: user +1, system +1. Main thread. Failure: two zeroes.
// Never starts GlobalEnv initialization: its init can restore preferences.
enter STHChooserCopyCatalogs
 sub sp,sp,#32
 str x0,[sp]
 stp xzr,xzr,[x0]
 adrp x9,_sth_action_core_base@PAGE
 ldr x9,[x9,_sth_action_core_base@PAGEOFF]
 cbz x9,LCatalogNo
 add x10,x9,#0xe9,lsl #12
 ldr x10,[x10,#0x590]
 cmn x10,#1
 b.ne LCatalogNo
 add x9,x9,#0xf7,lsl #12
 ldr x20,[x9,#0xac0]
 cbz x20,LCatalogNo
 ldp x0,x1,[x20,#0x18]
 cbz x0,LCatalogNo
 cbz x1,LCatalogNo
 stp x0,x1,[sp,#8]
 callcore 0xb081c
 ldr x0,[sp,#16]
 callcore 0xb081c
 ldp x0,x1,[sp,#8]
 ldr x8,[sp]
 stp x0,x1,[x8]
 mov w0,#1
 b LCatalogDone
LCatalogNo:
 mov w0,#0
LCatalogDone:
 add sp,sp,#32
 leave

// C: void *STHChooserCopyPinnedManagers(void);
// Returns +1 Array<ReflectManager>, or NULL if DeviceEnv not initialized.
// Native Published getter: self in x20, result x0. No direct Published layout.
enter STHChooserCopyPinnedManagers
 sub sp,sp,#16
 adrp x9,_sth_action_core_base@PAGE
 ldr x9,[x9,_sth_action_core_base@PAGEOFF]
 cbz x9,LManagersNo
 add x10,x9,#0xe9,lsl #12
 ldr x10,[x10,#0x598]
 cmn x10,#1
 b.ne LManagersNo
 add x9,x9,#0xf7,lsl #12
 ldr x20,[x9,#0xae8]
 cbz x20,LManagersNo
 mov x0,x20
 callcore 0xb0a2c
 mov x21,#0
 callcore 0x7ea40
 str x0,[sp]
 mov x0,x20
 callcore 0xb0a0c
 ldr x0,[sp]
 b LManagersDone
LManagersNo:
 mov x0,#0
LManagersDone:
 add sp,sp,#16
 leave

// C: size_t STHChooserManagersCount(void *borrowedArray);
// Requires nonnull known native Array<ReflectManager>; supports Cocoa storage.
enter STHChooserManagersCount
 lsr x8,x0,#62
 cbnz x8,LManagersCocoa
 and x8,x0,#0xfffffffffffffff8
 ldr x0,[x8,#0x10]
 b LCountDone
LManagersCocoa:
 and x8,x0,#0xfffffffffffffff8
 cmp x0,#0
 csel x0,x8,x0,ge
 callcore 0xb00fc
LCountDone:
 leave

// C: void *STHChooserCopyManagerAt(size_t checkedIndex, void *borrowedArray);
// Original typed subscript handles both native/Cocoa arrays, returns model +1.
// The caller MUST check index < count first; native bounds failure traps.
enter STHChooserCopyManagerAt
 callcore 0x48394
 leave

// Read existing native getters; no Published backing-layout assumptions.
enter STHChooserRingScale
 mov x20,x0
 mov x21,#0
 callcore 0x53e7c
 leave
enter STHChooserRingOffset
 mov x20,x0
 mov x21,#0
 callcore 0x53f10
 leave
enter STHChooserQuickSetting
 mov x20,x0
 mov x21,#0
 callcore 0xe050
 leave
enter STHChooserEditing
 mov x20,x0
 mov x21,#0
 callcore 0xe078
 leave
enter STHChooserShowTab
 mov x20,x0
 mov x21,#0
 callcore 0xe064
 leave
enter STHChooserDamping
 mov x21,#0
 callcore 0x51454
 leave
// C Double AppStorage getter: (ring, validated live field offset).
enter STHChooserRingPreference
 sub sp,sp,#16
 ldr x20,[x0,x1]
 mov x0,x20
 callcore 0xb0a2c
 adrp x9,_sth_action_core_base@PAGE
 ldr x9,[x9,_sth_action_core_base@PAGEOFF]
 add x9,x9,#0xdd,lsl #12
 ldr x1,[x9,#0x490]
 mov x8,sp
 callcore 0xaef7c
 mov x0,x20
 callcore 0xb0a0c
 ldr d0,[sp]
 add sp,sp,#16
 leave
