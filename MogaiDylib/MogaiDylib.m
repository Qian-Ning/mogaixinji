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

// ========== 1. NSURLProtocol 网络层拦截 ==========

@interface MogaiURLProtocol : NSURLProtocol
@end

static NSMutableSet *g_interceptedURLs = nil;

@implementation MogaiURLProtocol

+ (void)load {
    // Handled in constructor
}

+ (BOOL)canInitWithRequest:(NSURLRequest *)request {
    if (request.URL.absoluteString.length == 0) return NO;
    // 只处理抖音 / TikTok 的请求
    NSString *host = request.URL.host;
    if (!host) return NO;
    if ([host containsString:@"aweme"] || [host containsString:@"douyin"] ||
        [host containsString:@"tiktok"] || [host containsString:@"snssdk"] ||
        [host containsString:@"bytedance"] || [host containsString:@"byteimg"] ||
        [host containsString:@"byted"] || [host containsString:@"toutiao"] ||
        [host containsString:@"iesdouyin"]) {
        return ![g_interceptedURLs containsObject:request.URL.absoluteString];
    }
    return NO;
}

+ (NSURLRequest *)canonicalRequestForRequest:(NSURLRequest *)request {
    return request;
}

- (void)startLoading {
    [g_interceptedURLs addObject:self.request.URL.absoluteString];

    NSMutableURLRequest *mod = [self.request mutableCopy];

    // 篡改 HTTP Header 中的设备信息
    [mod setValue:@"off" forHTTPHeaderField:@"X-SS-REQ-TICKET"]; // 安全魔方 ticket
    [mod setValue:[DeviceRandomizer sharedInstance].currentModel forHTTPHeaderField:@"X-SS-DEVICE-MODEL"];
    [mod setValue:[DeviceRandomizer sharedInstance].currentSystemVersion forHTTPHeaderField:@"X-SS-DEVICE-VERSION"];
    [mod setValue:[DeviceRandomizer sharedInstance].currentIDFV forHTTPHeaderField:@"X-SS-DEVICE-ID"];

    // 随机化 URL 参数中的 device_id / iid 等
    NSURLComponents *comps = [NSURLComponents componentsWithURL:mod.URL resolvingAgainstBaseURL:NO];
    NSMutableArray *queryItems = [comps.queryItems mutableCopy] ?: [NSMutableArray array];
    for (NSInteger i = queryItems.count - 1; i >= 0; i--) {
        NSURLQueryItem *item = queryItems[i];
        if ([item.name containsString:@"device_id"] ||
            [item.name containsString:@"install_id"] ||
            [item.name containsString:@"iid"] ||
            [item.name containsString:@"openudid"] ||
            [item.name containsString:@"clientudid"]) {
            [queryItems removeObjectAtIndex:i];
        }
    }
    comps.queryItems = queryItems;
    mod.URL = comps.URL;

    // 原始数据转发
    NSURLSessionTask *task = [[NSURLSession sharedSession] dataTaskWithRequest:mod completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        [g_interceptedURLs removeObject:self.request.URL.absoluteString];

        if (error) {
            [self.client URLProtocol:self didFailWithError:error];
        } else {
            // 检查响应中是否包含 verify/risk/captcha 的标记，尝试拦截
            NSMutableURLResponse *modResp = [response mutableCopy];
            if ([response isKindOfClass:[NSHTTPURLResponse class]]) {
                NSHTTPURLResponse *httpResp = (NSHTTPURLResponse *)response;
                NSMutableDictionary *headers = [httpResp.allHeaderFields mutableCopy];
                // 去掉服务器下发的安全验证标记
                [headers removeObjectForKey:@"X-SS-Verify-Required"];
                [headers removeObjectForKey:@"X-NEED-CAPTCHA"];
                [headers removeObjectForKey:@"X-Risk-Level"];
                modResp = [[NSHTTPURLResponse alloc] initWithURL:httpResp.URL statusCode:httpResp.statusCode HTTPVersion:@"HTTP/1.1" headerFields:headers] ?: modResp;
            }

            [self.client URLProtocol:self didReceiveResponse:modResp cacheStoragePolicy:NSURLCacheStorageNotAllowed];
            if (data) [self.client URLProtocol:self didLoadData:data];
            [self.client URLProtocolDidFinishLoading:self];
        }
    }];
    [task resume];
}

