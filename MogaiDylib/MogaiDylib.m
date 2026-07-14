#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <sys/sysctl.h>
#import <dlfcn.h>
#import "Fishhook/fishhook.h"
#import "DeviceRandomizer.h"

// ========== 原函数指针 ==========

static CFTypeRef (*orig_MGCopyAnswer)(CFStringRef key) = NULL;
static int (*orig_sysctl)(int *, u_int, void *, size_t *, void *, size_t);
static int (*orig_sysctlbyname)(const char *, void *, size_t *, void *, size_t);

static NSString *(*orig_idfv)(id, SEL);
static NSString *(*orig_name)(id, SEL);
static NSString *(*orig_model)(id, SEL);
static NSString *(*orig_sysVer)(id, SEL);
static NSString *(*orig_osVerStr)(id, SEL);
static NSString *(*orig_hostName)(id, SEL);

static BOOL g_enabled = NO;

// ========== sysctl (hw params only) ==========

static int hook_sysctl(int *name, u_int namelen, void *oldp, size_t *oldlenp, void *newp, size_t newlen) {
    if (!g_enabled || !oldp || !oldlenp)
        return orig_sysctl(name, namelen, oldp, oldlenp, newp, newlen);

    if (namelen == 2 && name[0] == CTL_HW) {
        if (name[1] == HW_MACHINE || name[1] == HW_MODEL) {
            const char *c = [[DeviceRandomizer sharedInstance].currentModel UTF8String];
            size_t len = strlen(c) + 1;
            if (*oldlenp >= len) memcpy(oldp, c, len);
            *oldlenp = len;
            return 0;
        }
    }
    return orig_sysctl(name, namelen, oldp, oldlenp, newp, newlen);
}

