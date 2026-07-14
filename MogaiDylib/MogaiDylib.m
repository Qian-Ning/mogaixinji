#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <sys/sysctl.h>
#import <dlfcn.h>
#import "Fishhook/fishhook.h"
#import "DeviceRandomizer.h"

// ========== 原函数指针 ==========

static CFTypeRef (*orig_MGCopyAnswer)(CFStringRef key) = NULL;
static int (*orig_sysctl)(int *, u_int, void *, size_t *, void *, size_t);
static int (*orig_sysctlbyname)(const char *, void *, size_t *, void *, size_t);
static NSString *(*orig_idfv)(id, SEL);
static NSString *(*orig_name)(id, SEL);
static NSString *(*orig_model)(id, SEL);
static NSString *(*orig_sysVer)(id, SEL);
static NSString *(*orig_osVerStr)(id, SEL);
static NSString *(*orig_hostName)(id, SEL);
static void (*orig_presentVC)(id, SEL, UIViewController *, BOOL, void (^)(void));

static BOOL g_enabled = NO;
static NSString *const kMogaiHandled = @"MogaiHandled";

// ========== 1. NSURLProtocol ==========

@interface MogaiURLProtocol : NSURLProtocol
@end

@implementation MogaiURLProtocol

+ (BOOL)canInitWithRequest:(NSURLRequest *)request {
    if (!g_enabled) return NO;
    // 防止递归：已标记的请求直接放行
    if ([NSURLProtocol propertyForKey:kMogaiHandled inRequest:request]) return NO;
    NSString *host = request.URL.host;
    if (!host) return NO;
    return [host containsString:@"aweme"] || [host containsString:@"douyin"] ||
           [host containsString:@"tiktok"] || [host containsString:@"snssdk"] ||
           [host containsString:@"bytedance"] || [host containsString:@"byteimg"] ||
           [host containsString:@"byted"] || [host containsString:@"toutiao"] ||
           [host containsString:@"iesdouyin"];
}

+ (NSURLRequest *)canonicalRequestForRequest:(NSURLRequest *)request {
    return request;
}

- (void)startLoading {
    NSMutableURLRequest *mod = [self.request mutableCopy];

    // 标记此请求已处理，防止递归
    [NSURLProtocol setProperty:@YES forKey:kMogaiHandled inRequest:mod];

    // 抹除安全魔方签名头
    [mod setValue:nil forHTTPHeaderField:@"X-SS-REQ-TICKET"];
    [mod setValue:nil forHTTPHeaderField:@"X-Khronos"];
    [mod setValue:nil forHTTPHeaderField:@"X-Gorgon"];
    [mod setValue:nil forHTTPHeaderField:@"X-Argus"];

    // 随机化 URL 中 device_id / iid / openudid
    NSURLComponents *comps = [NSURLComponents componentsWithURL:mod.URL resolvingAgainstBaseURL:NO];
    if (comps) {
        NSMutableArray *items = [comps.queryItems mutableCopy] ?: [NSMutableArray array];
        NSArray *strip = @[@"device_id", @"install_id", @"iid", @"openudid", @"clientudid"];
        for (NSInteger i = items.count - 1; i >= 0; i--) {
            NSURLQueryItem *item = (NSURLQueryItem *)items[i];
            if ([strip containsObject:item.name]) [items removeObjectAtIndex:i];
        }
        comps.queryItems = items;
        mod.URL = comps.URL;
    }

    // 用 ephemeral config + 空 protocolClasses，避免被自己拦截
    NSURLSessionConfiguration *cfg = [NSURLSessionConfiguration ephemeralSessionConfiguration];
    cfg.protocolClasses = @[];
    NSURLSession *session = [NSURLSession sessionWithConfiguration:cfg delegate:nil delegateQueue:nil];

    NSURLSessionTask *task = [session dataTaskWithRequest:mod completionHandler:^(NSData *data, NSURLResponse *resp, NSError *err) {
        if (err) {
            [self.client URLProtocol:self didFailWithError:err];
        } else {
            [self.client URLProtocol:self didReceiveResponse:resp cacheStoragePolicy:NSURLCacheStorageNotAllowed];
            if (data) [self.client URLProtocol:self didLoadData:data];
            [self.client URLProtocolDidFinishLoading:self];
        }
    }];
    [task resume];
}

- (void)stopLoading {}

@end

// ========== 2. 验证弹窗拦截 ==========

