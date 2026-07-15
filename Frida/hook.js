// ============================================================
// 魔改新机 — Frida Hook 脚本
// 目标: 抖音 (com.ss.iphone.ugc.Aweme)
// 用法: frida -U -f com.ss.iphone.ugc.Aweme -l hook.js
// ============================================================

// ========== 配置区（留空则随机生成）==========
var CONFIG = {
    model: "",              // 如 "iPhone15,3"，留空随机
    systemVersion: "",      // 如 "16.6.1"，留空随机
    deviceName: "",         // 如 "My iPhone"，留空随机
    locale: "zh_CN",
    timezone: "Asia/Shanghai"
};

// ========== 随机生成器 ==========

var MODELS = [
    "iPhone16,2", "iPhone16,1", "iPhone15,5", "iPhone15,4",
    "iPhone15,3", "iPhone15,2", "iPhone15,1", "iPhone14,6",
    "iPhone14,5", "iPhone14,4", "iPhone14,3", "iPhone14,2",
    "iPhone14,7", "iPhone14,8"
];

var VERSIONS = [
    "17.5.1", "17.5", "17.4.1", "17.4",
    "16.7", "16.6.1", "16.6", "16.5.1",
    "15.8", "15.7"
];

var DEVICE_NAMES = [
    "iPhone", "My iPhone", "iPhone 15 Pro", "iPhone 15 Pro Max",
    "iPhone 16", "iPhone 16 Pro", "Apple Device", "Personal iPhone"
];

function randomChoice(arr) {
    return arr[Math.floor(Math.random() * arr.length)];
}

function randomUUID() {
    var chars = "0123456789abcdef";
    var uuid = "";
    for (var i = 0; i < 36; i++) {
        if (i === 8 || i === 13 || i === 18 || i === 23) {
            uuid += "-";
        } else if (i === 14) {
            uuid += "4";
        } else if (i === 19) {
            uuid += chars[Math.floor(Math.random() * 4) + 8];
        } else {
            uuid += chars[Math.floor(Math.random() * 16)];
        }
    }
    return uuid;
}

function randomMAC() {
    var hex = "0123456789abcdef";
    var mac = "";
    for (var i = 0; i < 6; i++) {
        if (i > 0) mac += ":";
        mac += hex[Math.floor(Math.random() * 256)];
        mac += hex[Math.floor(Math.random() * 256)];
    }
    return mac;
}

// 生成当前设备身份
var IDENTITY = {
    idfv: randomUUID(),
    deviceName: CONFIG.deviceName || randomChoice(DEVICE_NAMES),
    model: CONFIG.model || randomChoice(MODELS),
    systemVersion: CONFIG.systemVersion || randomChoice(VERSIONS),
    serialNumber: randomUUID(),
    wifiMac: randomMAC(),
    btMac: randomMAC(),
    locale: CONFIG.locale,
    timezone: CONFIG.timezone
};

console.log("[Mogai-Frida] 生成设备身份:");
console.log("  型号: " + IDENTITY.model);
console.log("  版本: " + IDENTITY.systemVersion);
console.log("  IDFV: " + IDENTITY.idfv);
console.log("  设备名: " + IDENTITY.deviceName);
console.log("  序列号: " + IDENTITY.serialNumber);
console.log("  WiFi MAC: " + IDENTITY.wifiMac);
console.log("  蓝牙 MAC: " + IDENTITY.btMac);

// ========== Hook 实现 ==========

function hookUIDevice() {
    var UIDevice = ObjC.classes.UIDevice;

    // identifierForVendor
    var idfvMethod = UIDevice['- identifierForVendor'];
    Interceptor.attach(idfvMethod.implementation, {
        onLeave: function(retval) {
            var newUuid = ObjC.classes.NSUUID.alloc().initWithUUIDString_(IDENTITY.idfv);
            retval.replace(newUuid);
        }
    });

    // name
    Interceptor.attach(UIDevice['- name'].implementation, {
        onLeave: function(retval) {
            retval.replace(ObjC.classes.NSString.stringWithString_(IDENTITY.deviceName));
        }
    });

    // model
    Interceptor.attach(UIDevice['- model'].implementation, {
        onLeave: function(retval) {
            retval.replace(ObjC.classes.NSString.stringWithString_(IDENTITY.model));
        }
    });

    // systemVersion
    Interceptor.attach(UIDevice['- systemVersion'].implementation, {
        onLeave: function(retval) {
            retval.replace(ObjC.classes.NSString.stringWithString_(IDENTITY.systemVersion));
        }
    });

    console.log("[Mogai-Frida] UIDevice hooked");
}

