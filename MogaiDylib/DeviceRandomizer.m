#import "DeviceRandomizer.h"

static NSString *ConfigPath(void) {
    return @"/var/mobile/Documents/.mogai_config.plist";
}

static NSArray *kDeviceModels(void) {
    return @[
        @"iPhone16,2", @"iPhone16,1", @"iPhone15,5", @"iPhone15,4",
        @"iPhone15,3", @"iPhone15,2", @"iPhone15,1", @"iPhone14,6",
        @"iPhone14,5", @"iPhone14,4", @"iPhone14,3", @"iPhone14,2",
        @"iPhone14,7", @"iPhone14,8",
    ];
}

static NSArray *kSystemVersions(void) {
    return @[
        @"17.5.1", @"17.5", @"17.4.1", @"17.4",
        @"16.7", @"16.6.1", @"16.6", @"16.5.1",
        @"15.8", @"15.7",
    ];
}

static NSString *kRandomMAC(void) {
    return [NSString stringWithFormat:@"%02x:%02x:%02x:%02x:%02x:%02x",
        arc4random_uniform(256), arc4random_uniform(256),
        arc4random_uniform(256), arc4random_uniform(256),
        arc4random_uniform(256), arc4random_uniform(256)];
}

static NSString *kRandomUUID(void) {
    CFUUIDRef uuid = CFUUIDCreate(NULL);
    CFStringRef str = CFUUIDCreateString(NULL, uuid);
    CFRelease(uuid);
    return (__bridge_transfer NSString *)str;
}

static NSString *kRandomDeviceName(void) {
    NSArray *names = @[@"iPhone", @"My iPhone", @"iPhone 15 Pro", @"iPhone 15 Pro Max", @"iPhone 16"];
    return names[arc4random_uniform((uint32_t)names.count)];
}

@interface DeviceRandomizer ()
@property (nonatomic, strong) NSMutableArray *logEntries;
@property (nonatomic, copy) NSString *currentIDFV;
@property (nonatomic, copy) NSString *currentDeviceName;
@property (nonatomic, copy) NSString *currentModel;
@property (nonatomic, copy) NSString *currentSystemVersion;
@property (nonatomic, copy) NSString *currentSerialNumber;
@property (nonatomic, copy) NSString *currentWifiMac;
@property (nonatomic, copy) NSString *currentBluetoothMac;
@property (nonatomic, copy) NSString *currentLocale;
@property (nonatomic, copy) NSString *currentTimeZone;
@end

@implementation DeviceRandomizer

+ (instancetype)sharedInstance {
    static DeviceRandomizer *instance = nil;
    static dispatch_once_t token;
    dispatch_once(&token, ^{ instance = [[self alloc] init]; });
    return instance;
}

- (instancetype)init {
    if (self = [super init]) {
        _logEntries = [NSMutableArray array];
    }
    return self;
}

- (void)generateNewIdentity {
    self.currentIDFV = kRandomUUID();
    self.currentDeviceName = kRandomDeviceName();

    if (self.customModel.length > 0) {
        self.currentModel = self.customModel;
    } else {
        self.currentModel = kDeviceModels()[arc4random_uniform((uint32_t)kDeviceModels().count)];
    }

    if (self.customSystemVersion.length > 0) {
        self.currentSystemVersion = self.customSystemVersion;
    } else {
        self.currentSystemVersion = kSystemVersions()[arc4random_uniform((uint32_t)kSystemVersions().count)];
    }

    self.currentSerialNumber = kRandomUUID();
    self.currentWifiMac = kRandomMAC();
    self.currentBluetoothMac = kRandomMAC();

    NSArray *locales = @[@"zh_CN", @"en_US", @"ja_JP", @"ko_KR", @"zh_TW"];
    self.currentLocale = locales[arc4random_uniform((uint32_t)locales.count)];

    NSArray *tzs = @[@"Asia/Shanghai", @"America/New_York", @"Europe/London", @"Asia/Tokyo", @"Asia/Seoul"];
    self.currentTimeZone = tzs[arc4random_uniform((uint32_t)tzs.count)];

    [self log:@"New identity: %@ / %@", self.currentModel, self.currentSystemVersion];
    [self saveConfig];
}

