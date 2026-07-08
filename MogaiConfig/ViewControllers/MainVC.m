#import "MainVC.h"
#import "MogaiConfig.h"
#import "LogVC.h"

@interface MainVC ()
@property (nonatomic, strong) UISwitch *enabledSwitch;
@property (nonatomic, strong) UILabel *statusLabel;
@property (nonatomic, strong) UILabel *previewLabel;
@property (nonatomic, strong) UISwitch *autoRandomizeSwitch;
@property (nonatomic, strong) UITextField *modelField;
@property (nonatomic, strong) UITextField *sysVerField;
@property (nonatomic, strong) UIButton *generateButton;
@property (nonatomic, strong) UIButton *cleanButton;
@property (nonatomic, strong) UIButton *resetButton;
@property (nonatomic, strong) UIScrollView *scrollView;
@property (nonatomic, assign) BOOL viewsCreated;
@property (nonatomic, strong) NSMutableArray *dynamicViews;
@end

@implementation MainVC

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"魔改新机 v2.0 Pro";
    self.view.backgroundColor = [UIColor systemBackgroundColor];
    self.dynamicViews = [NSMutableArray array];
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

- (CGFloat)contentWidth {
    return self.scrollView.frame.size.width > 20 ? self.scrollView.frame.size.width : [UIScreen mainScreen].bounds.size.width;
}

