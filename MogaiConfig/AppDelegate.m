#import "AppDelegate.h"
#import "MainVC.h"
#import "LogVC.h"

@implementation AppDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    self.window = [[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];

    UITabBarController *tabController = [[UITabBarController alloc] init];

    MainVC *mainVC = [[MainVC alloc] init];
    UINavigationController *nav1 = [[UINavigationController alloc] initWithRootViewController:mainVC];
    mainVC.tabBarItem = [[UITabBarItem alloc] initWithTitle:@"魔改" image:nil tag:0];

    LogVC *logVC = [[LogVC alloc] init];
    UINavigationController *nav2 = [[UINavigationController alloc] initWithRootViewController:logVC];
    logVC.tabBarItem = [[UITabBarItem alloc] initWithTitle:@"日志" image:nil tag:1];

    tabController.viewControllers = @[nav1, nav2];
    self.window.rootViewController = tabController;
    [self.window makeKeyAndVisible];

    return YES;
}

@end
