#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <sys/sysctl.h>
#import <dlfcn.h>
#import <AdSupport/ASIdentifierManager.h>
#import "Fishhook/fishhook.h"
#import "DeviceRandomizer.h"

// ========== 原函数指针 ==========

static CFTypeRef (*orig_MGCopyAnswer)(CFStringRef key) = NULL;
static void *(*orig_dlsym)(void *handle, const char *symbol);
static int (*orig_sysctl)(int *, u_int, void *, size_t *, void *, size_t);
static int (*orig_sysctlbyname)(const char *, void *, size_t *, void *, size_t);

static NSString *(*orig_idfv)(id, SEL);
static NSString *(*orig_name)(id, SEL);
static NSString *(*orig_model)(id, SEL);
static NSString *(*orig_sysVer)(id, SEL);
static NSString *(*orig_osVerStr)(id, SEL);
static NSUUID *(*orig_advertisingId)(id, SEL);
static CGRect (*orig_screenBounds)(id, SEL);
static CGFloat (*orig_screenScale)(id, SEL);

static BOOL g_enabled = NO;

// ========== 前置声明 ==========
static CFTypeRef hook_MGCopyAnswer(CFStringRef key);

// ========== dlsym 拦截 — 关键：防止抖音绕过 GOT ==========

static void *hook_dlsym(void *handle, const char *symbol) {
    if (g_enabled && symbol && strcmp(symbol, "MGCopyAnswer") == 0 && orig_MGCopyAnswer) {
        return hook_MGCopyAnswer;
    }
    return orig_dlsym(handle, symbol);
}

// ========== sysctl ==========

static int hook_sysctl(int *name, u_int namelen, void *oldp, size_t *oldlenp, void *newp, size_t newlen) {
    if (!g_enabled || !oldp || !oldlenp)
        return orig_sysctl(name, namelen, oldp, oldlenp, newp, newlen);

    // hw.machine / hw.model
    if (namelen == 2 && name[0] == CTL_HW && (name[1] == HW_MACHINE || name[1] == HW_MODEL)) {
        const char *c = [[DeviceRandomizer sharedInstance].currentModel UTF8String];
        size_t len = strlen(c) + 1;
        if (*oldlenp >= len) memcpy(oldp, c, len);
        *oldlenp = len;
        return 0;
    }
    // hw.memsize
    if (namelen == 2 && name[0] == CTL_HW && name[1] == HW_MEMSIZE) {
        uint64_t mem = 6442450944ULL;
        if (*oldlenp >= sizeof(uint64_t)) { memcpy(oldp, &mem, sizeof(uint64_t)); *oldlenp = sizeof(uint64_t); }
        return 0;
    }
    // hw.ncpu
    if (namelen == 2 && name[0] == CTL_HW && name[1] == HW_NCPU) {
        int cpu = 6;
        if (*oldlenp >= sizeof(int)) { memcpy(oldp, &cpu, sizeof(int)); *oldlenp = sizeof(int); }
        return 0;
    }
    return orig_sysctl(name, namelen, oldp, oldlenp, newp, newlen);
}

static int hook_sysctlbyname(const char *name, void *oldp, size_t *oldlenp, void *newp, size_t newlen) {
    return orig_sysctlbyname(name, oldp, oldlenp, newp, newlen);
}

// ========== UIDevice ==========

static NSString *hook_idfv(id self, SEL _cmd) {
    return g_enabled ? [DeviceRandomizer sharedInstance].currentIDFV : orig_idfv(self, _cmd);
}

static NSString *hook_name(id self, SEL _cmd) {
    return g_enabled ? [DeviceRandomizer sharedInstance].currentDeviceName : orig_name(self, _cmd);
}

static NSString *hook_model(id self, SEL _cmd) {
    return g_enabled ? [DeviceRandomizer sharedInstance].currentModel : orig_model(self, _cmd);
}

