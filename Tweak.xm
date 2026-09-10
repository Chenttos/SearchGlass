#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wunused-function"
#pragma clang diagnostic ignored "-Wunused-const-variable"
#pragma clang diagnostic ignored "-Wmissing-prototypes"
#include <atomic>
@import Darwin.sys.sysctl;
@import Darwin.os.lock;
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

#pragma mark - Liquid Glass constants

static NSString * const kSGFilterType = @"dylv.liquidglass.searchpill";
static const CGFloat kSGSearchRefractionScale = 3.40;
static const CGFloat kSGSearchRefractiveIndex = 2.40;
static const CGFloat kSGSearchDispersion = 3.50;
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



#pragma mark - Embedded Liquid (Gl)ass LGHostRegistry.h


#include <stddef.h>
#include <string.h>

typedef struct {
    const char *identifier;
    const char *filterType;
    const char *preferencePrefix;
    float cornerRadiusRatio;
    float bezelWidthPoints;
    float glassThickness;
    float refractionScale;
    float refractiveIndex;
    float blur;
    float specularOpacity;
    float dispersionStrength;
    const char *lightTintHex;
    const char *darkTintHex;
} LGHostDefinition;

//    host            filter                            pref             corner          bezel      thick   refr  index  blur  spec   disp   light        dark
#define LG_HOST_REGISTRY(X) \
    X(Default,        "dylv.liquidglass.refraction",   "Default",         28.0f / 220.0f, 20.00f,    108.0f, 2.6f, 1.80f, 1.0f, 1.0f,  2.00f, "#FFFFFF1A", "#00000000") \
    X(FolderIcon,     "dylv.liquidglass.folder",       "FolderIcon",      28.0f / 220.0f, 13.75f,    108.0f, 2.6f, 1.80f, 1.0f, 1.0f,  1.00f, "#FFFFFF1A", "#00000000") \
    X(OpenFolder,     "dylv.liquidglass.openfolder",   "OpenFolder",      28.0f / 220.0f, 36.00f,    108.0f, 2.6f, 1.80f, 0.0f, 1.0f,  0.00f, "#FFFFFF1A", "#00000000") \
    X(Dock,           "dylv.liquidglass.dock",         "Dock",            0.35f,          17.50f,    120.0f, 2.6f, 1.60f, 3.0f, 1.0f,  0.00f, "#FFFFFF1A", "#00000000") \
    X(Banner,         "dylv.liquidglass.banner",       "Banner",          28.0f / 220.0f, 20.75f,    132.0f, 1.6f, 1.60f, 3.0f, 1.0f,  0.00f, "#FFFFFFCC", "#00000080") \
    X(Notification,   "dylv.liquidglass.notification", "Notification",    28.0f / 220.0f, 20.75f,    132.0f, 1.6f, 1.60f, 3.0f, 1.0f,  0.00f, "#FFFFFF00", "#00000000") \
    X(ControlCenter,  "dylv.liquidglass.cc",           "ControlCenter",   28.0f / 220.0f, 15.50f,    120.0f, 1.8f, 1.60f, 0.0f, 1.0f,  2.00f, "#FFFFFF1A", "#00000000") \
    X(AppLibrary,     "dylv.liquidglass.applibpod",    "AppLibrary",      28.0f / 220.0f, 25.00f,    120.0f, 2.2f, 1.60f, 0.0f, 1.0f,  2.00f, "#FFFFFF1A", "#00000000") \
    X(AppLibSearch,   "dylv.liquidglass.applibsearch", "AppLibSearch",    0.50f,          25.00f,    108.0f, 1.8f, 1.60f, 0.0f, 1.0f,  2.00f, "#FFFFFF1A", "#00000000") \
    X(Spotlight,      "dylv.liquidglass.spotlight",    "Spotlight",       0.50f,          25.00f,    108.0f, 1.8f, 1.60f, 0.0f, 1.0f,  2.00f, "#FFFFFFCC", "#0000004d") \
    X(SearchPill,     "dylv.liquidglass.searchpill",   "SearchPill",      0.50f,          12.00f,    140.0f, 3.40f, 2.40f, 0.0f, 1.25f,  3.50f, "#FFFFFF24", "#00000000") \
    X(Widgets,        "dylv.liquidglass.widget",       "Widgets",         28.0f / 220.0f, 30.00f,    120.0f, 2.2f, 1.60f, 1.0f, 1.0f,  0.00f, "#FFFFFF1A", "#0000004D") \
    X(ContextMenu,    "dylv.liquidglass.contextmenu",  "ContextMenu",     28.0f / 220.0f, 32.00f,    120.0f, 1.8f, 1.80f, 8.0f, 1.0f,  0.00f, "#FFFFFFCC", "#0000004c") \
    X(Alerts,         "dylv.liquidglass.alerts",       "Alerts",          28.0f / 220.0f, 32.00f,    120.0f, 1.6f, 1.60f, 3.0f, 1.0f,  0.00f, "#FFFFFFCC", "#0000004c") \
    X(QuickActions,   "dylv.liquidglass.quickaction",  "QuickActions",    0.50f,          12.00f,    96.00f, 1.6f, 1.40f, 1.0f, 1.0f,  1.00f, "#FFFFFF1A", "#00000000") \
    X(Passcode,       "dylv.liquidglass.passcode",     "Passcode",        0.50f,          28.00f,    96.00f, 2.2f, 1.60f, 1.0f, 1.0f,  1.00f, "#FFFFFF1A", "#0000001F") \
    X(Clock,          "dylv.liquidglass.clock",        "Clock",           0.00f,          12.00f,    120.0f, 1.6f, 1.60f, 2.0f, 1.0f,  0.00f, "#FFFFFF4C", "#FFFFFF4C") \
    X(PrefsSlider,    "dylv.liquidglass.prefsslider",  "PrefsSlider",     0.50f,          10.00f,    108.0f, 2.6f, 1.60f, 0.0f, 1.0f,  1.00f, "#FFFFFF1A", "#00000000") \
    X(PrefsSwitch,    "dylv.liquidglass.prefsswitch",  "PrefsSwitch",     0.50f,          6.500f,    108.0f, 2.6f, 1.60f, 0.0f, 1.0f,  1.00f, "#FFFFFF1A", "#00000000") \
    X(PrefsButton,    "dylv.liquidglass.prefsbutton",  "PrefsButton",     0.50f,          16.00f,    108.0f, 2.0f, 1.60f, 3.0f, 1.0f,  1.00f, "#FFFFFFCC", "#2A2A2D80") \
    X(PrefsSegment,   "dylv.liquidglass.prefssegment", "PrefsSegment",    0.50f,          8.000f,    132.0f, 1.4f, 1.60f, 0.0f, 1.0f,  0.50f, "#FFFFFF1A", "#00000000") \
    X(CoverSheet,     "dylv.liquidglass.coversheet",   "CoverSheet",      0.00f,          64.00f,    192.0f, 1.4f, 1.60f, 0.0f, 0.0f,  2.00f, "#0000002E", "#0000002E") \
    X(TabBar,         "dylv.liquidglass.tabbar",       "TabBar",          0.50f,          20.00f,    108.0f, 2.2f, 1.80f, 3.0f, 1.0f,  2.00f, "#FFFFFF80", "#2A2A2D80") \
    X(TabBarSelection,"dylv.liquidglass.tabbarselect", "TabBarSelection", 0.50f,          12.00f,    132.0f, 1.4f, 1.60f, 0.0f, 1.0f,  0.50f, "#FFFFFF1A", "#FFFFFF0D") \
    X(Keyboard,       "dylv.liquidglass.keyboard",     "Keyboard",        28.0f / 220.0f, 26.00f,    120.0f, 1.8f, 1.60f, 8.0f, 0.0f,  0.00f, "#D1D3D980", "#0000004d") \
    X(AppIcons,       "dylv.liquidglass.appicons",     "AppIcons",        28.0f / 220.0f, 13.75f,    108.0f, 2.6f, 1.80f, 1.0f, 1.0f,  1.00f, "#FFFFFF1A", "#00000000") \
    X(AssistiveTouch, "dylv.liquidglass.assistivetouch","AssistiveTouch", 0.50f,          22.80f,    18.00f, 2.75f, 2.10f, 0.5f, 0.35f, 0.00f, "#00000000", "#00000000") \
    X(VolumeHUD,      "dylv.liquidglass.volumehud",    "VolumeHUD",       0.50f,          28.00f,    280.0f, 3.00f, 3.20f, 5.0f, 0.35f, 1.20f, "#B8B8B8CC", "#666666CC") \
    X(PillHUD,        "dylv.liquidglass.pillhud",      "PillHUD",         0.50f,          17.50f,    120.0f, 2.2f, 1.70f, 1.0f, 0.35f, 1.20f, "#FFFFFF1A", "#0000002E")

enum LGHostIdentifier {
#define LG_HOST_ENUM(identifier, ...) LGHostIdentifier##identifier,
    LG_HOST_REGISTRY(LG_HOST_ENUM)
#undef LG_HOST_ENUM
    LGHostIdentifierCount
};

