#import "AppDelegate.h"
#import "MainVC.h"
#import "LogVC.h"

@implementation AppDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    self.window = [[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];

    UITabBarController *tabController = [[UITabBarController alloc] init];

    MainVC *mainVC = [[MainVC alloc] init];
    mainVC.tabBarItem = [[UITabBarItem alloc] initWithTitle:@"魔改" image:[UIImage systemImageNamed:@"wand.and.stars"] tag:0];

    LogVC *logVC = [[LogVC alloc] init];
    logVC.tabBarItem = [[UITabBarItem alloc] initWithTitle:@"日志" image:[UIImage systemImageNamed:@"list.bullet"] tag:1];

    tabController.viewControllers = @[
        [[UINavigationController alloc] initWithRootViewController:mainVC],
        [[UINavigationController alloc] initWithRootViewController:logVC],
    ];

    self.window.rootViewController = tabController;
    [self.window makeKeyAndVisible];

    return YES;
}

@end
