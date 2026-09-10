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

@interface UISearchBar (SGSearchPrivate)
- (void)searchFieldBecomeFirstResponder;
@end

#pragma mark - Liquid Glass renderer

/*
 * SearchGlass uses the upstream Liquid (Gl)ass renderer from:
 * https://github.com/winaviation-tweaks/liquidass
 *
 * The renderer supplies the live backdrop, refraction, specular
 * highlights and dynamic light/dark variants.
 *
 * Required upstream Shared files:
 *   LGHostRegistry.h
 *   LGFramework.h/.m
 *   LGGlassKit.h/.x
 *   LGLiquidMotion.h
 *   LGLiveBackdropView.h/.m
 *   LGSharedSupport.h/.m
 */

#import "Shared/LGLiveBackdropView.h"
#import "Shared/LGGlassKit.h"
#import "Shared/LGHostRegistry.h"

@interface SGLiveGlassView : LGLiveBackdropView
@property(nonatomic, assign) CGFloat cornerRadius;
@end

@implementation SGLiveGlassView

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame
                       groupName:@"SearchGlass"
                     filterType:@"dylv.liquidglass.searchpill"];
    if (!self) return nil;

    self.backgroundColor = UIColor.clearColor;
    self.opaque = NO;
    self.userInteractionEnabled = NO;

    self.cornerRadius = MIN(CGRectGetWidth(frame), CGRectGetHeight(frame)) * 0.5;

    self.lgShapeRect = self.bounds;
    self.lgShapeCornerRadius = self.cornerRadius;
    self.lgBackdropZoom = 1.035;

    [self applyFilters];
    return self;
}

- (void)setCornerRadius:(CGFloat)cornerRadius {
    _cornerRadius = cornerRadius;

    self.layer.cornerRadius = cornerRadius;
    self.layer.cornerCurve = kCACornerCurveContinuous;
    self.lgShapeRect = self.bounds;
    self.lgShapeCornerRadius = cornerRadius;
    [self applyFilters];
}

- (void)layoutSubviews {
    [super layoutSubviews];

    self.layer.cornerRadius = self.cornerRadius;
    self.layer.cornerCurve = kCACornerCurveContinuous;
    // IMPORTANT: the Liquid Glass shape is the entire pill.
    self.lgShapeRect = self.bounds;
    self.lgShapeCornerRadius = MIN(self.cornerRadius,
                                   CGRectGetHeight(self.bounds) * 0.5);
    self.lgBackdropZoom = 1.035;

    [self applyFilters];
}

- (void)traitCollectionDidChange:(UITraitCollection *)previousTraitCollection {
    [super traitCollectionDidChange:previousTraitCollection];

    if (@available(iOS 13.0, *)) {
        if (previousTraitCollection.userInterfaceStyle !=
            self.traitCollection.userInterfaceStyle) {
            [self applyFilters];
        }
    }
}

@end

#pragma mark - Search button

@interface SGSearchButton : UIControl
@property(nonatomic, strong) SGLiveGlassView *glassView;
@property(nonatomic, strong) UIImageView *searchIcon;
@property(nonatomic, strong) UILabel *titleLabel;
@property(nonatomic, strong) UIImageView *micIcon;
@end

@interface SGSearchButton ()
- (UIViewController *)nearestViewController;
- (UISearchController *)findSearchController:(UIViewController *)controller;
- (UISearchBar *)findSearchBarInView:(UIView *)view;
- (UIScrollView *)findScrollViewContainingView:(UIView *)target;
@end

@implementation SGSearchButton


- (void)updateAppearance {
    BOOL darkMode = NO;

    if (@available(iOS 13.0, *)) {
        darkMode =
            (self.traitCollection.userInterfaceStyle ==
             UIUserInterfaceStyleDark);
    }

    UIColor *color =
        darkMode ? UIColor.whiteColor : UIColor.blackColor;

    self.titleLabel.textColor = color;
    self.searchIcon.tintColor = color;
    self.micIcon.tintColor = color;
}



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
    self.glassView.cornerRadius = 22.0;

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

    [self updateAppearance];
}