static const LGHostDefinition kLGHostRegistry[LGHostIdentifierCount] = {
#define LG_HOST_ENTRY(identifier, filter, prefix, radius, bezel, thickness, refraction, index, blurValue, specular, dispersion, lightTint, darkTint) \
    { #identifier, filter, prefix, radius, bezel, thickness, refraction, index, blurValue, specular, dispersion, lightTint, darkTint },
    LG_HOST_REGISTRY(LG_HOST_ENTRY)
#undef LG_HOST_ENTRY
};

static inline enum LGHostIdentifier LGHostIdentifierForDefinition(const LGHostDefinition *host) {
    return host ? (enum LGHostIdentifier)(host - kLGHostRegistry) : LGHostIdentifierCount;
}

static inline const LGHostDefinition *LGHostDefinitionForPreferencePrefix(const char *prefix) {
    if (!prefix) return NULL;
    for (size_t i = 0; i < LGHostIdentifierCount; ++i)
        if (strcmp(kLGHostRegistry[i].preferencePrefix, prefix) == 0) return &kLGHostRegistry[i];
    return NULL;
}

static inline const LGHostDefinition *LGHostDefinitionForFilterType(const char *filterType) {
    if (!filterType) return NULL;
    for (size_t i = 0; i < LGHostIdentifierCount; ++i) {
        const char *base = kLGHostRegistry[i].filterType;
        size_t length = strlen(base);

        if (strncmp(filterType, base, length) == 0 &&
            (filterType[length] == '\0' || filterType[length] == '.')) return &kLGHostRegistry[i];
    }
    return NULL;
}

static inline enum LGHostIdentifier LGHostIdentifierForFilterType(const char *filterType) {
    return LGHostIdentifierForDefinition(LGHostDefinitionForFilterType(filterType));
}

#pragma mark - Embedded Liquid (Gl)ass LGCoverSheetState.h

#ifndef LG_COVER_SHEET_STATE_H
#define LG_COVER_SHEET_STATE_H

#include <stdbool.h>
#include <stdint.h>
#include <fcntl.h>
#include <string.h>
#include <sys/mman.h>
#include <sys/stat.h>
#include <unistd.h>

#if __has_include(<roothide.h>)
#include <roothide.h>
#else
#ifndef jbroot
#define jbroot(path) (path)
#endif
#endif

#define LG_COVER_SHEET_STATE_MAGIC 0x4c474353u
static inline const char *LGCoverSheetStatePath(void) {
    return "/var/mobile/Library/Accessibility/liquidglass-coversheet-state.bin";
}

typedef struct {
    uint32_t magic;
    uint32_t sequence;
    uint32_t active;

    uint32_t deviceOrientation;
    float originXRatio;
    float originYRatio;
    float pixelsPerPoint;
} LGCoverSheetSharedState;

static inline LGCoverSheetSharedState *
LGCoverSheetMapSharedState(bool writable) {
    static LGCoverSheetSharedState *readOnlyState;
    static LGCoverSheetSharedState *writableState;
    LGCoverSheetSharedState **slot =
        writable ? &writableState : &readOnlyState;
    if (*slot) return *slot;

    int flags = writable ? (O_RDWR | O_CREAT) : O_RDONLY;
    int fd = open(LGCoverSheetStatePath(), flags, 0666);
    if (fd < 0) return NULL;
    if (writable &&
        ftruncate(fd, (off_t)sizeof(LGCoverSheetSharedState)) != 0) {
        close(fd);
        return NULL;
    }

    struct stat info = {};
    if (fstat(fd, &info) != 0 ||
        info.st_size < (off_t)sizeof(LGCoverSheetSharedState)) {
        close(fd);
        return NULL;
    }

    int protection = PROT_READ | (writable ? PROT_WRITE : 0);
    void *mapping = mmap(NULL, sizeof(LGCoverSheetSharedState), protection,
                         MAP_SHARED, fd, 0);
    close(fd);
    if (mapping == MAP_FAILED) return NULL;

    *slot = (LGCoverSheetSharedState *)mapping;
    if (writable && (*slot)->magic != LG_COVER_SHEET_STATE_MAGIC) {
        memset(*slot, 0, sizeof(**slot));
        (*slot)->magic = LG_COVER_SHEET_STATE_MAGIC;
    }
    return *slot;
}

static inline void
LGCoverSheetWriteSharedState(bool active, float originXRatio,
                             float originYRatio, float pixelsPerPoint,
                             uint32_t deviceOrientation) {
    LGCoverSheetSharedState *state = LGCoverSheetMapSharedState(true);
    if (!state) return;

    uint32_t sequence =
        __atomic_load_n(&state->sequence, __ATOMIC_RELAXED);
    uint32_t writing = (sequence + 1u) | 1u;
    __atomic_store_n(&state->sequence, writing, __ATOMIC_RELEASE);
    state->active = active ? 1u : 0u;
    state->deviceOrientation = deviceOrientation;
    state->originXRatio = originXRatio;
    state->originYRatio = originYRatio;
    state->pixelsPerPoint = pixelsPerPoint;
    __atomic_store_n(&state->sequence, writing + 1u, __ATOMIC_RELEASE);
}

static inline bool
LGCoverSheetReadSharedState(LGCoverSheetSharedState *snapshot) {
    if (!snapshot) return false;
    LGCoverSheetSharedState *state = LGCoverSheetMapSharedState(false);
    if (!state || state->magic != LG_COVER_SHEET_STATE_MAGIC) return false;

    for (int attempt = 0; attempt < 4; attempt++) {
        uint32_t before =
            __atomic_load_n(&state->sequence, __ATOMIC_ACQUIRE);
        if (before & 1u) continue;
        memcpy(snapshot, state, sizeof(*snapshot));
        uint32_t after =
            __atomic_load_n(&state->sequence, __ATOMIC_ACQUIRE);
        if (before == after && !(after & 1u) &&
            snapshot->magic == LG_COVER_SHEET_STATE_MAGIC) {
            return true;
        }
    }
    return false;
}

#endif

#pragma mark - Embedded Liquid (Gl)ass LGLensRectState.h

#ifndef LG_LENS_RECT_STATE_H
#define LG_LENS_RECT_STATE_H


#include <stdbool.h>
#include <stdint.h>
#include <notify.h>

enum {
    LGLensRectSlotPrefsSegment = 0,
    LGLensRectSlotTabBarSelection = 1,
    LGLensRectSlotNowPlayingArtwork = 2,
    LGLensRectSlotCount = 4,
};

typedef struct {
    uint32_t active;
    float originXRatio;
    float originYRatio;
    float widthRatio;
    float heightRatio;
} LGLensRectSlot;

static inline const char *LGLensRectNotifyName(uint32_t slotIndex) {
    switch (slotIndex) {
        case LGLensRectSlotPrefsSegment:
            return "dylv.liquidglass.lensrect.prefssegment";
        case LGLensRectSlotTabBarSelection:
            return "dylv.liquidglass.lensrect.tabbarselect";
        case LGLensRectSlotNowPlayingArtwork:
            return "dylv.liquidglass.lensrect.npartwork";
        default:
            return NULL;
    }
}

static inline int LGLensRectToken(uint32_t slotIndex) {
    static int sTokens[LGLensRectSlotCount];
    static bool sRegistered[LGLensRectSlotCount];
    if (slotIndex >= (uint32_t)LGLensRectSlotCount) return -1;
    if (!sRegistered[slotIndex]) {
        const char *name = LGLensRectNotifyName(slotIndex);
        if (!name) return -1;
        int token = 0;
        if (notify_register_check(name, &token) != NOTIFY_STATUS_OK) return -1;
        sTokens[slotIndex] = token;
        sRegistered[slotIndex] = true;
    }
    return sTokens[slotIndex];
}

#define LG_LENS_RECT_RATIO_MIN  (-0.5f)
#define LG_LENS_RECT_RATIO_SPAN (2.0f)

static inline uint64_t LGLensRectQuantize(float ratio) {
    float t = (ratio - LG_LENS_RECT_RATIO_MIN) / LG_LENS_RECT_RATIO_SPAN;
    if (!(t > 0.f)) t = 0.f;
    if (t > 1.f) t = 1.f;
    return (uint64_t)(t * 65535.f + 0.5f);
}

static inline float LGLensRectDequantize(uint64_t raw) {
    return (float)(raw & 0xffffu) / 65535.f * LG_LENS_RECT_RATIO_SPAN
         + LG_LENS_RECT_RATIO_MIN;
}

static inline bool LGLensRectWrite(uint32_t slotIndex, bool active,
                                   float originXRatio, float originYRatio,
                                   float widthRatio, float heightRatio) {
    int token = LGLensRectToken(slotIndex);
    if (token < 0) return false;
    uint64_t packed = 0;
    if (active) {
        packed = (LGLensRectQuantize(originXRatio) << 48) |
                 (LGLensRectQuantize(originYRatio) << 32) |
                 (LGLensRectQuantize(widthRatio)   << 16) |
                  LGLensRectQuantize(heightRatio);
    }
    return notify_set_state(token, packed) == NOTIFY_STATUS_OK;
}

static inline bool LGLensRectRead(uint32_t slotIndex, LGLensRectSlot *out) {
    if (!out) return false;
    int token = LGLensRectToken(slotIndex);
    if (token < 0) return false;
    uint64_t packed = 0;
    if (notify_get_state(token, &packed) != NOTIFY_STATUS_OK) return false;
    out->originXRatio = LGLensRectDequantize(packed >> 48);
    out->originYRatio = LGLensRectDequantize(packed >> 32);
    out->widthRatio   = LGLensRectDequantize(packed >> 16);
    out->heightRatio  = LGLensRectDequantize(packed);
    out->active = (out->widthRatio > 0.f && out->heightRatio > 0.f) ? 1u : 0u;
    return out->active != 0u;
}

#endif

#pragma mark - Embedded Liquid (Gl)ass LGLiquidMotion.h

#import <CoreGraphics/CoreGraphics.h>

typedef struct {
    CGFloat centerX;
    CGFloat width;
    CGFloat height;
    CGFloat rubberBandOffset;
} LGLiquidDragState;

typedef struct {
    CGFloat centerX;
    CGFloat width;
    CGFloat height;
} LGLiquidRenderedState;

static inline CGFloat LGLiquidRubberBandedCenterX(CGFloat touchX, CGFloat minX, CGFloat maxX, CGFloat factor) {
    if (touchX < minX) {
        return minX - sqrt(minX - touchX) * factor;
    }
    if (touchX > maxX) {
        return maxX + sqrt(touchX - maxX) * factor;
    }
    return touchX;
}

static inline CGFloat LGLiquidOvershootDistance(CGFloat touchX, CGFloat minX, CGFloat maxX) {
    if (touchX < minX) return minX - touchX;
    if (touchX > maxX) return touchX - maxX;
    return 0.0;
}

static inline CGFloat LGLiquidFilteredVelocity(CGFloat previous, CGFloat raw) {
    return previous * 0.35 + raw * 0.65;
}

static inline LGLiquidDragState LGLiquidDragStateMake(CGFloat touchX,
                                                      CGFloat minX,
                                                      CGFloat maxX,
                                                      CGSize baseSize,
                                                      CGFloat velocity,
                                                      CGFloat minHeight) {
    LGLiquidDragState state;
    state.centerX = LGLiquidRubberBandedCenterX(touchX, minX, maxX, 1.24);
    state.width = baseSize.width;
    state.height = baseSize.height;
    state.rubberBandOffset = 0.0;

    if (touchX < minX) {
        state.rubberBandOffset = state.centerX - minX;
    } else if (touchX > maxX) {
        state.rubberBandOffset = state.centerX - maxX;
    }

    CGFloat overshoot = LGLiquidOvershootDistance(touchX, minX, maxX);
    CGFloat normalizedVelocity = fmin(fabs(velocity) / 900.0, 1.0);
    CGFloat motionStretch = pow(normalizedVelocity, 0.71);
    CGFloat directionalBias = velocity >= 0.0 ? 1.0 : -1.0;
    CGFloat overshootBias = fmin(overshoot / 16.0, 1.0);
    CGFloat widthBoost = 19.5 * motionStretch + 5.8 * overshootBias;
    CGFloat heightReduction = 5.4 * motionStretch + 1.8 * overshootBias;
    CGFloat xShift = directionalBias * (5.1 * motionStretch + 2.4 * overshootBias);

    state.centerX += xShift;
    state.width += widthBoost;
    state.height = fmax(minHeight, state.height - heightReduction);
    return state;
}

static inline LGLiquidRenderedState LGLiquidRenderedStateMake(CGFloat centerX, CGSize size) {
    LGLiquidRenderedState state;
    state.centerX = centerX;
    state.width = size.width;
    state.height = size.height;
    return state;
}

static inline LGLiquidRenderedState LGLiquidRenderedStateStep(LGLiquidRenderedState current,
                                                              LGLiquidRenderedState target,
                                                              BOOL active,
                                                              CGFloat dt) {
    CGFloat frameFactor = fmin(fmax(dt * 60.0, 0.35), 1.4);
    CGFloat centerLerp = (active ? 0.21 : 0.14) * frameFactor;
    CGFloat sizeLerp = (active ? 0.25 : 0.15) * frameFactor;
    current.centerX += (target.centerX - current.centerX) * centerLerp;
    current.width += (target.width - current.width) * sizeLerp;
    current.height += (target.height - current.height) * sizeLerp;
    return current;
}

#pragma mark - Embedded Liquid (Gl)ass LGSharedSupport.h



#if __has_include(<roothide.h>)
#else
#ifndef jbroot
#define jbroot(path) (path)
#endif
#endif

FOUNDATION_EXPORT NSString * const LGPrefsDomain;
FOUNDATION_EXPORT CFStringRef const LGPrefsChangedNotification;
FOUNDATION_EXPORT CFStringRef const LGPrefsRespringNotification;
FOUNDATION_EXPORT const char * const LGPrefsChangedNotificationCString;
FOUNDATION_EXPORT const char * const LGPrefsRespringNotificationCString;

NSString *LGMainBundleIdentifier(void);
BOOL LGIsSpringBoardProcess(void);
BOOL LGIsPreferencesProcess(void);
BOOL LGIsExcludedSystemProcess(void);
BOOL LGIsAtLeastiOS16(void);
BOOL LGBackboardSafeModeActive(void);
void LGClearBackboardSafeMode(void);

NSString *LGRWBDefaultWidgetBundleIDsText(void);

#define LG_BOOL_PREF_FUNC(name, key, fallback) \
    static BOOL name(void) { return LG_prefBool(@key, fallback); }
#define LG_ENABLED_BOOL_PREF_FUNC(name, key, fallback) \
    static BOOL name(void) { return LG_globalEnabled() && LG_prefBool(@key, fallback); }
#define LG_FLOAT_PREF_FUNC(name, key, fallback) \
    static CGFloat name(void) { return LG_prefFloat(@key, fallback); }

FOUNDATION_EXPORT const CGFloat LGKeyboardDefaultCornerRadius;
FOUNDATION_EXPORT const CGFloat LGKeyboardDefaultOverhang;
FOUNDATION_EXPORT const CGFloat LGKeyboardDefaultKeyRadius;
FOUNDATION_EXPORT const CGFloat LGBannerDefaultCornerRadius;
FOUNDATION_EXPORT const CGFloat LGBannerDefaultBezelWidth;
FOUNDATION_EXPORT const CGFloat LGBannerDefaultBlur;
FOUNDATION_EXPORT const CGFloat LGBannerDefaultDarkTintAlpha;
FOUNDATION_EXPORT const CGFloat LGBannerDefaultGlassThickness;
FOUNDATION_EXPORT const CGFloat LGBannerDefaultLightTintAlpha;
FOUNDATION_EXPORT const CGFloat LGBannerDefaultRefractionScale;
FOUNDATION_EXPORT const CGFloat LGBannerDefaultRefractiveIndex;
FOUNDATION_EXPORT const CGFloat LGBannerDefaultSpecularOpacity;
FOUNDATION_EXPORT const CGFloat LGBannerDefaultWallpaperScale;
FOUNDATION_EXPORT NSString * const LGBannerWindowClassName;
FOUNDATION_EXPORT NSString * const LGBannerContentViewClassName;
FOUNDATION_EXPORT NSString * const LGBannerControllerClassName;
FOUNDATION_EXPORT NSString * const LGBannerPresentableControllerClassName;
FOUNDATION_EXPORT NSString * const LGAppLibrarySidebarMarkerClassName;
FOUNDATION_EXPORT NSString * const LGTintOverrideSystem;
FOUNDATION_EXPORT NSString * const LGTintOverrideLight;
FOUNDATION_EXPORT NSString * const LGTintOverrideDark;

CGFloat LGEffectiveBannerBlur(CGFloat configuredBlur);

BOOL LG_prefBool(NSString *key, BOOL fallback);
CGFloat LG_prefFloat(NSString *key, CGFloat fallback);
NSInteger LG_prefInteger(NSString *key, NSInteger fallback);
NSString *LG_prefString(NSString *key, NSString *fallback);
BOOL LGHasExplicitPreferenceValue(NSString *key);
BOOL LG_globalEnabled(void);
void LGReloadPreferences(void);
void LGObservePreferenceChanges(dispatch_block_t block);

BOOL LGDebugLoggingEnabled(void);
void LGLog(NSString *format, ...);

CGColorSpaceRef LGSharedRGBColorSpace(void);
UIImage *LGNormalizedImageForUpload(UIImage *image);
NSNumber *LGTextureScaleKey(CGFloat scale);
NSNumber *LGBlurSettingKey(CGFloat blur);
NSString *LGImageStableCacheKey(UIImage *image);
void LGSetImageStableCacheKey(UIImage *image, NSString *cacheKey);

#pragma mark - Embedded Liquid (Gl)ass LGSharedSupport.m


static const char *kLGBackboardSafeModeStatePath =
    "/var/mobile/Library/Accessibility/liquidass-backboardd-guard.bin";
static const char *kLGBackboardSafeModePendingPath =
    "/var/mobile/Library/Accessibility/liquidass-backboardd-alert";

typedef struct {
    uint32_t magic;
    uint32_t version;
    int64_t bootTime;
    uint64_t lastStartMilliseconds;
    uint32_t rapidStarts;
    uint32_t disabled;
} LGBackboardSafeModeState;

BOOL LGBackboardSafeModeActive(void) {
    NSData *data = [NSData dataWithContentsOfFile:
        [NSString stringWithUTF8String:kLGBackboardSafeModeStatePath]];
    if (data.length != sizeof(LGBackboardSafeModeState)) return NO;

    LGBackboardSafeModeState state = {};
    [data getBytes:&state length:sizeof(state)];
    if (state.magic != 0x4c47534d || state.version != 1 || !state.disabled) return NO;

    /*
     * Avoid the Darwin sysctl module-only declarations in the iPhoneOS 16.5
     * Objective-C++ SDK. systemUptime gives us a stable boot-time estimate
     * without depending on CTL_KERN/KERN_BOOTTIME.
     */
    int64_t bootTime = (int64_t)(time(NULL) -
                                 (time_t)NSProcessInfo.processInfo.systemUptime);
    return state.bootTime == bootTime;
}

void LGClearBackboardSafeMode(void) {
    unlink(kLGBackboardSafeModeStatePath);
    unlink(kLGBackboardSafeModePendingPath);
}

__attribute__((weak)) int __isOSVersionAtLeast(int major, int minor, int patch) {
    NSOperatingSystemVersion version = NSProcessInfo.processInfo.operatingSystemVersion;
    if (version.majorVersion != major) return version.majorVersion > major;
    if (version.minorVersion != minor) return version.minorVersion > minor;
    return version.patchVersion >= patch;
}

NSString * const LGPrefsDomain = @"dylv.liquidassprefs";
CFStringRef const LGPrefsChangedNotification = CFSTR("dylv.liquidassprefs/Reload");
CFStringRef const LGPrefsRespringNotification = CFSTR("dylv.liquidassprefs/Respring");
const char * const LGPrefsChangedNotificationCString = "dylv.liquidassprefs/Reload";
const char * const LGPrefsRespringNotificationCString = "dylv.liquidassprefs/Respring";
const CGFloat LGKeyboardDefaultCornerRadius = 28.0;
const CGFloat LGKeyboardDefaultOverhang = 20.0;
const CGFloat LGKeyboardDefaultKeyRadius = 10.0;
const CGFloat LGBannerDefaultCornerRadius = 18.5;
const CGFloat LGBannerDefaultBezelWidth = 18.0;
const CGFloat LGBannerDefaultBlur = 40.0;
const CGFloat LGBannerDefaultDarkTintAlpha = 0.5;
const CGFloat LGBannerDefaultGlassThickness = 150.0;
const CGFloat LGBannerDefaultLightTintAlpha = 0.8;
const CGFloat LGBannerDefaultRefractionScale = 1.5;
const CGFloat LGBannerDefaultRefractiveIndex = 4.0;
const CGFloat LGBannerDefaultSpecularOpacity = 0.6;
const CGFloat LGBannerDefaultWallpaperScale = 1.0;
NSString * const LGBannerWindowClassName = @"SBBannerWindow";
NSString * const LGBannerContentViewClassName = @"BNContentViewControllerView";
NSString * const LGBannerControllerClassName = @"BNContentViewController";
NSString * const LGBannerPresentableControllerClassName = @"SBNotificationPresentableViewController";
NSString * const LGAppLibrarySidebarMarkerClassName = @"_SBHLibraryFrozenSafeAreaInsetsView";
NSString * const LGTintOverrideSystem = @"system";
NSString * const LGTintOverrideLight = @"light";
NSString * const LGTintOverrideDark = @"dark";
static NSString * const LGPrefsDidReloadInProcessNotification = @"dylv.liquidassprefs.InProcessReload";

static NSDictionary<NSString *, id> *sLGCachedPreferences = nil;
static NSObject *sLGPrefsLock = nil;
static dispatch_once_t sLGPrefsSetupOnce;
static dispatch_queue_t sLGLogQueue;
static NSFileHandle *sLGLogHandle;
static void *kLGImageStableCacheKeyAssociation = &kLGImageStableCacheKeyAssociation;

static NSDictionary<NSString *, id> *LGCopyPreferencesDictionary(void);

static void LGCloseLogHandle(void) {
    if (!sLGLogHandle) return;
    if (@available(iOS 13.0, *)) {
        [sLGLogHandle closeAndReturnError:nil];
    } else {
        [sLGLogHandle closeFile];
    }
    sLGLogHandle = nil;
}

static void LGCloseLogHandleAtExit(void) {
    if (!sLGLogQueue) {
        LGCloseLogHandle();
        return;
    }
    dispatch_sync(sLGLogQueue, ^{
        LGCloseLogHandle();
    });
}

static NSString *LGLogFilePath(void) {
    static NSString *sPath = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
#if TARGET_OS_SIMULATOR
        sPath = @"/tmp/liquidglass.log";
#else

        if ([NSBundle.mainBundle.bundleIdentifier
                isEqualToString:@"com.apple.mobilesafari"]) {
            NSString *temporaryDirectory = NSTemporaryDirectory();
            sPath = [temporaryDirectory
                stringByAppendingPathComponent:@"liquidglass.log"];
        } else {
            sPath = @"/var/mobile/Library/Accessibility/liquidglass.log";
        }
#endif
    });
    return sPath;
}

