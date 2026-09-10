/*
 * SearchGlass
 * Liquid Glass renderer adapted from the public Liquid (Gl)ass project:
 * https://github.com/winaviation-tweaks/liquidass
 *
 * Uses the same Liquid (Gl)ass render-server approach:
 * CABackdropLayer + CAFilter + live refraction + specular reflection.
 *
 * GPL-3.0 applies to code derived from Liquid (Gl)ass.
 */

#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/message.h>
#import <objc/runtime.h>

#pragma mark - Liquid Glass constants

static NSString * const kSGFilterType = @"dylv.liquidglass.searchpill";
static NSString * const kSGGroupNamespace = @"dylv.liquidglass";
static NSString * const kSGGroupName = @"SearchGlass";

static Class SGBackdropClass(void) {
    return NSClassFromString(@"CABackdropLayer");
}

static Class SGFilterClass(void) {
    return NSClassFromString(@"CAFilter");
}

static id SGFilterWithType(NSString *type) {
    Class cls = SGFilterClass();
    if (!cls || !type.length) return nil;

    SEL selector = NSSelectorFromString(@"filterWithType:");
    if (![cls respondsToSelector:selector]) return nil;

    return ((id (*)(Class, SEL, NSString *))objc_msgSend)(cls, selector, type);
}

static id SGFilterWithName(NSString *name) {
    Class cls = SGFilterClass();
    if (!cls || !name.length) return nil;

    SEL selector = NSSelectorFromString(@"filterWithName:");
    if (![cls respondsToSelector:selector]) return nil;

    return ((id (*)(Class, SEL, NSString *))objc_msgSend)(cls, selector, name);
}

static void SGSetValue(id object, id value, NSString *key) {
    if (!object || !key.length) return;

    @try {
        [object setValue:value forKey:key];
    } @catch (__unused NSException *exception) {
    }
}

static NSString *SGEffectiveFilterType(UIView *view) {
    NSString *type = kSGFilterType;

    if (@available(iOS 13.0, *)) {
        if (view.traitCollection.userInterfaceStyle == UIUserInterfaceStyleDark)
            type = [type stringByAppendingString:@".dark"];
    }

    return type;
}

#pragma mark - Live Liquid Glass

@interface SGLiveGlassView : UIView
@property(nonatomic, assign) CGFloat cornerRadius;
@property(nonatomic, assign) BOOL liquidFilterAvailable;
- (void)applyLiquidGlass;
@end

@implementation SGLiveGlassView {
    CAGradientLayer *_specular;
    CAGradientLayer *_specularBoost;
    CAShapeLayer *_specularMask;
    CAShapeLayer *_specularBoostMask;
    CALayer *_nativeBlurLayer;
}

+ (Class)layerClass {
    Class backdrop = SGBackdropClass();
    return backdrop ?: [CALayer class];
}

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];

    if (!self) return nil;

    self.backgroundColor = UIColor.clearColor;
    self.opaque = NO;
    self.userInteractionEnabled = NO;

    self.autoresizingMask =
        UIViewAutoresizingFlexibleWidth |
        UIViewAutoresizingFlexibleHeight;

    self.cornerRadius =
        MIN(CGRectGetWidth(frame), CGRectGetHeight(frame)) * 0.5;

    [self setupSpecular];
    [self applyLiquidGlass];

    return self;
}

- (void)setupSpecular {
    /*
     * Same visual concept used by LGLiveBackdropView:
     * a normal specular gradient and a stronger overlay-blended
     * gradient, both clipped to the rounded glass shape.
     */

    _specular = [CAGradientLayer layer];

    _specular.colors = @[
        (id)[UIColor colorWithWhite:1.0 alpha:0.30].CGColor,
        (id)[UIColor clearColor].CGColor,
        (id)[UIColor colorWithWhite:1.0 alpha:0.12].CGColor
    ];

    _specular.locations = @[
        @0.0,
        @0.50,
        @1.0
    ];

    _specularBoost = [CAGradientLayer layer];

    _specularBoost.colors = @[
        (id)[UIColor colorWithWhite:1.0 alpha:0.32].CGColor,
        (id)[UIColor clearColor].CGColor,
        (id)[UIColor colorWithWhite:1.0 alpha:0.16].CGColor
    ];

    _specularBoost.locations = @[
        @0.0,
        @0.50,
        @1.0
    ];

    _specularBoost.compositingFilter = @"overlayBlendMode";

    _specularMask = [CAShapeLayer layer];
    _specularBoostMask = [CAShapeLayer layer];

    _specular.mask = _specularMask;
    _specularBoost.mask = _specularBoostMask;

    [self.layer addSublayer:_specular];
    [self.layer addSublayer:_specularBoost];
}

