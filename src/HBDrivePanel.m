#import "HBDrivePanel.h"

static NSTextField *HBDField(NSView *view, NSString *value, NSRect frame, BOOL editable) {
    NSTextField *field = [[[NSTextField alloc] initWithFrame:frame] autorelease];
    [field setStringValue:value ? value : @""]; [field setEditable:editable]; [field setSelectable:YES];
    if (!editable) { [field setBezeled:NO]; [field setDrawsBackground:NO]; }
    [view addSubview:field]; return field;
}
static void HBDButton(NSView *view, NSString *title, NSRect frame, id target, SEL selector) {
    NSButton *button = [[[NSButton alloc] initWithFrame:frame] autorelease]; [button setTitle:title];
    [button setBezelStyle:NSRoundedBezelStyle]; [button setTarget:target]; [button setAction:selector]; [view addSubview:button];
}
@implementation HBDrivePanel
- (id)initWithSettings:(NSDictionary *)settings {
    self = [super init]; if (!self) return nil;
    _keyAlias = [[settings objectForKey:@"keyAlias"] copy];
    _window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 700, 330) styleMask:NSTitledWindowMask backing:NSBackingStoreBuffered defer:NO];
    [_window setReleasedWhenClosed:NO]; [_window setTitle:@"Google Drive - Compte de service"]; [_window center];
    NSView *view = [_window contentView]; NSString *arch;
#if defined(__ppc__) || defined(__POWERPC__)
    arch = @"ppc";
#elif defined(__aarch64__) || defined(__arm64__)
    arch = @"arm64";
#else
    arch = @"x86_64";
#endif
    NSString *prefix = [NSHomeDirectory() stringByAppendingPathComponent:[NSString stringWithFormat:@"homebank-https-sources/out/%@", arch]];
    NSString *bundled = [[[NSBundle mainBundle] resourcePath] stringByAppendingPathComponent:@"Drive"];
    BOOL hasBundled = [[NSFileManager defaultManager] fileExistsAtPath:[bundled stringByAppendingPathComponent:@"curl"]];
    NSString *defaultCurl = hasBundled ? [bundled stringByAppendingPathComponent:@"curl"] : [prefix stringByAppendingPathComponent:@"bin/curl"];
    NSString *defaultCA = hasBundled ? [bundled stringByAppendingPathComponent:@"cacert.pem"] : [prefix stringByAppendingPathComponent:@"share/cacert.pem"];
    HBDField(view, @"Fichier Drive (identifiant)", NSMakeRect(20, 280, 190, 22), NO);
    _fileID = HBDField(view, [settings objectForKey:@"fileID"], NSMakeRect(220, 278, 460, 26), YES);
    HBDField(view, @"Client curl HTTPS", NSMakeRect(20, 230, 190, 22), NO);
    _curlPath = HBDField(view, [settings objectForKey:@"curlPath"] ? [settings objectForKey:@"curlPath"] : defaultCurl, NSMakeRect(220, 228, 460, 26), YES);
    HBDField(view, @"Certificats CA", NSMakeRect(20, 180, 190, 22), NO);
    _caPath = HBDField(view, [settings objectForKey:@"caPath"] ? [settings objectForKey:@"caPath"] : defaultCA, NSMakeRect(220, 178, 460, 26), YES);
    [_curlPath setToolTip:[_curlPath stringValue]]; [_caPath setToolTip:[_caPath stringValue]];
    HBDField(view, @"Cle du compte de service", NSMakeRect(20, 130, 190, 22), NO);
    HBDButton(view, @"Importer une cle JSON...", NSMakeRect(220, 124, 230, 30), self, @selector(importKey:));
    _keyLabel = HBDField(view, [_keyAlias length] ? @"Cle conservee dans le trousseau" : @"Aucune cle importee", NSMakeRect(20, 78, 660, 30), NO);
    HBDButton(view, @"Annuler", NSMakeRect(440, 20, 110, 32), self, @selector(cancel:));
    HBDButton(view, @"Enregistrer", NSMakeRect(560, 20, 120, 32), self, @selector(accept:));
    return self;
}
- (void)importKey:(id)sender {
    NSOpenPanel *panel = [NSOpenPanel openPanel]; [panel setAllowsMultipleSelection:NO]; [panel setCanChooseDirectories:NO];
    if ([panel runModalForDirectory:nil file:nil types:[NSArray arrayWithObject:@"json"]] != NSOKButton) return;
    NSString *error = nil; NSData *data = HBDriveReadPrivateFile([[panel filenames] objectAtIndex:0], 65536, &error);
    NSDictionary *credentials = data ? HBDriveCredentials(data, &error) : nil;
    if (!credentials) { NSRunAlertPanel(@"Cle refusee", @"%@", @"OK", nil, nil, error); return; }
    [_keyData release]; _keyData = [data copy]; [_keyLabel setStringValue:[credentials objectForKey:@"client_email"]];
}
- (void)accept:(id)sender {
    NSString *error = nil;
    NSMutableDictionary *settings = [NSMutableDictionary dictionaryWithObjectsAndKeys:
        [_fileID stringValue], @"fileID", [[_curlPath stringValue] stringByExpandingTildeInPath], @"curlPath",
        [[_caPath stringValue] stringByExpandingTildeInPath], @"caPath", _keyAlias ? _keyAlias : @"new-key", @"keyAlias", nil];
    if (!HBDriveValidSettings(settings, &error) || (!_keyData && ![_keyAlias length])) {
        NSRunAlertPanel(@"Configuration refusee", @"%@", @"OK", nil, nil, error ? error : @"Importer une cle de compte de service."); return;
    }
    if (_keyData) {
        NSString *alias = nil;
        if (!HBDriveStoreKey(_keyData, &alias, &error)) { NSRunAlertPanel(@"Configuration refusee", @"%@", @"OK", nil, nil, error); return; }
        [settings setObject:alias forKey:@"keyAlias"];
    }
    _result = [settings copy]; [NSApp stopModal]; [_window orderOut:nil];
}
- (void)cancel:(id)sender { [NSApp stopModal]; [_window orderOut:nil]; }
- (NSDictionary *)run { [_window makeKeyAndOrderFront:nil]; [NSApp runModalForWindow:_window]; return [[_result retain] autorelease]; }
- (void)dealloc { [_window release]; [_keyData release]; [_keyAlias release]; [_result release]; [super dealloc]; }
@end
