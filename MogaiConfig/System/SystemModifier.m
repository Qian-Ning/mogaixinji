#import "SystemModifier.h"
#import <dlfcn.h>

@implementation SystemModifier

+ (instancetype)shared {
    static SystemModifier *i;
    static dispatch_once_t t;
    dispatch_once(&t, ^{ i = [[self alloc] init]; });
    return i;
}

// 查找 MobileGestalt 缓存路径
- (NSString *)findMGCachePath {
    // 常见路径（按优先级）
    NSArray *paths = @[
        @"/var/containers/Shared/SystemGroup/systemgroup.com.apple.mobilegestaltcache/Library/Caches/com.apple.MobileGestalt.plist",
        @"/var/mobile/Library/Caches/com.apple.MobileGestalt.plist",
        @"/var/containers/Shared/SystemGroup/systemgroup.com.apple.mobilegestaltcache/Library/Caches/MobileGestaltCache.db",
        @"/var/mobile/Library/Caches/MobileGestaltCache.db",
    ];
    for (NSString *p in paths) {
        if ([[NSFileManager defaultManager] fileExistsAtPath:p]) {
            NSLog(@"[System] MGCache found: %@", p);
            return p;
        }
    }
    // 动态搜索 systemgroup 目录
    NSString *base = @"/var/containers/Shared/SystemGroup";
    NSFileManager *fm = [NSFileManager defaultManager];
    NSArray *groups = [fm contentsOfDirectoryAtPath:base error:nil];
    for (NSString *g in groups) {
        NSString *p = [base stringByAppendingPathComponent:g];
        p = [p stringByAppendingPathComponent:@"Library/Caches/com.apple.MobileGestalt.plist"];
        if ([fm fileExistsAtPath:p]) {
            NSLog(@"[System] MGCache found (dynamic): %@", p);
            return p;
        }
    }
    NSLog(@"[System] MGCache not found!");
    return nil;
}

// 核心：修改 MobileGestalt 缓存
- (BOOL)applyToMGCacheWithModel:(NSString *)model
                      sysVersion:(NSString *)sysVersion
                      deviceName:(NSString *)deviceName
                         serialN:(NSString *)serial
                     wifiAddress:(NSString *)wifiMac
                      btAddress:(NSString *)btMac
                           udid:(NSString *)udid
                        locale:(NSString *)locale
                      timezone:(NSString *)timezone {
    NSString *path = [self findMGCachePath];
    if (!path) return NO;

    NSMutableDictionary *plist = [NSMutableDictionary dictionaryWithContentsOfFile:path];
    if (!plist) {
        NSLog(@"[System] Cannot read MGCache plist");
        return NO;
    }

    NSLog(@"[System] MGCache keys: %lu", (unsigned long)plist.count);

    // 获取或创建 CacheData
    NSMutableDictionary *cacheData = [plist[@"CacheData"] mutableCopy];
    if (!cacheData) {
        cacheData = [NSMutableDictionary dictionary];
    }

    // 写入伪造值
    if (model)      cacheData[@"ProductType"] = model;
    if (model)      cacheData[@"HWModelStr"] = model;
    if (sysVersion) cacheData[@"ProductVersion"] = sysVersion;
    if (deviceName) cacheData[@"UserAssignedDeviceName"] = deviceName;
    if (deviceName) cacheData[@"DeviceName"] = deviceName;
    if (serial)     cacheData[@"SerialNumber"] = serial;
    if (serial)     cacheData[@"MLBSerialNumber"] = serial;
    if (udid)       cacheData[@"UniqueDeviceID"] = udid;
    if (wifiMac)    cacheData[@"WifiAddress"] = wifiMac;
    if (btMac)      cacheData[@"BluetoothAddress"] = btMac;
    if (locale)     cacheData[@"RegionCode"] = locale;
    if (locale)     cacheData[@"RegionInfo"] = locale;
    if (timezone)   cacheData[@"TimeZone"] = timezone;

    // 屏幕参数匹配型号
    cacheData[@"MainScreenWidth"] = @390;
    cacheData[@"MainScreenHeight"] = @844;
    cacheData[@"MainScreenScale"] = @3.0;

    // 硬件参数
    cacheData[@"hw.machine"] = model;
    cacheData[@"hw.model"] = model;

    // 写回
    plist[@"CacheData"] = cacheData;

    // 备份原文件（第一次修改时）
    NSString *backupPath = [path stringByAppendingString:@".mogai_backup"];
    if (![[NSFileManager defaultManager] fileExistsAtPath:backupPath]) {
        [[NSFileManager defaultManager] copyItemAtPath:path toPath:backupPath error:nil];
        NSLog(@"[System] Backup created: %@", backupPath);
    }

    BOOL ok = [plist writeToFile:path atomically:YES];
    NSLog(@"[System] MGCache write: %@", ok ? @"SUCCESS" : @"FAILED");
    return ok;
}

