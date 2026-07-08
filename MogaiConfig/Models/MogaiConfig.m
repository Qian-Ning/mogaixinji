#import "MogaiConfig.h"

NSString *const kMogaiSuiteName = @"group.com.mogai.config";
NSString *const kEnabledKey = @"MogaiEnabled";
NSString *const kCustomModelKey = @"MogaiCustomModel";
NSString *const kCustomSysVerKey = @"MogaiCustomSysVer";
NSString *const kRandomizeOnLaunchKey = @"MogaiRandomizeOnLaunch";
NSString *const kCurrentIDFVKey = @"MogaiCurrentIDFV";
NSString *const kCurrentDeviceNameKey = @"MogaiCurrentDeviceName";
NSString *const kCurrentModelKey = @"MogaiCurrentModel";
NSString *const kCurrentSysVerKey = @"MogaiCurrentSysVer";
NSString *const kCurrentSerialKey = @"MogaiCurrentSerial";
NSString *const kCurrentWifiMacKey = @"MogaiCurrentWifiMac";
NSString *const kCurrentBtMacKey = @"MogaiCurrentBtMac";
NSString *const kCurrentLocaleKey = @"MogaiCurrentLocale";
NSString *const kCurrentTZKey = @"MogaiCurrentTZ";

static NSArray *DeviceModels(void) {
    return @[
        @"iPhone16,2", @"iPhone16,1", @"iPhone15,5", @"iPhone15,4",
        @"iPhone15,3", @"iPhone15,2", @"iPhone15,1", @"iPhone14,6",
        @"iPhone14,5", @"iPhone14,4", @"iPhone14,3", @"iPhone14,2",
        @"iPhone14,7", @"iPhone14,8",
    ];
}

static NSArray *SysVersions(void) {
    return @[
        @"17.5.1", @"17.5", @"17.4.1", @"17.4", @"17.3.1", @"17.3",
        @"17.2.1", @"17.2", @"17.1.2", @"17.1", @"17.0",
        @"16.7", @"16.6.1", @"16.6", @"16.5.1", @"16.5",
    ];
}

static NSString *RandomMAC(void) {
    return [NSString stringWithFormat:@"%02x:%02x:%02x:%02x:%02x:%02x",
        arc4random_uniform(256), arc4random_uniform(256),
        arc4random_uniform(256), arc4random_uniform(256),
        arc4random_uniform(256), arc4random_uniform(256)];
}

static NSString *RandomUUID(void) {
    CFUUIDRef uuid = CFUUIDCreate(NULL);
    CFStringRef str = CFUUIDCreateString(NULL, uuid);
    CFRelease(uuid);
    return (__bridge_transfer NSString *)str;
}

static NSString *RandomDeviceName(void) {
    NSArray *names = @[@"iPhone", @"iPad", @"My iPhone", @"Apple Device",
        @"iPhone 15 Pro", @"iPhone 15 Pro Max", @"iPhone 16 Pro", @"Test iPhone"];
    return names[arc4random_uniform((uint32_t)names.count)];
}

@implementation MogaiConfig

+ (instancetype)sharedConfig {
    static MogaiConfig *instance = nil;
    static dispatch_once_t token;
    dispatch_once(&token, ^{
        instance = [[self alloc] init];
    });
    return instance;
}

- (void)load {
    NSUserDefaults *defaults = [[NSUserDefaults alloc] initWithSuiteName:kMogaiSuiteName];
    self.enabled = [defaults boolForKey:kEnabledKey];
    self.customModel = [defaults stringForKey:kCustomModelKey];
    self.customSystemVersion = [defaults stringForKey:kCustomSysVerKey];
    self.randomizeOnLaunch = [defaults boolForKey:kRandomizeOnLaunchKey];
    self.currentIDFV = [defaults stringForKey:kCurrentIDFVKey];
    self.currentDeviceName = [defaults stringForKey:kCurrentDeviceNameKey];
    self.currentModel = [defaults stringForKey:kCurrentModelKey];
    self.currentSystemVersion = [defaults stringForKey:kCurrentSysVerKey];
    self.currentSerialNumber = [defaults stringForKey:kCurrentSerialKey];
    self.currentWifiMac = [defaults stringForKey:kCurrentWifiMacKey];
    self.currentBluetoothMac = [defaults stringForKey:kCurrentBtMacKey];
    self.currentLocale = [defaults stringForKey:kCurrentLocaleKey];
    self.currentTimeZone = [defaults stringForKey:kCurrentTZKey];

    // 首次启动填充默认值
    if (!self.currentIDFV) [self generateNew];
}

- (void)save {
    NSUserDefaults *defaults = [[NSUserDefaults alloc] initWithSuiteName:kMogaiSuiteName];
    [defaults setBool:self.enabled forKey:kEnabledKey];
    if (self.customModel) [defaults setObject:self.customModel forKey:kCustomModelKey];
    else [defaults removeObjectForKey:kCustomModelKey];
    if (self.customSystemVersion) [defaults setObject:self.customSystemVersion forKey:kCustomSysVerKey];
    else [defaults removeObjectForKey:kCustomSysVerKey];
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

- (void)generateNew {
    self.currentIDFV = RandomUUID();
    self.currentDeviceName = RandomDeviceName();

    if (self.customModel.length > 0) {
        self.currentModel = self.customModel;
    } else {
        self.currentModel = DeviceModels()[arc4random_uniform((uint32_t)DeviceModels().count)];
    }

    if (self.customSystemVersion.length > 0) {
        self.currentSystemVersion = self.customSystemVersion;
    } else {
        self.currentSystemVersion = SysVersions()[arc4random_uniform((uint32_t)SysVersions().count)];
    }

    self.currentSerialNumber = RandomUUID();
    self.currentWifiMac = RandomMAC();
    self.currentBluetoothMac = RandomMAC();

    NSArray *locales = @[@"zh_CN", @"en_US", @"en_GB", @"ja_JP", @"ko_KR", @"zh_TW"];
    self.currentLocale = locales[arc4random_uniform((uint32_t)locales.count)];

    NSArray *tzs = @[@"Asia/Shanghai", @"America/New_York", @"Europe/London", @"Asia/Tokyo", @"Asia/Seoul"];
    self.currentTimeZone = tzs[arc4random_uniform((uint32_t)tzs.count)];

    [self save];
}

- (void)resetToDefaults {
    self.enabled = YES;
    self.customModel = nil;
    self.customSystemVersion = nil;
    self.randomizeOnLaunch = YES;
    [self generateNew];
}

@end