function hookNSProcessInfo() {
    var NSProcessInfo = ObjC.classes.NSProcessInfo;

    Interceptor.attach(NSProcessInfo['- operatingSystemVersionString'].implementation, {
        onLeave: function(retval) {
            var str = "Version " + IDENTITY.systemVersion;
            retval.replace(ObjC.classes.NSString.stringWithString_(str));
        }
    });

    Interceptor.attach(NSProcessInfo['- hostName'].implementation, {
        onLeave: function(retval) {
            retval.replace(ObjC.classes.NSString.stringWithString_(IDENTITY.deviceName));
        }
    });

    console.log("[Mogai-Frida] NSProcessInfo hooked");
}

function hookMobileGestalt() {
    var MGCopyAnswer = Module.findExportByName(null, "MGCopyAnswer");
    if (!MGCopyAnswer) {
        console.log("[Mogai-Frida] MGCopyAnswer not found, skipping");
        return;
    }

    Interceptor.attach(MGCopyAnswer, {
        onEnter: function(args) {
            var key = new ObjC.Object(args[0]);
            this.keyStr = key.toString();
        },
        onLeave: function(retval) {
            if (retval.isNull()) return;

            var key = this.keyStr;
            var newVal = null;

            // Serial / Unique / ChipID
            if (key.indexOf("Unique") === 0 ||
                key.indexOf("SerialNumber", key.length - 12) !== -1 ||
                key.indexOf("ChipID") !== -1) {
                newVal = IDENTITY.serialNumber;
            }
            // Model
            else if (key === "ProductType" || key === "HWModelStr" ||
                     key === "ModelNumber" || key === "RegulatoryModelNumber") {
                newVal = IDENTITY.model;
            }
            // Version
            else if (key === "ProductVersion" || key === "BuildVersion") {
                newVal = IDENTITY.systemVersion;
            }
            // WiFi
            else if (key === "WifiAddress" || key === "WifiAddressData") {
                newVal = IDENTITY.wifiMac;
            }
            // Bluetooth
            else if (key === "BluetoothAddress") {
                newVal = IDENTITY.btMac;
            }
            // Device Name
            else if (key === "UserAssignedDeviceName" || key === "DeviceName") {
                newVal = IDENTITY.deviceName;
            }
            // Screen
            else if (key === "MainScreenWidth") {
                retval.replace(ObjC.classes.NSNumber.numberWithInt_(390));
                return;
            }
            else if (key === "MainScreenHeight") {
                retval.replace(ObjC.classes.NSNumber.numberWithInt_(844));
                return;
            }
            else if (key === "MainScreenScale") {
                retval.replace(ObjC.classes.NSNumber.numberWithDouble_(3.0));
                return;
            }
            // Region
            else if (key === "RegionCode" || key === "RegionInfo") {
                newVal = IDENTITY.locale;
            }

            if (newVal !== null) {
                retval.replace(ObjC.classes.NSString.stringWithString_(newVal));
            }
        }
    });

    console.log("[Mogai-Frida] MGCopyAnswer hooked");
}

function hookSysctl() {
    var sysctlbyname = Module.findExportByName(null, "sysctlbyname");
    if (!sysctlbyname) return;

    Interceptor.attach(sysctlbyname, {
        onEnter: function(args) {
            this.name = args[0].readUtf8String();
            this.oldp = args[1];
            this.oldlenp = args[2];
        },
        onLeave: function(retval) {
            if (retval.toInt32() !== 0) return;
            if (!this.oldp || this.oldp.isNull()) return;
            if (!this.oldlenp || this.oldlenp.isNull()) return;

            if (this.name === "hw.machine" || this.name === "hw.model") {
                var model = IDENTITY.model;
                var modelBytes = Memory.allocUtf8String(model);
                var len = model.length + 1;
                var bufLen = this.oldlenp.readU64();
                if (bufLen >= len) {
                    Memory.copy(this.oldp, modelBytes, len);
                }
                this.oldlenp.writeU64(len);
            }
        }
    });

    // sysctl (HW_MACHINE / HW_MODEL)
    var sysctl = Module.findExportByName(null, "sysctl");
    if (sysctl) {
        Interceptor.attach(sysctl, {
            onEnter: function(args) {
                this.name = args[0];
                this.namelen = args[1].toInt32();
                this.oldp = args[2];
                this.oldlenp = args[3];
            },
            onLeave: function(retval) {
                if (retval.toInt32() !== 0) return;
                if (!this.oldp || this.oldp.isNull()) return;
                if (this.namelen < 2) return;

                var mib0 = this.name.readInt();
                var mib1 = this.name.add(4).readInt();

                // CTL_HW=6, HW_MACHINE=1, HW_MODEL=2
                if (mib0 === 6 && (mib1 === 1 || mib1 === 2)) {
                    var model = IDENTITY.model;
                    var modelBytes = Memory.allocUtf8String(model);
                    var len = model.length + 1;
                    var bufLen = this.oldlenp.readU64();
                    if (bufLen >= len) {
                        Memory.copy(this.oldp, modelBytes, len);
                    }
                    this.oldlenp.writeU64(len);
                }
            }
        });
    }

    console.log("[Mogai-Frida] sysctl hooked");
}