// 调用 MGSetAnswer 私有API（立即生效，不需要重启）
- (void)applyMGSetAnswerWithModel:(NSString *)model
                        sysVersion:(NSString *)sysVersion
                        deviceName:(NSString *)deviceName
                           serialN:(NSString *)serial
                       wifiAddress:(NSString *)wifiMac
                        btAddress:(NSString *)btMac
                             udid:(NSString *)udid {
    // 尝试获取 MGSetAnswer 函数指针
    typedef void (*MGSetAnswerFunc)(CFStringRef key, CFTypeRef value);
    MGSetAnswerFunc MGSetAnswer = (MGSetAnswerFunc)dlsym(RTLD_DEFAULT, "MGSetAnswer");

    if (!MGSetAnswer) {
        NSLog(@"[System] MGSetAnswer not available, cache-only mode");
        return;
    }

    NSLog(@"[System] MGSetAnswer available, applying live values");

    if (model)      MGSetAnswer(CFSTR("ProductType"), (__bridge CFTypeRef)model);
    if (sysVersion) MGSetAnswer(CFSTR("ProductVersion"), (__bridge CFTypeRef)sysVersion);
    if (deviceName) MGSetAnswer(CFSTR("UserAssignedDeviceName"), (__bridge CFTypeRef)deviceName);
    if (deviceName) MGSetAnswer(CFSTR("DeviceName"), (__bridge CFTypeRef)deviceName);
    if (serial)     MGSetAnswer(CFSTR("SerialNumber"), (__bridge CFTypeRef)serial);
    if (serial)     MGSetAnswer(CFSTR("MLBSerialNumber"), (__bridge CFTypeRef)serial);
    if (udid)       MGSetAnswer(CFSTR("UniqueDeviceID"), (__bridge CFTypeRef)udid);
    if (wifiMac)    MGSetAnswer(CFSTR("WifiAddress"), (__bridge CFTypeRef)wifiMac);
    if (btMac)      MGSetAnswer(CFSTR("BluetoothAddress"), (__bridge CFTypeRef)btMac);

    NSLog(@"[System] MGSetAnswer applied");
}

// 修改系统偏好
- (void)applySystemPreferencesWithLocale:(NSString *)locale
                               timezone:(NSString *)timezone
                             deviceName:(NSString *)deviceName {
    // 区域设置
    if (locale) {
        NSString *intlPath = @"/var/mobile/Library/Preferences/com.apple.international.plist";
        NSMutableDictionary *intl = [NSMutableDictionary dictionaryWithContentsOfFile:intlPath];
        if (!intl) intl = [NSMutableDictionary dictionary];
        intl[@"Locale"] = locale;
        intl[@"AppleLanguages"] = @[locale];
        [intl writeToFile:intlPath atomically:YES];
        NSLog(@"[System] Locale set: %@", locale);
    }

    // 时区
    if (timezone) {
        NSString *tzPath = @"/var/mobile/Library/Preferences/com.apple.preferences.datetime.plist";
        NSMutableDictionary *tz = [NSMutableDictionary dictionaryWithContentsOfFile:tzPath];
        if (!tz) tz = [NSMutableDictionary dictionary];
        tz[@"TimeZone"] = timezone;
        [tz writeToFile:tzPath atomically:YES];

        // 直接设置系统时区
        system([[@"ln -sf /usr/share/zoneinfo/" stringByAppendingString:timezone]
                stringByAppendingPathComponent:@"/var/mobile/Library/Preferences/TimeZone"] UTF8String]);
        NSLog(@"[System] Timezone set: %@", timezone);
    }

    // 设备名（写入系统偏好）
    if (deviceName) {
        NSString *namePath = @"/var/mobile/Library/Preferences/com.apple.preferences.network.plist";
        NSMutableDictionary *name = [NSMutableDictionary dictionaryWithContentsOfFile:namePath];
        if (!name) name = [NSMutableDictionary dictionary];
        name[@"DeviceName"] = deviceName;
        [name writeToFile:namePath atomically:YES];
        NSLog(@"[System] Device name set: %@", deviceName);
    }
}

// 刷新 MobileGestalt 守护进程（让缓存立即生效）
- (void)refreshMobileGestalt {
    // 杀掉 mobilegestalt 守护进程，系统会重启它并读取我们修改的缓存
    system("killall -9 mobilegestalt 2>/dev/null");
    NSLog(@"[System] mobilegestalt refreshed");
}

// 读取当前缓存值
- (NSDictionary *)readCurrentCache {
    NSString *path = [self findMGCachePath];
    if (!path) return @{};

    NSDictionary *plist = [NSDictionary dictionaryWithContentsOfFile:path];
    return plist[@"CacheData"] ?: @{};
}

@end