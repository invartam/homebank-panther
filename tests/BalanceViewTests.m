#import "HBBalanceWindow.h"
#import "HBWalletStore.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

@interface HBBalanceWindow (TestActions)
- (void)scopeChanged:(id)sender;
- (void)horizonChanged:(id)sender;
- (void)datesChanged:(id)sender;
- (void)requestHistory;
@end
@interface HBGraphTestWindow : HBBalanceWindow
- (HBBalanceHistory *)history;
- (NSWindow *)window;
- (HBBalanceView *)plot;
- (HBHistoryRange)range;
- (NSString *)status;
- (void)selectScope:(NSString *)scope;
- (void)selectHorizon:(unsigned int)index;
- (void)enterFrom:(NSString *)from to:(NSString *)to;
- (BOOL)deferred;
@end
@implementation HBGraphTestWindow
- (HBBalanceHistory *)history { return _history; }
- (NSWindow *)window { return _window; }
- (HBBalanceView *)plot { return _plot; }
- (HBHistoryRange)range { return _range; }
- (NSString *)status { return [_status stringValue]; }
- (BOOL)deferred { return _needsRefresh && !_busy; }
- (void)selectScope:(NSString *)scope {
    unsigned int i; for (i = 0; i < [_scope numberOfItems]; i++) if ([[[_scope itemAtIndex:i] representedObject] isEqualToString:scope]) [_scope selectItemAtIndex:i];
    [self scopeChanged:nil];
}
- (void)selectHorizon:(unsigned int)index { [_horizon selectItemAtIndex:index]; [self horizonChanged:nil]; }
- (void)enterFrom:(NSString *)from to:(NSString *)to { [_from setStringValue:from]; [_to setStringValue:to]; [self datesChanged:nil]; }
@end

