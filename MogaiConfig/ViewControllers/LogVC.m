#import "LogVC.h"

@interface LogVC ()
@property (nonatomic, strong) UITextView *textView;
@property (nonatomic, strong) NSMutableArray *logs;
@end

static LogVC *_sharedLogVC;

@implementation LogVC

+ (void)log:(NSString *)message {
    dispatch_async(dispatch_get_main_queue(), ^{
        NSDateFormatter *df = [[NSDateFormatter alloc] init];
        df.dateFormat = @"HH:mm:ss";
        NSString *entry = [NSString stringWithFormat:@"[%@] %@", [df stringFromDate:[NSDate date]], message];
        [_sharedLogVC.logs addObject:entry];
        if (_sharedLogVC.logs.count > 200) {
            [_sharedLogVC.logs removeObjectsInRange:NSMakeRange(0, _sharedLogVC.logs.count - 200)];
        }
        _sharedLogVC.textView.text = [_sharedLogVC.logs componentsJoinedByString:@"\n"];
        if (_sharedLogVC.textView.text.length > 0) {
            NSRange range = NSMakeRange(_sharedLogVC.textView.text.length - 1, 1);
            [_sharedLogVC.textView scrollRangeToVisible:range];
        }
    });
}

- (void)viewDidLoad {
    [super viewDidLoad];
    _sharedLogVC = self;
    self.logs = [NSMutableArray array];
    self.title = @"日志";

    self.textView = [[UITextView alloc] initWithFrame:self.view.bounds];
    self.textView.font = [UIFont fontWithName:@"Menlo" size:11];
    self.textView.backgroundColor = [UIColor colorWithWhite:0.05 alpha:1.0];
    self.textView.textColor = [UIColor colorWithRed:0.2 green:1.0 blue:0.4 alpha:1.0];
    self.textView.editable = NO;
    self.textView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [self.view addSubview:self.textView];

    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"清除" style:UIBarButtonItemStylePlain target:self action:@selector(clearLog)];

    [self.logs addObject:@"[魔改新机 v2.0 Pro]"];
    [self.logs addObject:@"[配置APP就绪]"];
    self.textView.text = [self.logs componentsJoinedByString:@"\n"];
}

- (void)clearLog {
    [self.logs removeAllObjects];
    [self.logs addObject:@"[已清除]"];
    self.textView.text = [self.logs componentsJoinedByString:@"\n"];
}

@end
