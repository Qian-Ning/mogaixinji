#import <UIKit/UIKit.h>
#import "AppDelegate.h"
#include <signal.h>

static NSString *CrashLogPath(void) {
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    return [[paths firstObject] stringByAppendingPathComponent:@"crash.log"];
}

static void SignalHandler(int sig) {
    NSString *msg = [NSString stringWithFormat:@"SIGNAL: %d (%s)\n", sig, strsignal(sig)];
    [msg writeToFile:CrashLogPath() atomically:YES encoding:NSUTF8StringEncoding error:nil];
    exit(sig);
}

static void ExceptionHandler(NSException *exception) {
    NSString *msg = [NSString stringWithFormat:@"EXCEPTION: %@\nREASON: %@\nCALLSTACK: %@\n",
                     exception.name, exception.reason, exception.callStackSymbols];
    [msg writeToFile:CrashLogPath() atomically:YES encoding:NSUTF8StringEncoding error:nil];
}

int main(int argc, char *argv[]) {
    @autoreleasepool {
        // Crash reporter
        NSSetUncaughtExceptionHandler(&ExceptionHandler);
        signal(SIGABRT, SignalHandler);
        signal(SIGSEGV, SignalHandler);
        signal(SIGBUS, SignalHandler);
        signal(SIGTRAP, SignalHandler);

        return UIApplicationMain(argc, argv, nil, NSStringFromClass([AppDelegate class]));
    }
}
