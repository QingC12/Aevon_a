from pathlib import Path
import json,subprocess,tempfile
R=Path(__file__).resolve().parent
f=json.loads((R/'inputs/device31-frame-fixture.json').read_text())
def c(r):return '{'+','.join(repr(r[k]) for k in ('x','y','w','h'))+'}'
code=['#include <assert.h>','#include <stdio.h>','#include "ViewportAuthority.h"','int main(void){',f'STHVRect card={c(f["card"])},scene={c(f["scene"])},screen={c(f["screen"])},sb={c(f["sb_scenario"])},mapped;']
for e in f['events']:
 code.append('{STHVRect appRaw='+c(e['raw'])+',oldMapped='+c(e['mapped31'])+';assert(STHVNear(STHVMap(card,appRaw,scene),oldMapped,1e-7));assert(STHVAuthoritativeMap(card,sb,screen,scene,123,true,&mapped));assert(fabs(mapped.y-489.5)<1e-7&&fabs(mapped.h-241.5)<1e-7);}')
code+=['assert(!STHVAuthoritativeMap(card,sb,screen,scene,0,true,&mapped));','assert(!STHVAuthoritativeMap(card,sb,screen,scene,124,false,&mapped));','assert(!STHVAuthoritativeMap(card,(STHVRect){0},screen,scene,124,true,&mapped));','puts("Uploaded fixture: 24 old mappings reproduced; declared SB authority keeps inset241.5 for every app raw; pending/hide have no guessed physical frame");return 0;}']
with tempfile.TemporaryDirectory() as d:
 p=Path(d);(p/'test.c').write_text('\n'.join(code));subprocess.run(['clang','-std=c11','-Wall','-Wextra','-Werror','-I',str(R),str(p/'test.c'),'-lm','-o',str(p/'test')],check=True);subprocess.run([str(p/'test')],check=True)
print('Fixture source SHA:',f['source_sha256'])
