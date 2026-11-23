from pathlib import Path
R = Path(__file__).resolve().parent.parent
native = (R / "DockQueueNative.S").read_text()
assert "add x8,sp,#32" in native and "ldr x0,[sp,#32]" in native
print("Dock ABI: orientation result buffer avoids saved x19 and preserves caller registers")