static unsigned int checks = 0, failures = 0;
static void HBTestCheck(BOOL condition, const char *message) { checks++; if (!condition) { failures++; fprintf(stderr, "FAIL: %s\n", message); } }
static void waitReady(HBGraphTestWindow *controller) {
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:10];
    while (![controller history] && [deadline timeIntervalSinceNow] > 0)
        [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
    HBTestCheck([controller history] != nil, "asynchronous history calculation completes on the main thread");
}
static HBWallet *fixture(int today) {
    NSString *text = [NSString stringWithFormat:@"<homebank v='1.6'><properties curr='1'/><cur key='1' iso='EUR' frac='2'/><account key='1' name='Compte fictif' curr='1' initial='200' minimum='-350'/><account key='2' name='Livret' curr='1' type='7' initial='4000'/><account key='3' name='Clos' flags='2' initial='999999'/><ope account='1' date='%d' amount='-700' st='2'/><ope account='1' date='%d' amount='2000' st='2'/><ope account='1' date='%d' amount='-1700' st='1'/><ope account='1' date='%d' amount='-400'/><ope account='1' date='%d' amount='-100'/><fav account='1' amount='1500' unit='2' recflg='3' limit='1' nextdate='%d'/></homebank>", today - 20, today - 15, today - 8, today - 2, today + 1, today + 5];
    return [[[HBWallet alloc] initWithData:[text dataUsingEncoding:NSUTF8StringEncoding] error:NULL] autorelease];
}
static NSBitmapImageRep *capture(HBBalanceView *view) {
    NSImage *image = [[[NSImage alloc] initWithSize:[view bounds].size] autorelease];
    [image lockFocus]; [view drawRect:[view bounds]];
    NSBitmapImageRep *bitmap = [[[NSBitmapImageRep alloc] initWithFocusedViewRect:[view bounds]] autorelease];
    [image unlockFocus]; return bitmap;
}
static void pixels(NSBitmapImageRep *bitmap, unsigned int *red, unsigned int *blue) {
    *red = *blue = 0;
    unsigned char *bytes = [bitmap bitmapData]; unsigned int x, y, stride = [bitmap bytesPerRow], samples = [bitmap samplesPerPixel];
    for (y = 0; y < [bitmap pixelsHigh]; y += 2) {
        NSAutoreleasePool *row = [[NSAutoreleasePool alloc] init];
        for (x = 112; x < [bitmap pixelsWide] - 20; x += 2) {
            int r, g, b;
#if MAC_OS_X_VERSION_MAX_ALLOWED >= 1040
            NSColor *color = [[bitmap colorAtX:x y:y] colorUsingColorSpaceName:NSCalibratedRGBColorSpace];
            r = [color redComponent] * 255; g = [color greenComponent] * 255; b = [color blueComponent] * 255;
#else
            if ([bitmap bitsPerSample] != 8 || [bitmap isPlanar] || samples < 3) continue;
            unsigned char *p = bytes + y * stride + x * samples; r = p[0]; g = p[1]; b = p[2];
#endif
            if (r > 150 && r - g > 30 && r - b > 30) (*red)++;
            if (b - r > 5 && b - g > 1) (*blue)++;
        }
        [row release];
    }
    (void)bytes; (void)stride; (void)samples;
}
static void savePlot(HBBalanceView *view, NSString *path, BOOL threshold) {
    NSBitmapImageRep *bitmap = capture(view); unsigned int red, blue; pixels(bitmap, &red, &blue);
    if (blue <= 1000 || (threshold ? red <= 50 : red != 0)) fprintf(stderr, "%s: blue=%u red=%u\n", [path UTF8String], blue, red);
    HBTestCheck(blue > 1000, "native canvas contains the blue curve and translucent fill");
    HBTestCheck(threshold ? red > 50 : red == 0, "authorized-overdraft line is rendered only in the individual scope");
    HBTestCheck([[bitmap representationUsingType:NSPNGFileType properties:[NSDictionary dictionary]] writeToFile:path atomically:YES], "exports a fictive native chart screenshot");
}
#if MAC_OS_X_VERSION_MAX_ALLOWED >= 1040
static void saveWindow(HBGraphTestWindow *controller, NSString *path) {
    NSView *content = [[controller window] contentView]; NSRect bounds = [content bounds];
    NSBitmapImageRep *bitmap = [content bitmapImageRepForCachingDisplayInRect:bounds];
    [content cacheDisplayInRect:bounds toBitmapImageRep:bitmap];
    HBTestCheck([[bitmap representationUsingType:NSPNGFileType properties:[NSDictionary dictionary]] writeToFile:path atomically:YES], "captures the actual native controls and chart together");
}
#endif

int main(int argc, const char *argv[]) {
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init]; [NSApplication sharedApplication];
#if MAC_OS_X_VERSION_MAX_ALLOWED >= 101400
    [NSAppearance setCurrentAppearance:[NSAppearance appearanceNamed:NSAppearanceNameAqua]];
    [NSApp setAppearance:[NSAppearance appearanceNamed:NSAppearanceNameAqua]];
#endif
    int today = HBOrdinalFromDate(HBToday()); HBWallet *wallet = fixture(today);
    NSData *before = [wallet sourceData];
    HBGraphTestWindow *controller = [[HBGraphTestWindow alloc] initWithWallet:wallet account:@"1"];
    [controller show]; waitReady(controller);
    if (![controller history]) { [controller release]; [pool release]; return 1; }
    HBTestCheck([[[controller history] accounts] count] == 1 && [[[[controller history] accounts] objectAtIndex:0] objectForKey:@"key"] != nil, "initial chart scope uses the account selected in the banking window");
    [controller enterFrom:[HBDateFromOrdinal(today - 21) descriptionWithCalendarFormat:@"%d/%m/%Y"] to:[HBDateFromOrdinal(today + 15) descriptionWithCalendarFormat:@"%d/%m/%Y"]];
    HBHistoryRange range = [controller range];
    if (argc == 2 && strcmp(argv[1], "--preview") == 0) {
        [[controller window] setTitle:@"HomeBank Panther - Graphique fictif"];
        [NSApp activateIgnoringOtherApps:YES];
        [NSTimer scheduledTimerWithTimeInterval:120 target:NSApp selector:@selector(terminate:) userInfo:nil repeats:NO];
        [NSApp run];
    }
    HBTestCheck(range.start == today - 21 && range.end == today + 15, "French date fields select both historical and future dates");
    HBTestCheck([[[controller history] balanceAt:range.end] isEqualToNumber:[NSDecimalNumber decimalNumberWithString:@"800"]], "native chart reports the same posted and planned balance as the web");
    [controller enterFrom:@"31/02/2026" to:@"15/10/2026"];
    HBTestCheck([[controller status] rangeOfString:@"Dates invalides"].location != NSNotFound && [controller range].start == range.start, "invalid dates cannot alter the displayed range");
    [controller balanceView:[controller plot] selectFrom:range.start to:range.end];
    savePlot([controller plot], @"build/balance-plot-light.png", YES);
