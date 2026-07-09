#import "MogaiConfig.h"

static NSString *ConfigPath(void) {
    return @"/var/mobile/Documents/.mogai_config.plist";
}

static NSArray *Models(void) {
    return @[@"iPhone16,2", @"iPhone16,1", @"iPhone15,5", @"iPhone15,4", @"iPhone15,3", @"iPhone15,2", @"iPhone14,6"];
}

static NSArray *Versions(void) {
    return @[@"17.5.1", @"17.4.1", @"16.7", @"16.6.1", @"16.5.1", @"15.8"];
}

static NSString *RandomMAC(void) {
    return [NSString stringWithFormat:@"%02x:%02x:%02x:%02x:%02x:%02x",
        arc4random_uniform(256), arc4random_uniform(256), arc4random_uniform(256),
        arc4random_uniform(256), arc4random_uniform(256), arc4random_uniform(256)];
}

static NSString *RandomUUID(void) {
    CFUUIDRef u = CFUUIDCreate(NULL);
    CFStringRef s = CFUUIDCreateString(NULL, u);
    CFRelease(u);
    return (__bridge_transfer NSString *)s;
}

static NSString *RandomName(void) {
    NSArray *n = @[@"iPhone", @"My iPhone", @"iPhone 15 Pro"];
    return n[arc4random_uniform((uint32_t)n.count)];
}

@implementation MogaiConfig

+ (instancetype)sharedConfig {
    static MogaiConfig *i = nil;
    static dispatch_once_t t;
    dispatch_once(&t, ^{ i = [[self alloc] init]; });
    return i;
}

- (void)load {
    NSDictionary *dict = [NSDictionary dictionaryWithContentsOfFile:ConfigPath()];
    if (!dict || dict.count == 0) {
        self.enabled = YES;
        self.randomizeOnLaunch = YES;
        [self generateNew];
        return;
    }
    self.enabled = [dict[@"enabled"] boolValue];
    self.customModel = dict[@"customModel"];
    self.customSystemVersion = dict[@"customSysVer"];
    self.randomizeOnLaunch = [dict[@"randomizeOnLaunch"] boolValue];
    self.cleanRequested = [dict[@"cleanRequested"] boolValue];
    self.currentIDFV = dict[@"idfv"];
    self.currentDeviceName = dict[@"deviceName"];
    self.currentModel = dict[@"model"];
    self.currentSystemVersion = dict[@"sysVer"];
    self.currentSerialNumber = dict[@"serial"];
    self.currentWifiMac = dict[@"wifiMac"];
    self.currentBluetoothMac = dict[@"btMac"];
    self.currentLocale = dict[@"locale"];
    self.currentTimeZone = dict[@"timezone"];
}

- (void)save {
    NSMutableDictionary *dict = [NSMutableDictionary dictionary];
    dict[@"enabled"] = @(self.enabled);
    if (self.customModel) dict[@"customModel"] = self.customModel;
    if (self.customSystemVersion) dict[@"customSysVer"] = self.customSystemVersion;
    dict[@"randomizeOnLaunch"] = @(self.randomizeOnLaunch);
    dict[@"cleanRequested"] = @(self.cleanRequested);
    if (self.currentIDFV) dict[@"idfv"] = self.currentIDFV;
    if (self.currentDeviceName) dict[@"deviceName"] = self.currentDeviceName;
    if (self.currentModel) dict[@"model"] = self.currentModel;
    if (self.currentSystemVersion) dict[@"sysVer"] = self.currentSystemVersion;
    if (self.currentSerialNumber) dict[@"serial"] = self.currentSerialNumber;
    if (self.currentWifiMac) dict[@"wifiMac"] = self.currentWifiMac;
    if (self.currentBluetoothMac) dict[@"btMac"] = self.currentBluetoothMac;
    if (self.currentLocale) dict[@"locale"] = self.currentLocale;
    if (self.currentTimeZone) dict[@"timezone"] = self.currentTimeZone;
    [dict writeToFile:ConfigPath() atomically:YES];
}

- (void)generateNew {
    self.currentIDFV = RandomUUID();
    self.currentDeviceName = RandomName();
    self.currentModel = self.customModel.length > 0 ? self.customModel : Models()[arc4random_uniform((uint32_t)Models().count)];
    self.currentSystemVersion = self.customSystemVersion.length > 0 ? self.customSystemVersion : Versions()[arc4random_uniform((uint32_t)Versions().count)];
    self.currentSerialNumber = RandomUUID();
    self.currentWifiMac = RandomMAC();
    self.currentBluetoothMac = RandomMAC();
    NSArray *l = @[@"zh_CN", @"en_US", @"ja_JP"];
    self.currentLocale = l[arc4random_uniform((uint32_t)l.count)];
    NSArray *t = @[@"Asia/Shanghai", @"America/New_York", @"Asia/Tokyo"];
    self.currentTimeZone = t[arc4random_uniform((uint32_t)t.count)];
    [self save];
}

- (void)resetToDefaults {
    self.enabled = YES;
    self.customModel = nil;
    self.customSystemVersion = nil;
    self.randomizeOnLaunch = YES;
    self.cleanRequested = NO;
    [self generateNew];
}

@end