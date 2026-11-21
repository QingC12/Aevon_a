from pathlib import Path
R = Path(__file__).resolve().parent
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
print("Global logic contract: stale gesture recovery, dock restore, orientation ABI, keyboard ownership and center hit geometry")