#if MAC_OS_X_VERSION_MAX_ALLOWED >= 1040
    saveWindow(controller, @"build/balance-window-light.png");
#endif
    NSSize original = [[controller window] frame].size;
    [[controller window] setContentSize:NSMakeSize(800, 560)];
    HBTestCheck([[controller plot] bounds].size.width > 700 && [[controller plot] bounds].size.height > 200, "graph remains framed at the minimum window size");
    savePlot([controller plot], @"build/balance-plot-compact.png", YES);
#if MAC_OS_X_VERSION_MAX_ALLOWED >= 1040
    saveWindow(controller, @"build/balance-window-compact.png");
#endif
#if MAC_OS_X_VERSION_MAX_ALLOWED >= 101400
    [NSAppearance setCurrentAppearance:[NSAppearance appearanceNamed:NSAppearanceNameDarkAqua]];
    [NSApp setAppearance:[NSAppearance appearanceNamed:NSAppearanceNameDarkAqua]];
    savePlot([controller plot], @"build/balance-plot-dark.png", YES);
    [NSAppearance setCurrentAppearance:[NSAppearance appearanceNamed:NSAppearanceNameAqua]];
    [NSApp setAppearance:[NSAppearance appearanceNamed:NSAppearanceNameAqua]];
#endif
    [[controller window] setFrame:NSMakeRect(20, 20, original.width, original.height) display:NO];
    unsigned int i; for (i = 0; i < 15; i++) [controller balanceView:[controller plot] zoom:0.5];
    HBTestCheck([controller range].end - [controller range].start == 1, "native zoom controls reach daily detail");
    [controller selectHorizon:2]; waitReady(controller);
    HBTestCheck([controller range].start == today && [controller range].end == [[controller history] end], "five-year forecast preset is navigable");
    [controller balanceView:[controller plot] zoom:0.5];
    savePlot([controller plot], @"build/balance-plot-future.png", YES);
    [controller selectScope:@"bank"]; waitReady(controller);
    savePlot([controller plot], @"build/balance-plot-group.png", NO);
    [controller selectScope:@"savings"]; [controller selectScope:@"account:1"]; waitReady(controller);
    HBTestCheck([[[[controller history] accounts] objectAtIndex:0] objectForKey:@"key"] && [[[[[controller history] accounts] objectAtIndex:0] objectForKey:@"key"] isEqualToString:@"1"], "queued scope changes discard stale worker results");
    HBWallet *edited = [wallet walletByChangingStatus:@"2" record:[[wallet records] objectAtIndex:3] error:NULL];
    HBTestCheck(edited != nil, "fictive edit produces a new immutable working wallet");
    [[controller window] orderOut:nil]; [controller setWallet:edited];
    HBTestCheck([controller deferred] && [controller history] == nil, "hidden report releases old drawing data and defers recalculation instead of slowing each edit");
    [controller show]; waitReady(controller);
    HBTestCheck([[wallet sourceData] isEqualToData:before] && [wallet generation] == 0, "chart controls never write XML or add journal commands");
    [[controller window] orderOut:nil]; [controller release];
    printf("%u/%u native graph checks passed\n", checks - failures, checks); [pool release]; return failures ? 1 : 0;
}
