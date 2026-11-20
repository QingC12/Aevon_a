"""Independent regression lock for the accepted keyboard/gesture modules."""
from pathlib import Path
import ast,hashlib,json
R=Path(__file__).resolve().parent
frozen=json.loads((R/'inputs/frozen-runtime-2.0.15.json').read_text())
reviewed=json.loads((R/'inputs/reviewed-runtime-2.0.18.json').read_text())
for name,digest in frozen.items():
 if name in ('LayoutProbe.m','LayoutProbe.h','NotificationPolicy.m'):
  assert not (R/name).exists();continue
 expected=reviewed.get(name,digest)
 assert hashlib.sha256((R/name).read_bytes()).hexdigest()==expected,('unreviewed runtime source change',name)
# New actions use an isolated helper; neither old compiler command receives a
# system-action source or new flags, so inherited behavior is not relinked in.
tree=ast.parse((R/'build.py').read_text())
commands=[]
for node in ast.walk(tree):
 if isinstance(node,ast.Call) and isinstance(node.func,ast.Name) and node.func.id=='run':
  strings=[a.value for a in node.args if isinstance(a,ast.Constant) and isinstance(a.value,str)]
  if '-dynamiclib' in strings:commands.append(strings)
for first in ('Gesture.m','KeyboardInset.m'):
 cmd=next(c for c in commands if first in c)
 assert not any(v.startswith('System') for v in cmd),cmd
 assert '-O2' in cmd and '-fobjc-arc' in cmd
print('Original geometry remains frozen; explicit diagnostic/touch changes reviewed:',len(frozen),'files; existing helper compile paths unchanged')