- (void)layoutSubviews {
    [super layoutSubviews];

    CGFloat width =
        CGRectGetWidth(self.bounds);

    CGFloat height =
        CGRectGetHeight(self.bounds);

    self.glassView.frame = self.bounds;
    self.glassView.cornerRadius =
        MIN(22.0, height * 0.5);

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
    UIViewController *vc = [self nearestViewController];
    if (!vc)
        return;

    UINavigationController *nav = vc.navigationController;

    // The real Settings search lives on the root controller.
    if (nav && nav.viewControllers.count > 1) {
        [nav popToRootViewControllerAnimated:YES];
    }

    dispatch_after(
        dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.20 * NSEC_PER_SEC)),
        dispatch_get_main_queue(), ^{
            UIViewController *root =
                nav ? nav.viewControllers.firstObject : vc;

            if (!root)
                return;

            // 1. Use the actual UISearchBar when it is already loaded.
            UISearchBar *bar = [self findSearchBarInView:root.view];

            if (bar) {
                UIScrollView *scroll =
                    [self findScrollViewContainingView:bar];

                if (scroll) {
                    CGRect rect =
                        [bar convertRect:bar.bounds toView:scroll];

                    [scroll scrollRectToVisible:rect animated:YES];
                }

                if ([bar respondsToSelector:
                     @selector(searchFieldBecomeFirstResponder)]) {
                    [bar searchFieldBecomeFirstResponder];
                } else {
                    [bar becomeFirstResponder];
                }
                return;
            }

            // 2. Some Settings versions keep the UISearchController in
            // the controller hierarchy rather than directly in the view.
            UISearchController *searchController =
                [self findSearchController:root];

            if (searchController) {
                searchController.active = YES;

                UISearchBar *searchBar =
                    searchController.searchBar;

                if ([searchBar respondsToSelector:
                     @selector(searchFieldBecomeFirstResponder)]) {
                    [searchBar searchFieldBecomeFirstResponder];
                } else {
                    [searchBar becomeFirstResponder];
                }
                return;
            }

            // 3. The search UI can be attached to a window/scene.
            if (@available(iOS 13.0, *)) {
                for (UIScene *scene in
                     UIApplication.sharedApplication.connectedScenes) {

                    if (![scene isKindOfClass:[UIWindowScene class]])
                        continue;

                    if (scene.activationState ==
                        UISceneActivationStateUnattached)
                        continue;

                    UIWindowScene *windowScene =
                        (UIWindowScene *)scene;

                    for (UIWindow *window in windowScene.windows) {
                        UISearchBar *windowBar =
                            [self findSearchBarInView:window];

                        if (!windowBar)
                            continue;

                        if ([windowBar respondsToSelector:
                             @selector(searchFieldBecomeFirstResponder)]) {
                            [windowBar searchFieldBecomeFirstResponder];
                        } else {
                            [windowBar becomeFirstResponder];
                        }
                        return;
                    }
                }
            }

            // 4. Settings may finish creating its search bar a little later.
            dispatch_after(
                dispatch_time(DISPATCH_TIME_NOW,
                              (int64_t)(0.30 * NSEC_PER_SEC)),
                dispatch_get_main_queue(), ^{
                    UISearchBar *retry =
                        [self findSearchBarInView:root.view];

                    if (!retry)
                        return;

                    if ([retry respondsToSelector:
                         @selector(searchFieldBecomeFirstResponder)]) {
                        [retry searchFieldBecomeFirstResponder];
                    } else {
                        [retry becomeFirstResponder];
                    }
                });
        });
}

#pragma mark - View controller finder

- (UIViewController *)nearestViewController {
    UIResponder *responder = self;

    while (responder) {
        responder = [responder nextResponder];

        if ([responder isKindOfClass:[UIViewController class]]) {
            return (UIViewController *)responder;
        }
    }

    return nil;
}

