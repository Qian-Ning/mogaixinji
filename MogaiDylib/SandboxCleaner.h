#import <Foundation/Foundation.h>

@interface SandboxCleaner : NSObject

+ (instancetype)sharedInstance;
- (void)performFullCleanForBundleID:(NSString *)bundleID;
- (void)cleanKeychainForService:(NSString *)serviceName;
- (void)cleanUserDefaultsForBundleID:(NSString *)bundleID;
- (void)cleanCacheDirectoryForBundleID:(NSString *)bundleID;
- (void)cleanCookies;
- (void)cleanAllForBundleID:(NSString *)bundleID;

@end
