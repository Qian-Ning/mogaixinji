#import <Foundation/Foundation.h>

@interface DeviceRandomizer : NSObject

+ (instancetype)sharedInstance;

// 配置读写
@property (nonatomic, assign) BOOL enabled;
@property (nonatomic, copy) NSString *customModel;
@property (nonatomic, copy) NSString *customSystemVersion;
@property (nonatomic, assign) BOOL randomizeOnLaunch;

// 当前生成的参数
@property (nonatomic, copy, readonly) NSString *currentIDFV;
@property (nonatomic, copy, readonly) NSString *currentDeviceName;
@property (nonatomic, copy, readonly) NSString *currentModel;
@property (nonatomic, copy, readonly) NSString *currentSystemVersion;
@property (nonatomic, copy, readonly) NSString *currentSerialNumber;
@property (nonatomic, copy, readonly) NSString *currentWifiMac;
@property (nonatomic, copy, readonly) NSString *currentBluetoothMac;
@property (nonatomic, copy, readonly) NSString *currentLocale;
@property (nonatomic, copy, readonly) NSString *currentTimeZone;

- (void)generateNewIdentity;
- (void)loadConfig;
- (void)saveConfig;
- (void)resetToDefaults;

// 日志
- (void)log:(NSString *)format, ... NS_FORMAT_FUNCTION(1, 2);
@property (nonatomic, strong, readonly) NSMutableArray *logEntries;

@end