- (UISearchController *)findSearchController:
    (UIViewController *)controller {

    if (!controller)
        return nil;

    if ([controller isKindOfClass:[UISearchController class]])
        return (UISearchController *)controller;

    for (UIViewController *child in controller.childViewControllers) {
        UISearchController *found =
            [self findSearchController:child];

        if (found)
            return found;
    }

    if (controller.presentedViewController) {
        UISearchController *found =
            [self findSearchController:controller.presentedViewController];

        if (found)
            return found;
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

    Class psClass = NSClassFromString(@"PSListController");

    if (!psClass ||
        ![controller isKindOfClass:psClass]) {
        return NO;
    }

    NSString *className = NSStringFromClass(controller.class);

    /*
     * Settings has used more than one root controller name across
     * iOS versions. Prefer the explicit root names, but keep the
     * navigation-stack fallback so the button still appears on the
     * actual Settings home page.
     */
    if ([className isEqualToString:@"PSRootListController"] ||
        [className isEqualToString:@"PSRootController"]) {
        UINavigationController *nav = controller.navigationController;

        if (!nav ||
            nav.viewControllers.firstObject == controller) {
            return YES;
        }

        return NO;
    }

    /*
     * Fallback for iOS versions where the Settings root controller
     * has another private class name:
     *
     * - must be a PSListController
     * - must be the first controller in the navigation stack
     * - must be the only controller currently pushed
     * - search-related controllers are explicitly rejected
     */
    UINavigationController *nav = controller.navigationController;

    if (!nav)
        return NO;

    if (nav.viewControllers.firstObject != controller)
        return NO;

    if (nav.viewControllers.count != 1)
        return NO;

    if ([className rangeOfString:@"Search"
                         options:NSCaseInsensitiveSearch].location != NSNotFound) {
        return NO;
    }

    return YES;
}

static void SGRemoveSearchGlass(
    UIViewController *controller
) {
    if (!controller)
        return;

    UIView *view = controller.view;
    SGSearchButton *button =
        (SGSearchButton *)[view viewWithTag:kSGSearchGlassTag];

    if (button)
        [button removeFromSuperview];
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

    CGFloat width =
        MIN(400.0,
            MAX(300.0,
                CGRectGetWidth(view.bounds) - 16.0));

    CGFloat height = 44.0;

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


#pragma mark - General icons

static NSString * const kSGAboutIconPath =
    @"/Library/Application Support/SearchGlass/AboutIcon.png";
static NSString * const kSGSoftwareUpdateIconPath =
    @"/Library/Application Support/SearchGlass/SoftwareUpdateIcon.png";

static BOOL SGIsGeneralController(UIViewController *controller) {
    if (!controller)
        return NO;

    NSString *title = controller.title;
    if (!title.length)
        title = controller.navigationItem.title;

    if ([title isEqualToString:@"General"])
        return YES;

    /*
     * Some Settings versions don't expose the title on the
     * controller itself. In that case use the navigation item.
     */
    NSString *navTitle = controller.navigationItem.title;
    return [navTitle isEqualToString:@"General"];
}

static UIImage *SGLoadGeneralAsset(NSString *path) {
    if (!path.length)
        return nil;

    /*
     * Rootless jailbreaks can expose /Library through the bootstrap,
     * while some installations keep the same files explicitly under
     * /var/jb/Library. Try both locations so the custom artwork is
     * reliably found after installation.
     */
    UIImage *image = [UIImage imageWithContentsOfFile:path];
    if (image)
        return image;

    if ([path hasPrefix:@"/Library/"]) {
        NSString *rootlessPath =
            [@"/var/jb" stringByAppendingString:path];

        image =
            [UIImage imageWithContentsOfFile:rootlessPath];

        if (image)
            return image;
    }

    return nil;
}

static UIImage *SGRoundedImage(UIImage *image, CGFloat size, CGFloat radius) {
    if (!image)
        return nil;

    UIGraphicsBeginImageContextWithOptions(CGSizeMake(size, size), NO, 0.0);

    CGRect rect = CGRectMake(0.0, 0.0, size, size);
    UIBezierPath *path =
        [UIBezierPath bezierPathWithRoundedRect:rect
                                   cornerRadius:radius];

    [path addClip];

    [image drawInRect:rect];

    UIImage *result = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();

    return result;
}

static UITableView *SGFindSettingsTableView(UIView *view) {
    if (!view)
        return nil;

    if ([view isKindOfClass:[UITableView class]])
        return (UITableView *)view;

    for (UIView *subview in view.subviews) {
        UITableView *table = SGFindSettingsTableView(subview);
        if (table)
            return table;
    }

    return nil;
}

static UITableViewCell *SGFindGeneralCell(UITableView *table,
                                          NSString *text) {
    if (!table)
        return nil;

    for (UITableViewCell *cell in table.visibleCells) {
        if ([cell.textLabel.text isEqualToString:text])
            return cell;
    }

    for (UIView *subview in table.subviews) {
        if (![subview isKindOfClass:[UITableViewCell class]])
            continue;

        UITableViewCell *cell = (UITableViewCell *)subview;

        if ([cell.textLabel.text isEqualToString:text])
            return cell;
    }

    return nil;
}

static void SGApplyGeneralIcon(UITableViewCell *cell,
                               NSString *path) {
    if (!cell)
        return;

    UIImage *image = SGLoadGeneralAsset(path);

    /*
     * Only use the supplied SearchGlass icons.
     * No SF Symbols are used as a fallback.
     */
    if (!image) {
        cell.imageView.image = nil;
        return;
    }

    /*
     * Smaller footprint than the previous version and rounded like
     * the newer iOS Settings design.
     */
    UIImage *rounded =
        SGRoundedImage(image, 18.0, 4.5);

    cell.imageView.image = rounded;
    cell.imageView.contentMode = UIViewContentModeScaleAspectFit;
    cell.imageView.clipsToBounds = YES;
    cell.imageView.layer.cornerRadius = 4.5;
    cell.imageView.layer.cornerCurve = kCACornerCurveContinuous;

    /*
     * Force a compact native-sized imageView footprint.
     * The cell remains completely native and keeps its own layout.
     */
    cell.imageView.bounds =
        CGRectMake(0.0, 0.0, 18.0, 18.0);
}

static void SGApplyGeneralIcons(UIViewController *controller) {
    if (!SGIsGeneralController(controller))
        return;

    UITableView *table =
        SGFindSettingsTableView(controller.view);

    if (!table)
        return;

    UITableViewCell *about =
        SGFindGeneralCell(table, @"About");

    UITableViewCell *software =
        SGFindGeneralCell(table, @"Software Update");

    SGApplyGeneralIcon(about, kSGAboutIconPath);
    SGApplyGeneralIcon(software, kSGSoftwareUpdateIconPath);
}


#pragma mark - Logos hooks

@interface PSListController : UIViewController
@end

%hook PSListController

- (void)viewDidAppear:(BOOL)animated {
    %orig;

    if (SGIsMainSettingsController(self)) {
        SGInstallSearchGlass(self);
    } else {
        SGRemoveSearchGlass(self);
    }

    if (SGIsGeneralController(self)) {
        dispatch_async(dispatch_get_main_queue(), ^{
            SGApplyGeneralIcons(self);
        });
    }
}

- (void)viewDidLayoutSubviews {
    %orig;

    SGApplyGeneralIcons(self);
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

    if (SGIsMainSettingsController(top)) {
        SGInstallSearchGlass(top);
    } else {
        /*
         * Remove it while any child Settings page is visible.
         * This guarantees the pill cannot remain visible on
         * sub-pages during navigation/interactive transitions.
         */
        for (UIViewController *controller in self.viewControllers) {
            SGRemoveSearchGlass(controller);
        }
    }
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