function hookIDFA() {
    try {
        var ASIdentifierManager = ObjC.classes.ASIdentifierManager;
        if (!ASIdentifierManager) {
            console.log("[Mogai-Frida] ASIdentifierManager not found, skipping IDFA");
            return;
        }

        Interceptor.attach(ASIdentifierManager['- advertisingIdentifier'].implementation, {
            onLeave: function(retval) {
                var newUuid = ObjC.classes.NSUUID.alloc().initWithUUIDString_(IDENTITY.idfv);
                retval.replace(newUuid);
            }
        });
        console.log("[Mogai-Frida] IDFA hooked");
    } catch (e) {
        console.log("[Mogai-Frida] IDFA hook failed: " + e);
    }
}

function hookVerifyDialogs() {
    var UIViewController = ObjC.classes.UIViewController;
    var origPresent = UIViewController['- presentViewController:animated:completion:'];

    Interceptor.attach(origPresent.implementation, {
        onEnter: function(args) {
            var vc = new ObjC.Object(args[2]);
            var className = vc.$className;
            var title = vc.title() ? vc.title().toString() : "";

            var keywords = [
                "Captcha", "Verify", "Risk", "Slider",
                "HumanVerify", "SecurityCheck",
                "验证", "滑块", "校验", "安全"
            ];

            for (var i = 0; i < keywords.length; i++) {
                if (className.indexOf(keywords[i]) !== -1 || title.indexOf(keywords[i]) !== -1) {
                    console.log("[Mogai-Frida] 拦截验证弹窗: " + className + " (title: " + title + ")");
                    // 阻止弹窗展示
                    args[2] = ptr(0);
                    return;
                }
            }
        }
    });

    console.log("[Mogai-Frida] 验证弹窗拦截已启用");
}

function hookNetwork() {
    // 拦截 NSMutableURLRequest setValue:forHTTPHeaderField:
    var NSMutableURLRequest = ObjC.classes.NSMutableURLRequest;
    var setValueMethod = NSMutableURLRequest['- setValue:forHTTPHeaderField:'];

    Interceptor.attach(setValueMethod.implementation, {
        onEnter: function(args) {
            var field = new ObjC.Object(args[3]);
            var fieldStr = field.toString();

            // 抹除安全签名头
            if (fieldStr === "X-SS-REQ-TICKET" ||
                fieldStr === "X-Khronos" ||
                fieldStr === "X-Gorgon" ||
                fieldStr === "X-Argus" ||
                fieldStr === "X-Ladon" ||
                fieldStr === "X-SS-STUB") {
                console.log("[Mogai-Frida] 抹除安全头: " + fieldStr);
                args[2] = ptr(0); // value = nil
            }
        }
    });

    console.log("[Mogai-Frida] 网络请求头拦截已启用");
}

// ========== 数据清理 ==========

function cleanDouyinData() {
    var home = ObjC.classes.NSString.stringWithUTF8String_(NSHomeDirectory());
    var fm = ObjC.classes.NSFileManager.defaultManager();

    var dirs = ["Library/Caches", "tmp"];
    for (var i = 0; i < dirs.length; i++) {
        var dirPath = home.stringByAppendingPathComponent_(dirs[i]);
        var items = fm.contentsOfDirectoryAtPath_error_(dirPath, NULL);
        if (items && items.count() > 0) {
            for (var j = 0; j < items.count(); j++) {
                var item = items.objectAtIndex_(j);
                var fullPath = dirPath.stringByAppendingPathComponent_(item);
                fm.removeItemAtPath_error_(fullPath, NULL);
            }
            console.log("[Mogai-Frida] 清理: " + dirs[i]);
        }
    }

    // Cookie
    var storage = ObjC.classes.NSHTTPCookieStorage.sharedHTTPCookieStorage();
    var cookies = storage.cookies();
    if (cookies && cookies.count() > 0) {
        for (var k = 0; k < cookies.count(); k++) {
            storage.deleteCookie_(cookies.objectAtIndex_(k));
        }
        console.log("[Mogai-Frida] Cookie 已清理");
    }

    // URL Cache
    ObjC.classes.NSURLCache.sharedURLCache().removeAllCachedResponses();
    console.log("[Mogai-Frida] 缓存已清理");
}

// ========== 主入口 ==========

console.log("[Mogai-Frida] ============================");
console.log("[Mogai-Frida] 魔改新机 Frida 版启动");
console.log("[Mogai-Frida] ============================");

// 清理数据
cleanDouyinData();

// 应用所有 Hook
hookUIDevice();
hookNSProcessInfo();
hookMobileGestalt();
hookSysctl();
hookIDFA();
hookVerifyDialogs();
hookNetwork();

console.log("[Mogai-Frida] ============================");
console.log("[Mogai-Frida] 所有 Hook 已激活");
console.log("[Mogai-Frida] 设备伪装: " + IDENTITY.model + " / iOS " + IDENTITY.systemVersion);
console.log("[Mogai-Frida] ============================");
