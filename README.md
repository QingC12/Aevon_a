# Stheno arm64e portrait gestures (binary-derived test build)

This private project reconstructs the requested portrait-gesture dispatch from the supplied Stheno binary. It is a replacement gesture module with ABI bridges, **not a recovery of the original full Swift source tree**.

## Behavior

- Existing hit-region geometry and width calculations remain in the original image.
- Red sides: one tap invokes native dock/minimize; .25s stationary hold arms native window movement.
- Green bottom corners: reuse native corner scaling.
- Blue bottom-left: hold for .25s to switch from portrait to landscape. In landscape, hold the middle of either original side edge or the lower-left blue segment for .25s to return to portrait.
- Blue bottom-right: hold for .25s to restore the model initializer's four scale values (.8,1,1,.8) and clear native aspect trim.
- Yellow bottom-center: touch and drag immediately to move; release is passed once to the original Stheno edge-middle drag-end routine with hit class 4 and its long-press latch cleared. Native flick threshold, cleanup and animation decide closing. There is no .25s hold requirement, 24pt threshold or custom close action.
- Yellow continuous movement never changes its saved edge-middle hit class. The native close recognition code is byte-for-byte preserved, and build.py asserts this before signing.
- Movement and corner scaling use original Stheno update paths. Docking uses the original SwiftUI spring transaction; closing uses the original native release path. Restoring a docked window and switching orientations retain their original callbacks.
- Sileo lists `stheno` at `2.0.3`. The Debian control file retains `stheno` as its short description.
- Keyboard: in portrait, the recently touched floating content is enlarged toward the screen width (12pt total horizontal margin, maximum 35% temporary increase), while original keyboard avoidance controls vertical placement. Hide restores the pre-keyboard scale and model offset, unless the user changed either while typing. Repeated show notifications do not replace the original snapshot. Hardware/floating keyboards and landscape cards retain native behavior.
- The video reference is approximated through model geometry; actual device timing and placement still require validation. Both hooks run inside the original Stheno keyboard SwiftUI spring; no UIKit duration replacement or screen-sized view transforms are applied.
- Assumed subdivisions within the existing bottom band, left to right: green 0–15%, blue 15–35%, yellow 35–65%, blue 65–85%, green 85–100%. These are inferred from the user's drawing, not measured device pixels.
- The original four-edge interaction switch and existing exclusion checks still apply. They are not silently enabled and no hit-zone width is expanded.

## Build

`python3 build.py` on macOS with Xcode's iPhoneOS SDK. The workflow is `.github/workflows/build.yml`.

The script verifies the input DEB and exact arm64e main-image SHA-256, assembles PAC-preserving entry stubs and original-entry trampolines, compiles `Gesture.m` and `native.S`, signs both changed Mach-O files, verifies signatures, packs a Debian archive and reads every archive member back. Eight original components and the gesture helper remain arm64e-only; the bundled Orion runtime is arm64e-only as well.

Only gesture entry code and the main library's Orion load path are patched. Media, keyboard, and package-maintenance logic is retained. Source model offsets are specific to the supplied sample, so the script rejects other binaries.

## Orion is bundled privately

The main image imports 79 symbols from Orion. This build does not delete that code or fake its symbols: it includes the official Theos Orion 1.0.2 arm64e runtime at `Library/MobileSubstrate/DynamicLibraries/.stheno/Orion` and links to it through `@loader_path/.stheno/Orion`. The private runtime has a distinct install name `@rpath/SthenoOrion`, preventing it from occupying the usual global Orion framework path. Its Substrate dependency uses RootHide's `.jbroot` path from the parent directory.

`Depends` no longer contains `dev.theos.orion`; only the existing MobileSubstrate and firmware dependencies remain. No other app or tweak is told that a global Orion package is installed. Do not remove an Orion package that other installed tweaks need.

Official source/release: https://github.com/theos/orion/releases/tag/1.0.2

Release archive SHA-256: `67ea96da8983a792bc9e5549472c2e597b84024c66bce888ce19e7940e413e55`

Input arm64e runtime SHA-256: `e7cbd6e055d9ec30c750741c9a2831d73c5ce7efaf812053e7b279a4e92dbe85`

The MIT license is preserved as `.stheno/Orion-LICENSE.txt` in the DEB. `test_embed_orion.py` verifies all imports, private resolution, unchanged load-command ordinals and code/fixup bytes, rejects a modified runtime, and checks the license. CI signs and verifies the private runtime along with the patched core and gesture helper.

Future versions use `2.0.2`, `2.0.3`, etc., without `+fix` suffixes.

## Validation

Build, archive and code-signature checks do not verify behavior in SpringBoard. This package is a **device-untested test build**. Confirm hit regions, side tap/hold competition, scaling, landscape rotation, default-size restoration, multiple floating windows, and docking/un-docking on the actual RootHide device. Prior arm64e repack was reported by the user to load successfully; that report does not establish this patch's runtime behavior.

The original install/uninstall scripts are retained. Installation may reset preferences and restart cfprefsd. Keep the previously working DEB available for rollback. No GitHub token is stored in this repository.