static void LGAppendLogLine(NSString *line) {
    NSString *path = LGLogFilePath();
    if (!path.length || !line.length) return;

    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sLGLogQueue = dispatch_queue_create("dylv.liquidass.logfile", DISPATCH_QUEUE_SERIAL);
        atexit(LGCloseLogHandleAtExit);
    });

    dispatch_async(sLGLogQueue, ^{
        NSFileManager *fm = [NSFileManager defaultManager];
        if (![fm fileExistsAtPath:path]) {
            NSError *createError = nil;
            [NSData.data writeToFile:path options:NSDataWritingAtomic error:&createError];
            if (createError) {
                NSLog(@"[LiquidAss] log file create failed %@", createError.localizedDescription ?: @"unknown");
                return;
            }
        }

        NSData *data = [line dataUsingEncoding:NSUTF8StringEncoding];
        if (!data.length) {
            return;
        }
        if (!sLGLogHandle) {
            sLGLogHandle = [NSFileHandle fileHandleForWritingAtPath:path];
        }
        if (!sLGLogHandle) {
            NSLog(@"[LiquidAss] log file open failed %@", path);
            return;
        }

        NSError *handleError = nil;
        if (@available(iOS 13.0, *)) {
            [sLGLogHandle seekToEndReturningOffset:nil error:&handleError];
            if (!handleError) {
                [sLGLogHandle writeData:data error:&handleError];
            }
        } else {
            @try {
                [sLGLogHandle seekToEndOfFile];
                [sLGLogHandle writeData:data];
            } @catch (NSException *exception) {
                handleError = [NSError errorWithDomain:@"dylv.liquidass.logfile"
                                                  code:1
                                              userInfo:@{NSLocalizedDescriptionKey: exception.reason ?: @"NSFileHandle exception"}];
            }
        }

        if (handleError) {
            LGCloseLogHandle();
            NSLog(@"[LiquidAss] log file append failed %@", handleError.localizedDescription ?: @"unknown");
        }
    });
}

static NSDictionary<NSString *, id> *LGCopyPreferencesDictionary(void) {
    CFPreferencesAppSynchronize((__bridge CFStringRef)LGPrefsDomain);
    CFDictionaryRef values = CFPreferencesCopyMultiple(NULL,
                                                       (__bridge CFStringRef)LGPrefsDomain,
                                                       kCFPreferencesCurrentUser,
                                                       kCFPreferencesAnyHost);
    NSDictionary *dictionary = CFBridgingRelease(values);
    if (![dictionary isKindOfClass:[NSDictionary class]]) {
        return @{};
    }
    return dictionary;
}

static void LGPreferencesChanged(CFNotificationCenterRef center,
                                 void *observer,
                                 CFStringRef name,
                                 const void *object,
                                 CFDictionaryRef userInfo) {
    (void)center;
    (void)observer;
    (void)name;
    (void)object;
    (void)userInfo;
    dispatch_async(dispatch_get_main_queue(), ^{
        LGReloadPreferences();
        [[NSNotificationCenter defaultCenter] postNotificationName:LGPrefsDidReloadInProcessNotification object:nil];
    });
}

static void LGEnsurePreferenceCacheInitialized(void) {
    dispatch_once(&sLGPrefsSetupOnce, ^{
        sLGPrefsLock = [NSObject new];
        LGReloadPreferences();
        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(),
                                        NULL,
                                        LGPreferencesChanged,
                                        LGPrefsChangedNotification,
                                        NULL,
                                        CFNotificationSuspensionBehaviorDeliverImmediately);
    });
}

NSString *LGMainBundleIdentifier(void) {
    static NSString *bundleID = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        bundleID = [NSBundle.mainBundle.bundleIdentifier copy] ?: @"";
    });
    return bundleID;
}

BOOL LGIsSpringBoardProcess(void) {
    return [LGMainBundleIdentifier() isEqualToString:@"com.apple.springboard"];
}

BOOL LGIsPreferencesProcess(void) {
    return [LGMainBundleIdentifier() isEqualToString:@"com.apple.Preferences"];
}

BOOL LGIsExcludedSystemProcess(void) {
    static BOOL excluded;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSString *bundleID = (LGMainBundleIdentifier() ?: @"").lowercaseString;
        NSString *executable = (NSBundle.mainBundle.executablePath ?: @"").lastPathComponent.lowercaseString;
        NSString *process = (NSProcessInfo.processInfo.processName ?: @"").lowercaseString;
        if ([bundleID isEqualToString:@"com.apple.springboard"] ||
            [bundleID isEqualToString:@"com.apple.preferences"] ||
            [bundleID isEqualToString:@"com.apple.mobilesafari"]) return;
        if (!bundleID.length) {
            excluded = YES;
            return;
        }
        for (NSString *name in @[@"assistivetouchd", @"posterboard", @"posterextension",
                                  @"wallpaper", @"widgetrenderer", @"chronod", @"backboardd",
                                  @"sharingd", @"bluetoothd", @"wifid", @"powerlog", @"coreauthui"]) {
            if ([bundleID containsString:name] || [executable containsString:name] ||
                [process containsString:name]) {
                excluded = YES;
                return;
            }
        }
    });
    return excluded;
}

BOOL LGIsAtLeastiOS16(void) {
    static BOOL cached;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        cached = [[NSProcessInfo processInfo] isOperatingSystemAtLeastVersion:(NSOperatingSystemVersion){16, 0, 0}];
    });
    return cached;
}

NSString *LGRWBDefaultWidgetBundleIDsText(void) {
    static NSString *text;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        text = [@[
            @"com.apple.mobiletimer.WorldClockWidget",
            @"com.apple.mobilecal.CalendarWidgetExtension",
            @"com.apple.mobilemail.MailWidgetExtension",
            @"com.apple.ScreenTimeWidgetApplication.ScreenTimeWidgetExtension",
            @"com.apple.reminders.WidgetExtension",
            @"com.apple.weather.widget",
            @"com.apple.Fitness.FitnessWidget",
            @"com.apple.Passbook.PassbookWidgets",
            @"com.apple.Health.Sleep.SleepWidgetExtension",
            @"com.apple.tips.TipsSwift",
            @"com.apple.Music.MusicWidgets",
            @"com.apple.gamecenter.widgets.extension",
            @"com.apple.tv.TVWidgetExtension",
            @"com.apple.news.widget",
            @"com.apple.Maps.GeneralMapsWidget",
        ] componentsJoinedByString:@"\n"];
    });
    return text;
}

CGFloat LGEffectiveBannerBlur(CGFloat configuredBlur) {
    return fmin(80.0, fmax(0.0, configuredBlur) * 2.2);
}

void LGReloadPreferences(void) {
    NSDictionary<NSString *, id> *dictionary = LGCopyPreferencesDictionary();
    @synchronized (sLGPrefsLock) {
        sLGCachedPreferences = dictionary;
    }
}

void LGObservePreferenceChanges(dispatch_block_t block) {
    if (!block) return;
    [[NSNotificationCenter defaultCenter] addObserverForName:LGPrefsDidReloadInProcessNotification
                                                      object:nil
                                                       queue:[NSOperationQueue mainQueue]
                                                  usingBlock:^(__unused NSNotification *note) {
        block();
    }];
}

static id LGPreferenceValue(NSString *key) {
    if (!key.length) return nil;
    LGEnsurePreferenceCacheInitialized();
    NSDictionary<NSString *, id> *preferences = nil;
    @synchronized (sLGPrefsLock) {
        preferences = sLGCachedPreferences;
    }
    return preferences[key];
}

BOOL LGHasExplicitPreferenceValue(NSString *key) {
    if (!key.length) return NO;
    LGEnsurePreferenceCacheInitialized();
    NSDictionary<NSString *, id> *preferences = nil;
    @synchronized (sLGPrefsLock) {
        preferences = sLGCachedPreferences;
    }
    return preferences[key] != nil;
}

BOOL LG_prefBool(NSString *key, BOOL fallback) {
    id value = LGPreferenceValue(key);
    if ([value isKindOfClass:[NSNumber class]]) return [value boolValue];
    return fallback;
}

CGFloat LG_prefFloat(NSString *key, CGFloat fallback) {
    id value = LGPreferenceValue(key);
    if ([value isKindOfClass:[NSNumber class]]) return (CGFloat)[value doubleValue];
    return fallback;
}

NSInteger LG_prefInteger(NSString *key, NSInteger fallback) {
    id value = LGPreferenceValue(key);
    if ([value isKindOfClass:[NSNumber class]]) return [value integerValue];
    return fallback;
}

NSString *LG_prefString(NSString *key, NSString *fallback) {
    id value = LGPreferenceValue(key);
    if ([value isKindOfClass:[NSString class]] && [value length] > 0) return value;
    return fallback;
}

BOOL LG_globalEnabled(void) {
    return LG_prefBool(@"Global.Enabled", NO);
}

BOOL LGDebugLoggingEnabled(void) {
    return LG_prefBool(@"Debug.Logging.Enabled", NO);
}

void LGLog(NSString *format, ...) {
    if (!LGDebugLoggingEnabled()) return;
    va_list args;
    va_start(args, format);
    NSString *message = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);
    NSLog(@"[LiquidAss] %@", message);
    LGAppendLogLine([NSString stringWithFormat:@"[LiquidAss] %@\n", message]);
}

CGColorSpaceRef LGSharedRGBColorSpace(void) {
    static CGColorSpaceRef sColorSpace = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sColorSpace = CGColorSpaceCreateDeviceRGB();
    });
    return sColorSpace;
}

UIImage *LGNormalizedImageForUpload(UIImage *image) {
    if (!image) return nil;
    if (image.imageOrientation == UIImageOrientationUp) return image;
    UIGraphicsBeginImageContextWithOptions(image.size, NO, image.scale);
    [image drawInRect:CGRectMake(0, 0, image.size.width, image.size.height)];
    UIImage *normalized = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return normalized ?: image;
}

NSNumber *LGTextureScaleKey(CGFloat scale) {
    NSInteger milli = (NSInteger)lrint(scale * 1000.0);
    return @(MAX(milli, 1));
}

NSNumber *LGBlurSettingKey(CGFloat blur) {
    NSInteger milli = (NSInteger)lrint(fmax(0.0, blur) * 1000.0);
    return @(MAX(milli, 0));
}

NSString *LGImageStableCacheKey(UIImage *image) {
    if (!image) return nil;
    return objc_getAssociatedObject(image, kLGImageStableCacheKeyAssociation);
}

void LGSetImageStableCacheKey(UIImage *image, NSString *cacheKey) {
    if (!image) return;
    objc_setAssociatedObject(image,
                             kLGImageStableCacheKeyAssociation,
                             [cacheKey copy],
                             OBJC_ASSOCIATION_COPY_NONATOMIC);
}

#pragma mark - Embedded Liquid (Gl)ass LGLiveBackdropView.h


void LGLog(NSString *format, ...);

#if __has_include(<roothide.h>)
#else
#ifndef jbroot
#define jbroot(path) (path)
#endif
#endif

id LGGlassPreferenceValue(NSString *key);
void LGInvalidateGlassPreferenceCache(void);
NSString *LGFilterTypeForHostPrefix(NSString *prefix);

@interface LGLiveBackdropView : UIView

@property (nonatomic, copy) NSString *lgFilterType;

@property (nonatomic, copy) NSNumber *lgSpecularEnabledOverride;

- (instancetype)initWithFrame:(CGRect)frame groupName:(NSString *)groupName;

- (instancetype)initWithFrame:(CGRect)frame groupName:(NSString *)groupName
                   filterType:(NSString *)filterType;
@property (nonatomic, assign) CGRect lgShapeRect;
@property (nonatomic, assign) CGFloat lgShapeCornerRadius;

- (void)applyFilters;
- (void)lgInvalidateFilterContents;
- (BOOL)lgFilterAttached;

@property (nonatomic, assign) CGFloat lgBackdropZoom;
@end

void LGInjectGlassIntoMaterialGroupType(UIView *materialView, const void *assocKey,
                                        UIEdgeInsets outset, CGFloat cornerRadius,
                                        NSString *groupName, NSString *filterType);

void LGResyncGlassGeometry(UIView *materialView, const void *assocKey);
void LGRemoveGlassFromMaterial(UIView *materialView, const void *assocKey);

BOOL LGMaterialHasGlass(UIView *materialView, const void *assocKey);

#pragma mark - Embedded Liquid (Gl)ass LGLiveBackdropView.m


static const void *kLGOutsetKey = &kLGOutsetKey;
static const void *kLGRadiusKey = &kLGRadiusKey;
static const void *kLGSpecularEnabledOverrideKey = &kLGSpecularEnabledOverrideKey;

static NSDictionary<NSString *, id> *sLGGlassPreferences;

static NSString *LGGlassPreferencesPath(void) {
    static NSString *path;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        path = jbroot(@"/var/mobile/Library/Preferences/dylv.liquidassprefs.plist");
    });
    return path;
}

