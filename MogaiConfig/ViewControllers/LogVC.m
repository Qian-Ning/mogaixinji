#import "LogVC.h"

@interface LogVC ()
@property (nonatomic, strong) UITextView *textView;
@property (nonatomic, strong) NSMutableArray *localLogs;
@end

static LogVC *_sharedLogVC = nil;

@implementation LogVC

+ (void)log:(NSString *)message {
    dispatch_async(dispatch_get_main_queue(), ^{
        NSDateFormatter *df = [[NSDateFormatter alloc] init];
        df.dateFormat = @"HH:mm:ss.SSS";
        NSString *ts = [df stringFromDate:[NSDate date]];
        NSString *entry = [NSString stringWithFormat:@"[%@] %@", ts, message];
        [_sharedLogVC.localLogs addObject:entry];
        if (_sharedLogVC.localLogs.count > 200) {
            [_sharedLogVC.localLogs removeObjectsInRange:NSMakeRange(0, _sharedLogVC.localLogs.count - 200)];
        }
        [_sharedLogVC refreshDisplay];
    });
}

- (void)viewDidLoad {
    [super viewDidLoad];
    _sharedLogVC = self;
    self.localLogs = [NSMutableArray array];

    self.title = @"日志";
    self.view.backgroundColor = [UIColor systemBackgroundColor];

    self.textView = [[UITextView alloc] initWithFrame:self.view.bounds];
    self.textView.font = [UIFont fontWithName:@"Menlo" size:11];
    self.textView.backgroundColor = [UIColor colorWithWhite:0.05 alpha:1.0];
    self.textView.textColor = [UIColor colorWithRed:0.2 green:1.0 blue:0.4 alpha:1.0];
    self.textView.editable = NO;
    self.textView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [self.view addSubview:self.textView];

    UIBarButtonItem *clearBtn = [[UIBarButtonItem alloc] initWithTitle:@"清除"
        style:UIBarButtonItemStylePlain target:self action:@selector(clearLog)];
    self.navigationItem.rightBarButtonItem = clearBtn;

    [self.localLogs addObject:@"[Mogai 配置 APP v2.0]"];
    [self.localLogs addObject:@"[Mogai] dylib日志请通过 idevicesyslog | grep Mogai 查看"];
    [self.localLogs addObject:@"[Mogai] 配置APP就绪"];
    [self refreshDisplay];
}

- (void)refreshDisplay {
    self.textView.text = [self.localLogs componentsJoinedByString:@"\n"];
    if (self.textView.text.length > 0) {
        NSRange range = NSMakeRange(self.textView.text.length - 1, 1);
        [self.textView scrollRangeToVisible:range];
    }
}

- (void)clearLog {
    [self.localLogs removeAllObjects];
    [self.localLogs addObject:@"[Mogai 配置 APP v2.0]"];
    [self.localLogs addObject:@"[日志已清除]"];
    [self refreshDisplay];
}

@end