static NSString *hook_sysVer(id self, SEL _cmd) {
    return g_enabled ? [DeviceRandomizer sharedInstance].currentSystemVersion : orig_sysVer(self, _cmd);
}

// ========== NSProcessInfo ==========

static NSString *hook_osVerStr(id self, SEL _cmd) {
    if (!g_enabled) return orig_osVerStr(self, _cmd);
    return [NSString stringWithFormat:@"Version %@", [DeviceRandomizer sharedInstance].currentSystemVersion];
}

// ========== IDFA ==========

static NSUUID *hook_advertisingId(id self, SEL _cmd) {
    if (!g_enabled) return orig_advertisingId(self, _cmd);
    return [[NSUUID alloc] initWithUUIDString:[DeviceRandomizer sharedInstance].currentIDFV];
}

// ========== UIScreen ==========

static CGRect hook_screenBounds(id self, SEL _cmd) {
    if (!g_enabled) return orig_screenBounds(self, _cmd);
    return CGRectMake(0, 0, 390, 844);
}

static CGFloat hook_screenScale(id self, SEL _cmd) {
    if (!g_enabled) return orig_screenScale(self, _cmd);
    return 3.0;
}

// ========== MobileGestalt ==========

static CFTypeRef hook_MGCopyAnswer(CFStringRef key) {
    if (!g_enabled || !orig_MGCopyAnswer) return orig_MGCopyAnswer ? orig_MGCopyAnswer(key) : NULL;
    DeviceRandomizer *dr = [DeviceRandomizer sharedInstance];
    NSString *k = (__bridge NSString *)key;

    // Serial / Unique
    if ([k hasPrefix:@"Unique"] || [k hasSuffix:@"SerialNumber"] || [k containsString:@"ChipID"])
        return (__bridge CFStringRef)[dr.currentSerialNumber copy];
    // Model
    if ([k isEqualToString:@"ProductType"] || [k isEqualToString:@"HWModelStr"])
        return (__bridge CFStringRef)[dr.currentModel copy];
    // Version
    if ([k isEqualToString:@"ProductVersion"] || [k isEqualToString:@"BuildVersion"])
        return (__bridge CFStringRef)[dr.currentSystemVersion copy];
    // WiFi/BT MAC
    if ([k isEqualToString:@"WifiAddress"])
        return (__bridge CFStringRef)[dr.currentWifiMac copy];
    if ([k isEqualToString:@"BluetoothAddress"])
        return (__bridge CFStringRef)[dr.currentBluetoothMac copy];
    // Device name
    if ([k isEqualToString:@"UserAssignedDeviceName"] || [k isEqualToString:@"DeviceName"])
        return (__bridge CFStringRef)[dr.currentDeviceName copy];
    // Screen
    if ([k isEqualToString:@"MainScreenWidth"]) return (__bridge CFNumberRef)@390;
    if ([k isEqualToString:@"MainScreenHeight"]) return (__bridge CFNumberRef)@844;
    if ([k isEqualToString:@"MainScreenScale"]) return (__bridge CFNumberRef)@3.0;
    // Region
    if ([k isEqualToString:@"RegionCode"] || [k isEqualToString:@"RegionInfo"])
        return (__bridge CFStringRef)[dr.currentLocale copy];

    return orig_MGCopyAnswer(key);
}

// ========== Soft cleanup (safe, only when requested) ==========

static void SoftClean(void) {
    NSString *home = NSHomeDirectory();
    if (!home) return;

    // Only clean caches + cookies, not documents or prefs
    NSString *caches = [home stringByAppendingPathComponent:@"Library/Caches"];
    NSArray *items = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:caches error:nil];
    for (NSString *item in items) {
        [[NSFileManager defaultManager] removeItemAtPath:[caches stringByAppendingPathComponent:item] error:nil];
    }

    NSString *tmp = [home stringByAppendingPathComponent:@"tmp"];
    items = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:tmp error:nil];
    for (NSString *item in items) {
        [[NSFileManager defaultManager] removeItemAtPath:[tmp stringByAppendingPathComponent:item] error:nil];
    }

    for (NSHTTPCookie *c in [NSHTTPCookieStorage sharedHTTPCookieStorage].cookies)
        [[NSHTTPCookieStorage sharedHTTPCookieStorage] deleteCookie:c];

    [[NSURLCache sharedURLCache] removeAllCachedResponses];

    NSLog(@"[Mogai] soft clean done");
}

