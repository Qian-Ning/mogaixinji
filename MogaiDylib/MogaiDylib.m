#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <sys/sysctl.h>
#import <dlfcn.h>
#import <AdSupport/ASIdentifierManager.h>
#import "Fishhook/fishhook.h"
#import "DeviceRandomizer.h"

// ========== 原函数指针 ==========

static CFTypeRef (*orig_MGCopyAnswer)(CFStringRef key);
static NSString *(*orig_idfv)(id, SEL);
static NSString *(*orig_name)(id, SEL);
static NSString *(*orig_model)(id, SEL);
static NSString *(*orig_sysVer)(id, SEL);
static NSString *(*orig_osVerStr)(id, SEL);
static int (*orig_sysctlbyname)(const char *, void *, size_t *, void *, size_t);
static NSUUID *(*orig_advertisingId)(id, SEL);
static CGRect (*orig_screenBounds)(id, SEL);
static CGFloat (*orig_screenScale)(id, SEL);

static inline BOOL IsEnabled(void) {
    return [DeviceRandomizer sharedInstance].enabled;
}

// ========== UIDevice ==========

static NSString *hook_idfv(id self, SEL _cmd) {
    return IsEnabled() ? [DeviceRandomizer sharedInstance].currentIDFV : orig_idfv(self, _cmd);
}

static NSString *hook_name(id self, SEL _cmd) {
    return IsEnabled() ? [DeviceRandomizer sharedInstance].currentDeviceName : orig_name(self, _cmd);
}

static NSString *hook_model(id self, SEL _cmd) {
    return IsEnabled() ? [DeviceRandomizer sharedInstance].currentModel : orig_model(self, _cmd);
}

static NSString *hook_sysVer(id self, SEL _cmd) {
    return IsEnabled() ? [DeviceRandomizer sharedInstance].currentSystemVersion : orig_sysVer(self, _cmd);
}

// ========== NSProcessInfo ==========

static NSString *hook_osVerStr(id self, SEL _cmd) {
    if (!IsEnabled()) return orig_osVerStr(self, _cmd);
    return [NSString stringWithFormat:@"Version %@", [DeviceRandomizer sharedInstance].currentSystemVersion];
}

// ========== IDFA ==========

static NSUUID *hook_advertisingId(id self, SEL _cmd) {
    if (!IsEnabled()) return orig_advertisingId(self, _cmd);
    return [[NSUUID alloc] initWithUUIDString:[DeviceRandomizer sharedInstance].currentIDFV];
}

// ========== UIScreen ==========

static CGRect hook_screenBounds(id self, SEL _cmd) {
    if (!IsEnabled()) return orig_screenBounds(self, _cmd);
    return CGRectMake(0, 0, 390, 844);
}

static CGFloat hook_screenScale(id self, SEL _cmd) {
    if (!IsEnabled()) return orig_screenScale(self, _cmd);
    return 3.0;
}

// ========== sysctlbyname ==========

static int hook_sysctlbyname(const char *name, void *oldp, size_t *oldlenp, void *newp, size_t newlen) {
    if (!IsEnabled() || !oldp || !oldlenp) return orig_sysctlbyname(name, oldp, oldlenp, newp, newlen);

    NSString *val = nil;

    if (strcmp(name, "hw.machine") == 0 || strcmp(name, "hw.model") == 0) {
        val = [DeviceRandomizer sharedInstance].currentModel;
    } else if (strcmp(name, "hw.memsize") == 0) {
        // ~6GB for modern iPhone
        uint64_t mem = 6442450944ULL;
        if (*oldlenp >= sizeof(uint64_t)) { memcpy(oldp, &mem, sizeof(uint64_t)); *oldlenp = sizeof(uint64_t); return 0; }
        return orig_sysctlbyname(name, oldp, oldlenp, newp, newlen);
    } else if (strcmp(name, "hw.ncpu") == 0) {
        int cpu = 6;
        if (*oldlenp >= sizeof(int)) { memcpy(oldp, &cpu, sizeof(int)); *oldlenp = sizeof(int); return 0; }
        return orig_sysctlbyname(name, oldp, oldlenp, newp, newlen);
    } else {
        return orig_sysctlbyname(name, oldp, oldlenp, newp, newlen);
    }

    if (val) {
        const char *c = [val UTF8String];
        size_t len = strlen(c) + 1;
        if (*oldlenp >= len) memcpy(oldp, c, len);
        *oldlenp = len;
        return 0;
    }
    return orig_sysctlbyname(name, oldp, oldlenp, newp, newlen);
}

