#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <sys/stat.h>
#import <sys/sysctl.h>
#import <unistd.h>
#import <dlfcn.h>
#import <mach-o/dyld.h>
#import "Fishhook/fishhook.h"
#import "DeviceRandomizer.h"
#import "SandboxCleaner.h"

// ========== 私有API声明 ==========

// MobileGestalt 私有框架
extern CFTypeRef MGCopyAnswer(CFStringRef key);
extern Boolean MGGetBoolAnswer(CFStringRef key);

// Shared suite name (must match DeviceRandomizer.m and MogaiConfig)
static NSString *const kMogaiSuiteName = @"group.com.mogai.config";

// ========== 原函数指针 ==========

// UIDevice
static NSString *(*orig_uidv_identifierForVendor)(id, SEL);
static NSString *(*orig_uidv_name)(id, SEL);
static NSString *(*orig_uidv_model)(id, SEL);
static NSString *(*orig_uidv_systemVersion)(id, SEL);
static NSString *(*orig_uidv_localizedModel)(id, SEL);

// NSProcessInfo
static NSString *(*orig_pi_operatingSystemVersionString)(id, SEL);
static NSString *(*orig_pi_hostName)(id, SEL);
static NSTimeInterval (*orig_pi_systemUptime)(id, SEL);

// NSLocale
static id (*orig_locale_currentLocale)(Class, SEL);
static id (*orig_locale_autoupdatingCurrentLocale)(Class, SEL);

// NSTimeZone
static id (*orig_tz_localTimeZone)(Class, SEL);
static id (*orig_tz_systemTimeZone)(Class, SEL);

// NSFileManager
static BOOL (*orig_fm_fileExistsAtPath)(id, SEL, NSString *);
static BOOL (*orig_fm_fileExistsAtPath_isDirectory)(id, SEL, NSString *, BOOL *);

// Keychain
static OSStatus (*orig_SecItemCopyMatching)(CFDictionaryRef, CFTypeRef *);

// C 函数
static int (*orig_stat)(const char *, struct stat *);
static int (*orig_lstat)(const char *, struct stat *);
static int (*orig_access)(const char *, int);
static int (*orig_open)(const char *, int, ...);
static int (*orig_sysctl)(int *, u_int, void *, size_t *, void *, size_t);
static int (*orig_sysctlbyname)(const char *, void *, size_t *, void *, size_t);
static int (*orig_dladdr)(const void *, Dl_info *);
static uint32_t (*orig_dyld_image_count)(void);
static const char *(*orig_dyld_get_image_name)(uint32_t);

// ========== MobileGestalt ==========
static CFTypeRef (*orig_MGCopyAnswer)(CFStringRef key);

// ========== 辅助函数 ==========

static BOOL IsMogaiEnabled(void) {
    return [DeviceRandomizer sharedInstance].enabled;
}

static BOOL IsJailbreakPath(const char *path) {
    if (!path) return NO;
    const char *jailbreak_paths[] = {
        "/Applications/Cydia.app",
        "/Applications/Sileo.app",
        "/Applications/Zebra.app",
        "/Library/MobileSubstrate",
        "/Library/Frameworks/CydiaSubstrate.framework",
        "/usr/libexec/cydia",
        "/usr/sbin/frida-server",
        "/bin/bash",
        "/bin/sh",
        "/etc/apt",
        "/private/var/lib/apt",
        "/private/var/tmp/cydia.log",
        "/var/log/syslog",
        "/var/mobile/Library/Preferences/abexport",
        "/var/containers/Bundle/Application/.cydia_no_stash",
        NULL
    };
    for (int i = 0; jailbreak_paths[i] != NULL; i++) {
        if (strstr(path, jailbreak_paths[i]) != NULL) return YES;
    }
    return NO;
}

static BOOL IsMogaiDylib(const char *name) {
    if (!name) return NO;
    if (strstr(name, "MogaiDylib") != NULL) return YES;
    if (strstr(name, "Mogai") != NULL) return YES;
    return NO;
}

// ========== UIDevice Hooks ==========

static NSString *hook_uidv_identifierForVendor(id self, SEL _cmd) {
    if (!IsMogaiEnabled()) return orig_uidv_identifierForVendor(self, _cmd);
    NSString *val = [DeviceRandomizer sharedInstance].currentIDFV;
    [[DeviceRandomizer sharedInstance] log:@"[Hook] identifierForVendor -> %@", val];
    return val;
}

static NSString *hook_uidv_name(id self, SEL _cmd) {
    if (!IsMogaiEnabled()) return orig_uidv_name(self, _cmd);
    NSString *val = [DeviceRandomizer sharedInstance].currentDeviceName;
    return val;
}

