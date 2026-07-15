#import "MainVC.h"
#import "MogaiConfig.h"
#import "LogVC.h"
#import "SystemModifier.h"

#define RECT(x,y,w,h) CGRectMake((x),(y),(w),(h))

@interface MainVC ()
@property (nonatomic, strong) UIScrollView *scrollView;
@property (nonatomic, strong) UISwitch *enabledSwitch;
@property (nonatomic, strong) UISwitch *autoRandomizeSwitch;
@property (nonatomic, strong) UILabel *statusLabel;
@property (nonatomic, strong) UILabel *previewLabel;
@property (nonatomic, strong) UITextField *modelField;
@property (nonatomic, strong) UITextField *sysVerField;
@property (nonatomic, strong) UIButton *generateButton;
@property (nonatomic, strong) UIButton *cleanButton;
@property (nonatomic, strong) UIButton *resetButton;
@property (nonatomic, assign) BOOL viewsCreated;
@end

@implementation MainVC

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"魔改新机 v2.0 Pro";
    self.view.backgroundColor = [UIColor systemBackgroundColor];
    self.viewsCreated = NO;

    self.scrollView = [[UIScrollView alloc] initWithFrame:self.view.bounds];
    self.scrollView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [self.view addSubview:self.scrollView];

    [[MogaiConfig sharedConfig] load];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    if (!self.viewsCreated) {
        [self createViews];
        self.viewsCreated = YES;
    }
    [self refreshDisplay];
}

- (CGFloat)w {
    CGFloat scrW = [UIScreen mainScreen].bounds.size.width;
    CGFloat viewW = self.scrollView.frame.size.width;
    return (viewW > 100) ? viewW : scrW;
}

- (void)createViews {
    CGFloat pad = 20;
    CGFloat y = pad;
    CGFloat cw = [self w];

    UILabel *header = [self lab:CGRectMake(pad, y, cw - pad*2, 30) font:[UIFont boldSystemFontOfSize:22] text:@"魔改新机 v2.0"];
    [self.scrollView addSubview:header];
    y += 40;

    self.enabledSwitch = [[UISwitch alloc] init];
    [self.enabledSwitch addTarget:self action:@selector(enabledChanged:) forControlEvents:UIControlEventValueChanged];
    [self.scrollView addSubview:[self row:RECT(pad, y, cw - pad*2, 44) text:@"启用魔改" sw:self.enabledSwitch]];
    y += 55;

    self.autoRandomizeSwitch = [[UISwitch alloc] init];
    [self.autoRandomizeSwitch addTarget:self action:@selector(autoRandomizeChanged:) forControlEvents:UIControlEventValueChanged];
    [self.scrollView addSubview:[self row:RECT(pad, y, cw - pad*2, 44) text:@"每次启动自动随机" sw:self.autoRandomizeSwitch]];
    y += 55;

    self.statusLabel = [self lab:RECT(pad, y, cw - pad*2, 20) font:[UIFont systemFontOfSize:14] text:nil];
    self.statusLabel.textColor = [UIColor secondaryLabelColor];
    [self.scrollView addSubview:self.statusLabel];
    y += 30;

    [self.scrollView addSubview:[self lab:RECT(pad, y, cw - pad*2, 24) font:[UIFont boldSystemFontOfSize:17] text:@"当前设备参数"]];
    y += 30;

    self.previewLabel = [self lab:RECT(pad, y, cw - pad*2, 160) font:[UIFont fontWithName:@"Menlo" size:12] text:nil];
    self.previewLabel.numberOfLines = 0;
    [self.scrollView addSubview:self.previewLabel];
    y += 170;

    [self.scrollView addSubview:[self lab:RECT(pad, y, cw - pad*2, 24) font:[UIFont boldSystemFontOfSize:17] text:@"自定义锁定（选填）"]];
    y += 30;

    UILabel *hint = [self lab:RECT(pad, y, cw - pad*2, 30) font:[UIFont systemFontOfSize:13] text:@"留空则随机生成"];
    hint.textColor = [UIColor secondaryLabelColor];
    [self.scrollView addSubview:hint];
    y += 30;

    [self.scrollView addSubview:[self lab:RECT(pad, y, 80, 34) font:[UIFont systemFontOfSize:15] text:@"型号"]];

    self.modelField = [[UITextField alloc] initWithFrame:CGRectMake(pad + 85, y, cw - pad*2 - 85, 34)];
    self.modelField.borderStyle = UITextBorderStyleRoundedRect;
    self.modelField.placeholder = @"如 iPhone15,3";
    self.modelField.font = [UIFont systemFontOfSize:15];
    [self.modelField addTarget:self action:@selector(modelChanged:) forControlEvents:UIControlEventEditingDidEnd];
    [self.scrollView addSubview:self.modelField];
    y += 44;

    [self.scrollView addSubview:[self lab:RECT(pad, y, 80, 34) font:[UIFont systemFontOfSize:15] text:@"系统版本"]];

    self.sysVerField = [[UITextField alloc] initWithFrame:CGRectMake(pad + 85, y, cw - pad*2 - 85, 34)];
    self.sysVerField.borderStyle = UITextBorderStyleRoundedRect;
    self.sysVerField.placeholder = @"如 16.6.1";
    self.sysVerField.font = [UIFont systemFontOfSize:15];
    [self.sysVerField addTarget:self action:@selector(sysVerChanged:) forControlEvents:UIControlEventEditingDidEnd];
    [self.scrollView addSubview:self.sysVerField];
    y += 50;

    self.generateButton = [self btn:RECT(pad, y, cw - pad*2, 50) title:@"一键生成新参数" color:[UIColor systemBlueColor] action:@selector(generateTapped)];
    [self.scrollView addSubview:self.generateButton];
    y += 60;

    // 系统级应用（写入 MobileGestalt 缓存，全设备生效）
    self.cleanButton = [self btn:RECT(pad, y, cw - pad*2, 50) title:@"系统级改机（全局生效）" color:[UIColor systemPurpleColor] action:@selector(systemApplyTapped)];
    [self.scrollView addSubview:self.cleanButton];
    y += 60;

    // 沙盒清理
    UIButton *cleanBtn2 = [self btn:RECT(pad, y, cw - pad*2, 50) title:@"清理缓存 + Cookie" color:[UIColor systemOrangeColor] action:@selector(cleanTapped)];
    [self.scrollView addSubview:cleanBtn2];
    y += 60;

    self.resetButton = [self btn:RECT(pad, y, cw - pad*2, 50) title:@"恢复出厂设置" color:[UIColor systemRedColor] action:@selector(resetTapped)];
    [self.scrollView addSubview:self.resetButton];
    y += 60;

    UILabel *tip = [self lab:RECT(pad, y, cw - pad*2, 60) font:[UIFont systemFontOfSize:12] text:@"使用说明：\n1. 修改参数后杀掉抖音后台重新打开\n2. 清理标记执行后自动清除"];
    tip.numberOfLines = 0;
    tip.textColor = [UIColor tertiaryLabelColor];
    [self.scrollView addSubview:tip];
    y += 80;

    self.scrollView.contentSize = CGSizeMake(cw, y);
}

