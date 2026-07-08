#import "SandboxCleaner.h"
#import "DeviceRandomizer.h"
#import <UIKit/UIKit.h>
#import <Security/Security.h>

@implementation SandboxCleaner

+ (instancetype)sharedInstance {
    static SandboxCleaner *instance = nil;
    static dispatch_once_t token;
    dispatch_once(&token, ^{
        instance = [[self alloc] init];
    });
    return instance;
}

- (NSString *)homePath {
    return NSHomeDirectory();
}

- (NSString *)documentsPath {
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    return paths.firstObject;
}

- (NSString *)libraryPath {
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSLibraryDirectory, NSUserDomainMask, YES);
    return paths.firstObject;
}

- (NSString *)cachesPath {
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES);
    return paths.firstObject;
}

- (NSString *)preferencesPath {
    return [[self libraryPath] stringByAppendingPathComponent:@"Preferences"];
}

- (void)performFullCleanForBundleID:(NSString *)bundleID {
    [[DeviceRandomizer sharedInstance] log:@"[SandboxCleaner] Full clean for %@", bundleID];
    [self cleanCacheDirectoryForBundleID:bundleID];
    [self cleanUserDefaultsForBundleID:bundleID];
    [self cleanKeychainForService:bundleID];
    [self cleanCookies];
    [[DeviceRandomizer sharedInstance] log:@"[SandboxCleaner] Full clean complete"];
}

- (void)cleanKeychainForService:(NSString *)serviceName {
    if (!serviceName) return;
    NSDictionary *query = @{
        (__bridge id)kSecClass: (__bridge id)kSecClassGenericPassword,
        (__bridge id)kSecAttrService: serviceName,
        (__bridge id)kSecMatchLimit: (__bridge id)kSecMatchLimitAll,
    };
    OSStatus status = SecItemDelete((__bridge CFDictionaryRef)query);
    if (status == errSecSuccess) {
        [[DeviceRandomizer sharedInstance] log:@"[Keychain] Deleted items for service: %@", serviceName];
    }

    // 也清理kSecClassInternetPassword
    NSDictionary *query2 = @{
        (__bridge id)kSecClass: (__bridge id)kSecClassInternetPassword,
        (__bridge id)kSecAttrServer: serviceName,
        (__bridge id)kSecMatchLimit: (__bridge id)kSecMatchLimitAll,
    };
    SecItemDelete((__bridge CFDictionaryRef)query2);

    // 清理kSecClassCertificate和kSecClassKey
    NSDictionary *query3 = @{
        (__bridge id)kSecClass: (__bridge id)kSecClassCertificate,
        (__bridge id)kSecMatchLimit: (__bridge id)kSecMatchLimitAll,
    };
    SecItemDelete((__bridge CFDictionaryRef)query3);

    [[DeviceRandomizer sharedInstance] log:@"[Keychain] Cleaned all keychain classes for %@", serviceName];
}

- (void)cleanUserDefaultsForBundleID:(NSString *)bundleID {
    NSString *prefsPath = [self preferencesPath];
    NSError *error = nil;
    NSArray *contents = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:prefsPath error:&error];
    if (error) return;

    for (NSString *file in contents) {
        if ([file containsString:bundleID] || [file hasSuffix:@".plist"]) {
            // 跳过系统plist
            if ([file isEqualToString:@"com.apple.PeoplePicker.plist"] ||
                [file isEqualToString:@"com.apple.Preferences.plist"]) continue;

            NSString *fullPath = [prefsPath stringByAppendingPathComponent:file];
            if (![file containsString:bundleID]) continue;

            [[NSFileManager defaultManager] removeItemAtPath:fullPath error:nil];
            [[DeviceRandomizer sharedInstance] log:@"[UserDefaults] Removed: %@", file];
        }
    }

    // 同步清除NSUserDefaults缓存
    NSString *suiteName = [[NSBundle mainBundle] bundleIdentifier];
    if (suiteName) {
        [[NSUserDefaults standardUserDefaults] removePersistentDomainForName:suiteName];
        [[NSUserDefaults standardUserDefaults] synchronize];
    }

    [[DeviceRandomizer sharedInstance] log:@"[UserDefaults] Cleaned preferences for %@", bundleID];
}

- (void)cleanCacheDirectoryForBundleID:(NSString *)bundleID {
    NSString *cachesPath = [self cachesPath];
    NSError *error = nil;
    NSArray *contents = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:cachesPath error:&error];
    if (error) {
        [[DeviceRandomizer sharedInstance] log:@"[Cache] Error reading caches: %@", error.localizedDescription];
        return;
    }

    for (NSString *item in contents) {
        if ([item isEqualToString:@"."] || [item isEqualToString:@".."]) continue;
        NSString *fullPath = [cachesPath stringByAppendingPathComponent:item];
        [[NSFileManager defaultManager] removeItemAtPath:fullPath error:nil];
    }

    // 清理tmp/目录
    NSString *tmpPath = NSTemporaryDirectory();
    NSArray *tmpContents = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:tmpPath error:nil];
    for (NSString *item in tmpContents) {
        if ([item isEqualToString:@"."] || [item isEqualToString:@".."]) continue;
        [[NSFileManager defaultManager] removeItemAtPath:[tmpPath stringByAppendingPathComponent:item] error:nil];
    }

    [[DeviceRandomizer sharedInstance] log:@"[Cache] Cache and tmp directories purged"];
}

- (void)cleanCookies {
    // 清除所有Cookie
    NSHTTPCookieStorage *cookieStorage = [NSHTTPCookieStorage sharedHTTPCookieStorage];
    NSArray *cookies = [cookieStorage cookies];
    for (NSHTTPCookie *cookie in cookies) {
        [cookieStorage deleteCookie:cookie];
    }
    [[DeviceRandomizer sharedInstance] log:@"[Cookies] All cookies deleted"];
}

- (void)cleanAllForBundleID:(NSString *)bundleID {
    [self performFullCleanForBundleID:bundleID];

    // 额外清理：Library/ 下其他敏感目录
    NSString *libraryPath = [self libraryPath];
    NSArray *subdirsToClean = @[
        @"WebKit",
        @"Safari",
        @"Caches",
        @"Preferences",
        @"Saved Application State",
    ];
    for (NSString *sub in subdirsToClean) {
        NSString *path = [libraryPath stringByAppendingPathComponent:sub];
        BOOL isDir = NO;
        if ([[NSFileManager defaultManager] fileExistsAtPath:path isDirectory:&isDir] && isDir) {
            if (![sub isEqualToString:@"Preferences"] && ![sub isEqualToString:@"Caches"]) {
                [[NSFileManager defaultManager] removeItemAtPath:path error:nil];
            }
        }
    }

    [[DeviceRandomizer sharedInstance] log:@"[Cleaner] Deep clean finished"];
}

@end