static NSString *hook_uidv_model(id self, SEL _cmd) {
    if (!IsMogaiEnabled()) return orig_uidv_model(self, _cmd);
    NSString *val = [DeviceRandomizer sharedInstance].currentModel;
    return val;
}

static NSString *hook_uidv_systemVersion(id self, SEL _cmd) {
    if (!IsMogaiEnabled()) return orig_uidv_systemVersion(self, _cmd);
    NSString *val = [DeviceRandomizer sharedInstance].currentSystemVersion;
    return val;
}

static NSString *hook_uidv_localizedModel(id self, SEL _cmd) {
    if (!IsMogaiEnabled()) return orig_uidv_localizedModel(self, _cmd);
    return hook_uidv_model(self, _cmd);
}

// ========== NSProcessInfo Hooks ==========

static NSString *hook_pi_operatingSystemVersionString(id self, SEL _cmd) {
    if (!IsMogaiEnabled()) return orig_pi_operatingSystemVersionString(self, _cmd);
    NSString *ver = [DeviceRandomizer sharedInstance].currentSystemVersion;
    return [NSString stringWithFormat:@"iOS %@", ver];
}

static NSString *hook_pi_hostName(id self, SEL _cmd) {
    if (!IsMogaiEnabled()) return orig_pi_hostName(self, _cmd);
    return [DeviceRandomizer sharedInstance].currentDeviceName;
}

static NSTimeInterval hook_pi_systemUptime(id self, SEL _cmd) {
    if (!IsMogaiEnabled()) return orig_pi_systemUptime(self, _cmd);
    // 返回一个合理的启动时间（1小时到7天之间），避免0值触发风控
    return (NSTimeInterval)(arc4random_uniform(604800) + 3600);
}

// ========== NSLocale Hooks ==========

static id hook_locale_currentLocale(Class self, SEL _cmd) {
    if (!IsMogaiEnabled()) return orig_locale_currentLocale(self, _cmd);
    NSString *locStr = [DeviceRandomizer sharedInstance].currentLocale;
    return [[NSLocale alloc] initWithLocaleIdentifier:locStr];
}

static id hook_locale_autoupdatingCurrentLocale(Class self, SEL _cmd) {
    return hook_locale_currentLocale(self, _cmd);
}

// ========== NSTimeZone Hooks ==========

static id hook_tz_localTimeZone(Class self, SEL _cmd) {
    if (!IsMogaiEnabled()) return orig_tz_localTimeZone(self, _cmd);
    NSString *tzName = [DeviceRandomizer sharedInstance].currentTimeZone;
    return [NSTimeZone timeZoneWithName:tzName];
}

static id hook_tz_systemTimeZone(Class self, SEL _cmd) {
    return hook_tz_localTimeZone(self, _cmd);
}

// ========== NSFileManager Hooks ==========

static BOOL hook_fm_fileExistsAtPath(id self, SEL _cmd, NSString *path) {
    if (IsMogaiEnabled() && IsJailbreakPath([path UTF8String])) {
        return NO;
    }
    return orig_fm_fileExistsAtPath(self, _cmd, path);
}

static BOOL hook_fm_fileExistsAtPath_isDirectory(id self, SEL _cmd, NSString *path, BOOL *isDir) {
    if (IsMogaiEnabled() && IsJailbreakPath([path UTF8String])) {
        return NO;
    }
    return orig_fm_fileExistsAtPath_isDirectory(self, _cmd, path, isDir);
}

// ========== Keychain Hooks ==========

static OSStatus hook_SecItemCopyMatching(CFDictionaryRef query, CFTypeRef *result) {
    if (!IsMogaiEnabled()) return orig_SecItemCopyMatching(query, result);

    // 如果查询的是IDFV相关，返回空
    NSString *bundleID = [[NSBundle mainBundle] bundleIdentifier];
    if (!bundleID) return orig_SecItemCopyMatching(query, result);

    // 如果查询的是抖音相关的keychain数据，返回errSecItemNotFound
    if (query) {
        CFStringRef service = CFDictionaryGetValue(query, kSecAttrService);
        if (service) {
            NSString *svc = (__bridge NSString *)service;
            if ([svc containsString:bundleID] || [svc containsString:@"aweme"] || [svc containsString:@"douyin"] || [svc containsString:@"snssdk"]) {
                if (result) *result = NULL;
                return errSecItemNotFound;
            }
        }
    }
    return orig_SecItemCopyMatching(query, result);
}

