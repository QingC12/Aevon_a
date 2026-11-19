// Compile the production delivery adapter with mock normalization/transport.
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#include <assert.h>
#include <stdio.h>
#import "KeyboardSession.h"
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
 phase=2;send(@"UIKeyboardWillShowNotification",545);assert(callbacks==0&&heldNotes.count==1);
 send(@"UIKeyboardWillChangeFrameNotification",518);assert(callbacks==0&&heldNotes.count==2);
 phase=1;currentEnd=489.5;flushHeld(YES);
 // One normalization before delivery, not a different read per observer.
 assert(callbacks==2&&fabs(first-second)<.001&&fabs(first-489.5)<.001);
 assert(heldNotes.count==0);
 // Hide cancels any delayed show. A later flush cannot replay last session.
 phase=2;send(@"UIKeyboardWillShowNotification",545);assert(heldNotes.count==1);
 send(@"UIKeyboardWillHideNotification",932);assert(heldNotes.count==0);
 flushHeld(YES);assert(callbacks==2);
 int beforeDid=preparations;phase=0;
 send(@"UIKeyboardDidHideNotification",932);assert(preparations==beforeDid+1&&!awaitingDidHide);
 // Inactive/fullscreen notification is forwarded untouched.
 [NSNotificationCenter.defaultCenter removeObserver:a];[NSNotificationCenter.defaultCenter removeObserver:b];
 __block double fullscreen=0;
 id c=[NSNotificationCenter.defaultCenter addObserverForName:@"UIKeyboardWillShowNotification" object:nil queue:nil usingBlock:^(NSNotification *n){fullscreen=[n.userInfo[@"top"] doubleValue];}];
 phase=0;send(@"UIKeyboardWillShowNotification",612);assert(fullscreen==612);
 [NSNotificationCenter.defaultCenter removeObserver:c];
 printf("Production delivery tests passed: immutable observer frame, deferred start, hide cancellation, fullscreen passthrough (%d preparations)\n",preparations);
}return 0;}
