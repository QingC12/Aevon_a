// Compile the production delivery adapter with mock normalization/transport.
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#include <assert.h>
#include <stdio.h>
#import "KeyboardSession.h"
#import "EditorSession.h"
// UIKit is unavailable on the macOS host; only names are mocked, not adapter code.
static NSString *const UIKeyboardWillShowNotification=@"UIKeyboardWillShowNotification";
static NSString *const UIKeyboardDidShowNotification=@"UIKeyboardDidShowNotification";
static NSString *const UIKeyboardWillChangeFrameNotification=@"UIKeyboardWillChangeFrameNotification";
static NSString *const UIKeyboardDidChangeFrameNotification=@"UIKeyboardDidChangeFrameNotification";
static NSString *const UIKeyboardWillHideNotification=@"UIKeyboardWillHideNotification";
static NSString *const UIKeyboardDidHideNotification=@"UIKeyboardDidHideNotification";
static char normalizedKey;
static STHKeyboardSession session;
static int phase=0,preparations=0;
static double currentEnd=489.5;
static int STHLayoutStatus(NSString *bundle){return phase;}
static void STHWriteLayoutLog(NSString *s){}
static NSDictionary *normalizedInfo(NSNotification *note,SEL selector){
 preparations++;
 return @{@"top":@(currentEnd)};
}
static STHEditorSession lifecycle;
static BOOL prepareKeyboardLifecycle(NSString *name,int state){
 if([name isEqualToString:UIKeyboardWillShowNotification]||[name isEqualToString:UIKeyboardDidShowNotification]){
  STHEditorShow(&lifecycle);return YES;
 }
 if([name isEqualToString:UIKeyboardWillHideNotification]){STHEditorWillHide(&lifecycle);return YES;}
 if([name isEqualToString:UIKeyboardDidHideNotification]){
  if(!STHEditorDidHide(&lifecycle)&&state>0&&lifecycle.active)return NO;
 }
 return YES;
}
#include "KeyboardDelivery.inc"
static void send(NSString *name,double top){
 [NSNotificationCenter.defaultCenter postNotificationName:name object:nil userInfo:@{@"top":@(top)}];
}
int main(void){@autoreleasepool{
 installDelivery();
 __block int callbacks=0;
 __block double first=0,second=0;
 id a=[NSNotificationCenter.defaultCenter addObserverForName:@"UIKeyboardWillShowNotification" object:nil queue:nil usingBlock:^(NSNotification *n){
  first=[n.userInfo[@"top"] doubleValue];callbacks++;currentEnd=444.5;
 }];
 id b=[NSNotificationCenter.defaultCenter addObserverForName:@"UIKeyboardWillShowNotification" object:nil queue:nil usingBlock:^(NSNotification *n){
  second=[n.userInfo[@"top"] doubleValue];callbacks++;
 }];
 phase=2;currentEnd=489.5;
 send(@"UIKeyboardWillShowNotification",545);
 // Same call stack, no160ms/650ms deferral and no late-show replay.
 assert(callbacks==2&&fabs(first-second)<.001&&fabs(first-489.5)<.001);
 int prepared=preparations;
 send(@"UIKeyboardWillChangeFrameNotification",518);assert(preparations==prepared+1);
 phase=1;currentEnd=489.5;
 send(@"UIKeyboardWillShowNotification",590);
 assert(callbacks==4&&fabs(first-second)<.001);
 send(@"UIKeyboardWillHideNotification",932);
 assert(callbacks==4);
 int beforeDid=preparations;phase=0;
 send(@"UIKeyboardDidHideNotification",932);assert(preparations==beforeDid+1&&!awaitingDidHide);
 // Close/open interleaving: an old DidHide cannot normalize/clear a new show.
 phase=1;send(@"UIKeyboardWillShowNotification",590);
 send(@"UIKeyboardWillHideNotification",932);
 send(@"UIKeyboardWillShowNotification",590);assert(lifecycle.active);
 int beforeStale=preparations;
 send(@"UIKeyboardDidHideNotification",932);
 assert(preparations==beforeStale&&lifecycle.active);
 send(@"UIKeyboardWillHideNotification",932);send(@"UIKeyboardDidHideNotification",932);
 assert(!lifecycle.active&&!lifecycle.closing);
 // Inactive/fullscreen notification is forwarded untouched.
 [NSNotificationCenter.defaultCenter removeObserver:a];[NSNotificationCenter.defaultCenter removeObserver:b];
 __block double fullscreen=0;
 id c=[NSNotificationCenter.defaultCenter addObserverForName:@"UIKeyboardWillShowNotification" object:nil queue:nil usingBlock:^(NSNotification *n){fullscreen=[n.userInfo[@"top"] doubleValue];}];
 phase=0;send(@"UIKeyboardWillShowNotification",612);assert(fullscreen==612);
 [NSNotificationCenter.defaultCenter removeObserver:c];
 printf("Production delivery tests passed: immediate Will delivery, immutable observer frame, hide lifecycle, fullscreen passthrough (%d preparations)\n",preparations);
}return 0;}
