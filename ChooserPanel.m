#import "ChooserPanel.h"
#import <objc/message.h>
#import "Chooser.h"
extern UIImage *STHAppChooserIcon(CGFloat);
@interface STHChooserPanel()<UITableViewDataSource,UITableViewDelegate,UITextFieldDelegate>
@property(nonatomic,strong) UIWindow *panelWindow;
@property(nonatomic,weak) UIWindow *previousKey;
@property(nonatomic,strong) UIControl *backdrop;
@property(nonatomic,strong) UIVisualEffectView *card;
@property(nonatomic,strong) UITableView *table;
@property(nonatomic,strong) UITextField *search;
@property(nonatomic,strong) UILabel *empty;
@property(nonatomic,strong) UILabel *subtitle;
@property(nonatomic,copy) NSArray<NSDictionary *> *visible;
@property(nonatomic) CGRect keyboard;
@property(nonatomic) CGPoint origin;
@property(nonatomic) BOOL closing,finished;
@property(nonatomic,copy) NSString *pendingIdentifier;
@end
@implementation STHChooserPanel
- (void)loadView{
 self.view=[[UIView alloc] initWithFrame:UIScreen.mainScreen.bounds];self.view.backgroundColor=UIColor.clearColor;
 self.backdrop=[UIControl new];self.backdrop.backgroundColor=[UIColor colorWithWhite:0 alpha:.18];[self.backdrop addTarget:self action:@selector(cancel) forControlEvents:UIControlEventTouchUpInside];[self.view addSubview:self.backdrop];
 self.card=[[UIVisualEffectView alloc] initWithEffect:[UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemMaterial]];
 self.card.layer.cornerRadius=26;self.card.clipsToBounds=YES;[self.view addSubview:self.card];
 UIImageView *mark=[[UIImageView alloc] initWithImage:STHAppChooserIcon(UIScreen.mainScreen.scale)];mark.tag=11;mark.layer.cornerRadius=8;mark.clipsToBounds=YES;[self.card.contentView addSubview:mark];
 UILabel *title=[UILabel new];title.text=@"打开应用";title.font=[UIFont systemFontOfSize:21 weight:UIFontWeightBold];title.textColor=UIColor.labelColor;title.tag=12;[self.card.contentView addSubview:title];
 self.subtitle=[UILabel new];self.subtitle.font=[UIFont systemFontOfSize:12];self.subtitle.textColor=UIColor.secondaryLabelColor;self.subtitle.text=self.items?@"仅显示未加入圆盘的应用":@"应用目录暂未就绪，请稍后重试";[self.card.contentView addSubview:self.subtitle];
 UIButton *close=[UIButton buttonWithType:UIButtonTypeSystem];[close setImage:[UIImage systemImageNamed:@"xmark.circle.fill"] forState:UIControlStateNormal];close.tintColor=UIColor.tertiaryLabelColor;close.tag=13;close.accessibilityLabel=@"关闭应用选择器";[close addTarget:self action:@selector(cancel) forControlEvents:UIControlEventTouchUpInside];[self.card.contentView addSubview:close];
 UIView *searchBox=[UIView new];searchBox.backgroundColor=UIColor.tertiarySystemFillColor;searchBox.layer.cornerRadius=12;searchBox.tag=14;[self.card.contentView addSubview:searchBox];
 UIImageView *magnifier=[[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"magnifyingglass"]];magnifier.tintColor=UIColor.secondaryLabelColor;magnifier.frame=CGRectMake(12,12,18,18);[searchBox addSubview:magnifier];
 self.search=[UITextField new];self.search.placeholder=@"搜索应用";self.search.font=[UIFont systemFontOfSize:16];self.search.returnKeyType=UIReturnKeyDone;self.search.clearButtonMode=UITextFieldViewModeWhileEditing;self.search.autocorrectionType=UITextAutocorrectionTypeNo;self.search.autocapitalizationType=UITextAutocapitalizationTypeNone;self.search.delegate=self;self.search.accessibilityLabel=@"搜索未加入圆盘的应用";[self.search addTarget:self action:@selector(filter) forControlEvents:UIControlEventEditingChanged];[searchBox addSubview:self.search];
 self.table=[[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];self.table.backgroundColor=UIColor.clearColor;self.table.rowHeight=62;self.table.dataSource=self;self.table.delegate=self;self.table.separatorInset=UIEdgeInsetsMake(0,66,0,16);self.table.keyboardDismissMode=UIScrollViewKeyboardDismissModeOnDrag;[self.card.contentView addSubview:self.table];
 self.empty=[UILabel new];self.empty.textColor=UIColor.secondaryLabelColor;self.empty.font=[UIFont systemFontOfSize:15];self.empty.textAlignment=NSTextAlignmentCenter;self.table.backgroundView=self.empty;
 [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(keyboardChanged:) name:UIKeyboardWillChangeFrameNotification object:nil];
 [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(keyboardChanged:) name:UIKeyboardWillHideNotification object:nil];
 [self filter];
}
- (void)viewDidLayoutSubviews{
 [super viewDidLayoutSubviews];self.backdrop.frame=self.view.bounds;
 CGRect bounds=self.view.bounds;UIEdgeInsets safe=self.view.safeAreaInsets;
 CGRect intersection=CGRectIntersection(bounds,self.keyboard);
 CGFloat bottom=CGRectGetHeight(bounds)-safe.bottom-18;
 if(!CGRectIsNull(intersection)&&!CGRectIsEmpty(intersection)&&CGRectGetWidth(intersection)>.6*CGRectGetWidth(bounds)&&CGRectGetMaxY(intersection)>=CGRectGetMaxY(bounds)-20)bottom=MIN(bottom,CGRectGetMinY(intersection)-12);
 CGFloat top=safe.top+18,available=MAX(0,bottom-top),width=MIN(390,CGRectGetWidth(bounds)-32);
 CGFloat height=MIN(560,MIN(available,MAX(240,CGRectGetHeight(bounds)*.62)));
 self.card.bounds=CGRectMake(0,0,width,height);self.card.center=CGPointMake(CGRectGetMidX(bounds),top+available*.5);
 UIView *content=self.card.contentView;BOOL compact=height<230,tiny=height<180;
 [content viewWithTag:11].hidden=tiny;[content viewWithTag:12].hidden=tiny;self.subtitle.hidden=compact;
 [content viewWithTag:11].frame=CGRectMake(20,20,32,32);
 [content viewWithTag:12].frame=CGRectMake(64,17,width-120,27);
 self.subtitle.frame=CGRectMake(20,60,width-40,18);
 [content viewWithTag:13].frame=CGRectMake(width-52,14,38,38);
 CGFloat searchY=tiny?14:(compact?60:91),searchWidth=tiny?width-76:width-32;
 [content viewWithTag:14].frame=CGRectMake(16,searchY,searchWidth,42);
 self.search.frame=CGRectMake(39,0,MAX(1,searchWidth-49),42);
 CGFloat tableY=searchY+54;self.table.frame=CGRectMake(0,tableY,width,MAX(0,height-tableY-8));
}
- (void)filter{
 NSString *query=[self.search.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
 NSMutableArray *rows=[NSMutableArray array];
 for(NSDictionary *row in self.items){
  if(!query.length||[row[@"name"] localizedCaseInsensitiveContainsString:query]||[row[@"identifier"] localizedCaseInsensitiveContainsString:query])[rows addObject:row];
 }
 self.visible=[rows sortedArrayUsingComparator:^NSComparisonResult(NSDictionary *a,NSDictionary *b){return [a[@"name"] localizedStandardCompare:b[@"name"]];}];
 self.empty.text=self.visible.count?@"":(self.items?(query.length?@"没有匹配的应用":@"所有应用都已加入圆盘"):@"暂时无法读取应用列表");
 [self.table reloadData];
}
- (NSInteger)tableView:(UITableView *)table numberOfRowsInSection:(NSInteger)section{(void)table;(void)section;return self.visible.count;}
- (UITableViewCell *)tableView:(UITableView *)table cellForRowAtIndexPath:(NSIndexPath *)index{
 UITableViewCell *cell=[table dequeueReusableCellWithIdentifier:@"app"];
 if(!cell){
  cell=[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"app"];cell.backgroundColor=UIColor.clearColor;
  UIImageView *image=[UIImageView new];image.tag=100;image.frame=CGRectMake(18,11,40,40);image.contentMode=UIViewContentModeScaleAspectFit;image.layer.cornerRadius=9;image.clipsToBounds=YES;[cell.contentView addSubview:image];
  UILabel *name=[UILabel new];name.tag=101;name.font=[UIFont systemFontOfSize:16 weight:UIFontWeightMedium];name.textColor=UIColor.labelColor;name.frame=CGRectMake(72,0,240,62);name.autoresizingMask=UIViewAutoresizingFlexibleWidth;[cell.contentView addSubview:name];
 }
 NSDictionary *row=self.visible[index.row];((UILabel *)[cell.contentView viewWithTag:101]).text=row[@"name"];
 SEL sel=NSSelectorFromString(@"_applicationIconImageForBundleIdentifier:format:scale:");UIImage *icon=nil;
 if([UIImage respondsToSelector:sel])icon=((id(*)(id,SEL,NSString *,int,CGFloat))objc_msgSend)(UIImage.class,sel,row[@"identifier"],0,UIScreen.mainScreen.scale);
 ((UIImageView *)[cell.contentView viewWithTag:100]).image=icon?:[UIImage systemImageNamed:@"app"];
 cell.accessibilityLabel=row[@"name"];cell.accessibilityHint=@"以浮窗打开，不加入圆盘";return cell;
}
- (void)tableView:(UITableView *)table didSelectRowAtIndexPath:(NSIndexPath *)index{
 [table deselectRowAtIndexPath:index animated:YES];if(self.closing)return;
 [self dismissChoosing:self.visible[index.row][@"identifier"] animated:YES];
}
- (BOOL)textFieldShouldReturn:(UITextField *)textField{[textField resignFirstResponder];return YES;}
- (void)keyboardChanged:(NSNotification *)note{
 if(self.closing)return;
 self.keyboard=[note.name isEqualToString:UIKeyboardWillHideNotification]?CGRectZero:[self.view convertRect:[note.userInfo[UIKeyboardFrameEndUserInfoKey] CGRectValue] fromView:nil];
 if(CGRectGetMinY(self.keyboard)>=CGRectGetHeight(self.view.bounds))self.keyboard=CGRectZero;
 NSTimeInterval duration=[note.userInfo[UIKeyboardAnimationDurationUserInfoKey] doubleValue];
 UIViewAnimationOptions options=((UIViewAnimationOptions)[note.userInfo[UIKeyboardAnimationCurveUserInfoKey] unsignedIntegerValue]<<16)|UIViewAnimationOptionBeginFromCurrentState;
 [UIView animateWithDuration:duration delay:0 options:options animations:^{[self.view setNeedsLayout];[self.view layoutIfNeeded];} completion:nil];
}
- (void)showFromPoint:(CGPoint)point inScene:(UIWindowScene *)scene aboveLevel:(CGFloat)level{
 self.origin=point;
 for(UIWindow *window in scene.windows)if(window.isKeyWindow){self.previousKey=window;break;}
 self.panelWindow=scene?[[UIWindow alloc] initWithWindowScene:scene]:[[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
 self.panelWindow.frame=UIScreen.mainScreen.bounds;self.panelWindow.windowLevel=MIN(UIWindowLevelAlert-1,MAX(UIWindowLevelNormal+2,level+1));self.panelWindow.rootViewController=self;
 [self.panelWindow makeKeyAndVisible];[self.view layoutIfNeeded];
 self.backdrop.alpha=0;self.card.alpha=0;
 if(!UIAccessibilityIsReduceMotionEnabled()){
  CGPoint origin=[self.view convertPoint:point fromCoordinateSpace:UIScreen.mainScreen.coordinateSpace];
  self.card.transform=CGAffineTransformConcat(CGAffineTransformMakeScale(.12,.12),CGAffineTransformMakeTranslation(origin.x-self.card.center.x,origin.y-self.card.center.y));
 }
 [UIView animateWithDuration:UIAccessibilityIsReduceMotionEnabled()?.16:.36 delay:0 usingSpringWithDamping:.88 initialSpringVelocity:0 options:UIViewAnimationOptionBeginFromCurrentState|UIViewAnimationOptionAllowUserInteraction animations:^{self.backdrop.alpha=1;self.card.alpha=1;self.card.transform=CGAffineTransformIdentity;} completion:nil];
 UIAccessibilityPostNotification(UIAccessibilityScreenChangedNotification,self.search);
}
- (void)cancel{[self dismissChoosing:nil animated:YES];}
- (void)finishDismissal{
 if(self.finished)return;self.finished=YES;
 BOOL restore=self.panelWindow.isKeyWindow;
 self.panelWindow.hidden=YES;
 if(restore&&self.previousKey&&!self.previousKey.hidden)[self.previousKey makeKeyWindow];
 self.panelWindow.rootViewController=nil;self.panelWindow=nil;
 void(^callback)(NSString *)=self.closed;self.closed=nil;
 NSString *identifier=self.pendingIdentifier;self.pendingIdentifier=nil;
 if(callback)callback(identifier);
}
- (void)dismissChoosing:(NSString *)identifier animated:(BOOL)animated{
 if(self.finished)return;
 if(self.closing){
  if(!animated){self.pendingIdentifier=nil;[self.view endEditing:YES];[self.card.layer removeAllAnimations];[self.backdrop.layer removeAllAnimations];[self finishDismissal];}
  return;
 }
 self.closing=YES;self.pendingIdentifier=identifier;[self.view endEditing:YES];
 if(!animated){[self finishDismissal];return;}
 [UIView animateWithDuration:.18 delay:0 options:UIViewAnimationOptionBeginFromCurrentState|UIViewAnimationOptionCurveEaseIn animations:^{self.backdrop.alpha=0;self.card.alpha=0;if(!UIAccessibilityIsReduceMotionEnabled())self.card.transform=CGAffineTransformMakeScale(.92,.92);} completion:^(BOOL done){(void)done;[self finishDismissal];}];
}
- (void)dealloc{[[NSNotificationCenter defaultCenter] removeObserver:self];}
@end