- (void)stopLoading {
    [g_interceptedURLs removeObject:self.request.URL.absoluteString];
}

@end

// ========== 2. 验证弹窗自动拦截 ==========

static void hook_presentVC(id self, SEL _cmd, UIViewController *vc, BOOL animated, void (^completion)(void)) {
    if (g_enabled) {
        NSString *className = NSStringFromClass([vc class]);
        NSString *title = vc.title ?: @"";
        // 检测验证相关弹窗并拦截
        if ([className containsString:@"Captcha"] ||
            [className containsString:@"Verify"] ||
            [className containsString:@"Check"] ||
            [className containsString:@"Risk"] ||
            [className containsString:@"Slider"] ||
            [className containsString:@"HumanVerify"] ||
            [className containsString:@"SecurityCheck"] ||
            [title containsString:@"验证"] ||
            [title containsString:@"滑块"] ||
            [title containsString:@"校验"] ||
            [title containsString:@"安全"]) {
            NSLog(@"[Mogai] Blocked verify VC: %@ (title: %@)", className, title);
            return;
        }
    }
    orig_presentVC(self, _cmd, vc, animated, completion);
}

// ========== 3. sysctl hooks ==========

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

// ========== 4. UIDevice hooks ==========

static NSString *hook_idfv(id self, SEL _cmd)       { return g_enabled ? [DeviceRandomizer sharedInstance].currentIDFV : orig_idfv(self, _cmd); }
static NSString *hook_name(id self, SEL _cmd)       { return g_enabled ? [DeviceRandomizer sharedInstance].currentDeviceName : orig_name(self, _cmd); }
static NSString *hook_model(id self, SEL _cmd)      { return g_enabled ? [DeviceRandomizer sharedInstance].currentModel : orig_model(self, _cmd); }
static NSString *hook_sysVer(id self, SEL _cmd)     { return g_enabled ? [DeviceRandomizer sharedInstance].currentSystemVersion : orig_sysVer(self, _cmd); }

// ========== 5. NSProcessInfo hooks ==========

static NSString *hook_osVerStr(id self, SEL _cmd) {
    if (!g_enabled) return orig_osVerStr(self, _cmd);
    return [NSString stringWithFormat:@"Version %@", [DeviceRandomizer sharedInstance].currentSystemVersion];
}

static NSString *hook_hostName(id self, SEL _cmd) {
    return g_enabled ? [DeviceRandomizer sharedInstance].currentDeviceName : orig_hostName(self, _cmd);
}

// ========== 6. MobileGestalt ==========

static CFTypeRef hook_MGCopyAnswer(CFStringRef key) {
    if (!g_enabled || !orig_MGCopyAnswer) return orig_MGCopyAnswer(key);
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
            for (NSString *item in [fm contentsOfDirectoryAtPath:dir error:nil])
                [fm removeItemAtPath:[dir stringByAppendingPathComponent:item] error:nil];
        }
        for (NSHTTPCookie *c in [NSHTTPCookieStorage sharedHTTPCookieStorage].cookies)
            [[NSHTTPCookieStorage sharedHTTPCookieStorage] deleteCookie:c];
        [[NSURLCache sharedURLCache] removeAllCachedResponses];
    }
}

// ========== Constructor ==========

__attribute__((constructor(101)))
static void MogaiInit(void) {
    @autoreleasepool {
        NSLog(@"[Mogai] injecting into %@", [[NSBundle mainBundle] bundleIdentifier]);

        g_interceptedURLs = [NSMutableSet set];

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

        // UI 拦截：阻止验证弹窗
        Swizzle([UIViewController class], @selector(presentViewController:animated:completion:),
                (IMP)hook_presentVC, (IMP *)&orig_presentVC);

        // NSURLProtocol 注册（网络层拦截）
        [NSURLProtocol registerClass:[MogaiURLProtocol class]];

        NSLog(@"[Mogai] all hooks active");
    }
}