// ========== MobileGestalt (comprehensive) ==========

static CFTypeRef hook_MGCopyAnswer(CFStringRef key) {
    if (!IsEnabled()) return orig_MGCopyAnswer(key);
    DeviceRandomizer *dr = [DeviceRandomizer sharedInstance];
    NSString *k = (__bridge NSString *)key;

    // ID / serial
    if ([k hasPrefix:@"Unique"] || [k hasSuffix:@"SerialNumber"] || [k containsString:@"ChipID"]) {
        return (__bridge CFStringRef)[dr.currentSerialNumber copy];
    }
    // Model
    if ([k isEqualToString:@"ProductType"] ||
        [k isEqualToString:@"HWModelStr"] ||
        [k isEqualToString:@"ModelNumber"] ||
        [k isEqualToString:@"RegulatoryModelNumber"]) {
        return (__bridge CFStringRef)[dr.currentModel copy];
    }
    // Version
    if ([k isEqualToString:@"ProductVersion"] || [k isEqualToString:@"BuildVersion"]) {
        return (__bridge CFStringRef)[dr.currentSystemVersion copy];
    }
    // MAC
    if ([k isEqualToString:@"WifiAddress"] || [k isEqualToString:@"WifiAddressData"]) {
        return (__bridge CFStringRef)[dr.currentWifiMac copy];
    }
    if ([k isEqualToString:@"BluetoothAddress"]) {
        return (__bridge CFStringRef)[dr.currentBluetoothMac copy];
    }
    // Name
    if ([k isEqualToString:@"UserAssignedDeviceName"] ||
        [k isEqualToString:@"DeviceName"] ||
        [k isEqualToString:@"device-name-localized"]) {
        return (__bridge CFStringRef)[dr.currentDeviceName copy];
    }
    // Screen
    if ([k isEqualToString:@"MainScreenWidth"]) return (__bridge CFNumberRef)@390;
    if ([k isEqualToString:@"MainScreenHeight"]) return (__bridge CFNumberRef)@844;
    if ([k isEqualToString:@"MainScreenScale"]) return (__bridge CFNumberRef)@3;
    // Region / Locale
    if ([k isEqualToString:@"RegionCode"] || [k isEqualToString:@"RegionInfo"]) {
        return (__bridge CFStringRef)[dr.currentLocale copy];
    }
    // Carrier / baseband
    if ([k containsString:@"Baseband"] || [k containsString:@"Carrier"]) {
        return NULL;
    }
    // Board / internal
    if ([k containsString:@"BoardId"] || [k containsString:@"DieId"]) {
        return orig_MGCopyAnswer(key);
    }

    return orig_MGCopyAnswer(key);
}

// ========== Sandbox cleanup (nuke old data) ==========

static void NukeDouyinData(void) {
    NSString *home = NSHomeDirectory();
    if (!home || home.length == 0) return;

    NSArray *dirs = @[
        [home stringByAppendingPathComponent:@"Library/Caches"],
        [home stringByAppendingPathComponent:@"Library/Preferences"],
        [home stringByAppendingPathComponent:@"tmp"],
        [home stringByAppendingPathComponent:@"Documents"],
    ];

    for (NSString *dir in dirs) {
        NSArray *items = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:dir error:nil];
        for (NSString *item in items) {
            if ([item isEqualToString:@"."] || [item isEqualToString:@".."]) continue;
            // Skip system prefs
            if ([dir containsString:@"Preferences"] && [item hasPrefix:@"com.apple"]) continue;
            [[NSFileManager defaultManager] removeItemAtPath:[dir stringByAppendingPathComponent:item] error:nil];
        }
    }

    // Cookie nuke
    for (NSHTTPCookie *c in [NSHTTPCookieStorage sharedHTTPCookieStorage].cookies) {
        [[NSHTTPCookieStorage sharedHTTPCookieStorage] deleteCookie:c];
    }

    // NSURLCache nuke
    [[NSURLCache sharedURLCache] removeAllCachedResponses];

    // Keychain — delete entries for Douyin
    NSArray *svcPatterns = @[@"aweme", @"douyin", @"snssdk", @"com.ss."];
    for (NSString *pat in svcPatterns) {
        NSDictionary *q = @{
            (id)kSecClass: (id)kSecClassGenericPassword,
            (id)kSecMatchLimit: (id)kSecMatchLimitAll,
            (id)kSecReturnAttributes: @YES,
        };
        CFTypeRef result = NULL;
        if (SecItemCopyMatching((CFDictionaryRef)q, &result) == errSecSuccess) {
            for (NSDictionary *item in (__bridge NSArray *)result) {
                NSString *svc = item[(id)kSecAttrService];
                if ([svc rangeOfString:pat options:NSCaseInsensitiveSearch].location != NSNotFound) {
                    NSDictionary *del = @{
                        (id)kSecClass: item[(id)kSecClass],
                        (id)kSecAttrService: svc ?: @"",
                        (id)kSecAttrAccount: item[(id)kSecAttrAccount] ?: @"",
                    };
                    SecItemDelete((CFDictionaryRef)del);
                }
            }
        }
        if (result) CFRelease(result);
    }

    NSLog(@"[Mogai] Douyin data wiped");
}

