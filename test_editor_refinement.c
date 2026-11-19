#include <assert.h>
#include <stdio.h>
#include "EditorRefinement.h"
#include "EditorProfiles.h"
#include "KeyboardAccessoryMath.h"
static void near(double a,double b){assert(fabs(a-b)<.001);}
int main(void){
 // Preserve2.0.11 route, no refined calculation or extra margin for known-good.
 assert(STHProfileForBundle("com.tencent.mqq")==STHEditorCompatible);
 assert(STHProfileForBundle("com.openminis.app")==STHEditorCompatible);
 assert(STHProfileForBundle("com.tencent.xin")==STHEditorCompact);
 assert(STHProfileForBundle("com.coolapk.app")==STHEditorCompact);
 assert(STHProfileForBundle("com.ss.iphone.ugc.Aweme")==STHEditorCompact);
 assert(STHProfileForBundle("com.feng.New.WPForumClient")==STHEditorTransparentTail);
 assert(STHProfileForBundle(NULL)==STHEditorCompatible);
 // Device log selected305pt WeChat panel. Keep compact52pt editor, not page.
 assert(!STHCompactComposer(430,305,430,731,false));
 assert(STHCompactComposer(430,52,430,731,false));
 assert(!STHCompactComposer(430,731,430,731,false));
 // Douyin112pt input assembly; emoji pane with layout spacing is attributable
 // only through same bounded branch and control evidence, not a fixed lift.
 STHRect input={0,365.625,430,112};
 assert(STHRefinedRow(input,(STHRect){0,489.625,430,240},731,true,true));
 assert(!STHRefinedRow(input,(STHRect){0,489.625,430,240},731,true,false));
 assert(!STHRefinedRow(input,(STHRect){0,489.625,430,240},731,false,true));
 assert(!STHRefinedRow(input,(STHRect){0,489.625,430,500},731,true,true));
 assert(!STHRefinedRow(input,(STHRect){500,477.625,430,150},731,true,true));
 // Repeated AutoLayout reposition with the same view transform must converge,
 // not accumulate238/255pt on top of already-aligned current geometry.
 double previous=0;
 for(int i=0;i<100;i++){
  double appBottom=(i%3==0)?731:((i%3==1)?494.5:477.5);
  double visible=appBottom-previous;
  previous=STHRefinedLift(previous,visible,460.5,appBottom-52,52,731);
  near(appBottom-previous,460.5);
  near(STHRefinedLift(previous,460.5,460.5,appBottom-52,52,731),previous);
 }
 near(STHRefinedLift(0,477.75,477.5,400,60,731),0);
 // WeiFeng: collapse only measured transparent wrapper tail, never a generic
 // small gap or opaque footer, and only after a stable observation interval.
 near(STHTransparentTailDrop(477.5,460.5,477.5,175,true,true),17);
 near(STHTransparentTailDrop(477.5,460.5,477.5,175,false,true),0);
 near(STHTransparentTailDrop(477.5,460.5,477.5,175,true,false),0);
 near(STHTransparentTailDrop(460.5,460.5,477.5,175,true,true),0);
 near(STHTransparentTailDrop(477.5,400,477.5,175,true,true),0);
 STHRect keyboard;
 assert(STHExcludeAppAccessory((STHRect){0,529,430,403},(STHRect){0,529,430,61},430,932,&keyboard));
 near(keyboard.y,590);near(keyboard.h,342);
 assert(!STHExcludeAppAccessory((STHRect){0,590,430,342},(STHRect){0,529,430,61},430,932,&keyboard));
 assert(!STHExcludeAppAccessory((STHRect){0,529,430,403},(STHRect){0,400,430,500},430,932,&keyboard));
 assert(STHExcludeAppAccessory((STHRect){0,533,430,399},(STHRect){0,533,430,57},430,932,&keyboard));
 near(keyboard.y,590); // Geometry, not a57/61pt universal subtraction.
 puts("Refined editor tests passed: QQ/Minis isolation, no305pt page, bounded emoji,100 reflows, measured transparent tail only");
 return 0;
}