- (void)createViews {
    CGFloat w = [self contentWidth];
    CGFloat pad = 20;
    CGFloat y = pad;

    UILabel *header = [self labelWithFrame:CGRectMake(pad, y, w - pad*2, 30) font:[UIFont boldSystemFontOfSize:22] text:@"魔改新机 v2.0"];
    [self.scrollView addSubview:header];
    y += 40;

    self.enabledSwitch = [[UISwitch alloc] init];
    [self.enabledSwitch addTarget:self action:@selector(enabledChanged:) forControlEvents:UIControlEventValueChanged];
    UIView *enabledRow = [self rowWithFrame:CGRectMake(pad, y, w - pad*2, 44) label:@"启用魔改" uiSwitch:self.enabledSwitch];
    [self.scrollView addSubview:enabledRow];
    y += 55;

    self.autoRandomizeSwitch = [[UISwitch alloc] init];
    [self.autoRandomizeSwitch addTarget:self action:@selector(autoRandomizeChanged:) forControlEvents:UIControlEventValueChanged];
    UIView *autoRow = [self rowWithFrame:CGRectMake(pad, y, w - pad*2, 44) label:@"每次启动自动随机" uiSwitch:self.autoRandomizeSwitch];
    [self.scrollView addSubview:autoRow];
    y += 55;

    self.statusLabel = [self labelWithFrame:CGRectMake(pad, y, w - pad*2, 20) font:[UIFont systemFontOfSize:14] text:nil];
    self.statusLabel.textColor = [UIColor secondaryLabelColor];
    [self.scrollView addSubview:self.statusLabel];
    y += 30;

    UILabel *ph = [self labelWithFrame:CGRectMake(pad, y, w - pad*2, 24) font:[UIFont boldSystemFontOfSize:17] text:@"当前设备参数"];
    [self.scrollView addSubview:ph];
    y += 30;

    self.previewLabel = [self labelWithFrame:CGRectMake(pad, y, w - pad*2, 160) font:[UIFont fontWithName:@"Menlo" size:12] text:nil];
    self.previewLabel.numberOfLines = 0;
    [self.scrollView addSubview:self.previewLabel];
    y += 170;

    UILabel *ch = [self labelWithFrame:CGRectMake(pad, y, w - pad*2, 24) font:[UIFont boldSystemFontOfSize:17] text:@"自定义锁定（选填）"];
    [self.scrollView addSubview:ch];
    y += 30;

    UILabel *hint = [self labelWithFrame:CGRectMake(pad, y, w - pad*2, 30) font:[UIFont systemFontOfSize:13] text:@"留空则随机生成"];
    hint.textColor = [UIColor secondaryLabelColor];
    [self.scrollView addSubview:hint];
    y += 30;

    UILabel *ml = [self labelWithFrame:CGRectMake(pad, y, 80, 34) font:[UIFont systemFontOfSize:15] text:@"型号"];
    [self.scrollView addSubview:ml];

    self.modelField = [[UITextField alloc] initWithFrame:CGRectMake(pad + 85, y, w - pad*2 - 85, 34)];
    self.modelField.borderStyle = UITextBorderStyleRoundedRect;
    self.modelField.placeholder = @"如 iPhone15,3";
    self.modelField.font = [UIFont systemFontOfSize:15];
    [self.modelField addTarget:self action:@selector(modelChanged:) forControlEvents:UIControlEventEditingDidEnd];
    [self.scrollView addSubview:self.modelField];
    y += 44;

    UILabel *vl = [self labelWithFrame:CGRectMake(pad, y, 80, 34) font:[UIFont systemFontOfSize:15] text:@"系统版本"];
    [self.scrollView addSubview:vl];

    self.sysVerField = [[UITextField alloc] initWithFrame:CGRectMake(pad + 85, y, w - pad*2 - 85, 34)];
    self.sysVerField.borderStyle = UITextBorderStyleRoundedRect;
    self.sysVerField.placeholder = @"如 16.6.1";
    self.sysVerField.font = [UIFont systemFontOfSize:15];
    [self.sysVerField addTarget:self action:@selector(sysVerChanged:) forControlEvents:UIControlEventEditingDidEnd];
    [self.scrollView addSubview:self.sysVerField];
    y += 50;

    self.generateButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.generateButton.frame = CGRectMake(pad, y, w - pad*2, 50);
    [self.generateButton setTitle:@"一键生成新参数" forState:UIControlStateNormal];
    self.generateButton.titleLabel.font = [UIFont boldSystemFontOfSize:18];
    self.generateButton.backgroundColor = [UIColor systemBlueColor];
    self.generateButton.tintColor = [UIColor whiteColor];
    self.generateButton.layer.cornerRadius = 12;
    [self.generateButton addTarget:self action:@selector(generateTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.scrollView addSubview:self.generateButton];
    y += 60;

    self.cleanButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.cleanButton.frame = CGRectMake(pad, y, w - pad*2, 50);
    [self.cleanButton setTitle:@"清理沙盒 + Keychain" forState:UIControlStateNormal];
    self.cleanButton.titleLabel.font = [UIFont boldSystemFontOfSize:17];
    self.cleanButton.backgroundColor = [UIColor systemOrangeColor];
    self.cleanButton.tintColor = [UIColor whiteColor];
    self.cleanButton.layer.cornerRadius = 12;
    [self.cleanButton addTarget:self action:@selector(cleanTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.scrollView addSubview:self.cleanButton];
    y += 60;

    self.resetButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.resetButton.frame = CGRectMake(pad, y, w - pad*2, 50);
    [self.resetButton setTitle:@"恢复出厂设置" forState:UIControlStateNormal];
    self.resetButton.titleLabel.font = [UIFont boldSystemFontOfSize:17];
    self.resetButton.backgroundColor = [UIColor systemRedColor];
    self.resetButton.tintColor = [UIColor whiteColor];
    self.resetButton.layer.cornerRadius = 12;
    [self.resetButton addTarget:self action:@selector(resetTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.scrollView addSubview:self.resetButton];
    y += 60;

    UILabel *tip = [self labelWithFrame:CGRectMake(pad, y, w - pad*2, 60) font:[UIFont systemFontOfSize:12] text:@"使用说明：\n1. 修改参数后杀掉抖音后台重新打开\n2. 清理标记执行后自动清除"];
    tip.numberOfLines = 0;
    tip.textColor = [UIColor tertiaryLabelColor];
    [self.scrollView addSubview:tip];
    y += 80;

    self.scrollView.contentSize = CGSizeMake(w, y);
}

- (UILabel *)labelWithFrame:(CGRect)frame font:(UIFont *)font text:(NSString *)text {
    UILabel *label = [[UILabel alloc] initWithFrame:frame];
    label.text = text;
    label.font = font;
    label.textColor = [UIColor labelColor];
    return label;
}

- (UIView *)rowWithFrame:(CGRect)frame label:(NSString *)text uiSwitch:(UISwitch *)sw {
    UIView *row = [[UIView alloc] initWithFrame:frame];
    UILabel *label = [self labelWithFrame:CGRectMake(0, 0, frame.size.width - 60, frame.size.height) font:[UIFont systemFontOfSize:17] text:text];
    sw.frame = CGRectMake(frame.size.width - 51, (frame.size.height - 31) / 2, 51, 31);
    [row addSubview:label];
    [row addSubview:sw];
    return row;
}

- (void)refreshDisplay {
    MogaiConfig *config = [MogaiConfig sharedConfig];
    self.enabledSwitch.on = config.enabled;
    self.autoRandomizeSwitch.on = config.randomizeOnLaunch;
    self.modelField.text = config.customModel;
    self.sysVerField.text = config.customSystemVersion;

    self.statusLabel.text = config.enabled ? @"魔改已启用 - Hook已生效" : @"魔改已禁用 - 使用真实设备参数";
    self.statusLabel.textColor = config.enabled ? [UIColor systemGreenColor] : [UIColor systemRedColor];

    self.previewLabel.text = [NSString stringWithFormat:
        @"IDFV:       %@\n设备名:     %@\n型号:       %@\n系统版本:   %@\n序列号:     %@\nWiFi MAC:   %@\n蓝牙 MAC:   %@\n区域:       %@\n时区:       %@",
        config.currentIDFV ?: @"-", config.currentDeviceName ?: @"-", config.currentModel ?: @"-",
        config.currentSystemVersion ?: @"-", config.currentSerialNumber ?: @"-",
        config.currentWifiMac ?: @"-", config.currentBluetoothMac ?: @"-",
        config.currentLocale ?: @"-", config.currentTimeZone ?: @"-"];
}

- (void)enabledChanged:(UISwitch *)sender {
    [MogaiConfig sharedConfig].enabled = sender.on;
    [[MogaiConfig sharedConfig] save];
    [self refreshDisplay];
    [LogVC log:[NSString stringWithFormat:@"魔改状态: %@", sender.on ? @"启用" : @"禁用"]];
}

- (void)autoRandomizeChanged:(UISwitch *)sender {
    [MogaiConfig sharedConfig].randomizeOnLaunch = sender.on;
    [[MogaiConfig sharedConfig] save];
}

- (void)modelChanged:(UITextField *)sender {
    NSString *val = sender.text;
    [MogaiConfig sharedConfig].customModel = val.length > 0 ? val : nil;
    [[MogaiConfig sharedConfig] save];
}

- (void)sysVerChanged:(UITextField *)sender {
    NSString *val = sender.text;
    [MogaiConfig sharedConfig].customSystemVersion = val.length > 0 ? val : nil;
    [[MogaiConfig sharedConfig] save];
}

- (void)generateTapped {
    [[MogaiConfig sharedConfig] generateNew];
    [self refreshDisplay];
    [LogVC log:@"一键生成新参数完成"];
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"已生成新参数" message:@"请关闭抖音后台进程后重新打开" preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)cleanTapped {
    [LogVC log:@"用户请求沙盒清理"];
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"沙盒清理" message:@"清理操作会在下次启动抖音时自动执行" preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"执行清理" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
        NSUserDefaults *defaults = [[NSUserDefaults alloc] initWithSuiteName:kMogaiSuiteName];
        [defaults setBool:YES forKey:@"MogaiCleanRequested"];
        [defaults synchronize];
        [LogVC log:@"清理标记已写入，下次启动目标APP时执行"];
        UIAlertController *done = [UIAlertController alertControllerWithTitle:@"已标记清理" message:@"下次打开注入目标APP时将自动执行全面清理" preferredStyle:UIAlertControllerStyleAlert];
        [done addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleDefault handler:nil]];
        [self presentViewController:done animated:YES completion:nil];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)resetTapped {
    [LogVC log:@"用户请求恢复出厂设置"];
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"确认重置" message:@"将恢复出厂默认配置并生成全新参数" preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"确认重置" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
        [[MogaiConfig sharedConfig] resetToDefaults];
        [self refreshDisplay];
        [LogVC log:@"已恢复出厂设置并生成新参数"];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

@end