static void hook_presentVC(id self, SEL _cmd, UIViewController *vc, BOOL animated, void (^completion)(void)) {
    if (g_enabled && vc) {
        NSString *cn = NSStringFromClass([vc class]);
        NSString *tt = vc.title ?: @"";
        // 只拦截抖音自己的验证弹窗，不碰系统弹窗
        NSBundle *b = [NSBundle bundleForClass:[vc class]];
        NSString *bid = b.bundleIdentifier ?: @"";
        BOOL isAppVC = [bid containsString:@"aweme"] || [bid containsString:@"douyin"] ||
                       [bid containsString:@"snssdk"] || [bid containsString:@"ugc"] ||
                       [bid containsString:@"bytedance"];
        if (isAppVC) {
            NSArray *kw = @[@"Captcha", @"Verify", @"Risk", @"Slider",
                            @"HumanVerify", @"SecurityCheck",
                            @"验证", @"滑块", @"校验"];
            for (NSString *w in kw) {
                if ([cn containsString:w] || [tt containsString:w]) {
                    NSLog(@"[Mogai] blocked: %@", cn);
                    if (completion) completion();
                    return;
                }
            }
        }
    }
    orig_presentVC(self, _cmd, vc, animated, completion);
}

// ========== 3. sysctl ==========

static int hook_sysctl(int *name, u_int namelen, void *oldp, size_t *oldlenp, void *newp, size_t newlen) {
    if (!g_enabled || !oldp || !oldlenp) return orig_sysctl(name, namelen, oldp, oldlenp, newp, newlen);
    if (namelen == 2 && name[0] == CTL_HW && (name[1] == HW_MACHINE || name[1] == HW_MODEL)) {
        const char *c = [[DeviceRandomizer sharedInstance].currentModel UTF8String];
        size_t len = strlen(c) + 1;
        if (*oldlenp >= len) memcpy(oldp, c, len);
        *oldlenp = len;
        return 0;
    }
    return orig_sysctl(name, namelen, oldp, oldlenp, newp, newlen);
}

static int hook_sysctlbyname(const char *name, void *oldp, size_t *oldlenp, void *newp, size_t newlen) {
    if (!g_enabled || !oldp || !oldlenp) return orig_sysctlbyname(name, oldp, oldlenp, newp, newlen);
    if (strcmp(name, "hw.machine") == 0 || strcmp(name, "hw.model") == 0) {
        const char *c = [[DeviceRandomizer sharedInstance].currentModel UTF8String];
        size_t len = strlen(c) + 1;
        if (*oldlenp >= len) memcpy(oldp, c, len);
        *oldlenp = len;
        return 0;
    }
    return orig_sysctlbyname(name, oldp, oldlenp, newp, newlen);
}

// ========== 4. UIDevice ==========

static NSString *hook_idfv(id self, SEL _cmd)   { return g_enabled ? [DeviceRandomizer sharedInstance].currentIDFV : orig_idfv(self, _cmd); }
static NSString *hook_name(id self, SEL _cmd)   { return g_enabled ? [DeviceRandomizer sharedInstance].currentDeviceName : orig_name(self, _cmd); }
static NSString *hook_model(id self, SEL _cmd)  { return g_enabled ? [DeviceRandomizer sharedInstance].currentModel : orig_model(self, _cmd); }
static NSString *hook_sysVer(id self, SEL _cmd) { return g_enabled ? [DeviceRandomizer sharedInstance].currentSystemVersion : orig_sysVer(self, _cmd); }

// ========== 5. NSProcessInfo ==========

static NSString *hook_osVerStr(id self, SEL _cmd) {
    if (!g_enabled) return orig_osVerStr(self, _cmd);
    return [NSString stringWithFormat:@"Version %@", [DeviceRandomizer sharedInstance].currentSystemVersion];
}

static NSString *hook_hostName(id self, SEL _cmd) {
    return g_enabled ? [DeviceRandomizer sharedInstance].currentDeviceName : orig_hostName(self, _cmd);
}

// ========== 6. MobileGestalt ==========

static CFTypeRef hook_MGCopyAnswer(CFStringRef key) {
    if (!g_enabled || !orig_MGCopyAnswer) return orig_MGCopyAnswer ? orig_MGCopyAnswer(key) : NULL;
    DeviceRandomizer *dr = [DeviceRandomizer sharedInstance];
    NSString *k = (__bridge NSString *)key;

    if ([k hasPrefix:@"Unique"] || [k hasSuffix:@"SerialNumber"] || [k containsString:@"ChipID"])
        return (__bridge CFStringRef)[dr.currentSerialNumber copy];
    if ([k isEqualToString:@"ProductType"] || [k isEqualToString:@"HWModelStr"])
        return (__bridge CFStringRef)[dr.currentModel copy];
    if ([k isEqualToString:@"ProductVersion"] || [k isEqualToString:@"BuildVersion"])
        return (__bridge CFStringRef)[dr.currentSystemVersion copy];
    if ([k isEqualToString:@"WifiAddress"] || [k isEqualToString:@"WifiAddressData"])
        return (__bridge CFStringRef)[dr.currentWifiMac copy];
    if ([k isEqualToString:@"BluetoothAddress"])
        return (__bridge CFStringRef)[dr.currentBluetoothMac copy];
    if ([k isEqualToString:@"UserAssignedDeviceName"] || [k isEqualToString:@"DeviceName"])
        return (__bridge CFStringRef)[dr.currentDeviceName copy];
    if ([k isEqualToString:@"RegionCode"] || [k isEqualToString:@"RegionInfo"])
        return (__bridge CFStringRef)[dr.currentLocale copy];
    if ([k isEqualToString:@"MainScreenWidth"])  return (__bridge CFNumberRef)@390;
    if ([k isEqualToString:@"MainScreenHeight"]) return (__bridge CFNumberRef)@844;
    if ([k isEqualToString:@"MainScreenScale"])  return (__bridge CFNumberRef)@3.0;

    return orig_MGCopyAnswer(key);
}

