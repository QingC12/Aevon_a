"""Explicit reset: preserve unrelated features, retire old keyboard runtime."""
from pathlib import Path
import hashlib,json
R=Path(__file__).resolve().parent.parent
m=json.loads((R/'inputs/reviewed-runtime-2.0.33.json').read_text())
repair=json.loads((R/'inputs/reviewed-runtime-2.0.60.json').read_text())
assert repair['version']==json.loads((R/'inputs/base-patched.json').read_text())['version']=='2.0.60'
assert repair['baseline_commit']=='93c9c8006980403d6015133a40cfd7bb490189ad'
approved=repair['approved_changes']

def digest(name):
 raw=(R/name).read_bytes()
 if b'\x00' not in raw:raw=raw.replace(b'\r\n',b'\n')
 return hashlib.sha256(raw).hexdigest()

for collection in ['preserved_nonkeyboard_sources','reviewed_active_production']:
 for name,baseline in m[collection].items():
  change=approved.get(name)
  if change:
   assert change['baseline_sha256']==baseline,('Incorrect prior audit digest',name)
   assert digest(name)==change['sha256'],('Repaired source digest mismatch',name)
  else:
   assert digest(name)==baseline,('Unreviewed production change',name)
for name,change in approved.items():
 assert digest(name)==change['sha256'],('Repaired source digest mismatch',name)
 assert change['reason'],('Missing repair rationale',name)
 if name not in m['reviewed_active_production'] and name not in m['preserved_nonkeyboard_sources']:
  assert change['baseline_sha256'] is None,('Unexpected pre-existing source',name)
for name in m['retired_production']:assert not (R/name).exists(),('Legacy source present',name)
build=(R/'build.py').read_text()
for name in ['ViewportHost.m','ViewportClient.m','ViewportBus.m','ViewportDiagnostics.m']:
 assert "'"+name+"'" in build,name
for name in m['retired_production']:assert "'"+name+"'" not in build,('Retired compiler input',name)
assert 'base-patched.deb' in build and 'compact_signature(p)' in build
assert "OUT/'SthenoGesture.dylib'" not in build
print('Runtime audit locks passed:',len(m['preserved_nonkeyboard_sources']),'baseline protected sources;',len(m['reviewed_active_production']),'active baseline sources;',len(approved),'exactly approved repair files;',len(m['retired_production']),'retired production files absent')
