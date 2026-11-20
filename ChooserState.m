#import "Chooser.h"
#import <UIKit/UIKit.h>
#include <math.h>
#include <string.h>
extern uintptr_t sth_action_core_base;
extern BOOL STHChooserImageReady(void);
extern double STHChooserRingScale(void *);
extern CGSize STHChooserRingOffset(void *);
extern double STHChooserRingPreference(void *,uintptr_t);
extern BOOL STHChooserQuickSetting(void *),STHChooserEditing(void *),STHChooserShowTab(void *);
extern double STHChooserDamping(void);
static BOOL field(uintptr_t base,uintptr_t slot,uintptr_t *out){
 uintptr_t value=*(uintptr_t *)(base+slot);
 if(value<16||value>4096)return NO;*out=value;return YES;
}
BOOL STHChooserReadRing(STHChooserRingSnapshot *out){
 if(!out)return NO;memset(out,0,sizeof(*out));
 if(!NSThread.isMainThread||!STHChooserImageReady())return NO;
 uintptr_t b=sth_action_core_base;
 if(*(uint64_t *)(b+0xe95a0)!=UINT64_MAX||*(uint64_t *)(b+0xe9560)!=UINT64_MAX)return NO;
 void *ring=*(void **)(b+0xf7af0);if(!ring)return NO;
 uintptr_t r,w,g;
 if(!field(b,0xec4e8,&r)||!field(b,0xec4f0,&w)||!field(b,0xf7a48,&g))return NO;
 out->scale=STHChooserRingScale(ring);CGSize offset=STHChooserRingOffset(ring);
 out->offsetX=offset.width;out->offsetY=offset.height;
 out->radius=STHChooserRingPreference(ring,r);out->iconWidth=STHChooserRingPreference(ring,w);
 out->portraitX=*(double *)(b+0xf79c0);out->portraitY=*(double *)(b+0xf79c8);
 out->gestureState=*((uint8_t *)ring+g);out->damping=1.1;
 if(*(uint64_t *)(b+0xe95a8)==UINT64_MAX){
  void *setting=*(void **)(b+0xf7af8);
  if(setting){out->editing=STHChooserEditing(setting);out->quickSetting=STHChooserQuickSetting(setting);out->showTab=STHChooserShowTab(setting);out->damping=STHChooserDamping();}
 }
 double values[]={out->scale,out->offsetX,out->offsetY,out->radius,out->iconWidth,out->portraitX,out->portraitY,out->damping};
 for(unsigned i=0;i<sizeof(values)/sizeof(*values);i++)if(!isfinite(values[i]))return NO;
 if(out->scale<0||out->scale>5||out->radius<1||out->radius>3000||out->iconWidth<8||out->iconWidth>600||out->portraitX<20||out->portraitY<20)return NO;
 out->valid=YES;return YES;
}
