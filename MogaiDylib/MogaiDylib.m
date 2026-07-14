#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <sys/sysctl.h>
#import <unistd.h>
#import <dlfcn.h>
#import <mach-o/dyld.h>
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

static inline BOOL IsEnabled(void) {
    return [DeviceRandomizer sharedInstance].enabled;
}

// ========== UIDevice Hooks (no logging, fast path) ==========

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

// ========== MobileGestalt ==========

static CFTypeRef hook_MGCopyAnswer(CFStringRef key) {
    if (!IsEnabled()) return orig_MGCopyAnswer(key);

    DeviceRandomizer *dr = [DeviceRandomizer sharedInstance];
    NSString *k = (__bridge NSString *)key;

    if ([k isEqualToString:@"UniqueDeviceID"] ||
        [k isEqualToString:@"UniqueChipID"] ||
        [k isEqualToString:@"AUniqueChipID"] ||
        [k isEqualToString:@"SerialNumber"] ||
        [k isEqualToString:@"MLBSerialNumber"])
        return (__bridge CFTypeRef)[dr.currentSerialNumber copy];

    if ([k isEqualToString:@"WifiAddress"])
        return (__bridge CFTypeRef)[dr.currentWifiMac copy];

    if ([k isEqualToString:@"BluetoothAddress"])
        return (__bridge CFTypeRef)[dr.currentBluetoothMac copy];

    if ([k isEqualToString:@"ProductType"])
        return (__bridge CFTypeRef)[dr.currentModel copy];

    if ([k isEqualToString:@"ProductVersion"])
        return (__bridge CFTypeRef)[dr.currentSystemVersion copy];

    return orig_MGCopyAnswer(key);
}

// ========== sysctlbyname ==========

static int hook_sysctlbyname(const char *name, void *oldp, size_t *oldlenp, void *newp, size_t newlen) {
    if (!IsEnabled() || strcmp(name, "hw.machine") != 0)
        return orig_sysctlbyname(name, oldp, oldlenp, newp, newlen);

    const char *cstr = [[DeviceRandomizer sharedInstance].currentModel UTF8String];
    size_t len = strlen(cstr) + 1;
    if (oldp && oldlenp && *oldlenp >= len)
        memcpy(oldp, cstr, len);
    if (oldlenp) *oldlenp = len;
    return 0;
}

// ========== ObjC swizzle helper ==========

static void Swizzle(Class cls, SEL sel, IMP newImp, IMP *old) {
    Method m = class_getInstanceMethod(cls, sel);
    if (m) *old = method_setImplementation(m, newImp);
}

// ========== Constructor ==========

__attribute__((constructor(101)))
static void MogaiInit(void) {
    @autoreleasepool {
        NSLog(@"[Mogai] injecting");

        [[DeviceRandomizer sharedInstance] loadConfig];

        if ([DeviceRandomizer sharedInstance].cleanRequested) {
            // Light sandbox clean: caches + cookies only
            NSArray *dirs = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES);
            if (dirs.count > 0) {
                NSArray *items = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:dirs[0] error:nil];
                for (NSString *item in items)
                    [[NSFileManager defaultManager] removeItemAtPath:[dirs[0] stringByAppendingPathComponent:item] error:nil];
            }
            for (NSHTTPCookie *c in [NSHTTPCookieStorage sharedHTTPCookieStorage].cookies)
                [[NSHTTPCookieStorage sharedHTTPCookieStorage] deleteCookie:c];

            [DeviceRandomizer sharedInstance].cleanRequested = NO;
            [[DeviceRandomizer sharedInstance] saveConfig];
            NSLog(@"[Mogai] sandbox cleaned");
        }

        if ([DeviceRandomizer sharedInstance].randomizeOnLaunch)
            [[DeviceRandomizer sharedInstance] generateNewIdentity];

        if (![DeviceRandomizer sharedInstance].enabled) return;

        Swizzle([UIDevice class], @selector(identifierForVendor), (IMP)hook_idfv, (IMP *)&orig_idfv);
        Swizzle([UIDevice class], @selector(name), (IMP)hook_name, (IMP *)&orig_name);
        Swizzle([UIDevice class], @selector(model), (IMP)hook_model, (IMP *)&orig_model);
        Swizzle([UIDevice class], @selector(systemVersion), (IMP)hook_sysVer, (IMP *)&orig_sysVer);

        Swizzle([NSProcessInfo class], @selector(operatingSystemVersionString), (IMP)hook_osVerStr, (IMP *)&orig_osVerStr);

        struct rebinding bindings[] = {
            {"sysctlbyname", hook_sysctlbyname, (void *)&orig_sysctlbyname},
        };
        rebind_symbols(bindings, 1);

        void *mg = dlsym(RTLD_DEFAULT, "MGCopyAnswer");
        if (mg) {
            orig_MGCopyAnswer = mg;
            struct rebinding rb[] = {{"MGCopyAnswer", hook_MGCopyAnswer, NULL}};
            rebind_symbols(rb, 1);
        }

        NSLog(@"[Mogai] hooks ready");
    }
}