id LGGlassPreferenceValue(NSString *key) {
    if (!key.length) return nil;
    @synchronized([LGLiveBackdropView class]) {
        if (!sLGGlassPreferences) {
            sLGGlassPreferences =
                [NSDictionary dictionaryWithContentsOfFile:LGGlassPreferencesPath()] ?: @{};
        }
        return sLGGlassPreferences[key];
    }
}

void LGInvalidateGlassPreferenceCache(void) {
    @synchronized([LGLiveBackdropView class]) {
        sLGGlassPreferences = nil;
    }
}

NSString *LGFilterTypeForHostPrefix(NSString *prefix) {
    if (!prefix.length) return nil;
    const LGHostDefinition *host =
        LGHostDefinitionForPreferencePrefix(prefix.UTF8String);
    return host ? [NSString stringWithUTF8String:host->filterType] : nil;
}

static void sblog(const char *fmt, ...) __attribute__((format(printf, 1, 2)));
static void sblog(const char *fmt, ...) {
    va_list ap;
    va_start(ap, fmt);
    NSString *format = [NSString stringWithUTF8String:fmt ?: ""];
    NSString *message = [[NSString alloc] initWithFormat:format arguments:ap];
    va_end(ap);
    LGLog(@"[LGSB] %@", message);
}

static const NSInteger kLGDynamicRadiusSteps = 32;

static BOOL LGNeedsGaussianIdentityFallback(void) {
    return access("/var/mobile/Library/Accessibility/liquidass-gaussian-identity-state.bin",
                  F_OK) == 0;
}

static CFStringRef const kLGParametersReloadedNotification =
    CFSTR("dylv.liquidglass/ParametersReloaded");
static NSHashTable<LGLiveBackdropView *> *sLGAllGlasses;
static BOOL sLGFilterRefreshSetup;
static BOOL LGSpecularEnabledForFilterType(NSString *type) {
    const LGHostDefinition *host = LGHostDefinitionForFilterType(type.UTF8String);
    if (host == &kLGHostRegistry[LGHostIdentifierCoverSheet]) return NO;
    if (host && host->specularOpacity <= 0.001f) return NO;
    NSString *prefix = host ? [NSString stringWithUTF8String:host->preferencePrefix] : nil;
    if (!prefix.length) return YES;
    id value = LGGlassPreferenceValue([prefix stringByAppendingString:@".SpecularEnabled"]);
    return [value isKindOfClass:[NSNumber class]] ? [value boolValue] : YES;
}

/* Optional motion-highlight subsystem disabled in the single-file
 * iPhoneOS16 build. The actual glass/refraction renderer does not depend on it.
 */
static void LGEnsureMotionHighlights(void) {
    /* no-op */
}


/*
 * Single-file SearchGlass compatibility helpers.
 *
 * These small helpers are normally supplied by the upstream Shared support
 * layer. Keep them local here so the merged Tweak.xm remains self-contained.
 */
static NSHashTable<LGLiveBackdropView *> *sLGMotionGlasses = nil;
static const CGFloat sLGSpecularAngle = -M_PI_4;

/* SearchGlass does not expose the upstream preference UI, so use the
 * renderer's default capture scale for non-special hosts. */
static const CGFloat kLGClockCaptureScale = 1.0;
static const CGFloat kLGPrefsControlScale = 1.0;

static BOOL LGUsesPrefsControlCaptureScale(NSString *filterType) {
    (void)filterType;
    return NO;
}

static CGFloat LGScaleForSize(CGSize size) {
    CGFloat shortest = MIN(size.width, size.height);
    if (shortest <= 0.0) return 1.0;
    /* Small surfaces benefit from a little extra capture resolution. */
    return MAX(1.0, MIN(2.0, shortest < 160.0 ? 1.5 : 1.0));
}

static CGFloat LGNativeBlurRadiusForFilterType(NSString *filterType) {
    /* Never add the old native overlay to SearchPill; it caused the
     * partial-width horizontal band seen on iOS 16. */
    if ([filterType hasPrefix:@"dylv.liquidglass.searchpill"])
        return 0.0;
    return 0.0;
}

static void LGEnsureFilterRefreshObserver(void) {
    /* SearchGlass performs filter setup directly on each live glass view. */
}

static const CGFloat kLGGlassEdgeWidth = 1.0;

@implementation LGLiveBackdropView {
    NSString        *_lgGroupName;
    CAGradientLayer *_specularLayer;
    CAShapeLayer    *_specularMask;
    CAShapeLayer    *_edge;
    UIView          *_nativeBlurView;
    CGFloat          _nativeBlurRadius;
    BOOL             _backdropConfigured;
    BOOL             _filterAttached;
    uint32_t         _lgId;
    CGFloat          _appliedScale;
    CGFloat          _appliedBackdropZoom;
    BOOL             _parameterRefreshVariant;
    NSInteger        _lastRadiusStep;
    CGFloat          _appliedSpecularOpacity;
}

- (NSString *)lgEffectiveFilterType {
    if (!_lgFilterType.length)
        return [NSString stringWithUTF8String:kLGHostRegistry[LGHostIdentifierDefault].filterType];
    NSString *base = _lgFilterType;

    if (LGUsesDynamicRadiusType(base) && !CGRectIsEmpty(self.bounds)) {
        CGFloat shortest = MIN(CGRectGetWidth(self.bounds), CGRectGetHeight(self.bounds));
        BOOL keyboard = LGHostIdentifierForFilterType(base.UTF8String) ==
            LGHostIdentifierKeyboard;
        CGFloat radius = keyboard ? _lgShapeCornerRadius : self.layer.cornerRadius;
        CGFloat ratio = shortest > 0.0 ? radius / shortest : 0.0;
        CGFloat exact = MAX(0.0, MIN(0.5, ratio)) * kLGDynamicRadiusSteps;
        NSInteger step = (NSInteger)llround(exact);
        if (_lastRadiusStep >= 0 && fabs(exact - (CGFloat)_lastRadiusStep) < 0.75)
            step = _lastRadiusStep;
        _lastRadiusStep = step;
        base = [base stringByAppendingFormat:@".r%ld", (long)step];
    }
    NSString *type = self.traitCollection.userInterfaceStyle == UIUserInterfaceStyleDark
        ? [base stringByAppendingString:@".dark"] : base;
    if (_parameterRefreshVariant) type = [type stringByAppendingString:@".refresh"];
    return type;
}

+ (Class)layerClass {
    return NSClassFromString(@"CABackdropLayer") ?: [CALayer class];
}

- (instancetype)initWithFrame:(CGRect)frame {
    return [self initWithFrame:frame groupName:nil filterType:nil];
}

- (instancetype)initWithFrame:(CGRect)frame groupName:(NSString *)groupName {
    return [self initWithFrame:frame groupName:groupName filterType:nil];
}

- (instancetype)initWithFrame:(CGRect)frame groupName:(NSString *)groupName filterType:(NSString *)filterType {
    self = [super initWithFrame:frame];
    if (!self) return nil;
    _lastRadiusStep = -1;
    _appliedSpecularOpacity = -1.0;
    _lgShapeRect = CGRectNull;
    _lgFilterType = [filterType copy];
    /*
     * Tweak.xm is compiled as Objective-C++ (.xm).
     * The C11 atomic_uint/atomic_fetch_add API from <stdatomic.h>
     * is not exposed correctly by some Theos/Clang C++ configurations.
     * Use the C++ atomic implementation instead.
     */
    static std::atomic_uint idCounter{0};
    _lgId = idCounter.fetch_add(1, std::memory_order_relaxed) + 1;
    if (groupName.length) {
        _lgGroupName = [groupName copy];
    } else {
        static uint32_t salt = 0;
        static dispatch_once_t onceToken;
        dispatch_once(&onceToken, ^{ salt = arc4random(); });
        _lgGroupName = [NSString stringWithFormat:@"dylv.liquidglass.p%d.%08x.g%u",
                                                  getpid(), salt, _lgId];
    }
    self.userInteractionEnabled = NO;
    self.backgroundColor        = [UIColor clearColor];
    self.opaque                 = NO;

    self.autoresizingMask       = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    LGEnsureFilterRefreshObserver();
    if (!sLGAllGlasses)
        sLGAllGlasses = [NSHashTable weakObjectsHashTable];
    if (!sLGMotionGlasses)
        sLGMotionGlasses = [NSHashTable weakObjectsHashTable];
    [sLGAllGlasses addObject:self];
    LGEnsureMotionHighlights();
    [sLGMotionGlasses addObject:self];
    [self applyFilters];
    return self;
}

- (void)dealloc {
    [sLGAllGlasses removeObject:self];
    [sLGMotionGlasses removeObject:self];
}

- (void)didMoveToWindow {
    [super didMoveToWindow];
    [self applyFilters];
}
- (void)traitCollectionDidChange:(UITraitCollection *)previousTraitCollection {
    [super traitCollectionDidChange:previousTraitCollection];
    if (previousTraitCollection.userInterfaceStyle != self.traitCollection.userInterfaceStyle) {
        _filterAttached = NO;
        [self applyFilters];
        [self updateSpecular];
        }
}

- (NSNumber *)lgSpecularEnabledOverride {
    return objc_getAssociatedObject(self, kLGSpecularEnabledOverrideKey);
}

