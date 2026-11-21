"""Verify scoped card animation in emitted ARM64e, never a keyboard replacement."""
from pathlib import Path
import sys
from test_published_bridge_abi import Image,calls
ROOT=Path(__file__).resolve().parent

def verify(folder):
    image=Image(Path(folder)/'SthenoSystemActions.dylib')
    symbol='_STHCardRunExpansion'
    assert symbol in image.symbols,'Missing scoped card expansion bridge (old bouncy path)'
    words=image.words(symbol)
    targets=[target for target,_ in calls(words,image.symbols[symbol])]
    assert targets==[0x51454,0xafb5c,0xaf19c,0xb0a0c],list(map(hex,targets))
    # response=.25/nativeSpeed; damping=max(nativeSpeed,1); blend=0.
    # No duplicated speed read, timer, model setter or keyboard callback here.
    pair=[0x1e6a1001,0x1e601822,0x1e6e1001,0x1e616801,0x1e604040,0x9e6703e2]
    first=calls(words,image.symbols[symbol])[0][1]
    assert words[first+1:first+7]==pair,'Response/damping pair must remain coherent and non-oscillating'
    assert words[0]==0xd503237f and words[-1]==0xd65f0fff
    assert 0xa90257f4 in words and 0xa94257f4 in words,'Swift context must be preserved'
    assert 0xd2800015 in words,'Swift error/context register must be clear'
    print('Card expansion ABI: one native speed read; original response, damping floor 1; separate block transaction; no keyboard delivery or geometry hook')
if __name__=='__main__':verify(Path(sys.argv[1]) if len(sys.argv)>1 else ROOT/'build')