- (UILabel *)lab:(CGRect)frame font:(UIFont *)font text:(NSString *)text {
    UILabel *l = [[UILabel alloc] initWithFrame:frame];
    l.text = text;
    l.font = font;
    l.textColor = [UIColor labelColor];
    return l;
}

- (UIView *)row:(CGRect)frame text:(NSString *)text sw:(UISwitch *)sw {
    UIView *r = [[UIView alloc] initWithFrame:frame];
    UILabel *l = [self lab:CGRectMake(0, 0, frame.size.width - 60, frame.size.height) font:[UIFont systemFontOfSize:17] text:text];
    sw.frame = CGRectMake(frame.size.width - 51, (frame.size.height - 31) / 2, 51, 31);
    [r addSubview:l];
    [r addSubview:sw];
    return r;
}

- (UIButton *)btn:(CGRect)frame title:(NSString *)title color:(UIColor *)color action:(SEL)action {
    UIButton *b = [UIButton buttonWithType:UIButtonTypeSystem];
    b.frame = frame;
    [b setTitle:title forState:UIControlStateNormal];
    b.titleLabel.font = [UIFont boldSystemFontOfSize:17];
    b.backgroundColor = color;
    b.tintColor = [UIColor whiteColor];
    b.layer.cornerRadius = 12;
    [b addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
    return b;
}

- (void)refreshDisplay {
    MogaiConfig *c = [MogaiConfig sharedConfig];
    self.enabledSwitch.on = c.enabled;
    self.autoRandomizeSwitch.on = c.randomizeOnLaunch;
    self.modelField.text = c.customModel;
    self.sysVerField.text = c.customSystemVersion;

    self.statusLabel.text = c.enabled ? @"魔改已启用" : @"魔改已禁用";
    self.statusLabel.textColor = c.enabled ? [UIColor systemGreenColor] : [UIColor systemRedColor];

    self.previewLabel.text = [NSString stringWithFormat:
        @"IDFV:       %@\n设备名:     %@\n型号:       %@\n系统版本:   %@\n序列号:     %@\nWiFi MAC:   %@\n蓝牙 MAC:   %@\n区域:       %@\n时区:       %@",
        c.currentIDFV ?: @"-", c.currentDeviceName ?: @"-", c.currentModel ?: @"-",
        c.currentSystemVersion ?: @"-", c.currentSerialNumber ?: @"-",
        c.currentWifiMac ?: @"-", c.currentBluetoothMac ?: @"-",
        c.currentLocale ?: @"-", c.currentTimeZone ?: @"-"];
}

- (void)enabledChanged:(UISwitch *)s {
    [MogaiConfig sharedConfig].enabled = s.on;
    [[MogaiConfig sharedConfig] save];
    [self refreshDisplay];
    [LogVC log:[NSString stringWithFormat:@"魔改 %@", s.on ? @"启用" : @"禁用"]];
}

- (void)autoRandomizeChanged:(UISwitch *)s {
    [MogaiConfig sharedConfig].randomizeOnLaunch = s.on;
    [[MogaiConfig sharedConfig] save];
}

- (void)modelChanged:(UITextField *)f {
    [MogaiConfig sharedConfig].customModel = f.text.length > 0 ? f.text : nil;
    [[MogaiConfig sharedConfig] save];
}

- (void)sysVerChanged:(UITextField *)f {
    [MogaiConfig sharedConfig].customSystemVersion = f.text.length > 0 ? f.text : nil;
    [[MogaiConfig sharedConfig] save];
}

- (void)generateTapped {
    [[MogaiConfig sharedConfig] generateNew];
    [self refreshDisplay];
    [LogVC log:@"生成新参数完成"];
    UIAlertController *a = [UIAlertController alertControllerWithTitle:@"已生成" message:@"请关闭抖音后台后重新打开" preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:a animated:YES completion:nil];
}

- (void)systemApplyTapped {
    [LogVC log:@"系统级改机启动..."];
    MogaiConfig *c = [MogaiConfig sharedConfig];

    // 1. 生成新参数
    if (!c.currentIDFV || c.currentIDFV.length == 0) {
        [c generateNew];
    }

    // 2. 写入 MobileGestalt 缓存
    SystemModifier *sm = [SystemModifier shared];
    BOOL ok = [sm applyToMGCacheWithModel:c.currentModel
                               sysVersion:c.currentSystemVersion
                               deviceName:c.currentDeviceName
                                  serialN:c.currentSerialNumber
                              wifiAddress:c.currentWifiMac
                               btAddress:c.currentBluetoothMac
                                     udid:c.currentIDFV
                                   locale:c.currentLocale
                                 timezone:c.currentTimeZone];
    // 3. 调用 MGSetAnswer 私有API
    [sm applyMGSetAnswerWithModel:c.currentModel
                        sysVersion:c.currentSystemVersion
                        deviceName:c.currentDeviceName
                           serialN:c.currentSerialNumber
                       wifiAddress:c.currentWifiMac
                        btAddress:c.currentBluetoothMac
                             udid:c.currentIDFV];
    // 4. 修改系统偏好
    [sm applySystemPreferencesWithLocale:c.currentLocale timezone:c.currentTimeZone deviceName:c.currentDeviceName];
    // 5. 刷新守护进程
    [sm refreshMobileGestalt];

    NSString *msg = ok ? @"系统级改机成功！\n\n所有APP将看到新设备身份。\n效果持续到下次重启。" : @"缓存文件未找到或写入失败。\n请确认TrollStore已授权。";
    [LogVC log:ok ? @"系统级改机完成" : @"系统级改机失败"];

    UIAlertController *a = [UIAlertController alertControllerWithTitle:ok ? @"系统级改机成功" : @"失败"
        message:msg preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:a animated:YES completion:nil];
}

- (void)cleanTapped {
    [LogVC log:@"请求沙盒清理"];
    MogaiConfig *c = [MogaiConfig sharedConfig];
    c.cleanRequested = YES;
    [c save];
    [LogVC log:@"清理标记已写入配置文件"];
    UIAlertController *a = [UIAlertController alertControllerWithTitle:@"已标记清理" message:@"下次启动目标APP时执行" preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:a animated:YES completion:nil];
}

- (void)resetTapped {
    [LogVC log:@"恢复出厂设置"];
    UIAlertController *a = [UIAlertController alertControllerWithTitle:@"确认重置" message:@"将恢复出厂并生成新参数" preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"确认" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *aa) {
        [[MogaiConfig sharedConfig] resetToDefaults];
        [self refreshDisplay];
        [LogVC log:@"已重置"];
    }]];
    [a addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:a animated:YES completion:nil];
}

@end