- (void)setLgSpecularEnabledOverride:(NSNumber *)override {
    NSNumber *previous = self.lgSpecularEnabledOverride;
    if ((previous == override) || [previous isEqualToNumber:override]) return;
    objc_setAssociatedObject(self, kLGSpecularEnabledOverrideKey, [override copy],
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [self updateSpecular];
}

- (void)layoutSubviews  { [super layoutSubviews];  [self applyFilters]; [self updateSpecular]; }

static BOOL LGIsSearchPillFilterType(NSString *filterType) {
    return [filterType hasPrefix:@"dylv.liquidglass.searchpill"];
}

static CGFloat LGSearchPillFallbackBlurRadius(void) {
    // SearchGlass must not use LGSettingsLowBlurView: on iOS 16 it can
    // produce a partial-width backdrop band. Use CABackdropLayer's own
    // gaussianBlur filter instead, which covers the complete pill bounds.
    return 13.0;
}

- (void)updateNativeBlurOverlayWithRadius:(CGFloat)radius {
    if (LGIsSearchPillFilterType(_lgFilterType)) {
        [_nativeBlurView removeFromSuperview];
        _nativeBlurView = nil;
        _nativeBlurRadius = 0.0;
        return;
    }

    if (radius <= 0.0) {
        [_nativeBlurView removeFromSuperview];
        _nativeBlurView = nil;
        _nativeBlurRadius = 0.0;
        return;
    }

    if (!_nativeBlurView) {
        Class blurClass = NSClassFromString(@"LGSettingsLowBlurView");
        if (!blurClass) return;
        _nativeBlurView = [[blurClass alloc] initWithFrame:self.bounds];
        _nativeBlurView.userInteractionEnabled = NO;
        [self insertSubview:_nativeBlurView atIndex:0];
    }

    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    _nativeBlurView.frame = self.bounds;
    _nativeBlurView.layer.cornerRadius = self.layer.cornerRadius;
    _nativeBlurView.layer.cornerCurve = self.layer.cornerCurve;
    _nativeBlurView.clipsToBounds = YES;
    if (fabs(_nativeBlurRadius - radius) > 0.001) {
        @try { [_nativeBlurView setValue:@(radius) forKey:@"lgBlurRadius"]; }
        @catch (__unused NSException *exception) {}
        _nativeBlurRadius = radius;
    }
    [CATransaction commit];
}

- (void)setLgShapeRect:(CGRect)rect {
    if (CGRectEqualToRect(_lgShapeRect, rect)) return;
    _lgShapeRect = rect;
    if (LGHostIdentifierForFilterType(_lgFilterType.UTF8String) ==
        LGHostIdentifierKeyboard) {
        _filterAttached = NO;
        [self applyFilters];
    }
    [self updateSpecular];
}

- (void)setLgShapeCornerRadius:(CGFloat)radius {
    if (fabs(_lgShapeCornerRadius - radius) < 0.01) return;
    _lgShapeCornerRadius = radius;
    if (LGHostIdentifierForFilterType(_lgFilterType.UTF8String) ==
        LGHostIdentifierKeyboard) {
        _filterAttached = NO;
        [self applyFilters];
    }
    [self updateSpecular];
}

- (void)updateSpecular {
    if (CGRectIsEmpty(self.bounds)) return;

    BOOL hasShape = !CGRectIsNull(_lgShapeRect) && !CGRectIsEmpty(_lgShapeRect);
    CGRect shapeRect = hasShape ? _lgShapeRect : self.bounds;
    CGFloat shapeRadius = hasShape ? _lgShapeCornerRadius
                                   : self.layer.cornerRadius;

    NSNumber *override = self.lgSpecularEnabledOverride;
    BOOL enabled = override ? override.boolValue
                            : LGSpecularEnabledForFilterType(_lgFilterType);
    const LGHostDefinition *host = LGHostDefinitionForFilterType(_lgFilterType.UTF8String);
    if (host == &kLGHostRegistry[LGHostIdentifierClock]) return;
    if (!enabled && !_specularLayer) return;

    if (!_edge) {
        _edge = [CAShapeLayer layer];
        _edge.backgroundColor = UIColor.clearColor.CGColor;
        _edge.borderWidth = kLGGlassEdgeWidth;
        [self.layer addSublayer:_edge];
    }

    CGFloat maxAlpha = 0.35;
    if (host) {
        NSString *prefix = [NSString stringWithUTF8String:host->preferencePrefix];
        id value = prefix.length
            ? LGGlassPreferenceValue([prefix stringByAppendingString:@".SpecularOpacity"])
            : nil;
        if ([value respondsToSelector:@selector(doubleValue)])
            maxAlpha = [value doubleValue];
        else if (host->specularOpacity > 0.001f)
            maxAlpha = host->specularOpacity;
    }
    maxAlpha = fmax(0.0, fmin(1.0, maxAlpha));

    if (!_specularLayer) {
        _specularLayer = [CAGradientLayer layer];
        _specularLayer.locations = @[@0.0, @0.12, @0.34, @0.66, @0.88, @1.0];
        _specularMask = [CAShapeLayer layer];
        _specularMask.backgroundColor = UIColor.clearColor.CGColor;
        _specularMask.borderColor = UIColor.blackColor.CGColor;
        _specularMask.borderWidth = 1.0;
        _specularLayer.mask = _specularMask;
        [self.layer addSublayer:_specularLayer];
    }
    if (fabs(_appliedSpecularOpacity - maxAlpha) > 0.001) {
        id clear = (id)UIColor.clearColor.CGColor;
        _specularLayer.colors = @[
            (id)[UIColor colorWithWhite:1.0 alpha:maxAlpha * 0.28].CGColor,
            (id)[UIColor colorWithWhite:1.0 alpha:maxAlpha * 0.10].CGColor,
            clear, clear,
            (id)[UIColor colorWithWhite:0.0 alpha:maxAlpha * 0.04].CGColor,
            (id)[UIColor colorWithWhite:1.0 alpha:maxAlpha * 0.12].CGColor
        ];
        _appliedSpecularOpacity = maxAlpha;
    }

    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    _specularLayer.hidden = !enabled;
    _specularLayer.frame = shapeRect;
    UIColor *edgeColor = [UIColor.separatorColor colorWithAlphaComponent:0.16];
    if (@available(iOS 13.0, *))
        edgeColor = [edgeColor resolvedColorWithTraitCollection:self.traitCollection];
    _edge.hidden = NO;
    _edge.frame = shapeRect;
    _edge.cornerRadius = shapeRadius;
    _edge.cornerCurve = self.layer.cornerCurve;
    _edge.borderWidth = kLGGlassEdgeWidth;
    _edge.borderColor = edgeColor.CGColor;

    _specularMask.frame = CGRectMake(0.0, 0.0, CGRectGetWidth(shapeRect),
                                     CGRectGetHeight(shapeRect));
    _specularMask.cornerRadius = shapeRadius;
    _specularMask.cornerCurve = self.layer.cornerCurve;
    _specularMask.borderWidth = 1.0;
    [CATransaction commit];
    [self applySpecularAngle:sLGSpecularAngle];
}

- (void)applySpecularAngle:(CGFloat)angle {
    if (!_specularLayer) return;
    CGFloat dx = cos(angle) * 0.5;
    CGFloat dy = sin(angle) * 0.5;
    _specularLayer.startPoint = CGPointMake(0.5 + dx, 0.5 + dy);
    _specularLayer.endPoint = CGPointMake(0.5 - dx, 0.5 - dy);
}

- (void)applyFilters {
    CALayer *layer = self.layer;
    Class backdropCls = NSClassFromString(@"CABackdropLayer");
    if (!backdropCls || ![layer isKindOfClass:backdropCls]) return;

    @try {

        if (!_backdropConfigured) {
            // these private flags keep capture in render server space
            [layer setValue:@NO  forKey:@"layerUsesCoreImageFilters"];
            [layer setValue:@NO forKey:@"windowServerAware"];
            [layer setValue:_lgGroupName forKey:@"groupName"];
            [layer setValue:@"dylv.liquidglass" forKey:@"groupNamespace"];

            [layer setValue:@YES forKey:@"ignoresScreenClip"];
            _backdropConfigured = YES;
        }

        CGFloat wantScale;
        enum LGHostIdentifier hostIdentifier =
            LGHostIdentifierForFilterType(_lgFilterType.UTF8String);
        if (hostIdentifier == LGHostIdentifierClock) {
            wantScale = kLGClockCaptureScale;
        } else if (hostIdentifier == LGHostIdentifierCoverSheet ||
                   hostIdentifier == LGHostIdentifierTabBar ||
                   hostIdentifier == LGHostIdentifierTabBarSelection) {
            wantScale = 1.0;
        } else {
            wantScale = LGUsesPrefsControlCaptureScale(_lgFilterType)
                ? kLGPrefsControlScale : LGScaleForSize(self.bounds.size);
        }
        CGFloat wantZoom = _lgBackdropZoom > 0.0 ? _lgBackdropZoom : 1.0;
        BOOL zoomRelevant = fabs(wantZoom - 1.0) > 0.001 || _appliedBackdropZoom > 0.0;
        if (zoomRelevant && fabs(wantZoom - _appliedBackdropZoom) > 0.001) {
            _appliedBackdropZoom = wantZoom;
            @try { [layer setValue:@(wantZoom) forKey:@"zoom"]; }
            @catch (__unused NSException *exception) {}
            LGLog(@"glass#%u zoom type=%@ want=%.3f readback=%@", _lgId,
                  _lgFilterType ?: @"default", wantZoom,
                  [layer valueForKey:@"zoom"] ?: @"<none>");
        }

        if (fabs(wantScale - _appliedScale) > 0.02) {
            [layer setValue:@(wantScale) forKey:@"scale"];
            _appliedScale = wantScale;
        }

        NSString *wantType = [self lgEffectiveFilterType];
        NSArray *existing = layer.filters;
        Class filterCls = NSClassFromString(@"CAFilter");
        [self updateNativeBlurOverlayWithRadius:
            LGNativeBlurRadiusForFilterType(_lgFilterType ?: wantType)];

        if (_filterAttached && existing.count == 1) {
            NSString *type = nil;
            @try { type = [existing.firstObject valueForKey:@"type"]; } @catch (...) {}
            if ([type isEqualToString:wantType]) {
                return;
            }
        }
        if (!filterCls) { sblog("CAFilter class not found"); return; }

        id glassFilter = ((id (*)(Class, SEL, NSString *))objc_msgSend)(
            filterCls, NSSelectorFromString(@"filterWithType:"), wantType);

        if (!glassFilter && LGIsSearchPillFilterType(_lgFilterType)) {
            // The full Liquid (Gl)ass refraction filter is registered by the
            // upstream backboardd component. SearchGlass can also run by
            // itself, so provide a clean full-surface fallback instead of
            // falling back to LGSettingsLowBlurView.
            glassFilter = ((id (*)(Class, SEL, NSString *))objc_msgSend)(
                filterCls, NSSelectorFromString(@"filterWithType:"), @"gaussianBlur");

            if (glassFilter) {
                @try {
                    [glassFilter setValue:@(LGSearchPillFallbackBlurRadius())
                                    forKey:@"inputRadius"];
                } @catch (...) {}
                LGLog(@"glass#%u using full-pill gaussian fallback", _lgId);
            }
        }

        if (!glassFilter) {
            LGLog(@"glass#%u filterWithType nil (not registered yet?)", _lgId);
            return;
        }

        if (LGNeedsGaussianIdentityFallback()) {
            @try { [glassFilter setValue:@1.0 forKey:@"inputRadius"]; }
            @catch (...) {}
        }

        layer.filters = @[glassFilter];
        _filterAttached = YES;
        [[NSNotificationCenter defaultCenter]
            postNotificationName:@"LGLiveBackdropViewFilterDidAttach" object:self];
    } @catch (NSException *e) {
        sblog("applyFilters exception: %s", e.reason.UTF8String);
    }
}

- (void)reapplyFilterForParameterReload {

    _parameterRefreshVariant = !_parameterRefreshVariant;

    _appliedScale = -1.0;
    _filterAttached = NO;
    [self applyFilters];
    [self updateSpecular];
    [self.layer setNeedsDisplay];
    [_specularLayer setNeedsDisplay];
}

- (void)lgInvalidateFilterContents {
    _parameterRefreshVariant = !_parameterRefreshVariant;
    _filterAttached = NO;
    [self applyFilters];
    [self.layer setNeedsDisplay];
}

- (BOOL)lgFilterAttached {
    return _filterAttached;
}

@end

#pragma mark - generic host injection

static CGRect LGOutsetFrame(CGRect mf, UIEdgeInsets outset) {
    return CGRectMake(mf.origin.x - outset.left,
                      mf.origin.y - outset.top,
                      mf.size.width  + outset.left + outset.right,
                      mf.size.height + outset.top  + outset.bottom);
}

void LGInjectGlassIntoMaterialGroupType(UIView *mat, const void *assocKey,
                                        UIEdgeInsets outset, CGFloat cornerRadius,
                                        NSString *groupName, NSString *filterType) {
    UIView *parent = mat.superview;
    if (!parent) return;

    CGRect gf = LGOutsetFrame(mat.frame, outset);

    LGLiveBackdropView *glass = objc_getAssociatedObject(mat, assocKey);
    if (!glass) {
        glass = [[LGLiveBackdropView alloc] initWithFrame:gf groupName:groupName filterType:filterType];
        __weak LGLiveBackdropView *weakGlass = glass;
        for (NSNumber *delay in @[ @1.5, @3.0, @5.0, @8.0, @12.0 ]) {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay.doubleValue * NSEC_PER_SEC)),
                           dispatch_get_main_queue(), ^{
                [weakGlass applyFilters];
            });
        }
        [parent insertSubview:glass aboveSubview:mat];
        objc_setAssociatedObject(mat, assocKey, glass, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    if (glass.superview != parent) [parent insertSubview:glass aboveSubview:mat];
    CGFloat radius = (cornerRadius >= 0.0) ? cornerRadius : mat.layer.cornerRadius;
    if (!CGRectEqualToRect(glass.frame, gf))          glass.frame              = gf;
    if (fabs(glass.layer.cornerRadius - radius) > 0.5) {
        glass.layer.cornerRadius = radius;
        [glass updateSpecular];
        [glass applyFilters];
    }
    glass.layer.cornerCurve   = kCACornerCurveContinuous;
    glass.layer.masksToBounds = YES;

    objc_setAssociatedObject(glass, kLGOutsetKey, [NSValue valueWithUIEdgeInsets:outset],
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(glass, kLGRadiusKey, @(cornerRadius), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    if (!mat.hidden) mat.hidden = YES;
}

static void LGSyncGlassGeometry(UIView *mat, const void *assocKey,
                                UIEdgeInsets outset, CGFloat cornerRadius);

void LGResyncGlassGeometry(UIView *mat, const void *assocKey) {
    LGLiveBackdropView *glass = objc_getAssociatedObject(mat, assocKey);
    if (!glass) return;
    NSValue *ov  = objc_getAssociatedObject(glass, kLGOutsetKey);
    NSNumber *rv = objc_getAssociatedObject(glass, kLGRadiusKey);
    LGSyncGlassGeometry(mat, assocKey, ov ? ov.UIEdgeInsetsValue : UIEdgeInsetsZero,
                        rv ? rv.doubleValue : -1.0);
}

static void LGSyncGlassGeometry(UIView *mat, const void *assocKey,
                                UIEdgeInsets outset, CGFloat cornerRadius) {
    LGLiveBackdropView *glass = objc_getAssociatedObject(mat, assocKey);
    if (!glass) return;
    CGRect gf = LGOutsetFrame(mat.frame, outset);
    CGFloat radius = (cornerRadius >= 0.0) ? cornerRadius : mat.layer.cornerRadius;

    if (!CGRectEqualToRect(glass.frame, gf)) {
        glass.frame = gf;
    }
    if (fabs(glass.layer.cornerRadius - radius) > 0.5) {
        glass.layer.cornerRadius = radius;
        [glass updateSpecular];
        [glass applyFilters];
    }
    if (!mat.hidden) mat.hidden = YES;
}

void LGRemoveGlassFromMaterial(UIView *mat, const void *assocKey) {
    LGLiveBackdropView *glass = objc_getAssociatedObject(mat, assocKey);
    if (!glass) return;
    objc_setAssociatedObject(mat, assocKey, nil, OBJC_ASSOCIATION_ASSIGN);
    mat.hidden = NO;

    [glass removeFromSuperview];
}

BOOL LGMaterialHasGlass(UIView *mat, const void *assocKey) {
    return objc_getAssociatedObject(mat, assocKey) != nil;
}

#pragma mark - Embedded Liquid (Gl)ass LGFramework.h


@interface LGAdjustableBlurView : UIView
@property (nonatomic, assign) CGFloat cornerRadius;
@property (nonatomic, assign) CGFloat blurRadius;
@property (nonatomic, assign) CGFloat qualityScale;
@property (nonatomic, assign) BOOL capturesAppIcon;
- (instancetype)initWithFrame:(CGRect)frame blurRadius:(CGFloat)radius;
- (void)applyFilters;
@end

@interface LGSpecularHighlightView : UIView
@property (nonatomic, assign) CGFloat cornerRadius;
@property (nonatomic, assign) CGFloat strokeWidth;
@property (nonatomic, assign) CGFloat topSpecularOpacity;
@property (nonatomic, assign) CGFloat bottomSpecularOpacity;
- (instancetype)initWithFrame:(CGRect)frame cornerRadius:(CGFloat)cornerRadius;
@end

@interface LGButtonView : UIControl

@property (nonatomic, strong) UIView *backgroundContainer;
@property (nonatomic, strong) LGAdjustableBlurView *blurView;
@property (nonatomic, strong) LGLiveBackdropView *lgView;
@property (nonatomic, strong) UIView *darkTintView;
@property (nonatomic, strong) UIImageView *innerGlowView;
@property (nonatomic, strong) CAGradientLayer *specularRimLayer;
@property (nonatomic, strong) CAShapeLayer *specularMaskLayer;
@property (nonatomic, strong) UIImageView *glyphImageView;
@property (nonatomic, strong) UILabel *titleLabel;

@property (nonatomic, assign) BOOL isPressed;
@property (nonatomic, assign) CGPoint touchStartPoint;
@property (nonatomic, copy) void (^actionHandler)(void);
@property (nonatomic, weak) UINavigationController *navigationController;
@property (nonatomic, strong) UIMenu *primaryMenu;
@property (nonatomic, strong) UIButton *menuAnchorButton;

- (void)setPrimaryMenu:(UIMenu *)menu;
- (void)presentMenu;

- (instancetype)initWithFrame:(CGRect)frame
                    symbolName:(NSString *)symbolName
                    blurRadius:(CGFloat)blurRadius;

- (instancetype)initWithFrame:(CGRect)frame
                        title:(NSString *)title
                    blurRadius:(CGFloat)blurRadius;

- (void)updateLayoutWithFrame:(CGRect)frame;
- (void)refreshGlass;
- (void)handleTouchDownAtPoint:(CGPoint)point;
- (void)handleTouchMovedToPoint:(CGPoint)point;
- (void)handleTouchEnded;
- (void)handleTouchCancelled;

@end

@interface LGLiquidBlockerGesture : UIPanGestureRecognizer <UIGestureRecognizerDelegate>
@end


#pragma mark - Embedded Liquid (Gl)ass LGFramework.m


@implementation LGAdjustableBlurView

+ (Class)layerClass {
    return NSClassFromString(@"CABackdropLayer") ?: CALayer.class;
}

- (instancetype)initWithFrame:(CGRect)frame blurRadius:(CGFloat)radius {
    self = [super initWithFrame:frame];
    if (!self) return nil;
    _blurRadius = radius;
    _qualityScale = 0.35;
    self.userInteractionEnabled = NO;
    self.backgroundColor = UIColor.clearColor;
    self.opaque = NO;
    self.layer.cornerCurve = kCACornerCurveContinuous;
    [self applyFilters];
    return self;
}

- (void)setCornerRadius:(CGFloat)cornerRadius {
    _cornerRadius = cornerRadius;
    self.layer.cornerRadius = cornerRadius;
    self.layer.cornerCurve = kCACornerCurveContinuous;
    self.layer.masksToBounds = YES;
}

- (void)didMoveToWindow {
    [super didMoveToWindow];
    [self applyFilters];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    [self applyFilters];
}

- (void)setBlurRadius:(CGFloat)blurRadius {
    if (fabs(_blurRadius - blurRadius) <= 0.01) return;
    _blurRadius = blurRadius;
    [self applyFilters];
}

- (void)applyFilters {
    CALayer *layer = self.layer;
    Class backdropClass = NSClassFromString(@"CABackdropLayer");
    if (!backdropClass || ![layer isKindOfClass:backdropClass]) return;

    @try {
        if (self.blurRadius <= 0.0) {
            layer.filters = nil;
            return;
        }
        [layer setValue:@NO forKey:@"layerUsesCoreImageFilters"];
        [layer setValue:@(!self.capturesAppIcon) forKey:@"windowServerAware"];
        if (self.capturesAppIcon) {
            [layer setValue:[NSString stringWithFormat:@"dylv.liquidglass.blur.%p", self]
                     forKey:@"groupName"];
        }
        [layer setValue:@(self.qualityScale) forKey:@"scale"];

        NSArray *existing = layer.filters;
        if (existing.count == 1) {
            NSString *type = nil;
            @try { type = [existing.firstObject valueForKey:@"type"]; } @catch (...) {}
            if ([type isEqualToString:@"gaussianBlur"]) {
                NSNumber *radius = nil;
                @try { radius = [existing.firstObject valueForKey:@"inputRadius"]; } @catch (...) {}
                if (radius && fabs(radius.doubleValue - self.blurRadius) < 0.01) return;
            }
        }

        Class filterClass = NSClassFromString(@"CAFilter");
        if (!filterClass) return;
        id filter = ((id (*)(Class, SEL, NSString *))objc_msgSend)(
            filterClass, NSSelectorFromString(@"filterWithType:"), @"gaussianBlur");
        if (filter) {
            [filter setValue:@(self.blurRadius) forKey:@"inputRadius"];
            layer.filters = @[filter];
        }
    } @catch (__unused NSException *exception) {}
}

@end

static UIImage *CreateRadialGlowImage(CGFloat diameter) {
    CGSize size = CGSizeMake(diameter, diameter);
    UIGraphicsBeginImageContextWithOptions(size, NO, 0.0);
    CGContextRef ctx = UIGraphicsGetCurrentContext();
    if (!ctx) return nil;

    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
    NSArray *colors = @[(id)[UIColor colorWithWhite:1.0 alpha:0.95].CGColor,
                        (id)[UIColor colorWithWhite:1.0 alpha:0.60].CGColor,
                        (id)[UIColor colorWithWhite:1.0 alpha:0.0].CGColor];
    CGFloat locations[] = {0.0, 0.35, 1.0};
    CGGradientRef gradient = CGGradientCreateWithColors(colorSpace, (__bridge CFArrayRef)colors, locations);

    CGPoint center = CGPointMake(diameter / 2.0, diameter / 2.0);
    CGContextDrawRadialGradient(ctx, gradient, center, 0.0, center, diameter / 2.0, kCGGradientDrawsAfterEndLocation);

    CGGradientRelease(gradient);
    CGColorSpaceRelease(colorSpace);

    UIImage *img = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return img;
}

@interface LGButtonView ()
@property (nonatomic, assign) NSTimeInterval touchDownTime;
@property (nonatomic, assign) uint64_t touchCycleId;
@end

@interface LGSpecularHighlightView ()
@property (nonatomic, strong) CAGradientLayer *specularRim;
@property (nonatomic, strong) CAShapeLayer *rimMask;
@end

@implementation LGSpecularHighlightView

- (instancetype)initWithFrame:(CGRect)frame {
    return [self initWithFrame:frame cornerRadius:40.0];
}

- (instancetype)initWithFrame:(CGRect)frame cornerRadius:(CGFloat)cornerRadius {
    self = [super initWithFrame:frame];
    if (self) {
        _cornerRadius = cornerRadius;
        _strokeWidth = 1.5;
        _topSpecularOpacity = 0.65;
        _bottomSpecularOpacity = 0.35;
        self.userInteractionEnabled = NO;
        self.backgroundColor = UIColor.clearColor;
        self.specularRim = [CAGradientLayer layer];
        self.specularRim.colors = @[(id)[UIColor colorWithWhite:1.0 alpha:_topSpecularOpacity].CGColor,
                                    (id)[UIColor colorWithWhite:1.0 alpha:0.0].CGColor,
                                    (id)[UIColor colorWithWhite:1.0 alpha:0.0].CGColor,
                                    (id)[UIColor colorWithWhite:1.0 alpha:_bottomSpecularOpacity].CGColor];
        self.specularRim.locations = @[@0.0, @0.35, @0.65, @1.0];
        self.specularRim.startPoint = CGPointMake(0, 0);
        self.specularRim.endPoint = CGPointMake(1, 1);
        self.rimMask = [CAShapeLayer layer];
        self.rimMask.fillColor = UIColor.clearColor.CGColor;
        self.rimMask.strokeColor = UIColor.whiteColor.CGColor;
        self.rimMask.lineWidth = _strokeWidth;
        self.specularRim.mask = self.rimMask;
        [self.layer addSublayer:self.specularRim];
    }
    return self;
}

- (void)setCornerRadius:(CGFloat)cornerRadius {
    _cornerRadius = cornerRadius;
    self.rimMask.path = [UIBezierPath bezierPathWithRoundedRect:self.bounds
                                                  cornerRadius:cornerRadius].CGPath;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    self.specularRim.frame = self.bounds;
    self.rimMask.lineWidth = self.strokeWidth;
    self.rimMask.path = [UIBezierPath bezierPathWithRoundedRect:self.bounds
                                                  cornerRadius:self.cornerRadius].CGPath;
}

@end

@implementation LGButtonView

- (void)commonInitWithBlurRadius:(CGFloat)blurRadius {
    self.clipsToBounds = NO;
    self.layer.masksToBounds = NO;
    self.backgroundColor = [UIColor clearColor];

    BOOL isCircular = fabs(self.bounds.size.width - self.bounds.size.height) < 1.0;
    CGFloat radius = MIN(self.bounds.size.width, self.bounds.size.height) * 0.5;
    CALayerCornerCurve curve = isCircular ? kCACornerCurveCircular : kCACornerCurveContinuous;

    self.backgroundContainer = [[UIView alloc] initWithFrame:self.bounds];
    self.backgroundContainer.clipsToBounds = NO;
    self.backgroundContainer.layer.cornerRadius = radius;
    self.backgroundContainer.layer.cornerCurve = curve;
    self.backgroundContainer.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.04];
    self.backgroundContainer.userInteractionEnabled = NO;
    [self addSubview:self.backgroundContainer];

    CAShapeLayer *containerMask = [CAShapeLayer layer];
    UIBezierPath *maskPath = isCircular ?
        [UIBezierPath bezierPathWithOvalInRect:self.backgroundContainer.bounds] :
        [UIBezierPath bezierPathWithRoundedRect:self.backgroundContainer.bounds cornerRadius:radius];
    containerMask.path = maskPath.CGPath;
    self.backgroundContainer.layer.mask = containerMask;

    self.blurView = [[LGAdjustableBlurView alloc] initWithFrame:self.backgroundContainer.bounds blurRadius:blurRadius];
    self.blurView.qualityScale = 0.35;
    self.blurView.clipsToBounds = NO;
    self.blurView.layer.cornerRadius = radius;
    self.blurView.layer.cornerCurve = curve;
    self.blurView.tag = 996;
    [self.backgroundContainer addSubview:self.blurView];

    self.lgView = [[LGLiveBackdropView alloc] initWithFrame:self.backgroundContainer.bounds
                                                  groupName:nil
                                                 filterType:LGFilterTypeForHostPrefix(@"PrefsButton")];
    self.lgView.clipsToBounds = NO;
    self.lgView.layer.cornerRadius = radius;
    self.lgView.layer.cornerCurve = curve;
    self.lgView.tag = 998;
    [self.backgroundContainer addSubview:self.lgView];

    self.darkTintView = [[UIView alloc] initWithFrame:self.backgroundContainer.bounds];
    self.darkTintView.userInteractionEnabled = NO;
    self.darkTintView.clipsToBounds = NO;
    self.darkTintView.layer.cornerRadius = radius;
    self.darkTintView.layer.cornerCurve = curve;
    self.darkTintView.backgroundColor = [UIColor colorWithDynamicProvider:^UIColor *(UITraitCollection *trait) {
        return trait.userInterfaceStyle == UIUserInterfaceStyleDark
            ? [UIColor colorWithWhite:1.0 alpha:0.06] : [UIColor colorWithWhite:1.0 alpha:0.12];
    }];
    [self.backgroundContainer addSubview:self.darkTintView];

    CGFloat glowDiameter = MAX(self.bounds.size.width, self.bounds.size.height) * 2.2;
    self.innerGlowView = [[UIImageView alloc] initWithImage:CreateRadialGlowImage(glowDiameter)];
    self.innerGlowView.frame = CGRectMake(0, 0, glowDiameter, glowDiameter);
    self.innerGlowView.center = CGPointMake(self.bounds.size.width / 2.0, self.bounds.size.height / 2.0);
    self.innerGlowView.alpha = 0.0;
    [self.backgroundContainer addSubview:self.innerGlowView];

    self.specularRimLayer = [CAGradientLayer layer];
    self.specularRimLayer.frame = self.backgroundContainer.bounds;
    self.specularRimLayer.startPoint = CGPointMake(0, 0);
    self.specularRimLayer.endPoint = CGPointMake(1, 1);
    self.specularRimLayer.colors = @[(id)[UIColor colorWithWhite:1.0 alpha:0.75].CGColor,
                                     (id)[UIColor colorWithWhite:1.0 alpha:0.0].CGColor,
                                     (id)[UIColor colorWithWhite:1.0 alpha:0.0].CGColor,
                                     (id)[UIColor colorWithWhite:1.0 alpha:0.75].CGColor];
    self.specularRimLayer.locations = @[@0.0, @0.28, @0.72, @1.0];

    self.specularMaskLayer = [CAShapeLayer layer];
    UIBezierPath *rimPath = isCircular ?
        [UIBezierPath bezierPathWithOvalInRect:self.backgroundContainer.bounds] :
        [UIBezierPath bezierPathWithRoundedRect:self.backgroundContainer.bounds cornerRadius:radius];
    self.specularMaskLayer.path = rimPath.CGPath;
    self.specularMaskLayer.fillColor = [UIColor clearColor].CGColor;
    self.specularMaskLayer.strokeColor = [UIColor whiteColor].CGColor;
    self.specularMaskLayer.lineWidth = 1.2;
    self.specularRimLayer.mask = self.specularMaskLayer;
    [self.backgroundContainer.layer addSublayer:self.specularRimLayer];
}

- (instancetype)initWithFrame:(CGRect)frame symbolName:(NSString *)symbolName blurRadius:(CGFloat)blurRadius {
    self = [super initWithFrame:frame];
    if (self) {
        [self commonInitWithBlurRadius:blurRadius];
        UIImageSymbolConfiguration *config = [UIImageSymbolConfiguration configurationWithPointSize:21.0 weight:UIImageSymbolWeightSemibold];
        self.glyphImageView = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:symbolName withConfiguration:config]];
        self.glyphImageView.contentMode = UIViewContentModeCenter;
        self.glyphImageView.tintColor = [UIColor labelColor];
        self.glyphImageView.frame = self.bounds;
        self.glyphImageView.userInteractionEnabled = NO;
        [self addSubview:self.glyphImageView];
    }
    return self;
}