- (void)layoutSpecular {
    CGRect bounds = self.bounds;
    CGFloat radius = self.cornerRadius;

    [CATransaction begin];
    [CATransaction setDisableActions:YES];

    _specular.frame = bounds;
    _specularBoost.frame = bounds;

    UIBezierPath *path =
        [UIBezierPath bezierPathWithRoundedRect:
            CGRectInset(bounds, 0.35, 0.35)
            cornerRadius:MAX(0.0, radius - 0.35)];

    _specularMask.frame = bounds;
    _specularMask.path = path.CGPath;
    _specularMask.fillColor = UIColor.clearColor.CGColor;
    _specularMask.strokeColor = UIColor.blackColor.CGColor;
    _specularMask.lineWidth = 1.0;

    _specularBoostMask.frame = bounds;
    _specularBoostMask.path = path.CGPath;
    _specularBoostMask.fillColor = UIColor.clearColor.CGColor;
    _specularBoostMask.strokeColor = UIColor.blackColor.CGColor;
    _specularBoostMask.lineWidth = 1.0;

    /*
     * Same default specular angle used by Liquid (Gl)ass.
     */
    CGFloat angle = -M_PI_4;
    CGFloat dx = cos(angle) * 0.5;
    CGFloat dy = sin(angle) * 0.5;

    _specular.startPoint =
        CGPointMake(0.5 + dx, 0.5 + dy);

    _specular.endPoint =
        CGPointMake(0.5 - dx, 0.5 - dy);

    _specularBoost.startPoint = _specular.startPoint;
    _specularBoost.endPoint = _specular.endPoint;

    [CATransaction commit];
}

- (void)applyNativeBlurFallback {
    Class backdropClass = SGBackdropClass();

    if (!backdropClass)
        return;

    id blur = SGFilterWithName(@"gaussianBlur");

    if (!blur)
        return;

    SGSetValue(blur, @2.0, @"inputRadius");
    SGSetValue(blur, @YES, @"inputNormalizeEdges");

    if (!_nativeBlurLayer) {
        _nativeBlurLayer = [backdropClass layer];

        SGSetValue(_nativeBlurLayer,
                   @NO,
                   @"layerUsesCoreImageFilters");

        SGSetValue(_nativeBlurLayer,
                   @YES,
                   @"windowServerAware");

        SGSetValue(_nativeBlurLayer,
                   kSGGroupName,
                   @"groupName");

        SGSetValue(_nativeBlurLayer,
                   kSGGroupNamespace,
                   @"groupNamespace");

        SGSetValue(_nativeBlurLayer,
                   @YES,
                   @"ignoresScreenClip");

        SGSetValue(_nativeBlurLayer,
                   @1.0,
                   @"scale");

        [self.layer insertSublayer:_nativeBlurLayer atIndex:0];
    }

    _nativeBlurLayer.frame = self.bounds;
    _nativeBlurLayer.cornerRadius = self.cornerRadius;
    _nativeBlurLayer.masksToBounds = YES;
    _nativeBlurLayer.filters = @[blur];
}

