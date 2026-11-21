"""Independent regression lock for the accepted keyboard/gesture modules."""
from pathlib import Path
import ast,hashlib,json
R=Path(__file__).resolve().parent
frozen=json.loads((R/'inputs/frozen-runtime-2.0.15.json').read_text())
reviewed=json.loads((R/'inputs/reviewed-runtime-2.0.18.json').read_text())
reviewed.update(json.loads((R/'inputs/reviewed-runtime-2.0.19.json').read_text()))
reviewed.update(json.loads((R/'inputs/reviewed-runtime-2.0.20.json').read_text()))
reviewed.update(json.loads((R/'inputs/reviewed-runtime-2.0.24.json').read_text()))
reviewed.update(json.loads((R/'inputs/reviewed-runtime-2.0.25.json').read_text()))
reviewed.update(json.loads((R/'inputs/reviewed-runtime-2.0.26.json').read_text()))
reviewed.update(json.loads((R/'inputs/reviewed-runtime-2.0.27.json').read_text()))
reviewed.update(json.loads((R/'inputs/reviewed-runtime-2.0.28.json').read_text()))
latest=json.loads((R/'inputs/reviewed-runtime-2.0.29.json').read_text())
reviewed.update(latest)
for name,digest in latest.items():
 assert hashlib.sha256((R/name).read_bytes()).hexdigest()==digest,('unreviewed current source',name)
for name,digest in frozen.items():
 if name in ('LayoutProbe.m','LayoutProbe.h','NotificationPolicy.m'):
  assert not (R/name).exists();continue
 expected=reviewed.get(name,digest)
 assert hashlib.sha256((R/name).read_bytes()).hexdigest()==expected,('unreviewed runtime source change',name)
# Structural changes are explicit: one SpringBoard runtime, separate app adapter.
build=(R/'build.py').read_text()
assert 'migrate_native_bridge(img,OUT' in build
assert "'Gesture.m','Keyboard.m','DefaultSize.m','LayoutPublisher.m','LayoutBus.m'" in build
assert "'-Oz','-dynamiclib','KeyboardInset.m'" in build
assert "'KeyboardFocusBus.m'" in build and 'compact_signature(p)' in build
assert "OUT/'SthenoGesture.dylib'" not in build
print('Runtime audit lock passed; merged host and separate app focus/geometry path retained')
