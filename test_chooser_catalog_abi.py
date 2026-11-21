"""Verify emitted native catalog entry selection; this is not a device LS test."""
from pathlib import Path
import sys
from test_published_bridge_abi import Image, calls
ROOT=Path(__file__).resolve().parent

def verify(folder):
    image=Image(Path(folder)/'SthenoSystemActions.dylib')
    words=image.words('_STHChooserCopyCatalogs')
    entries=calls(words,image.symbols['_STHChooserCopyCatalogs'])
    targets=[target for target,_ in entries]
    assert targets==[0x24fe8,0x24fe8,0xb07fc],('Catalog must enumerate types 0/1 and release a partial result',list(map(hex,targets)))
    # Each callcore macro occupies six instructions; the preceding argument
    # selects the original user/system filters. No synthetic LS proxies.
    assert words[entries[0][1]-6]==0x52800000, 'Expected user type 0'
    assert words[entries[1][1]-6]==0x52800020, 'Expected system type 1'
    assert 0xd2800015 in words, 'Swift error/context register must be cleared'
    assert words[0]==0xd503237f and words[-1]==0xd65f0fff
    assert 0xa9be57f4 in words and 0xa8c257f4 in words, 'Swift caller context must be preserved'
    # Both owned arrays are stored only after success; failed calls see zeros.
    assert 0xa9007c1f in words, 'Output must start as two null pointers'
    core=(Path(folder)/'Stheno.dylib').read_bytes()
    assert core[0x24fe8:0x24ff8]==bytes.fromhex('7f2303d5ff8302d1fa6705a9f85f06a9')
    # GlobalEnv initializes its App caches to the Swift empty-array singleton;
    # this is why retaining those fields is not an installed-app enumeration.
    assert core[0x84120:0x84130]==bytes.fromhex('c80200b0089142f9882201a9881200f9')
    print('Chooser catalog ABI: original user/system enumeration, independent of empty GlobalEnv cache; partial ownership and caller context retained')

if __name__=='__main__':
    verify(Path(sys.argv[1]) if len(sys.argv)>1 else ROOT/'build')
