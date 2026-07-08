#import "DeviceRandomizer.h"

// 共享suite名称，配置APP和dylib通过此通信
static NSString *const kMogaiSuiteName = @"group.com.mogai.config";
static NSString *const kEnabledKey = @"MogaiEnabled";
static NSString *const kCustomModelKey = @"MogaiCustomModel";
static NSString *const kCustomSysVerKey = @"MogaiCustomSysVer";
static NSString *const kRandomizeOnLaunchKey = @"MogaiRandomizeOnLaunch";
static NSString *const kCurrentIDFVKey = @"MogaiCurrentIDFV";
static NSString *const kCurrentDeviceNameKey = @"MogaiCurrentDeviceName";
static NSString *const kCurrentModelKey = @"MogaiCurrentModel";
static NSString *const kCurrentSysVerKey = @"MogaiCurrentSysVer";
static NSString *const kCurrentSerialKey = @"MogaiCurrentSerial";
static NSString *const kCurrentWifiMacKey = @"MogaiCurrentWifiMac";
static NSString *const kCurrentBtMacKey = @"MogaiCurrentBtMac";
static NSString *const kCurrentLocaleKey = @"MogaiCurrentLocale";
static NSString *const kCurrentTZKey = @"MogaiCurrentTZ";

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

static NSArray *kDeviceModels(void) {
    return @[
        @"iPhone16,2", @"iPhone16,1", @"iPhone15,5", @"iPhone15,4",
        @"iPhone15,3", @"iPhone15,2", @"iPhone15,1", @"iPhone14,6",
        @"iPhone14,5", @"iPhone14,4", @"iPhone14,3", @"iPhone14,2",
        @"iPhone14,7", @"iPhone14,8",
        @"iPad14,3", @"iPad14,4",
    ];
}