// ========== stat / access / open Hooks ==========

static int hook_stat(const char *path, struct stat *buf) {
    if (IsMogaiEnabled() && IsJailbreakPath(path)) {
        errno = ENOENT;
        return -1;
    }
    return orig_stat(path, buf);
}

static int hook_lstat(const char *path, struct stat *buf) {
    if (IsMogaiEnabled() && IsJailbreakPath(path)) {
        errno = ENOENT;
        return -1;
    }
    return orig_lstat(path, buf);
}

static int hook_access(const char *path, int mode) {
    if (IsMogaiEnabled() && IsJailbreakPath(path)) {
        errno = ENOENT;
        return -1;
    }
    return orig_access(path, mode);
}

static int hook_open(const char *path, int flags, ...) {
    if (IsMogaiEnabled() && IsJailbreakPath(path)) {
        errno = ENOENT;
        return -1;
    }
    va_list ap;
    va_start(ap, flags);
    int mode = (flags & O_CREAT) ? va_arg(ap, int) : 0;
    va_end(ap);
    return orig_open(path, flags, mode);
}

// ========== sysctl Hook ==========

static int hook_sysctl(int *name, u_int namelen, void *oldp, size_t *oldlenp, void *newp, size_t newlen) {
    if (!IsMogaiEnabled()) return orig_sysctl(name, namelen, oldp, oldlenp, newp, newlen);

    // 检测是否查询进程信息（常用于检测调试器/越狱进程）
    if (namelen >= 2 && name[0] == CTL_KERN && name[1] == KERN_PROC) {
        // 过滤掉越狱相关进程
        int ret = orig_sysctl(name, namelen, oldp, oldlenp, newp, newlen);
        if (ret == 0 && oldp && oldlenp && *oldlenp > 0) {
            // 可以在这里过滤进程列表，但比较复杂，目前先返回原始数据
        }
        return ret;
    }

    // 检测 KERN_BOOTTIME — 返回合理的启动时间
    if (namelen == 2 && name[0] == CTL_KERN && name[1] == KERN_BOOTTIME) {
        // 返回真实值（不伪造启动时间反而更安全）
    }

    return orig_sysctl(name, namelen, oldp, oldlenp, newp, newlen);
}

static int hook_sysctlbyname(const char *name, void *oldp, size_t *oldlenp, void *newp, size_t newlen) {
    if (!IsMogaiEnabled()) return orig_sysctlbyname(name, oldp, oldlenp, newp, newlen);

    // hw.machine / hw.model — 返回伪造的设备型号
    if (strcmp(name, "hw.machine") == 0 || strcmp(name, "hw.model") == 0) {
        NSString *model = [DeviceRandomizer sharedInstance].currentModel;
        if (oldp && oldlenp) {
            const char *cstr = [model UTF8String];
            size_t len = strlen(cstr) + 1;
            if (*oldlenp >= len) {
                memcpy(oldp, cstr, len);
                *oldlenp = len;
                return 0;
            }
            *oldlenp = len;
            return 0;
        }
        return 0;
    }

    // hw.memsize — 返回真实值（不伪造）
    // kern.boottime — 返回真实值

    return orig_sysctlbyname(name, oldp, oldlenp, newp, newlen);
}

// ========== dyld Hooks（隐藏注入） ==========

static uint32_t hook_dyld_image_count(void) {
    if (!IsMogaiEnabled()) return orig_dyld_image_count();
    uint32_t count = orig_dyld_image_count();
    uint32_t adjusted = count;
    for (uint32_t i = 0; i < count; i++) {
        const char *name = orig_dyld_get_image_name(i);
        if (IsMogaiDylib(name)) adjusted--;
    }
    return adjusted;
}

static const char *hook_dyld_get_image_name(uint32_t index) {
    if (!IsMogaiEnabled()) return orig_dyld_get_image_name(index);

    uint32_t count = orig_dyld_image_count();
    uint32_t adjusted_index = 0;
    for (uint32_t i = 0; i < count; i++) {
        const char *name = orig_dyld_get_image_name(i);
        if (IsMogaiDylib(name)) continue;
        if (adjusted_index == index) return name;
        adjusted_index++;
    }
    return orig_dyld_get_image_name(index);
}

// ========== dladdr Hook ==========

static int hook_dladdr(const void *addr, Dl_info *info) {
    int ret = orig_dladdr(addr, info);
    if (ret && info && info->dli_fname && IsMogaiEnabled()) {
        if (IsMogaiDylib(info->dli_fname)) {
            // 把地址指向的模块伪装成主二进制
            info->dli_fname = [[[NSBundle mainBundle] executablePath] UTF8String];
            info->dli_sname = NULL;
            info->dli_saddr = NULL;
        }
    }
    return ret;
}

