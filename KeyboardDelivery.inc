// Included by KeyboardCoordinates.m so preparation happens at DELIVERY, not
// independently during each app observer's userInfo read.
static void (*centerPost)(id,SEL,NSNotification *);
static void (*centerPostName)(id,SEL,NSString *,id,NSDictionary *);
static NSMutableDictionary<NSString *,NSNotification *> *heldNotes;
static NSMutableDictionary<NSString *,NSNumber *> *heldOrder;
static NSUInteger holdOrder,holdGeneration;
static __thread BOOL delivering;
static BOOL heldSession,awaitingDidHide;
static BOOL keyboardEvent(NSString *name){return [name hasPrefix:@"UIKeyboard"]&&
 ([name isEqualToString:UIKeyboardWillShowNotification]||[name isEqualToString:UIKeyboardDidShowNotification]||
  [name isEqualToString:UIKeyboardWillChangeFrameNotification]||[name isEqualToString:UIKeyboardDidChangeFrameNotification]||
  [name isEqualToString:UIKeyboardWillHideNotification]||[name isEqualToString:UIKeyboardDidHideNotification]);}
static BOOL hideEvent(NSString *n){return [n isEqualToString:UIKeyboardWillHideNotification]||[n isEqualToString:UIKeyboardDidHideNotification];}
static void deliverFrozen(NSNotificationCenter *center,NSNotification *note){
 NSDictionary *info=normalizedInfo(note,@selector(userInfo));
 // One immutable dictionary for every callback during this post. Original
 // KeyboardFix's postName rewrite is bypassed only for an active hosted app.
 NSNotification *frozen=[NSNotification notificationWithName:note.name object:note.object userInfo:info];
 objc_setAssociatedObject(frozen,&normalizedKey,@YES,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
 BOOL was=delivering;delivering=YES;
 @try{centerPost(center,@selector(postNotification:),frozen);}@finally{delivering=was;}
}
static void discardHeld(void){heldNotes=nil;heldOrder=nil;holdGeneration++;}
static void flushHeld(BOOL canonicalDelivery){
 NSDictionary *notes=heldNotes,*orders=heldOrder;discardHeld();
 NSArray *names=[notes.allKeys sortedArrayUsingComparator:^NSComparisonResult(NSString *a,NSString *b){return [orders[a] compare:orders[b]];}];
 for(NSString *name in names){NSNotification *note=notes[name];
  if(canonicalDelivery)deliverFrozen(NSNotificationCenter.defaultCenter,note);
  else {BOOL was=delivering;delivering=YES;@try{centerPost(NSNotificationCenter.defaultCenter,@selector(postNotification:),note);}@finally{delivering=was;}}
 }
}
static void queueHeld(NSNotification *note){
 if(!heldNotes){heldNotes=[NSMutableDictionary new];heldOrder=[NSMutableDictionary new];}
 if(!heldOrder[note.name])heldOrder[note.name]=@(++holdOrder);
 heldNotes[note.name]=note;heldSession=YES;
 NSUInteger generation=++holdGeneration;
 // Failure escape: original behavior is restored if host never commits. No
 // permanently swallowed notifications if an app/keyboard cannot be matched.
 dispatch_after(dispatch_time(DISPATCH_TIME_NOW,650*NSEC_PER_MSEC),dispatch_get_main_queue(),^{
  if(holdGeneration!=generation||!heldNotes.count)return;
  int status=STHLayoutStatus(NSBundle.mainBundle.bundleIdentifier);
  STHWriteLayoutLog([NSString stringWithFormat:@"deferred-keyboard timeout status=%d count=%lu",status,(unsigned long)heldNotes.count]);
  flushHeld(status==1);
 });
}
static BOOL interceptNotification(NSNotificationCenter *center,NSNotification *note){
 if(center!=NSNotificationCenter.defaultCenter||delivering||![NSThread isMainThread]||!keyboardEvent(note.name)||objc_getAssociatedObject(note,&normalizedKey))return NO;
 int status=STHLayoutStatus(NSBundle.mainBundle.bundleIdentifier);
 BOOL hide=hideEvent(note.name);
 if(hide){
  if(!status&&!heldSession&&!session.visible&&!session.hasSceneFrame&&!awaitingDidHide)return NO;
  awaitingDidHide=[note.name isEqualToString:UIKeyboardWillHideNotification];
  discardHeld();heldSession=NO;deliverFrozen(center,note);return YES;
 }
 awaitingDidHide=NO;
 if(status==2){queueHeld(note);return YES;}
 if(status==1){
  if(heldNotes.count)flushHeld(YES);
  heldSession=YES;deliverFrozen(center,note);return YES;
 }
 return NO;
}
static void stablePost(id center,SEL selector,NSNotification *note){
 if(!interceptNotification(center,note))centerPost(center,selector,note);
}
static void stablePostName(id center,SEL selector,NSString *name,id object,NSDictionary *info){
 if(!delivering&&[NSThread isMainThread]&&keyboardEvent(name)){
  NSNotification *note=[NSNotification notificationWithName:name object:object userInfo:info];
  if(interceptNotification(center,note))return;
 }
 centerPostName(center,selector,name,object,info);
}
static void installDelivery(void){
 Method p=class_getInstanceMethod(NSNotificationCenter.class,@selector(postNotification:));
 Method n=class_getInstanceMethod(NSNotificationCenter.class,@selector(postNotificationName:object:userInfo:));
 if(!p||!n)return;
 centerPost=(void *)method_getImplementation(p);centerPostName=(void *)method_getImplementation(n);
 method_setImplementation(p,(IMP)stablePost);method_setImplementation(n,(IMP)stablePostName);
}
