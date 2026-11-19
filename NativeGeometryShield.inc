// Called only on instances explicitly selected for the active three-app
// composer. Frame setters also need neutral transforms: UIKit defines frame
// assignment under a nonidentity transform through center/bounds conversion.
static void runNeutralGeometry(UIView *view,dispatch_block_t native){
 if(neutralLayoutDepth||!active||(![layoutAncestors containsObject:view]&&![adjustments objectForKey:view])){native();return;}
 neutralLayoutDepth++;
 NSMutableDictionary<NSValue *,STHCompositeTransform *> *saved=[NSMutableDictionary new];
 NSArray<UIView *> *live=adjustments.keyEnumerator.allObjects;
 for(UIView *part in live){
  if(part!=view&&![part isDescendantOfView:view])continue;
  STHCompositeTransform *state=[adjustments objectForKey:part];
  if(state&&CGAffineTransformEqualToTransform(part.transform,state.applied)){
   saved[[NSValue valueWithNonretainedObject:part]]=state;
   [UIView performWithoutAnimation:^{part.transform=state.original;}];
  }
 }
 @try{native();}@finally{
  for(UIView *part in live){
   STHCompositeTransform *state=saved[[NSValue valueWithNonretainedObject:part]];
   if(!state||!active||[adjustments objectForKey:part]!=state)continue;
   if(CGAffineTransformEqualToTransform(part.transform,state.original))
    [UIView performWithoutAnimation:^{part.transform=state.applied;}];
   else [adjustments removeObjectForKey:part];
  }
  neutralLayoutDepth--;
 }
}
static void installShieldClass(Class cls){
 if(!patchedLayoutClasses)patchedLayoutClasses=[NSMutableSet new];
 NSValue *key=[NSValue valueWithPointer:(__bridge const void *)cls];
 if([patchedLayoutClasses containsObject:key])return;
 SEL selectors[]={@selector(layoutSubviews),@selector(setFrame:),@selector(setBounds:),@selector(setCenter:)};
 for(int i=0;i<4;i++){
  SEL selector=selectors[i];Method m=class_getInstanceMethod(cls,selector);if(!m)continue;
  IMP old=method_getImplementation(m),replacement=NULL;
  if(i==0){
   void(*call)(id,SEL)=(void *)old;
   replacement=imp_implementationWithBlock(^(UIView *v){runNeutralGeometry(v,^{call(v,selector);});});
  }else if(i==3){
   void(*call)(id,SEL,CGPoint)=(void *)old;
   replacement=imp_implementationWithBlock(^(UIView *v,CGPoint p){runNeutralGeometry(v,^{call(v,selector,p);});});
  }else{
   void(*call)(id,SEL,CGRect)=(void *)old;
   replacement=imp_implementationWithBlock(^(UIView *v,CGRect r){runNeutralGeometry(v,^{call(v,selector,r);});});
  }
  if(!class_addMethod(cls,selector,replacement,method_getTypeEncoding(m)))
   class_replaceMethod(cls,selector,replacement,method_getTypeEncoding(m));
 }
 [patchedLayoutClasses addObject:key];
}
static void installNeutralLayout(UIView *root){
 if(!layoutAncestors)layoutAncestors=[NSHashTable weakObjectsHashTable];
 [layoutAncestors removeAllObjects];
 for(UIView *v=root;v&&v!=root.window;v=v.superview){
  if(v!=root&&v!=root.superview&&v!=root.superview.superview)break;
  [layoutAncestors addObject:v];installShieldClass(object_getClass(v));
 }
}
static void protectAdditionalPart(UIView *part){
 [layoutAncestors addObject:part];installShieldClass(object_getClass(part));
 // A sibling toolbar can lay itself out independently of its common owner.
 if(part.superview&&part.superview!=part.window){
  [layoutAncestors addObject:part.superview];installShieldClass(object_getClass(part.superview));
 }
}
