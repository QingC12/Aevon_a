"""Explicit reset: preserve unrelated features, retire old keyboard runtime."""
from pathlib import Path
import hashlib,json
R=Path(__file__).resolve().parent.parent
m=json.loads((R/'inputs/reviewed-runtime-2.0.33.json').read_text())
for collection in ['preserved_nonkeyboard_sources','reviewed_active_production']:
 for name,digest in m[collection].items():
  # The lock holds the digest of the committed blob, which is LF. A checkout
  # with core.autocrlf rewrites the working copy to CRLF, so the line ending is
  # normalised here instead of making every reviewed file look modified.
  raw=(R/name).read_bytes()
  if b'\x00' not in raw:
   raw=raw.replace(b'\r\n',b'\n')
  assert hashlib.sha256(raw).hexdigest()==digest,('Unreviewed production change',name)
for name in m['retired_production']:assert not (R/name).exists(),('Legacy source present',name)
build=(R/'build.py').read_text()
for name in ['ViewportHost.m','ViewportClient.m','ViewportBus.m','ViewportDiagnostics.m']:
 assert "'"+name+"'" in build,name
for name in m['retired_production']:assert "'"+name+"'" not in build,('Retired compiler input',name)
assert 'base-patched.deb' in build and 'compact_signature(p)' in build
assert "OUT/'SthenoGesture.dylib'" not in build
print('Runtime33 audit lock passed:',len(m['preserved_nonkeyboard_sources']),'unrelated production files preserved;',len(m['reviewed_active_production']),'active sources reviewed;',len(m['retired_production']),'retired production files absent')
