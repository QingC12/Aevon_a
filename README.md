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
- Sileo lists `stheno` at `2.0.9`. The Debian control file retains `stheno` as its short description.
- Keyboard: the touched portrait floating card is sized to the full screen width and horizontally centered, without the old 12pt margin or 35% cap. Hide restores the snapshot, unless the user changed it while typing. Hardware/floating keyboards and landscape retain native behavior.
- Keyboard coordinates now prefer a fresh, per-bundle snapshot published by SpringBoard: the native final card rectangle (which already includes final scale) and docked physical keyboard rectangle. Application notifications and UIKit insets map the keyboard using BOTH the card origin and its screen-to-app scale. Top-positioned cards can have zero obstruction; lower cards get the correct larger local obstruction. Native InputSetHost/physical-screen conversion remains a fallback if the host snapshot is absent. The native card's `finalFrame` is already computed as base frame times final scale at `0x9c73c–0x9c758`; it is not multiplied by scale a second time.
- New in2.0.9, based on the latest device log: keyboard frame and final card frame are debounced as a PAIR. No pre-expansion card is committed. Initial target has at least160ms collection and120ms quiet time; while a later candidate changes, the previous committed pair remains authoritative. Real sustained geometry changes are accepted; no hardcoded590/545 or minimum historical top is chosen. The log repeatedly showed590→545→590 in18–55ms with a fixed card; these transients are now test fixtures.
- The original native keyboard-avoidance height is reconciled to the stable physical keyboard frame using the SAME original SwiftUI keyboard spring; this avoids leaving the native model on the initial563 frame while apps use final590. The main binary/entry patch set is unchanged; only a helper ABI wrapper is added. Existing gestures/default-size source stay unchanged.
- Cross-process layout now uses a v4 double-buffer protocol: write the inactive pair and flip one generation/timestamp word. Active updates never temporarily set commit=0. Heartbeats refresh liveness silently without triggering repeated app re-layout. Pending and inactive states are distinct.
- A content focus pre-announces pending layout so an app keyboard event can wait for the host. App keyboard delivery is normalized ONCE before dispatch to all observers. During initial pending geometry, keyboard show/frame events are coalesced and deferred; normally this is about160–250ms, with650ms escape back to native delivery if the host fails. The short initial coordination delay is deliberate and requires device latency acceptance. Hide cancels pending events to avoid a late show. Other apps/fullscreen/non-keyboard notifications remain passthrough.
- In2.0.8, one resolver returns SCENE geometry and SCENE inset for both UIKit's `intersectionHeightForWindowScene:` API and notification consumers. No popup-window height/origin enters the hosted scene path. This fixes the prior path that could leak an extra window-origin offset (the repeated 241.5/286.5 and268.5/313.5 branches in the device log). All fallback sources obey the same bottom-occlusion contract. No fixed45pt compensation or per-app magic offset is used.
- Physical and delivered scene frames now have separate session storage. Self-generated notifications are tagged and not normalized twice or saved as physical-screen frames. Refresh commits canonical state before sending Will/DidChangeFrame, does not require an observer to read userInfo, reuses real keyboard animation metadata, and invalidates on hide/host expiry.
- The app adapter is explicitly excluded from SpringBoard, Spotlight and the keyboard process, preserving the publisher's physical notifications. Current visible input-set containers plus visible adjacent keyboard accessory/candidate/toolbar views form the live physical keyboard region. Old notification rectangles are no longer unioned into it; current native physical notification is only a fallback. Debug output identifies source, native rectangle and age. The log's27pt source changes alone do not prove which top is physically visible; device verification remains necessary.
- The new app coordinate correction requires a fresh, per-bundle active host snapshot. It does not stay enabled after keyboard hide/fullscreen return merely because a cached legacy frontmost value says so.
- First presentation of each manager uses the same default tuple and aspect-clear body as bottom-right reset, followed by native geometry refresh. It runs after scene setup through the native presentation entry, not during incomplete model initialization; subsequent presentation of a reused manager does not force-reset user size.
- Snapshot transport uses Darwin notify state and freshness/commit validation, not shared-file access. Updates are scoped to the floated bundle; hide invalidates them. Synthetic frame-change notifications only follow meaningful geometry changes and reuse the original keyboard animation metadata; card transitions retain the original spring.
- The existing full-width expansion/restore remains. A card whose editor would be completely behind the keyboard is minimally moved upward to retain editing space; hide restores its saved position unless manually changed.
- Geometry-only logs now originate in SpringBoard too, including module initialization, published layout and application acknowledgments. They try `/var/mobile/Documents/SthenoKeyboardLayout.log`, then the process's own `Documents/SthenoKeyboardLayout.log`, then its temporary directory; bounded to512KiB, mode 0600. No typed text or messages are logged. Permissions and RootHide path mirroring can still affect the physical location. Logging failure never controls coordinate correction.
- The doubled window borders in supplied screenshots came from the screenshot tool's freeze mode and are not diagnosed as a Stheno duplication bug.
- The video reference is approximated through model geometry; actual device timing and placement still require validation. Both hooks run inside the original Stheno keyboard SwiftUI spring; no UIKit duration replacement or screen-sized view transforms are applied.
- Assumed subdivisions within the existing bottom band, left to right: green 0–15%, blue 15–35%, yellow 35–65%, blue 65–85%, green 85–100%. These are inferred from the user's drawing, not measured device pixels.
- The original four-edge interaction switch and existing exclusion checks still apply. They are not silently enabled and no hit-zone width is expanded.

## Build

`python3 build.py` on macOS with Xcode's iPhoneOS SDK. The workflow is `.github/workflows/build.yml`.

The script verifies the input DEB and exact arm64e main-image SHA-256, assembles PAC-preserving entry stubs and original-entry trampolines, compiles `Gesture.m` and `native.S`, signs both changed Mach-O files, verifies signatures, packs a Debian archive and reads every archive member back. Eight original components and the gesture helper remain arm64e-only; the bundled Orion runtime is arm64e-only as well.

Only gesture entry code, the private Orion load path, and an added app-side keyboard-inset helper load command are patched. Media and package-maintenance logic are retained. The original app-side keyboard code is preserved; the helper wraps its result after the original hooks initialize. Source model offsets are specific to the supplied sample, so the script rejects other binaries.

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