- (void)loadConfig {
    NSDictionary *dict = [NSDictionary dictionaryWithContentsOfFile:ConfigPath()];
    if (!dict || dict.count == 0) {
        [self log:@"No config file, generating defaults"];
        self.enabled = YES;
        self.randomizeOnLaunch = YES;
        [self generateNewIdentity];
        return;
    }
    self.enabled = [dict[@"enabled"] boolValue];
    self.customModel = dict[@"customModel"];
    self.customSystemVersion = dict[@"customSysVer"];
    self.randomizeOnLaunch = [dict[@"randomizeOnLaunch"] boolValue];
    self.currentIDFV = dict[@"idfv"] ?: kRandomUUID();
    self.currentDeviceName = dict[@"deviceName"] ?: kRandomDeviceName();
    self.currentModel = dict[@"model"] ?: @"iPhone15,3";
    self.currentSystemVersion = dict[@"sysVer"] ?: @"16.6.1";
    self.currentSerialNumber = dict[@"serial"] ?: kRandomUUID();
    self.currentWifiMac = dict[@"wifiMac"] ?: kRandomMAC();
    self.currentBluetoothMac = dict[@"btMac"] ?: kRandomMAC();
    self.currentLocale = dict[@"locale"] ?: @"zh_CN";
    self.currentTimeZone = dict[@"timezone"] ?: @"Asia/Shanghai";
    self.cleanRequested = [dict[@"cleanRequested"] boolValue];

    if (self.randomizeOnLaunch) {
        [self generateNewIdentity];
    }
    [self log:@"Config loaded. Enabled: %d", self.enabled];
}

- (void)saveConfig {
    NSMutableDictionary *dict = [NSMutableDictionary dictionary];
    dict[@"enabled"] = @(self.enabled);
    if (self.customModel) dict[@"customModel"] = self.customModel;
    if (self.customSystemVersion) dict[@"customSysVer"] = self.customSystemVersion;
    dict[@"randomizeOnLaunch"] = @(self.randomizeOnLaunch);
    if (self.currentIDFV) dict[@"idfv"] = self.currentIDFV;
    if (self.currentDeviceName) dict[@"deviceName"] = self.currentDeviceName;
    if (self.currentModel) dict[@"model"] = self.currentModel;
    if (self.currentSystemVersion) dict[@"sysVer"] = self.currentSystemVersion;
    if (self.currentSerialNumber) dict[@"serial"] = self.currentSerialNumber;
    if (self.currentWifiMac) dict[@"wifiMac"] = self.currentWifiMac;
    if (self.currentBluetoothMac) dict[@"btMac"] = self.currentBluetoothMac;
    if (self.currentLocale) dict[@"locale"] = self.currentLocale;
    if (self.currentTimeZone) dict[@"timezone"] = self.currentTimeZone;
    dict[@"cleanRequested"] = @(self.cleanRequested);
    [dict writeToFile:ConfigPath() atomically:YES];
}

- (void)resetToDefaults {
    self.enabled = YES;
    self.customModel = nil;
    self.customSystemVersion = nil;
    self.randomizeOnLaunch = YES;
    [self generateNewIdentity];
}

- (void)log:(NSString *)format, ... {
    va_list args;
    va_start(args, format);
    NSString *msg = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);
    NSDateFormatter *df = [[NSDateFormatter alloc] init];
    df.dateFormat = @"HH:mm:ss.SSS";
    NSString *entry = [NSString stringWithFormat:@"[%@] %@", [df stringFromDate:[NSDate date]], msg];
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.logEntries addObject:entry];
        if (self.logEntries.count > 500) {
            [self.logEntries removeObjectsInRange:NSMakeRange(0, self.logEntries.count - 500)];
        }
        NSLog(@"[Mogai] %@", msg);
    });
}

@end