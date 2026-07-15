#import <Foundation/Foundation.h>

// 系统级改机：直接修改 MobileGestalt 缓存 + 系统偏好
// 需要 com.apple.private.security.no-container 权限（TrollStore）
// 效果：全设备所有APP生效，无需注入

@interface SystemModifier : NSObject

+ (instancetype)shared;

// 查找 MobileGestalt 缓存文件路径
- (NSString *)findMGCachePath;

// 修改 MobileGestalt 缓存（核心）
- (BOOL)applyToMGCacheWithModel:(NSString *)model
                      sysVersion:(NSString *)sysVersion
                      deviceName:(NSString *)deviceName
                         serialN:(NSString *)serial
                     wifiAddress:(NSString *)wifiMac
                      btAddress:(NSString *)btMac
                       udid:(NSString *)udid
                        locale:(NSString *)locale
                      timezone:(NSString *)timezone;

// 调用 MGSetAnswer 私有API（立即生效）
- (void)applyMGSetAnswerWithModel:(NSString *)model
                        sysVersion:(NSString *)sysVersion
                        deviceName:(NSString *)deviceName
                           serialN:(NSString *)serial
                       wifiAddress:(NSString *)wifiMac
                        btAddress:(NSString *)btMac
                             udid:(NSString *)udid;

// 修改系统偏好（区域、时区、设备名）
- (void)applySystemPreferencesWithLocale:(NSString *)locale
                               timezone:(NSString *)timezone
                             deviceName:(NSString *)deviceName;

// 刷新 MobileGestalt 守护进程
- (void)refreshMobileGestalt;

// 读取当前缓存中的值
- (NSDictionary *)readCurrentCache;

@end