- (instancetype)initWithFrame:(CGRect)frame title:(NSString *)title blurRadius:(CGFloat)blurRadius {
    self = [super initWithFrame:frame];
    if (self) {
        [self commonInitWithBlurRadius:blurRadius];
        self.titleLabel = [[UILabel alloc] initWithFrame:self.bounds];
        self.titleLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightMedium];
        self.titleLabel.textColor = [UIColor labelColor];
        self.titleLabel.textAlignment = NSTextAlignmentCenter;
        self.titleLabel.text = title;
        self.titleLabel.tag = 997;
        self.titleLabel.userInteractionEnabled = NO;
        [self addSubview:self.titleLabel];
    }
    return self;
}

- (void)updateLayoutWithFrame:(CGRect)frame {
    self.frame = frame;
    [self updateShapeWithTransform:CGAffineTransformIdentity shiftX:0 shiftY:0];
    if (self.titleLabel) self.titleLabel.frame = self.bounds;
    if (self.glyphImageView) self.glyphImageView.frame = self.bounds;
    if (self.menuAnchorButton) self.menuAnchorButton.frame = self.bounds;
}

- (CGSize)intrinsicContentSize {
    return self.bounds.size.width > 0 ? self.bounds.size : CGSizeMake(44.0, 44.0);
}

- (void)refreshGlass {
    [self.lgView applyFilters];
    [self.blurView applyFilters];
}

- (void)didMoveToSuperview {
    [super didMoveToSuperview];
    [self unclipHierarchy];
}

- (void)didMoveToWindow {
    [super didMoveToWindow];
    [self unclipHierarchy];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    [self unclipHierarchy];

    BOOL isCircular = fabs(self.bounds.size.width - self.bounds.size.height) < 1.0;
    CGFloat radius = MIN(self.bounds.size.width, self.bounds.size.height) * 0.5;
    CALayerCornerCurve curve = isCircular ? kCACornerCurveCircular : kCACornerCurveContinuous;

    if (self.backgroundContainer && !CGSizeEqualToSize(self.backgroundContainer.bounds.size, self.bounds.size)) {
        self.backgroundContainer.frame = self.bounds;
        self.blurView.frame = self.backgroundContainer.bounds;
        self.lgView.frame = self.backgroundContainer.bounds;
        self.darkTintView.frame = self.backgroundContainer.bounds;
        self.specularRimLayer.frame = self.backgroundContainer.bounds;

        self.backgroundContainer.layer.cornerRadius = radius;
        self.backgroundContainer.layer.cornerCurve = curve;
        self.blurView.layer.cornerRadius = radius;
        self.blurView.layer.cornerCurve = curve;
        self.lgView.layer.cornerRadius = radius;
        self.lgView.layer.cornerCurve = curve;
        self.darkTintView.layer.cornerRadius = radius;
        self.darkTintView.layer.cornerCurve = curve;
    }

    UIBezierPath *path = isCircular ?
        [UIBezierPath bezierPathWithOvalInRect:self.backgroundContainer.bounds] :
        [UIBezierPath bezierPathWithRoundedRect:self.backgroundContainer.bounds cornerRadius:radius];

    if (self.backgroundContainer.layer.mask && [self.backgroundContainer.layer.mask isKindOfClass:[CAShapeLayer class]]) {
        ((CAShapeLayer *)self.backgroundContainer.layer.mask).path = path.CGPath;
    }
    if (self.specularMaskLayer) {
        self.specularMaskLayer.path = path.CGPath;
    }
    if (self.menuAnchorButton) {
        self.menuAnchorButton.frame = self.bounds;
    }
}

- (void)unclipHierarchy {
    self.clipsToBounds = NO;
    self.layer.masksToBounds = NO;
    self.layer.zPosition = 9999;

    UIView *cur = self.superview;
    while (cur) {
        cur.clipsToBounds = NO;
        cur.layer.masksToBounds = NO;
        cur = cur.superview;
    }
}

