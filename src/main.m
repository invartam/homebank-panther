#import "HBApplication.h"

int main(int argc, const char *argv[]) {
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    HBApplication *application = [[HBApplication alloc] init];
    NSApplication *nativeApp = [NSApplication sharedApplication];
    [nativeApp setDelegate:(id)application];
    if (argc == 2 && argv[1][0] != '-') [application openPath:[NSString stringWithUTF8String:argv[1]]];
    [nativeApp run];
    [application release]; [pool release];
    return 0;
}
