#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

// 共享suite常量（必须与dylib一致）
extern NSString *const kMogaiSuiteName;
extern NSString *const kEnabledKey;
extern NSString *const kCustomModelKey;
extern NSString *const kCustomSysVerKey;
extern NSString *const kRandomizeOnLaunchKey;
extern NSString *const kCurrentIDFVKey;
extern NSString *const kCurrentDeviceNameKey;
extern NSString *const kCurrentModelKey;
extern NSString *const kCurrentSysVerKey;
extern NSString *const kCurrentSerialKey;
extern NSString *const kCurrentWifiMacKey;
extern NSString *const kCurrentBtMacKey;
extern NSString *const kCurrentLocaleKey;
extern NSString *const kCurrentTZKey;

@interface MogaiConfig : NSObject

@property (nonatomic, assign) BOOL enabled;
@property (nonatomic, copy, nullable) NSString *customModel;
@property (nonatomic, copy, nullable) NSString *customSystemVersion;
@property (nonatomic, assign) BOOL randomizeOnLaunch;

@property (nonatomic, copy, nullable) NSString *currentIDFV;
@property (nonatomic, copy, nullable) NSString *currentDeviceName;
@property (nonatomic, copy, nullable) NSString *currentModel;
@property (nonatomic, copy, nullable) NSString *currentSystemVersion;
@property (nonatomic, copy, nullable) NSString *currentSerialNumber;
@property (nonatomic, copy, nullable) NSString *currentWifiMac;
@property (nonatomic, copy, nullable) NSString *currentBluetoothMac;
@property (nonatomic, copy, nullable) NSString *currentLocale;
@property (nonatomic, copy, nullable) NSString *currentTimeZone;

+ (instancetype)sharedConfig;
- (void)load;
- (void)save;
- (void)generateNew;
- (void)resetToDefaults;

@end

NS_ASSUME_NONNULL_END
