"""Hash-locked old-source controls; host state tests, not device animation claims."""
from pathlib import Path
import hashlib,resource,subprocess,tempfile
R=Path(__file__).resolve().parent
OLD_SHA='22449eb76338393b91d178fe42a3bbf1eabfbcfa2107c630494475e4fe9da448'

def source29():
    source=(R/'Keyboard.m').read_text()
    source=source.replace('static NSUInteger inputReadGeneration;\n','').replace('  inputReadGeneration++;\n','').replace(' inputReadGeneration++;\n','')
    first=source.index('static void recheckInputOwner(')
    last=source.index('#if !defined(STH_KEYBOARD_TEST)\n__attribute__((constructor))',first)
    source=source[:first]+source[last:]
    prefix='''static void inputOwnerChanged(void){
 if(localInput)return;
 STHRect physical={0,0,0,0};
 void *model=STHSystemActionsEnabled()?STHCopyInputFocusedModelWithFrame(&physical):NULL;
 if(!model){
  if(owner||candidate)STHCenterRunAnimation(^{
   if(localInput)return;
   STHStopLayout();restoreCard();candidate=nil;candidateAt=0;candidateConfirmed=NO;
  },0);
  return;
 }
'''
    source=source.replace('static void acceptInputOwner(void *model,STHRect physical){\n',prefix)
    source=source.replace('extern void STHCenterRunAnimation(void (^block)(void),int);\n','extern void STHCenterRunAnimation(void (^block)(void),int);\nextern void STHCardRunExpansion(void (^block)(void));\n')
    scoped='''#if !defined(STH_KEYBOARD_TEST) || defined(STH_KEYBOARD_INPUT_TEST)
  double scale=target[0],x=target[1],y=target[2];
  STHCardRunExpansion(^{const double geometry[3]={scale,x,y};STHNativeSetKeyboardGeometry((__bridge void *)focus,geometry);});
#else
  STHNativeSetKeyboardGeometry((__bridge void *)focus,target);
#endif'''
    original='  STHNativeSetKeyboardGeometry((__bridge void *)focus,target);'
    assert source.count(original)==1
    source=source.replace(original,scoped)
    assert hashlib.sha256(source.encode()).hexdigest()==OLD_SHA,'Exact 2.0.29 reconstruction drift'
    return source

def main():
    resource.setrlimit(resource.RLIMIT_CORE,(0,0))
    with tempfile.TemporaryDirectory(prefix='stheno-transition-red-') as directory:
        tmp=Path(directory);old=tmp/'Keyboard29.m';old.write_text(source29());exe=tmp/'transition29'
        subprocess.check_call(['xcrun','--sdk','macosx','clang','-fobjc-arc','-Wall','-Wextra','-Wno-unused-parameter','-I',str(R),'-DSTH_OLD_TRANSITION',f'-DSTH_KEYBOARD_SOURCE="{old}"',str(R/'test_native_card_transition.m'),'-framework','Foundation','-framework','CoreGraphics','-framework','QuartzCore','-o',str(exe)])
        for args,marker in [([], 'allowOldSpring||transaction!=3'),(['--transient'],'owner==a&&geometryWrites==writes')]:
            result=subprocess.run([str(exe),*args],capture_output=True,text=True)
            assert result.returncode!=0 and 'Assertion failed' in result.stderr and marker in result.stderr,result.stderr
        print('Native transition negative controls: exact 2.0.29 source fails both nested-card-spring and transient-empty-read shrink assertions')
if __name__=='__main__':main()