static void LGDumpSubviewsAndLayers(UIView *view, int indent, NSMutableString *out) {
    if (!view) return;
    NSString *ind = [@"" stringByPaddingToLength:indent * 2 withString:@" " startingAtIndex:0];
    CALayer *l = view.layer;
    [out appendFormat:@"%@V[%@]: frame=%@ bounds=%@ clips=%d masks=%d mask=%@ radius=%.1f transform=%@\n",
        ind, NSStringFromClass(view.class), NSStringFromCGRect(view.frame), NSStringFromCGRect(view.bounds),
        view.clipsToBounds, l.masksToBounds, l.mask ? NSStringFromClass(l.mask.class) : @"nil",
        l.cornerRadius, NSStringFromCGAffineTransform(view.transform)];

    for (CALayer *sublayer in l.sublayers) {
        if (sublayer.delegate != (id)view) {
            [out appendFormat:@"%@  L[%@]: frame=%@ bounds=%@ masks=%d mask=%@ radius=%.1f\n",
                ind, NSStringFromClass(sublayer.class), NSStringFromCGRect(sublayer.frame), NSStringFromCGRect(sublayer.bounds),
                sublayer.masksToBounds, sublayer.mask ? NSStringFromClass(sublayer.mask.class) : @"nil",
                sublayer.cornerRadius];
        }
    }

    for (UIView *sub in view.subviews) {
        LGDumpSubviewsAndLayers(sub, indent + 1, out);
    }
}

static void LGDumpButtonHierarchy(UIView *view) {
    @try {
        NSMutableString *str = [NSMutableString string];
        [str appendFormat:@"\n=== LGButtonView Hierarchy Dump ===\n"];
        [str appendFormat:@"--- Button Tree ---\n"];
        LGDumpSubviewsAndLayers(view, 0, str);

        [str appendFormat:@"--- Layer Superlayers ---\n"];
        CALayer *curLayer = view.layer;
        int layerDepth = 0;
        while (curLayer) {
            [str appendFormat:@"Layer[%d]: %@, frame=%@, bounds=%@, masks=%d, mask=%@, cornerRadius=%.1f, zPos=%.1f\n",
                layerDepth, NSStringFromClass(curLayer.class), NSStringFromCGRect(curLayer.frame), NSStringFromCGRect(curLayer.bounds),
                curLayer.masksToBounds, curLayer.mask ? NSStringFromClass(curLayer.mask.class) : @"nil",
                curLayer.cornerRadius, curLayer.zPosition];
            curLayer = curLayer.superlayer;
            layerDepth++;
        }

        [str appendFormat:@"--- View Superviews ---\n"];
        UIView *cur = view.superview;
        int depth = 1;
        while (cur) {
            [str appendFormat:@"Super[%d]: %@, frame: %@, bounds: %@, clips: %d, masks: %d, hasMaskLayer: %d, zPos: %.1f\n",
                depth, NSStringFromClass(cur.class), NSStringFromCGRect(cur.frame), NSStringFromCGRect(cur.bounds),
                cur.clipsToBounds, cur.layer.masksToBounds, (cur.layer.mask != nil), cur.layer.zPosition];
            cur = cur.superview;
            depth++;
        }

        if (view.superview) {
            [str appendFormat:@"--- Siblings in Superview (%@) ---\n", NSStringFromClass(view.superview.class)];
            for (UIView *sib in view.superview.subviews) {
                [str appendFormat:@"Sibling: %@, frame: %@, hidden: %d, alpha: %.2f, zPos: %.1f\n",
                    NSStringFromClass(sib.class), NSStringFromCGRect(sib.frame), sib.hidden, sib.alpha, sib.layer.zPosition];
            }
        }

        [str writeToFile:@"/var/tmp/button_obstruction_dump.txt" atomically:YES encoding:NSUTF8StringEncoding error:nil];
    } @catch (...) {}
}

- (void)updateShapeWithTransform:(CGAffineTransform)transform shiftX:(CGFloat)shiftX shiftY:(CGFloat)shiftY {
    self.backgroundContainer.transform = transform;
    if (self.glyphImageView) {
        self.glyphImageView.transform = transform;
    }
    if (self.titleLabel) {
        self.titleLabel.transform = transform;
    }
}

- (void)updateGlowPositionWithTouchPoint:(CGPoint)point shiftX:(CGFloat)shiftX shiftY:(CGFloat)shiftY {
    CGFloat cx = self.bounds.size.width / 2.0;
    CGFloat cy = self.bounds.size.height / 2.0;

    CGFloat dx = point.x - (cx + shiftX);
    CGFloat dy = point.y - (cy + shiftY);

    CGFloat R = MAX(self.bounds.size.width, self.bounds.size.height) * 0.5;
    CGFloat dist = sqrt(dx * dx + dy * dy);
    if (dist > R && dist > 0.001) {
        dx = (dx / dist) * R;
        dy = (dy / dist) * R;
    }

    self.innerGlowView.center = CGPointMake(cx + dx, cy + dy);
}

- (void)setPrimaryMenu:(UIMenu *)menu {
    _primaryMenu = menu;
    if (menu) {
        if (!self.menuAnchorButton) {
            self.menuAnchorButton = [UIButton buttonWithType:UIButtonTypeCustom];
            self.menuAnchorButton.frame = self.bounds;
            self.menuAnchorButton.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
            self.menuAnchorButton.backgroundColor = [UIColor clearColor];
            self.menuAnchorButton.clipsToBounds = NO;
            self.menuAnchorButton.layer.masksToBounds = NO;
            [self.menuAnchorButton addTarget:self action:@selector(lg_menuButtonTouchDown) forControlEvents:UIControlEventTouchDown];
            [self.menuAnchorButton addTarget:self action:@selector(lg_menuButtonTouchUp) forControlEvents:UIControlEventTouchUpInside | UIControlEventTouchUpOutside | UIControlEventTouchCancel];
            [self.menuAnchorButton addTarget:self action:@selector(lg_menuButtonTouchMoved:forEvent:) forControlEvents:UIControlEventTouchDragInside | UIControlEventTouchDragOutside];
            [self addSubview:self.menuAnchorButton];
            [self bringSubviewToFront:self.menuAnchorButton];
        }
        self.menuAnchorButton.menu = menu;
        self.menuAnchorButton.showsMenuAsPrimaryAction = YES;
    } else {
        [self.menuAnchorButton removeFromSuperview];
        self.menuAnchorButton = nil;
    }
}

- (void)lg_menuButtonTouchDown {
    [self handleTouchDownAtPoint:CGPointMake(self.bounds.size.width / 2.0, self.bounds.size.height / 2.0)];
    uint64_t currentCycle = self.touchCycleId;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.22 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (self.isPressed && self.touchCycleId == currentCycle) {
            [self handleTouchEnded];
        }
    });
}

- (void)lg_menuButtonTouchUp {
    [self handleTouchEnded];
}

- (void)lg_menuButtonTouchMoved:(UIButton *)sender forEvent:(UIEvent *)event {
    UITouch *touch = [[event allTouches] anyObject];
    if (touch) {
        [self handleTouchMovedToPoint:[touch locationInView:self]];
    }
}

- (void)presentMenu {
    if (!self.primaryMenu) return;
    if (self.menuAnchorButton && self.menuAnchorButton.contextMenuInteraction && [self.menuAnchorButton.contextMenuInteraction respondsToSelector:@selector(_presentMenuAtLocation:)]) {
        CGPoint center = CGPointMake(CGRectGetMidX(self.menuAnchorButton.bounds), CGRectGetMidY(self.menuAnchorButton.bounds));
        ((void (*)(id, SEL, CGPoint))objc_msgSend)(self.menuAnchorButton.contextMenuInteraction, @selector(_presentMenuAtLocation:), center);
    }
}

- (BOOL)beginTrackingWithTouch:(UITouch *)touch withEvent:(UIEvent *)event {
    CGPoint point = [touch locationInView:self];
    [self handleTouchDownAtPoint:point];
    return YES;
}

- (BOOL)continueTrackingWithTouch:(UITouch *)touch withEvent:(UIEvent *)event {
    CGPoint point = [touch locationInView:self];
    [self handleTouchMovedToPoint:point];
    return YES;
}

- (void)endTrackingWithTouch:(UITouch *)touch withEvent:(UIEvent *)event {
    CGPoint point = [touch locationInView:self];
    CGFloat dx = point.x - self.touchStartPoint.x;
    CGFloat dy = point.y - self.touchStartPoint.y;
    CGFloat dist = sqrt(dx * dx + dy * dy);

    [self handleTouchEnded];

    if (dist < 55.0) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.06 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            if (self.actionHandler) {
                self.actionHandler();
            } else if (self.primaryMenu) {
                [self presentMenu];
            } else {
                [self sendActionsForControlEvents:UIControlEventTouchUpInside];
            }
        });
    } else {
        [self cancelTrackingWithEvent:event];
    }
}

- (void)cancelTrackingWithEvent:(UIEvent *)event {
    [self handleTouchCancelled];
}

- (BOOL)pointInside:(CGPoint)point withEvent:(UIEvent *)event {
    if (self.isPressed) {
        return CGRectContainsPoint(CGRectInset(self.bounds, -90.0, -90.0), point);
    }
    return [super pointInside:point withEvent:event];
}

- (void)handleTouchDownAtPoint:(CGPoint)point {
    self.isPressed = YES;
    self.touchStartPoint = point;
    self.touchDownTime = CACurrentMediaTime();
    self.touchCycleId++;

    [self unclipHierarchy];
    LGDumpButtonHierarchy(self);

    if (self.navigationController && self.navigationController.interactivePopGestureRecognizer) {
        self.navigationController.interactivePopGestureRecognizer.enabled = NO;
    }

    if (@available(iOS 13.0, *)) {
        UIImpactFeedbackGenerator *feedback = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleSoft];
        [feedback prepare];
        [feedback impactOccurred];
    }

    [self updateGlowPositionWithTouchPoint:point shiftX:0 shiftY:0];

    [UIView animateWithDuration:0.18 delay:0 usingSpringWithDamping:0.55 initialSpringVelocity:1.2 options:UIViewAnimationOptionAllowUserInteraction | UIViewAnimationOptionBeginFromCurrentState animations:^{
        CGAffineTransform pressTransform = CGAffineTransformMakeScale(1.10, 1.10);
        [self updateShapeWithTransform:pressTransform shiftX:0 shiftY:0];
        self.innerGlowView.transform = CGAffineTransformIdentity;
        self.innerGlowView.alpha = 0.90;
    } completion:nil];
}

- (void)handleTouchMovedToPoint:(CGPoint)point {
    if (!self.isPressed) {
        self.isPressed = YES;
        self.touchStartPoint = point;
        self.touchDownTime = CACurrentMediaTime();
        self.touchCycleId++;
    }

    [self unclipHierarchy];

    CGFloat dx = point.x - self.touchStartPoint.x;
    CGFloat dy = point.y - self.touchStartPoint.y;
    CGFloat dist = sqrt(dx * dx + dy * dy);

    CGFloat shiftX = 0;
    CGFloat shiftY = 0;
    CGAffineTransform transform = CGAffineTransformIdentity;

    if (dist > 0.5) {
        CGFloat angle = atan2(dy, dx);

        CGFloat maxShift = 28.0;
        CGFloat pullFactor = 1.0 - (1.0 / ((dist * 0.025) + 1.0));
        CGFloat currentShift = pullFactor * maxShift;

        shiftX = cos(angle) * currentShift;
        shiftY = sin(angle) * currentShift;

        CGFloat stretchFactor = 1.10 * (1.0 + (pullFactor * 0.28));
        CGFloat squashFactor = 1.10 * (1.0 - (pullFactor * 0.08));

        transform = CGAffineTransformMakeTranslation(shiftX, shiftY);
        transform = CGAffineTransformRotate(transform, angle);
        transform = CGAffineTransformScale(transform, stretchFactor, squashFactor);
        transform = CGAffineTransformRotate(transform, -angle);
    } else {
        transform = CGAffineTransformMakeScale(1.10, 1.10);
    }

    [self updateShapeWithTransform:transform shiftX:shiftX shiftY:shiftY];
    [self updateGlowPositionWithTouchPoint:point shiftX:shiftX shiftY:shiftY];

    CGFloat scaleSpread = 1.0 + MIN(dist * 0.006, 0.45);
    self.innerGlowView.transform = CGAffineTransformMakeScale(scaleSpread, scaleSpread);
    self.innerGlowView.alpha = MIN(0.90 + (dist * 0.003), 1.0);
}

- (void)handleTouchEnded {
    if (!self.isPressed) return;
    self.isPressed = NO;

    if (self.navigationController && self.navigationController.interactivePopGestureRecognizer) {
        self.navigationController.interactivePopGestureRecognizer.enabled = YES;
    }

    NSTimeInterval elapsed = CACurrentMediaTime() - self.touchDownTime;
    NSTimeInterval minPressDuration = 0.12;
    NSTimeInterval delay = (elapsed < minPressDuration) ? (minPressDuration - elapsed) : 0.0;

    uint64_t currentCycle = self.touchCycleId;
    void (^performBounceRelease)(void) = ^{
        if (self.touchCycleId != currentCycle || self.isPressed) return;
        [UIView animateWithDuration:0.52 delay:0 usingSpringWithDamping:0.44 initialSpringVelocity:1.8 options:UIViewAnimationOptionAllowUserInteraction animations:^{
            [self updateShapeWithTransform:CGAffineTransformIdentity shiftX:0 shiftY:0];
            self.innerGlowView.transform = CGAffineTransformIdentity;
            self.innerGlowView.alpha = 0.0;
        } completion:nil];
    };

    if (delay > 0.001) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)), dispatch_get_main_queue(), performBounceRelease);
    } else {
        performBounceRelease();
    }
}

- (void)handleTouchCancelled {
    [self handleTouchEnded];
}

@end

@implementation LGLiquidBlockerGesture

- (instancetype)init {
    self = [super initWithTarget:nil action:nil];
    if (self) {
        self.delegate = self;
        self.cancelsTouchesInView = NO;
        self.delaysTouchesEnded = NO;
        self.delaysTouchesBegan = NO;
    }
    return self;
}

- (BOOL)canPreventGestureRecognizer:(UIGestureRecognizer *)preventedGestureRecognizer {
    return YES;
}

- (BOOL)canBePreventedByGestureRecognizer:(UIGestureRecognizer *)preventingGestureRecognizer {
    return NO;
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)otherGestureRecognizer {
    return NO;
}

@end

#pragma mark - Embedded Liquid (Gl)ass LGGlassKit.h


@class LGLiveBackdropView;

#pragma mark - class / ancestry helpers

BOOL hasAncestorOfClassName(UIView *v, NSString *clsName);
BOOL ancestorNameContains(UIView *v, NSString *sub);

BOOL isExactClass(UIView *v, NSString *name);

#pragma mark - per-host enable

BOOL lgHostEnabled(NSString *prefix);

BOOL LGProcessMatchesExclusionList(id list);

void lgObservePreferenceReload(void (^handler)(void));

#pragma mark - injection registry (live disable -> restore)

extern void *kGlassKey;

void lgTrackGlass(UIView *glass, NSString *prefix, UIView *material);

void lgSuppressStock(UIView *v, NSString *prefix, BOOL setHidden);

#pragma mark - registered material lifecycle

LGLiveBackdropView *LGCreateRegisteredGlass(CGRect frame,
                                             NSString *groupName,
                                             NSString *prefix);

LGLiveBackdropView *LGInstallRegisteredGlassInMaterial(UIView *material,
                                                        const void *associationKey,
                                                        NSString *prefix,
                                                        UIEdgeInsets outset,
                                                        CGFloat cornerRadius,
                                                        NSString *groupName);