// ========== MobileGestalt Hook ==========

static CFTypeRef hook_MGCopyAnswer(CFStringRef key) {
    if (!IsMogaiEnabled()) return orig_MGCopyAnswer(key);

    DeviceRandomizer *dr = [DeviceRandomizer sharedInstance];
    NSString *keyStr = (__bridge NSString *)key;

    // 需要覆盖的设备标识key
    if ([keyStr isEqualToString:@"UniqueDeviceID"] ||
        [keyStr isEqualToString:@"UniqueChipID"] ||
        [keyStr isEqualToString:@"AUniqueChipID"] ||
        [keyStr isEqualToString:@"SerialNumber"] ||
        [keyStr isEqualToString:@"MLBSerialNumber"] ||
        [keyStr containsString:@"ChipID"]) {
        [[DeviceRandomizer sharedInstance] log:@"[MobileGestalt] Blocked: %@", keyStr];
        return (__bridge CFTypeRef)[dr.currentSerialNumber copy];
    }

    if ([keyStr isEqualToString:@"WifiAddress"] ||
        [keyStr isEqualToString:@"WifiAddressData"] ||
        [keyStr isEqualToString:@"BluetoothAddress"] ||
        [keyStr containsString:@"MACAddress"]) {
        NSString *mac = [keyStr containsString:@"Bluetooth"] ? dr.currentBluetoothMac : dr.currentWifiMac;
        return (__bridge CFTypeRef)[mac copy];
    }

    if ([keyStr isEqualToString:@"ProductType"] ||
        [keyStr isEqualToString:@"DeviceName"] ||
        [keyStr isEqualToString:@"ModelNumber"]) {
        return (__bridge CFTypeRef)[dr.currentModel copy];
    }

    if ([keyStr isEqualToString:@"ProductVersion"] ||
        [keyStr isEqualToString:@"iOSVersion"] ||
        [keyStr containsString:@"OSVersion"]) {
        return (__bridge CFTypeRef)[dr.currentSystemVersion copy];
    }

    if ([keyStr containsString:@"Region"] ||
        [keyStr containsString:@"Locale"] ||
        [keyStr isEqualToString:@"UserAssignedDeviceName"]) {
        return orig_MGCopyAnswer(key);
    }

    // 其他key返回真实值
    return orig_MGCopyAnswer(key);
}

// ========== 工具函数：Hook注册 ==========

static void HookObjcMethod(Class cls, SEL sel, IMP newImpl, IMP *origImpl) {
    Method method = class_getInstanceMethod(cls, sel);
    if (!method) return;
    *origImpl = method_setImplementation(method, newImpl);
}

static void HookObjcClassMethod(Class cls, SEL sel, IMP newImpl, IMP *origImpl) {
    Method method = class_getClassMethod(cls, sel);
    if (!method) return;
    *origImpl = method_setImplementation(method, newImpl);
}

// ========== Constructor 主入口 ==========