// ========== Helper ==========

static void Swizzle(Class cls, SEL sel, IMP newImp, IMP *old) {
    Method m = class_getInstanceMethod(cls, sel);
    if (m) *old = method_setImplementation(m, newImp);
}

// ========== Constructor ==========

__attribute__((constructor(102)))
static void MogaiInit(void) {
    @autoreleasepool {
        NSLog(@"[Mogai] injecting into %@", [[NSBundle mainBundle] bundleIdentifier]);

        // Always nuke old data first
        NukeDouyinData();

        [[DeviceRandomizer sharedInstance] loadConfig];

        if ([DeviceRandomizer sharedInstance].cleanRequested) {
            NukeDouyinData();
            [DeviceRandomizer sharedInstance].cleanRequested = NO;
            [[DeviceRandomizer sharedInstance] saveConfig];
            NSLog(@"[Mogai] clean flag processed");
        }

        if ([DeviceRandomizer sharedInstance].randomizeOnLaunch)
            [[DeviceRandomizer sharedInstance] generateNewIdentity];
        else if (![[NSDictionary dictionaryWithContentsOfFile:@"/var/mobile/Documents/.mogai_config.plist"] count])
            [[DeviceRandomizer sharedInstance] generateNewIdentity];

        if (![DeviceRandomizer sharedInstance].enabled) return;

        // UIDevice
        Swizzle([UIDevice class], @selector(identifierForVendor), (IMP)hook_idfv, (IMP *)&orig_idfv);
        Swizzle([UIDevice class], @selector(name), (IMP)hook_name, (IMP *)&orig_name);
        Swizzle([UIDevice class], @selector(model), (IMP)hook_model, (IMP *)&orig_model);
        Swizzle([UIDevice class], @selector(systemVersion), (IMP)hook_sysVer, (IMP *)&orig_sysVer);

        // NSProcessInfo
        Swizzle([NSProcessInfo class], @selector(operatingSystemVersionString), (IMP)hook_osVerStr, (IMP *)&orig_osVerStr);

        // IDFA
        Swizzle([ASIdentifierManager class], @selector(advertisingIdentifier), (IMP)hook_advertisingId, (IMP *)&orig_advertisingId);

        // UIScreen
        Swizzle([UIScreen class], @selector(bounds), (IMP)hook_screenBounds, (IMP *)&orig_screenBounds);
        Swizzle([UIScreen class], @selector(scale), (IMP)hook_screenScale, (IMP *)&orig_screenScale);

        // sysctlbyname
        struct rebinding rb[] = {{"sysctlbyname", hook_sysctlbyname, (void *)&orig_sysctlbyname}};
        rebind_symbols(rb, 1);

        // MGCopyAnswer
        void *mg = dlsym(RTLD_DEFAULT, "MGCopyAnswer");
        if (mg) {
            orig_MGCopyAnswer = mg;
            struct rebinding rb2[] = {{"MGCopyAnswer", hook_MGCopyAnswer, NULL}};
            rebind_symbols(rb2, 1);
        }

        NSLog(@"[Mogai] hooks ready, spoofing: %@ / %@", [DeviceRandomizer sharedInstance].currentModel, [DeviceRandomizer sharedInstance].currentSystemVersion);
    }
}