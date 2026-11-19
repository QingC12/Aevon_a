// Bounded inspection of the current composer's descendants and nearby rows.
// Never unhides an app view, creates an emoji row or reads label/input text.
static NSMapTable<UIView *,NSNumber *> *releasedClips;
static CFTimeInterval lastProbe;
static unsigned probeIndex;
static void restoreCompositeClips(void){
 for(UIView *v in releasedClips.keyEnumerator.allObjects)
  if(!v.clipsToBounds)v.clipsToBounds=[[releasedClips objectForKey:v] boolValue];
 releasedClips=nil;
}
static BOOL canReveal(UIView *row,UIView *root,UIWindowScene *scene){
 // Every clipping ancestor to the root must be a bounded input-only surface.
 for(UIView *a=row.superview;a;a=a.superview){
  if(a.clipsToBounds){
   CGRect r=[a convertRect:a.bounds toCoordinateSpace:scene.coordinateSpace];
   if(!STHCanReleaseComposerClip(r.size.height,scene.coordinateSpace.bounds.size.height,a==row.window,a.layer.mask!=nil))return NO;
  }
  if(a==root)return YES;
 }
 return NO;
}
static void revealBoundedRow(UIView *row,UIView *root){
 if(!releasedClips)releasedClips=[NSMapTable weakToStrongObjectsMapTable];
 for(UIView *a=row.superview;a;a=a.superview){
  if(a.clipsToBounds){
   if(![releasedClips objectForKey:a])[releasedClips setObject:@YES forKey:a];
   a.clipsToBounds=NO;
  }
  if(a==root)break;
 }
}
static void inspectRows(UIView *v,UIView *root,UIWindowScene *scene,CGRect *group,
 int depth,int *budget,NSMutableArray<UIView *> *probes){
 if(!v||depth>8||--*budget<0||!v.window)return;
 if(v!=root&&editingField&&v!=editingField&&![v isDescendantOfView:editingField]){
  CGRect raw=baseline(v,scene.coordinateSpace);unsigned controls=0;double bottom=-CGFLOAT_MAX;int b=220;
  peerMetrics(v,editingField,scene,0,&b,&controls,&bottom);
  BOOL fieldRelated=STHCompositeRow(rr(*group),rr(raw),rr(baseline(editingField,scene.coordinateSpace)),
      scene.coordinateSpace.bounds.size.height,YES,controls,namedPanel(v));
  BOOL geometricallyNear=raw.size.width>=group->size.width*.55&&raw.size.height>=8&&raw.size.height<=240&&
    raw.origin.y>=CGRectGetMinY(baseline(editingField,scene.coordinateSpace))-2&&
    raw.origin.y<=CGRectGetMaxY(*group)+80;
  if(geometricallyNear&&(controls||namedPanel(v)||[v isKindOfClass:UIScrollView.class]))[probes addObject:v];
  if(fieldRelated&&shown(v)){
   CGRect clipped=visibleRect(v,scene,YES);
   BOOL missing=CGRectIsNull(clipped)||CGRectGetMaxY(clipped)<CGRectGetMaxY(raw)-.75;
   if(missing&&canReveal(v,root,scene))revealBoundedRow(v,root);
   CGRect now=visibleRect(v,scene,YES);
   if(!CGRectIsNull(now)&&CGRectGetMaxY(now)>=CGRectGetMaxY(raw)-.75){
    *group=CGRectUnion(*group,raw);protrudingCount++;
   }
  }
 }
 // Hidden branch is recorded, not revealed or treated as displayed controls.
 if(v.hidden||v.alpha<.01)return;
 for(UIView *c in v.subviews){if(*budget<=0)break;inspectRows(c,root,scene,group,depth+1,budget,probes);}
}
static void scanInternalRows(UIView *root,UIWindowScene *scene,CGRect *group){
 NSMutableArray<UIView *> *probes=[NSMutableArray arrayWithObject:root];
 for(int pass=0;pass<3;pass++){int budget=700;inspectRows(root,root,scene,group,0,&budget,probes);}
 if(probes.count&&CACurrentMediaTime()-lastProbe>.18){
  lastProbe=CACurrentMediaTime();UIView *v=probes[(probeIndex++)%probes.count];
  CGRect raw=[v convertRect:v.bounds toCoordinateSpace:scene.coordinateSpace];
  CGRect visible=visibleRect(v,scene,NO);
  unsigned flags=(v.hidden?1:0)|(v.alpha<.01?2:0)|
   ((CGRectIsNull(visible)||CGRectGetMaxY(visible)<CGRectGetMaxY(raw)-.75)?4:0)|
   (namedPanel(v)?8:0)|([v isKindOfClass:UIScrollView.class]?16:0)|
   (releasedClips.count?32:0);
  STHReportLayoutProbe(NSBundle.mainBundle.bundleIdentifier,NSStringFromClass(v.class),raw,flags);
 }
}
