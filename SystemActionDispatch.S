// Linked at Stheno arm64e VA 0xd9500; exact-image patches only.
// External BRANCH26 relocations (all code executes inside Stheno image):
//   _STHSystemActionCoreDlsym     -> 0xb03bc
//   _STHSystemActionOldPresent   -> 0xd9440
//   _STHSystemActionCoreOpenPlus4 -> 0x47ec
// PRIMARY: 0x47e8 -> 0xd9700, before _floatings admission.
// OPTIONAL GUARD: 0x41a9c -> 0xd9500, before scene lookup/create.
// Verify current bytes and ensure d9500:d9908 remains free before integration.
// Do NOT append this to, rebuild, or mutate the old dispatch.S/native.S.
// Requires separate LC_LOAD_DYLIB @loader_path/SthenoSystemActions.dylib.
// C export: BOOL STHSystemActionPresent(void *borrowedReflectManager).
// It must return YES for either exact action ID, even on backend failure;
// enqueue work, do not synchronously capture inside SwiftUI withAnimation.
// Return NO for every other model. No NSString/Swift String passed here.

.text
.p2align 2
.globl _STHSystemActionPresentEntry
_STHSystemActionPresentEntry:
    pacibsp
    sub sp, sp, #256
    stp x29, x30, [sp, #0]
    stp x0, x1, [sp, #16]
    stp x2, x3, [sp, #32]
    stp x4, x5, [sp, #48]
    stp x6, x7, [sp, #64]
    str x8, [sp, #80]
    stp x20, x21, [sp, #96]
    stp q0, q1, [sp, #112]
    stp q2, q3, [sp, #144]
    stp q4, q5, [sp, #176]
    stp q6, q7, [sp, #208]
    mov x29, sp
    mov x0, #-2                         // RTLD_DEFAULT on Darwin
    adr x1, LSystemActionPresentName
    bl _STHSystemActionCoreDlsym
    cbz x0, LSystemActionPassthrough
    mov x16, x0
    ldr x0, [sp, #96]                   // original Swift self x20
    blraaz x16                         // dlsym's IA, zero-discriminator pointer
    tst w0, #0xff                      // C BOOL result; native result is Void
    b.eq LSystemActionPassthrough

LSystemActionHandled:
    ldp q6, q7, [sp, #208]
    ldp q4, q5, [sp, #176]
    ldp q2, q3, [sp, #144]
    ldp q0, q1, [sp, #112]
    ldp x20, x21, [sp, #96]
    ldr x8, [sp, #80]
    ldp x6, x7, [sp, #64]
    ldp x4, x5, [sp, #48]
    ldp x2, x3, [sp, #32]
    ldp x0, x1, [sp, #16]
    ldp x29, x30, [sp, #0]
    add sp, sp, #256
    retab                              // return to original present caller

LSystemActionPassthrough:
    ldp q6, q7, [sp, #208]
    ldp q4, q5, [sp, #176]
    ldp q2, q3, [sp, #144]
    ldp q0, q1, [sp, #112]
    ldp x20, x21, [sp, #96]
    ldr x8, [sp, #80]
    ldp x6, x7, [sp, #64]
    ldp x4, x5, [sp, #48]
    ldp x2, x3, [sp, #32]
    ldp x0, x1, [sp, #16]
    ldp x29, x30, [sp, #0]
    add sp, sp, #256
    autibsp                            // old entry expects unsigned caller LR
    b _STHSystemActionOldPresent        // unchanged d9440 -> STHFirstPresentation

LSystemActionPresentName:
    .asciz "STHSystemActionPresent"
.p2align 2

// PRIMARY ring admission hook: patch 0x47e8 -> 0xd9700.
// x0 = borrowed ReflectManager, x20 = ReflectEnv self, native result Void.
// This prevents action models entering _floatings / same-ID deduplication.
// The optional 0x41a9c guard above alone cannot provide that guarantee.
.org 0x200
.globl _STHSystemActionOpenEntry
_STHSystemActionOpenEntry:
    pacibsp
    sub sp, sp, #256
    stp x29, x30, [sp, #0]
    stp x0, x1, [sp, #16]
    stp x2, x3, [sp, #32]
    stp x4, x5, [sp, #48]
    stp x6, x7, [sp, #64]
    str x8, [sp, #80]
    stp x20, x21, [sp, #96]
    stp q0, q1, [sp, #112]
    stp q2, q3, [sp, #144]
    stp q4, q5, [sp, #176]
    stp q6, q7, [sp, #208]
    mov x29, sp
    mov x0, #-2
    adr x1, LSystemActionOpenName
    bl _STHSystemActionCoreDlsym
    cbz x0, LSystemActionOpenPassthrough
    mov x16, x0
    ldr x0, [sp, #16]                   // ORIGINAL x0, NOT ReflectEnv x20
    blraaz x16
    tst w0, #0xff
    b.eq LSystemActionOpenPassthrough

LSystemActionOpenHandled:
    ldp q6, q7, [sp, #208]
    ldp q4, q5, [sp, #176]
    ldp q2, q3, [sp, #144]
    ldp q0, q1, [sp, #112]
    ldp x20, x21, [sp, #96]
    ldr x8, [sp, #80]
    ldp x6, x7, [sp, #64]
    ldp x4, x5, [sp, #48]
    ldp x2, x3, [sp, #32]
    ldp x0, x1, [sp, #16]
    ldp x29, x30, [sp, #0]
    add sp, sp, #256
    retab

LSystemActionOpenPassthrough:
    ldp q6, q7, [sp, #208]
    ldp q4, q5, [sp, #176]
    ldp q2, q3, [sp, #144]
    ldp q0, q1, [sp, #112]
    ldp x20, x21, [sp, #96]
    ldr x8, [sp, #80]
    ldp x6, x7, [sp, #64]
    ldp x4, x5, [sp, #48]
    ldp x2, x3, [sp, #32]
    ldp x0, x1, [sp, #16]
    ldp x29, x30, [sp, #0]
    add sp, sp, #256
    autibsp
    b _STHSystemActionOriginalOpen

LSystemActionOpenName:
    .asciz "STHSystemActionPresent"
.p2align 2

// Local, directly branched trampoline. External BRANCH26 -> 0x47ec.
.org 0x400
_STHSystemActionOriginalOpen:
    pacibsp
    b _STHSystemActionCoreOpenPlus4

// Single System publication load, AFTER both native name sorts have finished.
// Patch 0xfe30 ldur x8,[x29,#-0x58] -> BL d9a00. The stack local owns +1.
.org 0x500
.globl _STHSystemActionPickerEntry
_STHSystemActionPickerEntry:
    pacibsp
    sub sp,sp,#32
    stp x29,x30,[sp,#16]
    ldur x8,[x29,#-0x58]
    str x8,[sp]
    mov x0,#-2
    adr x1,LSystemPickerName
    bl _STHSystemActionCoreDlsym
    cbz x0,LSystemPickerMissing
    mov x16,x0
    ldr x0,[sp]
    blraaz x16
    b LSystemPickerDone
LSystemPickerMissing:
    ldr x0,[sp]
LSystemPickerDone:
    mov x8,x0
    ldp x29,x30,[sp,#16]
    add sp,sp,#32
    retab
LSystemPickerName:
    .asciz "STHSystemActionPrependPicker"
.p2align 2

// The original saved-Apps cleanup drops identifiers with no SBApplication.
// Keep ONLY our two exact virtual IDs; preserve every ordinary validity test.
.macro savedCheck entry,found,second,valid,invalid
.globl _\entry
_\entry:
    cbz \found,1f
    b _\valid
1:
    pacibsp
    sub sp,sp,#256
    stp x29,x30,[sp]
    stp x0,x1,[sp,#16]
    stp x2,x3,[sp,#32]
    stp x4,x5,[sp,#48]
    stp x6,x7,[sp,#64]
    str x8,[sp,#80]
    stp q0,q1,[sp,#96]
    stp q2,q3,[sp,#128]
    stp q4,q5,[sp,#160]
    stp q6,q7,[sp,#192]
    str x21,[sp,#224]
    str \second,[sp,#232]
    mov x0,#-2
    adr x1,LSavedIdentifierName
    bl _STHSystemActionCoreDlsym
    cbz x0,2f
    mov x16,x0
    add x0,sp,#224
    blraaz x16
    b 3f
2:
    mov w0,#0
3:
    mov w17,w0
    ldp q6,q7,[sp,#192]
    ldp q4,q5,[sp,#160]
    ldp q2,q3,[sp,#128]
    ldp q0,q1,[sp,#96]
    ldr x8,[sp,#80]
    ldp x6,x7,[sp,#64]
    ldp x4,x5,[sp,#48]
    ldp x2,x3,[sp,#32]
    ldp x0,x1,[sp,#16]
    ldp x29,x30,[sp]
    add sp,sp,#256
    autibsp
    cbz w17,4f
    b _\valid
4:
    b _\invalid
.endm
.org 0x600
savedCheck STHSystemActionRestoreScan,x28,x22,STHSystemActionRestoreScanValid,STHSystemActionRestoreScanInvalid
.org 0x800
savedCheck STHSystemActionRestorePartition,x22,x25,STHSystemActionRestorePartitionValid,STHSystemActionRestorePartitionInvalid
LSavedIdentifierName:
    .asciz "STHSystemActionIsSavedIdentifier"
.p2align 2
