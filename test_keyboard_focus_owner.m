#import <Foundation/Foundation.h>
#import "KeyboardFocusBus.h"
#include <assert.h>
extern void *STHCopyInputFocusedModel(void);
static NSArray *cards;
static int retained,released;
void *STHDockCopyFloating(void){return (__bridge void *)cards;}
size_t STHChooserManagersCount(void *array){return [(__bridge NSArray *)array count];}
void *STHChooserCopyManagerAt(size_t i,void *array){retained++;return (__bridge void *)((NSArray *)cards)[i];}
void STHChooserReleaseArray(void *p){}
void STHChooserReleaseSwift(void *p){released++;}
BOOL STHDockNativeMinimized(void *p){return [((__bridge NSDictionary *)p)[@"minimized"] boolValue];}
void *STHSystemCopyModelIdentifier(void *p){return (__bridge_retained void *)[(__bridge NSDictionary *)p objectForKey:@"id"];}
int main(void){@autoreleasepool{
 NSString *a=[@"stheno.focus.a." stringByAppendingString:NSUUID.UUID.UUIDString];
 NSString *b=[@"stheno.focus.b." stringByAppendingString:NSUUID.UUID.UUIDString];
 NSDictionary *ca=@{@"id":a,@"minimized":@NO};NSMutableDictionary *cb=[@{@"id":b,@"minimized":@NO} mutableCopy];
 cards=@[ca,cb];
 for(int i=0;i<200;i++){
  STHPublishInputFocus(a,YES);assert(STHReadInputFocus(a)&&!STHReadInputFocus(b));
  void *m=STHCopyInputFocusedModel();assert(m==(__bridge void *)ca);STHChooserReleaseSwift(m);
  STHPublishInputFocus(b,YES);STHPublishInputFocus(a,NO);
  assert(STHReadInputFocus(b));m=STHCopyInputFocusedModel();assert(m==(__bridge void *)cb);STHChooserReleaseSwift(m);
  cb[@"minimized"]=@YES;assert(!STHCopyInputFocusedModel());cb[@"minimized"]=@NO;
  STHPublishInputFocus(b,NO);assert(!STHReadInputFocus(b)&&!STHCopyInputFocusedModel());
 }
 assert(retained==released);
 puts("Input owner: 200 real notify claim/handoff/minimize/clear cycles; no passive hit-test ownership");
}return 0;}