static int hook_sysctlbyname(const char *name, void *oldp, size_t *oldlenp, void *newp, size_t newlen) {
    if (!g_enabled || !oldp || !oldlenp)
        return orig_sysctlbyname(name, oldp, oldlenp, newp, newlen);

    if (strcmp(name, "hw.machine") == 0 || strcmp(name, "hw.model") == 0) {
        const char *c = [[DeviceRandomizer sharedInstance].currentModel UTF8String];
        size_t len = strlen(c) + 1;
        if (*oldlenp >= len) memcpy(oldp, c, len);
        *oldlenp = len;
        return 0;
    }
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

static NSString *hook_hostName(id self, SEL _cmd) {
    if (!g_enabled) return orig_hostName(self, _cmd);
    return [DeviceRandomizer sharedInstance].currentDeviceName;
}

// ========== MobileGestalt (comprehensive) ==========

static CFTypeRef hook_MGCopyAnswer(CFStringRef key) {
    if (!g_enabled || !orig_MGCopyAnswer) return orig_MGCopyAnswer(key);
    DeviceRandomizer *dr = [DeviceRandomizer sharedInstance];
    NSString *k = (__bridge NSString *)key;

    // Serial / Unique / Chip ID
    if ([k hasPrefix:@"Unique"] ||
        [k hasSuffix:@"SerialNumber"] ||
        [k containsString:@"ChipID"] ||
        [k containsString:@"ECID"])
        return (__bridge CFStringRef)[dr.currentSerialNumber copy];

    // Model (ProductType, HWModelStr, ModelNumber, etc.)
    if ([k isEqualToString:@"ProductType"] ||
        [k isEqualToString:@"HWModelStr"] ||
        [k isEqualToString:@"ModelNumber"] ||
        [k isEqualToString:@"RegulatoryModelNumber"])
        return (__bridge CFStringRef)[dr.currentModel copy];

    // Version
    if ([k isEqualToString:@"ProductVersion"] ||
        [k isEqualToString:@"BuildVersion"])
        return (__bridge CFStringRef)[dr.currentSystemVersion copy];

    // WiFi / Bluetooth
    if ([k isEqualToString:@"WifiAddress"] ||
        [k isEqualToString:@"WifiAddressData"])
        return (__bridge CFStringRef)[dr.currentWifiMac copy];
    if ([k isEqualToString:@"BluetoothAddress"])
        return (__bridge CFStringRef)[dr.currentBluetoothMac copy];

    // Device Name
    if ([k isEqualToString:@"UserAssignedDeviceName"] ||
        [k isEqualToString:@"DeviceName"] ||
        [k isEqualToString:@"device-name-localized"])
        return (__bridge CFStringRef)[dr.currentDeviceName copy];

    // Screen
    if ([k isEqualToString:@"MainScreenWidth"])  return (__bridge CFNumberRef)@390;
    if ([k isEqualToString:@"MainScreenHeight"]) return (__bridge CFNumberRef)@844;
    if ([k isEqualToString:@"MainScreenScale"])  return (__bridge CFNumberRef)@3.0;

    // Region / Locale
    if ([k isEqualToString:@"RegionCode"] ||
        [k isEqualToString:@"RegionInfo"])
        return (__bridge CFStringRef)[dr.currentLocale copy];

    // Timezone
    if ([k isEqualToString:@"TimeZone"])
        return (__bridge CFStringRef)[dr.currentTimeZone copy];

    return orig_MGCopyAnswer(key);
}

// ========== Soft clean (safe, only caches + cookies) ==========

static void SoftClean(void) {
    @autoreleasepool {
        NSString *home = NSHomeDirectory();
        if (!home || home.length == 0) return;

        NSFileManager *fm = [NSFileManager defaultManager];
        NSArray *dirs = @[
            [home stringByAppendingPathComponent:@"Library/Caches"],
            [home stringByAppendingPathComponent:@"tmp"],
        ];
        for (NSString *dir in dirs) {
            NSArray *items = [fm contentsOfDirectoryAtPath:dir error:nil];
            for (NSString *item in items) {
                [fm removeItemAtPath:[dir stringByAppendingPathComponent:item] error:nil];
            }
        }
        for (NSHTTPCookie *c in [NSHTTPCookieStorage sharedHTTPCookieStorage].cookies)
            [[NSHTTPCookieStorage sharedHTTPCookieStorage] deleteCookie:c];
        [[NSURLCache sharedURLCache] removeAllCachedResponses];
        NSLog(@"[Mogai] caches cleaned");
    }
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
        NSString *bundleID = [[NSBundle mainBundle] bundleIdentifier] ?: @"unknown";
        NSLog(@"[Mogai] injecting into %@", bundleID);

        [[DeviceRandomizer sharedInstance] loadConfig];
        g_enabled = [DeviceRandomizer sharedInstance].enabled;

        if (!g_enabled) {
            NSLog(@"[Mogai] disabled via config, exiting");
            return;
        }

        // Clean if requested
        if ([DeviceRandomizer sharedInstance].cleanRequested) {
            SoftClean();
            [DeviceRandomizer sharedInstance].cleanRequested = NO;
            [[DeviceRandomizer sharedInstance] saveConfig];
        }

        // Generate new identity if configured
        if ([DeviceRandomizer sharedInstance].randomizeOnLaunch)
            [[DeviceRandomizer sharedInstance] generateNewIdentity];

        // === Hook via fishhook (GOT patching, no dlsym interference) ===

        struct rebinding sc_reb[] = {
            {"sysctl",        hook_sysctl,        (void *)&orig_sysctl},
            {"sysctlbyname",  hook_sysctlbyname,  (void *)&orig_sysctlbyname},
        };
        rebind_symbols(sc_reb, 2);

        // MGCopyAnswer via GOT (NOT dlsym hook)
        orig_MGCopyAnswer = dlsym(RTLD_DEFAULT, "MGCopyAnswer");
        if (orig_MGCopyAnswer) {
            struct rebinding mg_reb[] = {{"MGCopyAnswer", hook_MGCopyAnswer, NULL}};
            rebind_symbols(mg_reb, 1);
            NSLog(@"[Mogai] MGCopyAnswer hooked via GOT");
        } else {
            NSLog(@"[Mogai] WARNING: MGCopyAnswer not found");
        }

        // === ObjC hooks (only safe ones) ===

        Swizzle([UIDevice class], @selector(identifierForVendor), (IMP)hook_idfv, (IMP *)&orig_idfv);
        Swizzle([UIDevice class], @selector(name), (IMP)hook_name, (IMP *)&orig_name);
        Swizzle([UIDevice class], @selector(model), (IMP)hook_model, (IMP *)&orig_model);
        Swizzle([UIDevice class], @selector(systemVersion), (IMP)hook_sysVer, (IMP *)&orig_sysVer);

        Swizzle([NSProcessInfo class], @selector(operatingSystemVersionString), (IMP)hook_osVerStr, (IMP *)&orig_osVerStr);
        Swizzle([NSProcessInfo class], @selector(hostName), (IMP)hook_hostName, (IMP *)&orig_hostName);

        NSLog(@"[Mogai] hooks ready — spoofing %@ / iOS %@",
              [DeviceRandomizer sharedInstance].currentModel,
              [DeviceRandomizer sharedInstance].currentSystemVersion);
    }
}