- (void)applyLiquidGlass {
    Class backdropClass = SGBackdropClass();
    CALayer *layer = self.layer;

    if (!backdropClass ||
        ![layer isKindOfClass:backdropClass]) {

        [self layoutSpecular];
        return;
    }

    @try {
        /*
         * These are the same private render-server properties
         * configured by LGLiveBackdropView in Liquid (Gl)ass.
         */

        SGSetValue(layer,
                   @NO,
                   @"layerUsesCoreImageFilters");

        SGSetValue(layer,
                   @YES,
                   @"windowServerAware");

        SGSetValue(layer,
                   kSGGroupName,
                   @"groupName");

        SGSetValue(layer,
                   kSGGroupNamespace,
                   @"groupNamespace");

        SGSetValue(layer,
                   @YES,
                   @"ignoresScreenClip");

        /*
         * SearchPill in LGHostRegistry:
         *
         * refraction       = 1.6
         * refractiveIndex  = 1.70
         * blur             = 1.0
         * specular         = 1.0
         *
         * The actual Liquid (Gl)ass filter consumes these parameters
         * through its registered filter type.
         */

        SGSetValue(layer, @1.0, @"scale");

        NSString *filterType =
            SGEffectiveFilterType(self);

        id glassFilter =
            SGFilterWithType(filterType);

        /*
         * Some builds register only the base filter name.
         * Try it before falling back to gaussian blur.
         */

        if (!glassFilter &&
            ![filterType isEqualToString:kSGFilterType]) {

            glassFilter =
                SGFilterWithType(kSGFilterType);
        }

        if (glassFilter) {
            layer.filters = @[glassFilter];
            self.liquidFilterAvailable = YES;

            if (_nativeBlurLayer) {
                [_nativeBlurLayer removeFromSuperlayer];
                _nativeBlurLayer = nil;
            }
        } else {
            self.liquidFilterAvailable = NO;
            [self applyNativeBlurFallback];
        }

    } @catch (__unused NSException *exception) {
        self.liquidFilterAvailable = NO;
        [self applyNativeBlurFallback];
    }

    [self layoutSpecular];
}

- (void)setCornerRadius:(CGFloat)cornerRadius {
    _cornerRadius = cornerRadius;

    self.layer.cornerRadius = cornerRadius;
    self.layer.cornerCurve = kCACornerCurveContinuous;
    self.layer.masksToBounds = YES;

    [self layoutSpecular];
    [self applyLiquidGlass];
}

- (void)traitCollectionDidChange:(UITraitCollection *)previousTraitCollection {
    [super traitCollectionDidChange:previousTraitCollection];

    if (@available(iOS 13.0, *)) {
        if (previousTraitCollection.userInterfaceStyle !=
            self.traitCollection.userInterfaceStyle) {

            [self applyLiquidGlass];
        }
    }
}

- (void)layoutSubviews {
    [super layoutSubviews];

    self.layer.cornerRadius = self.cornerRadius;
    self.layer.cornerCurve = kCACornerCurveContinuous;
    self.layer.masksToBounds = YES;

    [self layoutSpecular];

    if (!self.liquidFilterAvailable)
        [self applyNativeBlurFallback];
}

@end

#pragma mark - Search button

@interface SGSearchButton : UIControl
@property(nonatomic, strong) SGLiveGlassView *glassView;
@property(nonatomic, strong) UIImageView *searchIcon;
@property(nonatomic, strong) UILabel *titleLabel;
@property(nonatomic, strong) UIImageView *micIcon;
@end

@implementation SGSearchButton

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];

    if (!self)
        return nil;

    self.backgroundColor = UIColor.clearColor;
    self.opaque = NO;
    self.exclusiveTouch = YES;
    self.userInteractionEnabled = YES;

    [self buildUI];

    [self addTarget:self
             action:@selector(searchPressed:)
   forControlEvents:UIControlEventTouchUpInside];

    [self addTarget:self
             action:@selector(sgTouchDown:)
   forControlEvents:UIControlEventTouchDown |
                    UIControlEventTouchDragEnter];

    [self addTarget:self
             action:@selector(sgTouchUp:)
   forControlEvents:UIControlEventTouchUpInside |
                    UIControlEventTouchCancel |
                    UIControlEventTouchDragExit];

    return self;
}

