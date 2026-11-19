// The selected composer must contain the editable field AND its companion
// controls. A wide20pt text wrapper is not a complete reply assembly.
static __weak UIView *editingField;
static NSHashTable<UIView *> *layoutAncestors;
static NSMutableSet<NSValue *> *patchedLayoutClasses;
static __thread unsigned neutralLayoutDepth;
static STHResidualHistory residualHistory;
static BOOL namedPanel(UIView *v){
 NSString *n=NSStringFromClass(v.class).lowercaseString;
 return [n containsString:@"toolbar"]||[n containsString:@"emoji"]||[n containsString:@"emoticon"]||
        [n containsString:@"emotion"]||[n containsString:@"inputaccessory"];
}
static void peerMetrics(UIView *view,UIView *field,UIWindowScene *scene,int depth,int *budget,unsigned *count,double *bottom){
 if(!shown(view)||depth>6||--*budget<0||view==field||[view isDescendantOfView:field])return;
 BOOL control=[view isKindOfClass:UIControl.class]||view.gestureRecognizers.count||namedPanel(view);
 if(control&&![view isKindOfClass:UIScrollView.class]){
  CGRect r=[view convertRect:view.bounds toCoordinateSpace:scene.coordinateSpace];
  if(r.size.width>=6&&r.size.height>=6&&r.size.height<=240){(*count)++;*bottom=fmax(*bottom,CGRectGetMaxY(r));}
 }
 for(UIView *child in view.subviews){if(*budget<=0)break;peerMetrics(child,field,scene,depth+1,budget,count,bottom);}
}
static BOOL sharedComposerBranch(UIView *root,UIView *row){
 UIView *ancestor=root.superview;
 for(int level=0;ancestor&&ancestor!=root.window&&level<6;level++,ancestor=ancestor.superview)
  if([row isDescendantOfView:ancestor])return YES;
 return NO;
}
static UIView *composerOwner(UIView *field,UIWindow *window,UIWindowScene *scene){
 UIView *root=nil;unsigned rootPeers=0;CGRect text=baseline(field,scene.coordinateSpace);
 for(UIView *v=field;v&&v!=window;v=v.superview){
  CGRect r=baseline(v,scene.coordinateSpace);double sh=scene.coordinateSpace.bounds.size.height;
  if(r.size.height>fmin(240,sh*.34))break;
  if(!STHComposerOwner(r.size.width,r.size.height,scene.coordinateSpace.bounds.size.width,sh,
      [v isKindOfClass:UIScrollView.class],editing(v)))continue;
  unsigned peers=0;double bottom=-CGFLOAT_MAX;int budget=600;peerMetrics(v,field,scene,0,&budget,&peers,&bottom);
  if(!root){root=v;rootPeers=peers;continue;}
  CGRect small=baseline(root,scene.coordinateSpace);
  if(STHExpandOwner(rr(small),rr(r),rr(text),sh,bottom,peers)||
    (rootPeers==0&&peers>0&&r.size.height<=small.size.height+100)) {root=v;rootPeers=peers;}
 }
 return root;
}
static void installNeutralLayout(UIView *root){
 // Let AutoLayout see original child transforms while it recomputes frames;
 // only reapply our temporary offsets AFTER native layout. This prevents the
 // Coolapk17,34,51... feedback observed despite unchanged measured controls.
 if(!layoutAncestors)layoutAncestors=[NSHashTable weakObjectsHashTable];
 [layoutAncestors removeAllObjects];
 if(!patchedLayoutClasses)patchedLayoutClasses=[NSMutableSet new];
 for(UIView *v=root;v&&v!=root.window;v=v.superview){
  if(v!=root&&v!=root.superview&&v!=root.superview.superview)break;
  [layoutAncestors addObject:v];Class cls=object_getClass(v);
  NSValue *key=[NSValue valueWithPointer:(__bridge const void *)cls];
  if([patchedLayoutClasses containsObject:key])continue;
  SEL selector=@selector(layoutSubviews);Method method=class_getInstanceMethod(cls,selector);if(!method)continue;
  void(*native)(id,SEL)=(void *)method_getImplementation(method);
  IMP replacement=imp_implementationWithBlock(^(UIView *view){
   if(neutralLayoutDepth||![layoutAncestors containsObject:view]){native(view,selector);return;}
   neutralLayoutDepth++;
   NSMutableDictionary<NSValue *,STHCompositeTransform *> *restore=[NSMutableDictionary new];
   NSArray<UIView *> *live=adjustments.keyEnumerator.allObjects;
   for(UIView *part in live){
    if(part!=view&&![part isDescendantOfView:view])continue;
    STHCompositeTransform *state=[adjustments objectForKey:part];
    if(state&&CGAffineTransformEqualToTransform(part.transform,state.applied)){
     restore[[NSValue valueWithNonretainedObject:part]]=state;
     [UIView performWithoutAnimation:^{part.transform=state.original;}];
    }
   }
   @try{native(view,selector);}@finally{
    for(UIView *part in live){
     STHCompositeTransform *state=restore[[NSValue valueWithNonretainedObject:part]];if(!state)continue;
     if(CGAffineTransformEqualToTransform(part.transform,state.original))
      [UIView performWithoutAnimation:^{part.transform=state.applied;}];
     else [adjustments removeObjectForKey:part]; // independent app transform wins
    }
    neutralLayoutDepth--;
   }
  });
  // Add a class-local method if inherited, never replace a shared superclass
  // implementation merely because this instance happens to inherit it.
  if(!class_addMethod(cls,selector,replacement,method_getTypeEncoding(method)))
   class_replaceMethod(cls,selector,replacement,method_getTypeEncoding(method));
  [patchedLayoutClasses addObject:key];
 }
}