__attribute__((constructor(101)))
static void MogaiInit(void) {
    @autoreleasepool {
        NSLog(@"[Mogai] ===== 魔改新机 v2.0 Pro injecting =====");
        NSLog(@"[Mogai] Target: %@", [[NSBundle mainBundle] bundleIdentifier]);
        NSLog(@"[Mogai] Home: %@", NSHomeDirectory());

        // 加载配置
        [[DeviceRandomizer sharedInstance] loadConfig];

        // 检查是否需要执行清理
        NSUserDefaults *defaults = [[NSUserDefaults alloc] initWithSuiteName:kMogaiSuiteName];
        if ([defaults boolForKey:@"MogaiCleanRequested"]) {
            NSLog(@"[Mogai] Clean requested — performing full sandbox cleanup");
            [[SandboxCleaner sharedInstance] cleanAllForBundleID:[[NSBundle mainBundle] bundleIdentifier]];
            [defaults setBool:NO forKey:@"MogaiCleanRequested"];
            [defaults synchronize];
            NSLog(@"[Mogai] Clean complete");
        }

        // 如果启用了随机化，生成新参数
        if ([DeviceRandomizer sharedInstance].randomizeOnLaunch) {
            [[DeviceRandomizer sharedInstance] generateNewIdentity];
        }

        BOOL enabled = [DeviceRandomizer sharedInstance].enabled;
        NSLog(@"[Mogai] Enabled: %d", enabled);

        if (!enabled) return;

        // ===== 注册Objective-C方法Hook =====

        // UIDevice
        HookObjcMethod([UIDevice class], @selector(identifierForVendor),
            (IMP)hook_uidv_identifierForVendor, (IMP *)&orig_uidv_identifierForVendor);
        HookObjcMethod([UIDevice class], @selector(name),
            (IMP)hook_uidv_name, (IMP *)&orig_uidv_name);
        HookObjcMethod([UIDevice class], @selector(model),
            (IMP)hook_uidv_model, (IMP *)&orig_uidv_model);
        HookObjcMethod([UIDevice class], @selector(systemVersion),
            (IMP)hook_uidv_systemVersion, (IMP *)&orig_uidv_systemVersion);
        HookObjcMethod([UIDevice class], @selector(localizedModel),
            (IMP)hook_uidv_localizedModel, (IMP *)&orig_uidv_localizedModel);

        // NSProcessInfo
        HookObjcMethod([NSProcessInfo class], @selector(operatingSystemVersionString),
            (IMP)hook_pi_operatingSystemVersionString, (IMP *)&orig_pi_operatingSystemVersionString);
        HookObjcMethod([NSProcessInfo class], @selector(hostName),
            (IMP)hook_pi_hostName, (IMP *)&orig_pi_hostName);
        HookObjcMethod([NSProcessInfo class], @selector(systemUptime),
            (IMP)hook_pi_systemUptime, (IMP *)&orig_pi_systemUptime);

        // NSLocale
        HookObjcClassMethod([NSLocale class], @selector(currentLocale),
            (IMP)hook_locale_currentLocale, (IMP *)&orig_locale_currentLocale);
        HookObjcClassMethod([NSLocale class], @selector(autoupdatingCurrentLocale),
            (IMP)hook_locale_autoupdatingCurrentLocale, (IMP *)&orig_locale_autoupdatingCurrentLocale);

        // NSTimeZone
        HookObjcClassMethod([NSTimeZone class], @selector(localTimeZone),
            (IMP)hook_tz_localTimeZone, (IMP *)&orig_tz_localTimeZone);
        HookObjcClassMethod([NSTimeZone class], @selector(systemTimeZone),
            (IMP)hook_tz_systemTimeZone, (IMP *)&orig_tz_systemTimeZone);

        // NSFileManager
        HookObjcMethod([NSFileManager class], @selector(fileExistsAtPath:),
            (IMP)hook_fm_fileExistsAtPath, (IMP *)&orig_fm_fileExistsAtPath);
        HookObjcMethod([NSFileManager class], @selector(fileExistsAtPath:isDirectory:),
            (IMP)hook_fm_fileExistsAtPath_isDirectory, (IMP *)&orig_fm_fileExistsAtPath_isDirectory);

        // ===== 注册C函数Hook (fishhook) =====

        struct rebinding bindings[] = {
            // Keychain
            {"SecItemCopyMatching", hook_SecItemCopyMatching, (void *)&orig_SecItemCopyMatching},

            // 文件系统
            {"stat", hook_stat, (void *)&orig_stat},
            {"lstat", hook_lstat, (void *)&orig_lstat},
            {"access", hook_access, (void *)&orig_access},
            {"open", hook_open, (void *)&orig_open},

            // 系统信息
            {"sysctl", hook_sysctl, (void *)&orig_sysctl},
            {"sysctlbyname", hook_sysctlbyname, (void *)&orig_sysctlbyname},

            // 动态库注入检测
            {"dladdr", hook_dladdr, (void *)&orig_dladdr},
            {"_dyld_image_count", hook_dyld_image_count, (void *)&orig_dyld_image_count},
            {"_dyld_get_image_name", hook_dyld_get_image_name, (void *)&orig_dyld_get_image_name},
        };

        rebind_symbols(bindings, sizeof(bindings) / sizeof(struct rebinding));

        // ===== MobileGestalt Hook =====
        // MGCopyAnswer 可能不是所有镜像都绑定，通过 dlsym 尝试获取
        void *mgSymbol = dlsym(RTLD_DEFAULT, "MGCopyAnswer");
        if (mgSymbol) {
            orig_MGCopyAnswer = mgSymbol;
            struct rebinding mgBinding[] = {
                {"MGCopyAnswer", hook_MGCopyAnswer, NULL},
            };
            rebind_symbols(mgBinding, 1);
            NSLog(@"[Mogai] MobileGestalt hooked");
        } else {
            NSLog(@"[Mogai] MobileGestalt not available in this process");
        }

        NSLog(@"[Mogai] ===== 魔改新机 v2.0 Pro injected successfully =====");
    }
}