#pragma mark - material host router

typedef BOOL (^LGMaterialHostMatcher)(UIView *material);
typedef CGFloat (^LGMaterialHostCornerRadiusProvider)(UIView *material);
typedef void (^LGMaterialHostPostInstall)(UIView *material,
                                          LGLiveBackdropView *glass);
void LGRegisterMaterialHost(NSString *prefix,
                            NSInteger priority,
                            LGMaterialHostMatcher matcher,
                            UIEdgeInsets outset,
                            LGMaterialHostCornerRadiusProvider cornerRadiusProvider,
                            NSString *groupName,
                            LGMaterialHostPostInstall postInstall);

#pragma mark - Embedded Liquid (Gl)ass LGGlassKit.x


#pragma mark - class / ancestry helpers

BOOL hasAncestorOfClassName(UIView *v, NSString *clsName) {
    Class cls = NSClassFromString(clsName);
    if (!cls) return NO;
    for (UIView *cur = v; cur; cur = cur.superview)
        if ([cur isKindOfClass:cls]) return YES;
    return NO;
}

BOOL ancestorNameContains(UIView *v, NSString *sub) {
    for (UIView *cur = v; cur; cur = cur.superview)
        if ([NSStringFromClass(cur.class) containsString:sub]) return YES;
    return NO;
}

BOOL isExactClass(UIView *v, NSString *name) {
    return v && [NSStringFromClass(v.class) isEqualToString:name];
}

#pragma mark - per-host enable prefs

BOOL LGProcessMatchesExclusionList(id list) {
    NSString *bundleID = NSBundle.mainBundle.bundleIdentifier.lowercaseString ?: @"";
    if ([list isKindOfClass:NSArray.class]) {
        for (id value in (NSArray *)list)
            if ([value isKindOfClass:NSString.class] &&
                [bundleID isEqualToString:[value lowercaseString]]) return YES;
        return NO;
    }
    if (![list isKindOfClass:NSString.class] || ![list length]) return NO;
    NSString *executable =
        NSBundle.mainBundle.executablePath.lastPathComponent.lowercaseString ?: @"";
    NSString *processName = NSProcessInfo.processInfo.processName.lowercaseString ?: @"";
    NSCharacterSet *separators =
        [NSCharacterSet characterSetWithCharactersInString:@"\n,;"];
    for (NSString *rawEntry in [(NSString *)list componentsSeparatedByCharactersInSet:separators]) {
        NSString *entry = [rawEntry stringByTrimmingCharactersInSet:
            NSCharacterSet.whitespaceAndNewlineCharacterSet].lowercaseString;
        if (!entry.length || [entry hasPrefix:@"#"]) continue;
        if ([entry isEqualToString:bundleID] ||
            [entry isEqualToString:executable] ||
            [entry isEqualToString:processName]) return YES;
    }
    return NO;
}

BOOL lgHostEnabled(NSString *prefix) {
    if (!prefix.length) return YES;
    id global = LGGlassPreferenceValue(@"Global.Enabled");
    if (![prefix isEqualToString:@"Global"] && [global isKindOfClass:[NSNumber class]] && ![global boolValue])
        return NO;
    id v = LGGlassPreferenceValue([prefix stringByAppendingString:@".Enabled"]);

    if (!v) {
        static NSDictionary<NSString *, NSString *> *legacyPrefixes;
        static dispatch_once_t once;
        dispatch_once(&once, ^{
            legacyPrefixes = @{
                @"OpenFolder":   @"FolderOpen",
                @"AppLibSearch": @"AppLibrary.Search",
                @"Passcode":     @"Lockscreen.Passcode",
                @"Clock":        @"Lockscreen.Clock",
                @"QuickActions": @"LockscreenQuickActions",
            };
        });
        NSString *legacy = legacyPrefixes[prefix];
        if (legacy) v = LGGlassPreferenceValue([legacy stringByAppendingString:@".Enabled"]);
    }
    if ([v isKindOfClass:[NSNumber class]]) return [v boolValue];

    if ([prefix isEqualToString:@"AppIcons"]) return NO;
    return YES;
}

#pragma mark - uniform injection registry

@interface LGGlassRec : NSObject
@property (nonatomic, copy) NSString *prefix;
@property (nonatomic, weak) UIView *glass;
@property (nonatomic, weak) UIView *material;
@end
@implementation LGGlassRec @end

void *kGlassKey = &kGlassKey;

static NSMapTable<UIView *, LGGlassRec *> *sGlassRecs;
static NSMapTable<UIView *, NSString *> *sSuppressed;
static NSMutableArray<void (^)(void)> *sReloadHandlers;

@interface LGMaterialHostRoute : NSObject
@property (nonatomic, copy) NSString *prefix;
@property (nonatomic) NSInteger priority;
@property (nonatomic, copy) LGMaterialHostMatcher matcher;
@property (nonatomic) UIEdgeInsets outset;
@property (nonatomic, copy) LGMaterialHostCornerRadiusProvider cornerRadiusProvider;
@property (nonatomic, copy) NSString *groupName;
@property (nonatomic, copy) LGMaterialHostPostInstall postInstall;
@end
@implementation LGMaterialHostRoute @end
static NSMutableArray<LGMaterialHostRoute *> *sMaterialHostRoutes;

void lgObservePreferenceReload(void (^handler)(void)) {
    if (!handler) return;
    if (!sReloadHandlers) sReloadHandlers = [NSMutableArray array];
    [sReloadHandlers addObject:[handler copy]];
}

void lgTrackGlass(UIView *glass, NSString *prefix, UIView *material) {
    if (!glass || !prefix.length) return;
    if (!sGlassRecs) sGlassRecs = [NSMapTable weakToStrongObjectsMapTable];
    LGGlassRec *existing = [sGlassRecs objectForKey:glass];
    if (existing) {
        existing.prefix = prefix;
        existing.material = material;
        return;
    }
    LGGlassRec *rec = [LGGlassRec new];
    rec.prefix = prefix; rec.glass = glass; rec.material = material;
    [sGlassRecs setObject:rec forKey:glass];
}

void lgSuppressStock(UIView *v, NSString *prefix, BOOL setHidden) {
    if (!v || !prefix.length) return;
    if (setHidden) v.hidden = YES;
    if (!sSuppressed) sSuppressed = [NSMapTable weakToStrongObjectsMapTable];
    [sSuppressed setObject:prefix forKey:v];
}

#pragma mark - registered material lifecycle

LGLiveBackdropView *LGCreateRegisteredGlass(CGRect frame,
                                             NSString *groupName,
                                             NSString *prefix) {
    if (!prefix.length) return nil;
    NSString *filterType = LGFilterTypeForHostPrefix(prefix);
    if (!filterType) {
        LGLog(@"lifecycle rejected unknown host prefix=%@", prefix);
        return nil;
    }
    return [[LGLiveBackdropView alloc]
        initWithFrame:frame
            groupName:groupName
           filterType:filterType];
}

LGLiveBackdropView *LGInstallRegisteredGlassInMaterial(UIView *material,
                                                        const void *associationKey,
                                                        NSString *prefix,
                                                        UIEdgeInsets outset,
                                                        CGFloat cornerRadius,
                                                        NSString *groupName) {
    if (!material || !associationKey || !prefix.length) return nil;
    const LGHostDefinition *host =
        LGHostDefinitionForPreferencePrefix(prefix.UTF8String);
    if (!host) {
        LGLog(@"lifecycle rejected unknown host prefix=%@", prefix);
        return nil;
    }
    if (!lgHostEnabled(prefix)) {
        LGRemoveGlassFromMaterial(material, associationKey);
        return nil;
    }

    NSString *filterType = [NSString stringWithUTF8String:host->filterType];
    LGInjectGlassIntoMaterialGroupType(material, associationKey, outset,
                                       cornerRadius, groupName, filterType);
    LGLiveBackdropView *glass = objc_getAssociatedObject(material, associationKey);
    if (glass) lgTrackGlass(glass, prefix, material);
    return glass;
}

void LGRegisterMaterialHost(NSString *prefix,
                            NSInteger priority,
                            LGMaterialHostMatcher matcher,
                            UIEdgeInsets outset,
                            LGMaterialHostCornerRadiusProvider cornerRadiusProvider,
                            NSString *groupName,
                            LGMaterialHostPostInstall postInstall) {
    if (!prefix.length || !matcher ||
        !LGHostDefinitionForPreferencePrefix(prefix.UTF8String)) {
        LGLog(@"router rejected invalid material host prefix=%@", prefix);
        return;
    }
    if (!sMaterialHostRoutes) sMaterialHostRoutes = [NSMutableArray array];
    for (LGMaterialHostRoute *route in sMaterialHostRoutes) {
        if ([route.prefix isEqualToString:prefix]) return;
    }
    LGMaterialHostRoute *route = [LGMaterialHostRoute new];
    route.prefix = prefix;
    route.priority = priority;
    route.matcher = [matcher copy];
    route.outset = outset;
    route.cornerRadiusProvider = [cornerRadiusProvider copy];
    route.groupName = groupName;
    route.postInstall = [postInstall copy];
    [sMaterialHostRoutes addObject:route];

    // priority makes one host own each material
    [sMaterialHostRoutes sortUsingComparator:^NSComparisonResult(LGMaterialHostRoute *a,
                                                                   LGMaterialHostRoute *b) {
        if (a.priority == b.priority)
            return [a.prefix compare:b.prefix];

        return a.priority > b.priority
            ? NSOrderedAscending
            : NSOrderedDescending;
    }];
}

static void lgRouteMaterialHost(UIView *material) {
    if (!material.window) {
        LGRemoveGlassFromMaterial(material, kGlassKey);
        return;
    }

    for (LGMaterialHostRoute *route in sMaterialHostRoutes) {
        if (!route.matcher(material))
            continue;

        CGFloat radius = route.cornerRadiusProvider
            ? route.cornerRadiusProvider(material)
            : -1.0;

        LGLiveBackdropView *glass =
            LGInstallRegisteredGlassInMaterial(
                material,
                kGlassKey,
                route.prefix,
                route.outset,
                radius,
                route.groupName);

        if (glass && route.postInstall)
            route.postInstall(material, glass);

        return;
    }
}

static void lgReconcileInjectionsForDisable(void) {
    // disabled hosts must restore stock views and remove live glass
    if (sGlassRecs.count) {
        for (UIView *glass in sGlassRecs.keyEnumerator.allObjects) {
            LGGlassRec *r = [sGlassRecs objectForKey:glass];
            if (!r) continue;

            if (!lgHostEnabled(r.prefix)) {
                if (r.material)
                    LGRemoveGlassFromMaterial(r.material, kGlassKey);
                else
                    [glass removeFromSuperview];

                [sGlassRecs removeObjectForKey:glass];
            }
        }
    }

    for (UIView *v in sSuppressed.keyEnumerator.allObjects) {
        NSString *p = [sSuppressed objectForKey:v];

        if (p && !lgHostEnabled(p)) {
            v.hidden = NO;
            [sSuppressed removeObjectForKey:v];
        }
    }
}

static void lgEnablePrefsReloadCallback(CFNotificationCenterRef c,
                                        void *o,
                                        CFStringRef n,
                                        const void *obj,
                                        CFDictionaryRef info) {
    LGLog(@"prefs Reload received; invalidating SpringBoard host-enable cache");
    LGInvalidateGlassPreferenceCache();

    dispatch_async(dispatch_get_main_queue(), ^{
        lgReconcileInjectionsForDisable();

        LGLog(@"prefs Reload reconciled material hosts; extraHandlers=%lu",
              (unsigned long)sReloadHandlers.count);

        for (void (^handler)(void) in [sReloadHandlers copy])
            handler();
    });
}

__attribute__((constructor))
static void lgGlassInitEnableObserver(void) {
    CFNotificationCenterAddObserver(
        CFNotificationCenterGetDarwinNotifyCenter(),
        NULL,
        lgEnablePrefsReloadCallback,
        CFSTR("dylv.liquidassprefs/Reload"),
        NULL,
        CFNotificationSuspensionBehaviorCoalesce);
}

#pragma mark - shared material lifecycle

%hook MTMaterialView

- (void)didMoveToWindow {
    %orig;
    lgRouteMaterialHost((UIView *)self);
}

- (void)layoutSubviews {
    %orig;
    lgRouteMaterialHost((UIView *)self);
}

- (void)setHidden:(BOOL)hidden {
    if (LGMaterialHasGlass((UIView *)self, kGlassKey)) {
        hidden = YES;
    }

    %orig;
}

- (void)setFrame:(CGRect)frame {
    %orig;
    LGResyncGlassGeometry((UIView *)self, kGlassKey);
}

- (void)setBounds:(CGRect)bounds {
    %orig;
    LGResyncGlassGeometry((UIView *)self, kGlassKey);
}

- (void)setCenter:(CGPoint)center {
    %orig;
    LGResyncGlassGeometry((UIView *)self, kGlassKey);
}

%end
#pragma mark - SearchGlass Liquid Glass surface

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

    /*
     * Stronger lens capture than the stock SearchPill profile.
     * The actual refraction multiplier comes from the embedded
     * LGHostRegistry SearchPill entry above.
     */
    self.lgBackdropZoom = 1.10;
    self.lgShapeRect = self.bounds;
    self.lgShapeCornerRadius = self.cornerRadius;

    [self applyFilters];
    return self;
}

- (void)setCornerRadius:(CGFloat)cornerRadius {
    _cornerRadius = cornerRadius;

    self.layer.cornerRadius = cornerRadius;
    self.layer.cornerCurve = kCACornerCurveContinuous;

    self.lgShapeRect = self.bounds;
    self.lgShapeCornerRadius = cornerRadius;
    self.lgBackdropZoom = 1.10;

    [self applyFilters];
}

- (void)layoutSubviews {
    [super layoutSubviews];

    self.layer.cornerRadius = self.cornerRadius;
    self.layer.cornerCurve = kCACornerCurveContinuous;

    /*
     * Do NOT use masksToBounds on the CABackdropLayer.
     * The upstream Liquid (Gl)ass renderer uses its own shape
     * rectangle/radius; clipping the backdrop layer itself can
     * create the partial horizontal glass band seen previously.
     */
    self.lgShapeRect = self.bounds;
    self.lgShapeCornerRadius =
        MIN(self.cornerRadius, CGRectGetHeight(self.bounds) * 0.5);
    self.lgBackdropZoom = 1.10;

    [self applyFilters];
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
    UIBlurEffect *buttonBlurEffect =
        [UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemMaterial];

    UIVisualEffectView *buttonBlur =
        [[UIVisualEffectView alloc] initWithEffect:buttonBlurEffect];

    buttonBlur.frame = self.bounds;
    buttonBlur.userInteractionEnabled = NO;
    buttonBlur.autoresizingMask =
        UIViewAutoresizingFlexibleWidth |
        UIViewAutoresizingFlexibleHeight;
    buttonBlur.layer.cornerRadius = 22.0;
    buttonBlur.layer.cornerCurve = kCACornerCurveContinuous;
    buttonBlur.clipsToBounds = YES;
    buttonBlur.alpha = 0.72;

    [self addSubview:buttonBlur];

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