// ========== Helpers ==========

static void Swizzle(Class cls, SEL sel, IMP newImp, IMP *old) {
    Method m = class_getInstanceMethod(cls, sel);
    if (m) *old = method_setImplementation(m, newImp);
}

// ========== Constructor ==========

__attribute__((constructor(101)))
static void MogaiInit(void) {
    @autoreleasepool {
        NSLog(@"[Mogai] injecting into %@", [[NSBundle mainBundle] bundleIdentifier]);

        [[DeviceRandomizer sharedInstance] loadConfig];
        g_enabled = [DeviceRandomizer sharedInstance].enabled;

        // Soft clean only if requested
        if ([DeviceRandomizer sharedInstance].cleanRequested) {
            SoftClean();
            [DeviceRandomizer sharedInstance].cleanRequested = NO;
            [[DeviceRandomizer sharedInstance] saveConfig];
        }

        if ([DeviceRandomizer sharedInstance].randomizeOnLaunch)
            [[DeviceRandomizer sharedInstance] generateNewIdentity];

        if (!g_enabled) {
            NSLog(@"[Mogai] disabled, skipping hooks");
            return;
        }

        // dlsym — MUST hook first so everything below goes through it
        struct rebinding dl_reb[] = {{"dlsym", hook_dlsym, (void *)&orig_dlsym}};
        rebind_symbols(dl_reb, 1);

        // Get original MGCopyAnswer (might be pre-loaded in GOT)
        orig_MGCopyAnswer = dlsym(RTLD_DEFAULT, "MGCopyAnswer");
        if (orig_MGCopyAnswer) {
            struct rebinding mg_reb[] = {{"MGCopyAnswer", hook_MGCopyAnswer, NULL}};
            rebind_symbols(mg_reb, 1);
        }

        // sysctl + sysctlbyname
        struct rebinding sc_reb[] = {
            {"sysctl", hook_sysctl, (void *)&orig_sysctl},
            {"sysctlbyname", hook_sysctlbyname, (void *)&orig_sysctlbyname},
        };
        rebind_symbols(sc_reb, 2);

        // ObjC hooks
        Swizzle([UIDevice class], @selector(identifierForVendor), (IMP)hook_idfv, (IMP *)&orig_idfv);
        Swizzle([UIDevice class], @selector(name), (IMP)hook_name, (IMP *)&orig_name);
        Swizzle([UIDevice class], @selector(model), (IMP)hook_model, (IMP *)&orig_model);
        Swizzle([UIDevice class], @selector(systemVersion), (IMP)hook_sysVer, (IMP *)&orig_sysVer);
        Swizzle([NSProcessInfo class], @selector(operatingSystemVersionString), (IMP)hook_osVerStr, (IMP *)&orig_osVerStr);
        Swizzle([ASIdentifierManager class], @selector(advertisingIdentifier), (IMP)hook_advertisingId, (IMP *)&orig_advertisingId);
        Swizzle([UIScreen class], @selector(bounds), (IMP)hook_screenBounds, (IMP *)&orig_screenBounds);
        Swizzle([UIScreen class], @selector(scale), (IMP)hook_screenScale, (IMP *)&orig_screenScale);

        NSLog(@"[Mogai] hooks ready — model: %@, ver: %@",
              [DeviceRandomizer sharedInstance].currentModel,
              [DeviceRandomizer sharedInstance].currentSystemVersion);
    }
}