- (void)buildUI {
    self.glassView =
        [[SGLiveGlassView alloc] initWithFrame:self.bounds];

    /*
     * IMPORTANT:
     * The glass is visual only. It cannot steal touches from
     * the SGSearchButton underneath it.
     */
    self.glassView.userInteractionEnabled = NO;
    self.glassView.cornerRadius = 14.0;

    [self addSubview:self.glassView];

    UIImageSymbolConfiguration *searchConfig =
        [UIImageSymbolConfiguration
            configurationWithPointSize:15.0
            weight:UIImageSymbolWeightRegular];

    UIImage *searchImage =
        [UIImage systemImageNamed:@"magnifyingglass"
                withConfiguration:searchConfig];

    self.searchIcon =
        [[UIImageView alloc] initWithImage:searchImage];

    self.searchIcon.tintColor =
        [UIColor colorWithWhite:0.08 alpha:0.92];

    self.searchIcon.contentMode =
        UIViewContentModeScaleAspectFit;

    self.searchIcon.userInteractionEnabled = NO;

    [self addSubview:self.searchIcon];

    self.titleLabel =
        [[UILabel alloc] initWithFrame:CGRectZero];

    self.titleLabel.text = @"Search";

    self.titleLabel.font =
        [UIFont systemFontOfSize:15.0
                          weight:UIFontWeightRegular];

    self.titleLabel.textColor =
        [UIColor colorWithWhite:0.20 alpha:0.88];

    self.titleLabel.textAlignment =
        NSTextAlignmentLeft;

    self.titleLabel.backgroundColor =
        UIColor.clearColor;

    self.titleLabel.userInteractionEnabled = NO;

    [self addSubview:self.titleLabel];

    UIImageSymbolConfiguration *micConfig =
        [UIImageSymbolConfiguration
            configurationWithPointSize:15.0
            weight:UIImageSymbolWeightRegular];

    UIImage *micImage =
        [UIImage systemImageNamed:@"mic"
                withConfiguration:micConfig];

    self.micIcon =
        [[UIImageView alloc] initWithImage:micImage];

    self.micIcon.tintColor =
        [UIColor colorWithWhite:0.08 alpha:0.92];

    self.micIcon.contentMode =
        UIViewContentModeScaleAspectFit;

    self.micIcon.userInteractionEnabled = NO;

    [self addSubview:self.micIcon];
}

- (void)layoutSubviews {
    [super layoutSubviews];

    CGFloat width =
        CGRectGetWidth(self.bounds);

    CGFloat height =
        CGRectGetHeight(self.bounds);

    self.glassView.frame = self.bounds;
    self.glassView.cornerRadius =
        MIN(14.0, height * 0.5);

    self.searchIcon.frame =
        CGRectMake(11.0,
                   floor((height - 18.0) * 0.5),
                   18.0,
                   18.0);

    self.micIcon.frame =
        CGRectMake(width - 29.0,
                   floor((height - 18.0) * 0.5),
                   18.0,
                   18.0);

    self.titleLabel.frame =
        CGRectMake(37.0,
                   0.0,
                   MAX(0.0, width - 72.0),
                   height);
}

- (void)sgTouchDown:(id)sender {
    [UIView animateWithDuration:0.08
                     animations:^{
        self.transform =
            CGAffineTransformMakeScale(0.985, 0.985);

        self.alpha = 0.88;
    }];
}

- (void)sgTouchUp:(id)sender {
    [UIView animateWithDuration:0.12
                     animations:^{
        self.transform =
            CGAffineTransformIdentity;

        self.alpha = 1.0;
    }];
}

#pragma mark - Search action

- (void)searchPressed:(id)sender {
    UIViewController *vc =
        [self nearestViewController];

    if (!vc)
        return;

    UINavigationController *navigationController =
        vc.navigationController;

    if (navigationController &&
        navigationController.viewControllers.count > 1) {

        [navigationController
            popToRootViewControllerAnimated:YES];
    }

    dispatch_after(
        dispatch_time(DISPATCH_TIME_NOW,
                      (int64_t)(0.30 * NSEC_PER_SEC)),
        dispatch_get_main_queue(),
        ^{
            UIViewController *root =
                navigationController
                ? navigationController.viewControllers.firstObject
                : vc;

            if (!root)
                return;

            UISearchBar *searchBar =
                [self findSearchBarInView:root.view];

            if (searchBar) {
                UIScrollView *scroll =
                    [self findScrollViewContainingView:searchBar];

                if (scroll) {
                    CGRect rect =
                        [searchBar convertRect:searchBar.bounds
                                        toView:scroll];

                    [scroll
                        scrollRectToVisible:rect
                        animated:YES];
                }

                [searchBar becomeFirstResponder];
                return;
            }

            dispatch_after(
                dispatch_time(DISPATCH_TIME_NOW,
                              (int64_t)(0.25 * NSEC_PER_SEC)),
                dispatch_get_main_queue(),
                ^{
                    UISearchBar *retry =
                        [self findSearchBarInView:root.view];

                    if (retry)
                        [retry becomeFirstResponder];
                });
        });
}

