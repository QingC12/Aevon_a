from pathlib import Path
R = Path(__file__).resolve().parent.parent
center = (R / "CenterChooser.swift").read_text()
gesture = (R / "Gesture.m").read_text()
dock = (R / "DockQueueBridge.m").read_text()
dock_native = (R / "DockQueueNative.S").read_text()
defaults = (R / "DefaultSize.m").read_text()
keyboard = (R / "ViewportHost.m").read_text()
chooser_native = (R / "ChooserNative.S").read_text()
assert "pendingRehit" in gesture and "resetGestureState" in gesture and "finishGestureState" in gesture
assert "STHNativeMinimized(m)" in gesture and "if(s.docked)" in gesture
assert "STHNativeMinimized(model)" in defaults and "STHNativeSetMinimized(model,NO)" in defaults
assert "STHChooserClearMinimized" in chooser_native
assert "add x8,sp,#32" in dock_native and "ldr x0,[sp,#32]" in dock_native
assert "blockedSides" in dock and "STHDockMayApply" in dock
assert "STHViewportModelMinimized" in keyboard and "restoreOwner" in keyboard and "maintainOwner" in keyboard
assert "UIBezierPath(ovalIn: hitArea).contains(point)" in center
assert "CenterGlyphGeometry.visibleHitArea" in center
# The size-reset long press also returns the card to its resting place.
assert "static CGSize centerDelta(CGRect card,CGRect screen)" in gesture
assert "static void recenterCard(void *m)" in gesture
assert "STHNativeReset(m);" in gesture and "recenterCard(m);" in gesture
assert gesture.index("STHNativeReset(m);")<gesture.index("recenterCard(m);")
assert "UIScreen.mainScreen.bounds" in gesture and "STHTestScreenBounds" in gesture
# The restored size may land on a later layout pass, which moves the centre after
# the first measurement. The place is therefore returned twice with the same
# relative rule, and the card is retained across the window because it can close
# before the second pass runs.
assert "static void recenterOnce(void *m)" in gesture
assert "80*NSEC_PER_MSEC" in gesture
assert 'dlsym(RTLD_DEFAULT,"swift_retain")' in gesture
assert gesture.index("retain(m);")<gesture.index("recenterOnce(m);release(m);")
print("Global logic contract: stale gesture recovery, dock restore, orientation ABI, keyboard ownership, reset place and center hit geometry")