// ========== Helpers ==========

static void Swizzle(Class cls, SEL sel, IMP newImp, IMP *old) {
    Method m = class_getInstanceMethod(cls, sel);
    if (m) *old = method_setImplementation(m, newImp);
}

static void SoftClean(void) {
    @autoreleasepool {
        NSString *home = NSHomeDirectory();
        if (!home) return;
        NSFileManager *fm = [NSFileManager defaultManager];
        for (NSString *dir in @[
            [home stringByAppendingPathComponent:@"Library/Caches"],
            [home stringByAppendingPathComponent:@"tmp"]
        ]) {
            NSArray *items = [[fm contentsOfDirectoryAtPath:dir error:nil] copy];
            for (NSString *item in items)
                [fm removeItemAtPath:[dir stringByAppendingPathComponent:item] error:nil];
        }
        // Cookie: copy array first, then delete
        NSArray *cookies = [[NSHTTPCookieStorage sharedHTTPCookieStorage].cookies copy];
        for (NSHTTPCookie *c in cookies)
            [[NSHTTPCookieStorage sharedHTTPCookieStorage] deleteCookie:c];
        [[NSURLCache sharedURLCache] removeAllCachedResponses];
    }
}

// ========== Constructor ==========

__attribute__((constructor(101)))
static void MogaiInit(void) {
    @autoreleasepool {
        NSLog(@"[Mogai] injecting into %@", [[NSBundle mainBundle] bundleIdentifier]);

        [[DeviceRandomizer sharedInstance] loadConfig];
        g_enabled = [DeviceRandomizer sharedInstance].enabled;
        if (!g_enabled) return;

        if ([DeviceRandomizer sharedInstance].cleanRequested) {
            SoftClean();
            [DeviceRandomizer sharedInstance].cleanRequested = NO;
            [[DeviceRandomizer sharedInstance] saveConfig];
        }
        if ([DeviceRandomizer sharedInstance].randomizeOnLaunch)
            [[DeviceRandomizer sharedInstance] generateNewIdentity];

        // GOT hooks
        struct rebinding sc[] = {
            {"sysctl", hook_sysctl, (void *)&orig_sysctl},
            {"sysctlbyname", hook_sysctlbyname, (void *)&orig_sysctlbyname},
        };
        rebind_symbols(sc, 2);

        orig_MGCopyAnswer = dlsym(RTLD_DEFAULT, "MGCopyAnswer");
        if (orig_MGCopyAnswer) {
            struct rebinding mg[] = {{"MGCopyAnswer", hook_MGCopyAnswer, NULL}};
            rebind_symbols(mg, 1);
        }

        // ObjC hooks
        Swizzle([UIDevice class], @selector(identifierForVendor), (IMP)hook_idfv, (IMP *)&orig_idfv);
        Swizzle([UIDevice class], @selector(name), (IMP)hook_name, (IMP *)&orig_name);
        Swizzle([UIDevice class], @selector(model), (IMP)hook_model, (IMP *)&orig_model);
        Swizzle([UIDevice class], @selector(systemVersion), (IMP)hook_sysVer, (IMP *)&orig_sysVer);
        Swizzle([NSProcessInfo class], @selector(operatingSystemVersionString), (IMP)hook_osVerStr, (IMP *)&orig_osVerStr);
        Swizzle([NSProcessInfo class], @selector(hostName), (IMP)hook_hostName, (IMP *)&orig_hostName);

        // UI 拦截
        Swizzle([UIViewController class], @selector(presentViewController:animated:completion:),
                (IMP)hook_presentVC, (IMP *)&orig_presentVC);

        // NSURLProtocol
        [NSURLProtocol registerClass:[MogaiURLProtocol class]];

        NSLog(@"[Mogai] hooks active — %@ / iOS %@",
              [DeviceRandomizer sharedInstance].currentModel,
              [DeviceRandomizer sharedInstance].currentSystemVersion);
    }
}