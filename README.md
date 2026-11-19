# Stheno arm64e portrait gestures (binary-derived test build)

This private project reconstructs the requested portrait-gesture dispatch from the supplied Stheno binary. It is a replacement gesture module with ABI bridges, **not a recovery of the original full Swift source tree**.

## Behavior

- Existing hit-region geometry and width calculations remain in the original image.
- Red sides: one tap invokes native dock/minimize; .25s stationary hold arms native window movement.
- Green bottom corners: reuse native corner scaling.
- Blue bottom-left: hold for .25s to switch from portrait to landscape. In landscape, hold the middle of either original side edge or the lower-left blue segment for .25s to return to portrait.
- Blue bottom-right: hold for .25s to restore the model initializer's four scale values (.8,1,1,.8) and clear native aspect trim.
- Yellow bottom-center: drag to move the window. An upward flick that matches the original Stheno threshold closes the window on release.
- Sileo package name is `stheno` and the version is `2.0.1`. The Debian control file retains only `stheno` as its short description.
- Assumed subdivisions within the existing bottom band, left to right: green 0–15%, blue 15–35%, yellow 35–65%, blue 65–85%, green 85–100%. These are inferred from the user's drawing, not measured device pixels.
- The original four-edge interaction switch and existing exclusion checks still apply. They are not silently enabled and no hit-zone width is expanded.

## Build

`python3 build.py` on macOS with Xcode's iPhoneOS SDK. The workflow is `.github/workflows/build.yml`.

The script verifies the input DEB and exact arm64e main-image SHA-256, assembles PAC-preserving entry stubs and original-entry trampolines, compiles `Gesture.m` and `native.S`, signs both changed Mach-O files, verifies signatures, packs a Debian archive and reads every archive member back. Eight original components remain arm64e-only; the helper is also arm64e.

Only UI gesture entries are changed. Original license, media, keyboard, and package-maintenance logic is retained. Source model offsets are specific to the supplied sample, so the script rejects other binaries.

## Validation

Build, archive and code-signature checks do not verify behavior in SpringBoard. This package is a **device-untested test build**. Confirm hit regions, side tap/hold competition, scaling, landscape rotation, default-size restoration, multiple floating windows, and docking/un-docking on the actual RootHide device. Prior arm64e repack was reported by the user to load successfully; that report does not establish this patch's runtime behavior.

The original install/uninstall scripts are retained. Installation may reset preferences and restart cfprefsd. Keep the previously working DEB available for rollback. No GitHub token is stored in this repository.
