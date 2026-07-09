#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface MogaiConfig : NSObject

@property (nonatomic, assign) BOOL enabled;
@property (nonatomic, copy, nullable) NSString *customModel;
@property (nonatomic, copy, nullable) NSString *customSystemVersion;
@property (nonatomic, assign) BOOL randomizeOnLaunch;
@property (nonatomic, assign) BOOL cleanRequested;

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