static NSArray *kSystemVersions(void) {
    return @[
        @"17.5.1", @"17.5", @"17.4.1", @"17.4", @"17.3.1", @"17.3",
        @"17.2.1", @"17.2", @"17.1.2", @"17.1", @"17.0",
        @"16.7", @"16.6.1", @"16.6", @"16.5.1", @"16.5",
        @"16.4.1", @"16.4", @"16.3.1", @"16.3", @"16.2", @"16.1", @"16.0",
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
    NSArray *names = @[
        @"iPhone", @"iPad", @"Apple Device",
        @"My iPhone", @"iPhone 15 Pro", @"iPhone 15 Pro Max",
        @"iPhone 16", @"iPhone 16 Pro",
        @"iDevice", @"Test iPhone",
        @"Personal iPhone",
    ];
    return names[arc4random_uniform((uint32_t)names.count)];
}

@implementation DeviceRandomizer

+ (instancetype)sharedInstance {
    static DeviceRandomizer *instance = nil;
    static dispatch_once_t token;
    dispatch_once(&token, ^{
        instance = [[self alloc] init];
    });
    return instance;
}

- (instancetype)init {
    if (self = [super init]) {
        _logEntries = [NSMutableArray array];
        [self log:@"DeviceRandomizer initialized"];
    }
    return self;
}

- (void)generateNewIdentity {
    self.currentIDFV = kRandomUUID();
    self.currentDeviceName = kRandomDeviceName();

    if (self.customModel.length > 0) {
        self.currentModel = self.customModel;
    } else {
        NSArray *models = kDeviceModels();
        self.currentModel = models[arc4random_uniform((uint32_t)models.count)];
    }

    if (self.customSystemVersion.length > 0) {
        self.currentSystemVersion = self.customSystemVersion;
    } else {
        NSArray *versions = kSystemVersions();
        self.currentSystemVersion = versions[arc4random_uniform((uint32_t)versions.count)];
    }

    self.currentSerialNumber = [NSString stringWithFormat:@"%@", kRandomUUID()];
    self.currentWifiMac = kRandomMAC();
    self.currentBluetoothMac = kRandomMAC();

    // 区域和时区
    NSArray *locales = @[@"zh_CN", @"en_US", @"en_GB", @"ja_JP", @"ko_KR", @"zh_TW", @"zh_HK", @"fr_FR", @"de_DE"];
    self.currentLocale = locales[arc4random_uniform((uint32_t)locales.count)];

    NSArray *timezones = @[@"Asia/Shanghai", @"America/New_York", @"Europe/London", @"Asia/Tokyo", @"Asia/Seoul", @"Europe/Berlin", @"Australia/Sydney", @"America/Los_Angeles"];
    self.currentTimeZone = timezones[arc4random_uniform((uint32_t)timezones.count)];

    [self log:@"New identity generated: %@ / %@ / %@", self.currentModel, self.currentSystemVersion, self.currentIDFV];
    [self saveConfig];
}

- (void)loadConfig {
    NSUserDefaults *defaults = [[NSUserDefaults alloc] initWithSuiteName:kMogaiSuiteName];
    self.enabled = [defaults boolForKey:kEnabledKey];
    self.customModel = [defaults stringForKey:kCustomModelKey];
    self.customSystemVersion = [defaults stringForKey:kCustomSysVerKey];
    self.randomizeOnLaunch = [defaults boolForKey:kRandomizeOnLaunchKey];

    self.currentIDFV = [defaults stringForKey:kCurrentIDFVKey] ?: kRandomUUID();
    self.currentDeviceName = [defaults stringForKey:kCurrentDeviceNameKey] ?: kRandomDeviceName();
    self.currentModel = [defaults stringForKey:kCurrentModelKey] ?: kDeviceModels()[0];
    self.currentSystemVersion = [defaults stringForKey:kCurrentSysVerKey] ?: @"17.5.1";
    self.currentSerialNumber = [defaults stringForKey:kCurrentSerialKey] ?: kRandomUUID();
    self.currentWifiMac = [defaults stringForKey:kCurrentWifiMacKey] ?: kRandomMAC();
    self.currentBluetoothMac = [defaults stringForKey:kCurrentBtMacKey] ?: kRandomMAC();
    self.currentLocale = [defaults stringForKey:kCurrentLocaleKey] ?: @"zh_CN";
    self.currentTimeZone = [defaults stringForKey:kCurrentTZKey] ?: @"Asia/Shanghai";

    if (self.randomizeOnLaunch) {
        [self generateNewIdentity];
    }

    [self log:@"Config loaded. Enabled: %d", self.enabled];
}

- (void)saveConfig {
    NSUserDefaults *defaults = [[NSUserDefaults alloc] initWithSuiteName:kMogaiSuiteName];
    [defaults setBool:self.enabled forKey:kEnabledKey];
    if (self.customModel) [defaults setObject:self.customModel forKey:kCustomModelKey];
    if (self.customSystemVersion) [defaults setObject:self.customSystemVersion forKey:kCustomSysVerKey];
    [defaults setBool:self.randomizeOnLaunch forKey:kRandomizeOnLaunchKey];
    if (self.currentIDFV) [defaults setObject:self.currentIDFV forKey:kCurrentIDFVKey];
    if (self.currentDeviceName) [defaults setObject:self.currentDeviceName forKey:kCurrentDeviceNameKey];
    if (self.currentModel) [defaults setObject:self.currentModel forKey:kCurrentModelKey];
    if (self.currentSystemVersion) [defaults setObject:self.currentSystemVersion forKey:kCurrentSysVerKey];
    if (self.currentSerialNumber) [defaults setObject:self.currentSerialNumber forKey:kCurrentSerialKey];
    if (self.currentWifiMac) [defaults setObject:self.currentWifiMac forKey:kCurrentWifiMacKey];
    if (self.currentBluetoothMac) [defaults setObject:self.currentBluetoothMac forKey:kCurrentBtMacKey];
    if (self.currentLocale) [defaults setObject:self.currentLocale forKey:kCurrentLocaleKey];
    if (self.currentTimeZone) [defaults setObject:self.currentTimeZone forKey:kCurrentTZKey];
    [defaults synchronize];
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
    NSString *timestamp = [df stringFromDate:[NSDate date]];
    NSString *entry = [NSString stringWithFormat:@"[%@] %@", timestamp, msg];

    dispatch_async(dispatch_get_main_queue(), ^{
        [self.logEntries addObject:entry];
        if (self.logEntries.count > 500) {
            [self.logEntries removeObjectsInRange:NSMakeRange(0, self.logEntries.count - 500)];
        }
        NSLog(@"[Mogai] %@", msg);
    });
}

@end