#pragma mark - View controller finder

- (UIViewController *)nearestViewController {
    UIResponder *responder = self;

    while (responder) {
        responder = [responder nextResponder];

        if ([responder
             isKindOfClass:[UIViewController class]]) {

            return (UIViewController *)responder;
        }
    }

    return nil;
}

#pragma mark - SearchBar finder

- (UISearchBar *)findSearchBarInView:(UIView *)view {
    if (!view)
        return nil;

    if ([view isKindOfClass:[UISearchBar class]])
        return (UISearchBar *)view;

    for (UIView *subview in view.subviews) {
        UISearchBar *result =
            [self findSearchBarInView:subview];

        if (result)
            return result;
    }

    return nil;
}

#pragma mark - ScrollView finder

- (UIScrollView *)findScrollViewContainingView:(UIView *)target {
    UIView *view = target.superview;

    while (view) {
        if ([view isKindOfClass:[UIScrollView class]])
            return (UIScrollView *)view;

        view = view.superview;
    }

    return nil;
}

@end

#pragma mark - Settings installation

static const NSInteger kSGSearchGlassTag = 0x53474153;

static BOOL SGIsMainSettingsController(
    UIViewController *controller
) {
    if (!controller)
        return NO;

    Class psClass =
        NSClassFromString(@"PSListController");

    if (!psClass ||
        ![controller isKindOfClass:psClass]) {

        return NO;
    }

    NSString *className =
        NSStringFromClass(controller.class);

    if ([className containsString:@"Search"])
        return NO;

    return YES;
}

static void SGInstallSearchGlass(
    UIViewController *controller
) {
    if (!controller.view ||
        !SGIsMainSettingsController(controller)) {

        return;
    }

    UIView *view = controller.view;

    SGSearchButton *existing =
        (SGSearchButton *)[view viewWithTag:kSGSearchGlassTag];

    if (existing) {
        [view bringSubviewToFront:existing];
        return;
    }

    /*
     * Smaller than the old 316 x 44 version.
     */
    CGFloat width =
        MIN(316.0,
            MAX(260.0,
                CGRectGetWidth(view.bounds) - 32.0));

    CGFloat height = 40.0;

    CGFloat x =
        (CGRectGetWidth(view.bounds) - width) * 0.5;

    CGFloat y =
        CGRectGetHeight(view.bounds) -
        view.safeAreaInsets.bottom -
        height -
        18.0;

    if (y < 20.0)
        y = 20.0;

    SGSearchButton *button =
        [[SGSearchButton alloc]
            initWithFrame:CGRectMake(x,
                                     y,
                                     width,
                                     height)];

    button.tag = kSGSearchGlassTag;

    button.autoresizingMask =
        UIViewAutoresizingFlexibleLeftMargin |
        UIViewAutoresizingFlexibleRightMargin |
        UIViewAutoresizingFlexibleTopMargin;

    [view addSubview:button];
    [view bringSubviewToFront:button];
}

#pragma mark - Logos hooks

@interface PSListController : UIViewController
@end

%hook PSListController

- (void)viewDidAppear:(BOOL)animated {
    %orig;

    if (!SGIsMainSettingsController(self))
        return;

    SGInstallSearchGlass(self);
}

%end

%hook UINavigationController

- (void)viewDidLayoutSubviews {
    %orig;

    if (!self.view.window.isKeyWindow)
        return;

    NSString *bundleID =
        [NSBundle.mainBundle bundleIdentifier];

    if (![bundleID isEqualToString:@"com.apple.Preferences"])
        return;

    UIViewController *top =
        self.topViewController;

    if (SGIsMainSettingsController(top))
        SGInstallSearchGlass(top);
}

%end

%ctor {
    @autoreleasepool {
        /*
         * No private class is linked at build time.
         * CABackdropLayer and CAFilter are resolved dynamically.
         *
         * If Liquid (Gl)ass has registered the
         * dylv.liquidglass.searchpill filter, the button uses
         * the live Liquid Glass refraction engine.
         *
         * If the filter is unavailable, the code falls back to
         * a live CABackdropLayer gaussian blur rather than crashing.
         */
    }
}
