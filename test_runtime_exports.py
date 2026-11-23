from pathlib import Path
import json
from macho import exports
R=Path(__file__).resolve().parent
manifest=json.loads((R/'build/build-manifest.json').read_text())
image=(R/'build/SthenoSystemActions.dylib').read_bytes()
names=exports(image)
required={'_STHCenterRingPan','_STHInstallCenterChooser','_STHChooserHideBeforeCapture','_STHChooserShowFromNativeSelection','_STHSystemActionPresent','_STHDockReflow','_STHSystemUIBlocked'}
assert required<=names,('runtime C callback not dynamically exported',sorted(required-names))
assert manifest['center_app_chooser']['ring_auto_dismiss_preserved'] is True
print('Dynamic callback exports verified from actual Mach-O export trie:',len(required),'C entry points; internal Swift symbols alone are insufficient')
