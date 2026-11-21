// Hold both shell assertions for exactly one chooser presentation.
#include <string.h>
static const char *focusType(const char *s){while(s&&*s&&strchr("rnNoORV",*s))s++;return s;}
static BOOL focusInvalidatable(id value){
 NSMethodSignature *s=[value methodSignatureForSelector:NSSelectorFromString(@"invalidate")];
 return s&&s.numberOfArguments==2&&focusType(s.methodReturnType)[0]=='v';
}
static void invalidateFocus(id value){
 if(focusInvalidatable(value))((void(*)(id,SEL))objc_msgSend)(value,NSSelectorFromString(@"invalidate"));
}
static id focusObject2(id target,NSString *name,id a,id b){
 SEL sel=NSSelectorFromString(name);NSMethodSignature *s=[target methodSignatureForSelector:sel];
 if(!s||s.numberOfArguments!=4||focusType(s.methodReturnType)[0]!='@'||
    focusType([s getArgumentTypeAtIndex:2])[0]!='@'||focusType([s getArgumentTypeAtIndex:3])[0]!='@')return nil;
 return ((id(*)(id,SEL,id,id))objc_msgSend)(target,sel,a,b);
}
@interface STHChooserFocusToken : NSObject
@property(nonatomic,strong) id sceneLock;
@property(nonatomic,strong) id windowStealing;
- (void)invalidate;
@end
@implementation STHChooserFocusToken
- (void)invalidate{
 id steal=_windowStealing,lock=_sceneLock;_windowStealing=nil;_sceneLock=nil;
 invalidateFocus(steal);invalidateFocus(lock);
}
- (void)dealloc{[self invalidate];}
@end
static NSObject *createChooserFocusToken(id controller,id scene,id window){
 NSString *reason=@"Stheno application search";
 id lock=focusObject2(controller,@"lockFocusToSpringBoardWindowScene:forReason:",scene,reason);
 if(!focusInvalidatable(lock))return nil;
 id steal=focusObject2(controller,@"requestFocusStealingForSpringBoardWindow:forReason:",window,reason);
 if(!focusInvalidatable(steal)){invalidateFocus(lock);return nil;}
 STHChooserFocusToken *token=[STHChooserFocusToken new];token.sceneLock=lock;token.windowStealing=steal;
 return token;
}
