#import "HBBalanceWindow.h"

@interface HBBalanceWindow (Private)
- (void)layout;
- (void)rebuildScopes;
- (void)rebuildCurrencies;
- (void)clearHistory;
- (void)requestHistory;
- (void)updateRange;
- (void)worker:(NSDictionary *)context;
- (void)finished:(NSDictionary *)result;
@end

static NSTextField *HWLabel(NSView *view, NSString *text, float size) {
    NSTextField *label = [[[NSTextField alloc] initWithFrame:NSZeroRect] autorelease];
    [label setStringValue:text]; [label setEditable:NO]; [label setSelectable:YES]; [label setBezeled:NO]; [label setDrawsBackground:NO];
    [label setFont:[NSFont systemFontOfSize:size]]; [view addSubview:label]; return label;
}
static NSButton *HWButton(NSView *view, NSString *title, NSString *tip, id owner, SEL action) {
    NSButton *button = [[[NSButton alloc] initWithFrame:NSZeroRect] autorelease];
    [button setTitle:title]; [button setToolTip:tip]; [button setBezelStyle:NSRoundedBezelStyle]; [button setTarget:owner]; [button setAction:action];
    [view addSubview:button]; return button;
}
static NSPopUpButton *HWSelect(NSView *view, id owner, SEL action) {
    NSPopUpButton *select = [[[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO] autorelease];
    [select setTarget:owner]; [select setAction:action]; [view addSubview:select]; return select;
}
static NSString *HWDate(int date) { return [HBDateFromOrdinal(date) descriptionWithCalendarFormat:@"%d/%m/%Y"]; }
static void HWChoose(NSPopUpButton *select, NSString *key) {
    unsigned int i;
    for (i = 0; key && i < [select numberOfItems]; i++) if ([[[select itemAtIndex:i] representedObject] isEqualToString:key]) { [select selectItemAtIndex:i]; break; }
}

@implementation HBBalanceWindow
- (id)initWithWallet:(HBWallet *)wallet account:(NSString *)key {
    self = [super init]; if (!self) return nil;
    _period = 1; _needsRefresh = YES;
    _window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 880, 620)
        styleMask:NSTitledWindowMask | NSClosableWindowMask | NSMiniaturizableWindowMask | NSResizableWindowMask backing:NSBackingStoreBuffered defer:NO];
    [_window setTitle:@"Rapport de solde"]; [_window setMinSize:NSMakeSize(800, 560)]; [_window setReleasedWhenClosed:NO];
    [_window setDelegate:(id)self]; [_window setAcceptsMouseMovedEvents:YES]; [_window center];
    NSView *view = [_window contentView];
    _labels = [[NSMutableArray alloc] init];
    [_labels addObject:HWLabel(view, @"Evolution du solde", 20)]; [_labels addObject:HWLabel(view, @"Comptes", 12)];
    [_labels addObject:HWLabel(view, @"Devise", 12)]; [_labels addObject:HWLabel(view, @"Horizon des previsions", 12)];
    [_labels addObject:HWLabel(view, @"Du", 12)]; [_labels addObject:HWLabel(view, @"Au", 12)];
    _scope = HWSelect(view, self, @selector(scopeChanged:)); _currency = HWSelect(view, self, @selector(currencyChanged:));
    _horizon = HWSelect(view, self, @selector(horizonChanged:));
    [_horizon addItemsWithTitles:[NSArray arrayWithObjects:@"3 mois", @"1 an", @"5 ans", nil]]; [_horizon selectItemAtIndex:1];
    _periodControl = [[[NSSegmentedControl alloc] initWithFrame:NSZeroRect] autorelease]; [_periodControl setSegmentCount:6];
    NSArray *periods = [NSArray arrayWithObjects:@"1 M", @"3 M", @"1 A", @"5 A", @"Tout", @"Previsions", nil]; unsigned int i;
    for (i = 0; i < [periods count]; i++) { [_periodControl setLabel:[periods objectAtIndex:i] forSegment:i]; [_periodControl setWidth:i == 5 ? 92 : 54 forSegment:i]; }
    [_periodControl setSelectedSegment:_period]; [_periodControl setTarget:self]; [_periodControl setAction:@selector(periodChanged:)]; [view addSubview:_periodControl];
    _previous = HWButton(view, @"<", @"Periode precedente", self, @selector(previous:));
    _zoomIn = HWButton(view, @"+", @"Zoomer jusqu'au jour", self, @selector(zoomIn:));
    _zoomOut = HWButton(view, @"-", @"Dezoomer", self, @selector(zoomOut:));
    _next = HWButton(view, @">", @"Periode suivante", self, @selector(next:));
    _from = [[[NSTextField alloc] initWithFrame:NSZeroRect] autorelease]; _to = [[[NSTextField alloc] initWithFrame:NSZeroRect] autorelease];
    [_from setTarget:self]; [_from setAction:@selector(datesChanged:)]; [_from setDelegate:(id)self]; [_from setToolTip:@"Date de debut (JJ/MM/AAAA)"]; [view addSubview:_from];
    [_to setTarget:self]; [_to setAction:@selector(datesChanged:)]; [_to setDelegate:(id)self]; [_to setToolTip:@"Date de fin (JJ/MM/AAAA)"]; [view addSubview:_to];
    _closingTitle = HWLabel(view, @"", 12); [_closingTitle setAlignment:NSRightTextAlignment];
    _closing = HWLabel(view, @"", 21); [_closing setAlignment:NSRightTextAlignment];
    _legend = HWLabel(view, @"", 12); _status = HWLabel(view, @"", 11); [[_status cell] setWraps:YES];
    _plot = [[[HBBalanceView alloc] initWithFrame:NSZeroRect] autorelease]; [_plot setDelegate:self]; [view addSubview:_plot];
    _wallet = [wallet retain]; [self rebuildScopes];
    if (key) HWChoose(_scope, [@"account:" stringByAppendingString:key]);
    [self rebuildCurrencies]; [self layout]; return self;
}
- (void)layout {
    NSRect bounds = [[_window contentView] bounds]; float w = bounds.size.width, h = bounds.size.height, half = w / 2;
    [[_labels objectAtIndex:0] setFrame:NSMakeRect(16, h - 40, w - 32, 26)];
    [[_labels objectAtIndex:1] setFrame:NSMakeRect(16, h - 65, half - 24, 18)];
    [[_labels objectAtIndex:2] setFrame:NSMakeRect(half + 8, h - 65, 172, 18)];
    [[_labels objectAtIndex:3] setFrame:NSMakeRect(half + 200, h - 65, half - 216, 18)];
    [_scope setFrame:NSMakeRect(16, h - 98, half - 24, 28)]; [_currency setFrame:NSMakeRect(half + 8, h - 98, 172, 28)];
    [_horizon setFrame:NSMakeRect(half + 200, h - 98, half - 216, 28)];
    [_periodControl setFrame:NSMakeRect(16, h - 144, 390, 28)];
    [_previous setFrame:NSMakeRect(w - 172, h - 144, 34, 28)]; [_zoomIn setFrame:NSMakeRect(w - 130, h - 144, 34, 28)];
    [_zoomOut setFrame:NSMakeRect(w - 88, h - 144, 34, 28)]; [_next setFrame:NSMakeRect(w - 46, h - 144, 30, 28)];
    [[_labels objectAtIndex:4] setFrame:NSMakeRect(16, h - 183, 115, 18)]; [[_labels objectAtIndex:5] setFrame:NSMakeRect(158, h - 183, 115, 18)];
    [_from setFrame:NSMakeRect(16, h - 211, 126, 24)]; [_to setFrame:NSMakeRect(158, h - 211, 126, 24)];
    [_closingTitle setFrame:NSMakeRect(w - 440, h - 184, 424, 18)]; [_closing setFrame:NSMakeRect(w - 440, h - 216, 424, 28)];
    [_plot setFrame:NSMakeRect(16, 88, w - 32, h - 320)]; [_legend setFrame:NSMakeRect(16, 60, w - 32, 20)]; [_status setFrame:NSMakeRect(16, 12, w - 32, 40)];
}
- (void)windowDidResize:(NSNotification *)notification { [self layout]; }
- (void)show {
    [_window makeKeyAndOrderFront:nil]; [_window makeFirstResponder:_plot];
    if (_needsRefresh || (_history && [_history today] != HBOrdinalFromDate(HBToday()))) [self requestHistory];
}
- (void)setWallet:(HBWallet *)wallet {
    if (wallet == _wallet) return;
    [wallet retain]; [_wallet release]; _wallet = wallet; _request++; _needsRefresh = YES;
    [self rebuildScopes]; [self rebuildCurrencies];
    if ([_window isVisible]) [self requestHistory]; else [self clearHistory];
}
- (void)rebuildScopes {
    NSString *selected = [[[_scope selectedItem] representedObject] retain];
    [_scope removeAllItems]; [_scope addItemWithTitle:@"Comptes banque"]; [[_scope lastItem] setRepresentedObject:@"bank"];
    [_scope addItemWithTitle:@"Comptes epargne"]; [[_scope lastItem] setRepresentedObject:@"savings"];
    unsigned int i;
    for (i = 0; i < [[_wallet accounts] count]; i++) {
        NSDictionary *account = [[_wallet accounts] objectAtIndex:i]; if ([[account objectForKey:@"flags"] intValue] & 2) continue;
        [_scope addItemWithTitle:[NSString stringWithFormat:@"Compte : %@", [account objectForKey:@"name"]]];
        [[_scope lastItem] setRepresentedObject:[@"account:" stringByAppendingString:[account objectForKey:@"key"]]];
    }
    HWChoose(_scope, selected); [selected release];
}
- (void)rebuildCurrencies {
    NSString *selected = [[[_currency selectedItem] representedObject] retain]; [_currency removeAllItems];
    NSArray *accounts = [HBBalanceHistory accountsForWallet:_wallet scope:[[_scope selectedItem] representedObject] currency:nil];
    NSMutableSet *keys = [NSMutableSet set]; unsigned int i;
    for (i = 0; i < [accounts count]; i++) {
        NSDictionary *account = [accounts objectAtIndex:i]; NSString *key = [_wallet currencyKeyForAccount:account];
        if ([keys containsObject:key]) continue; [keys addObject:key];
        [_currency addItemWithTitle:[_wallet currencyNameForAccount:account]]; [[_currency lastItem] setRepresentedObject:key];
    }
    HWChoose(_currency, selected); [selected release]; [_currency setEnabled:[_currency numberOfItems] > 1];
}
- (void)scopeChanged:(id)sender { _period = 1; [self rebuildCurrencies]; [self requestHistory]; }
- (void)currencyChanged:(id)sender { _period = 1; [self requestHistory]; }
- (void)horizonChanged:(id)sender { _period = 5; [self requestHistory]; }
- (void)clearHistory {
    [_history release]; _history = nil;
    HBHistoryRange empty = {0, 1}; [_plot setHistory:nil wallet:nil range:empty overdraft:nil];
    [_closing setStringValue:@""]; [_closingTitle setStringValue:@""]; [_legend setStringValue:@""];
}
- (void)requestHistory {
    _request++; _needsRefresh = YES; [self clearHistory];
    [_status setStringValue:@"Calcul du rapport en arriere-plan..."]; [self updateRange];
    if (!_wallet) { _needsRefresh = NO; [_status setStringValue:@"Aucun fichier ouvert."]; return; }
    if (_busy) return;
    _busy = YES; _needsRefresh = NO;
    int months[] = {3, 12, 60};
    NSMutableDictionary *context = [NSMutableDictionary dictionaryWithObjectsAndKeys:_wallet, @"wallet", [[_scope selectedItem] representedObject], @"scope",
        [NSNumber numberWithUnsignedInt:_request], @"request", [NSNumber numberWithInt:months[[_horizon indexOfSelectedItem]]], @"months",
        [NSNumber numberWithInt:HBOrdinalFromDate(HBToday())], @"today", nil];
    if ([[_currency selectedItem] representedObject]) [context setObject:[[_currency selectedItem] representedObject] forKey:@"currency"];
    [NSThread detachNewThreadSelector:@selector(worker:) toTarget:self withObject:context];
}
- (void)worker:(NSDictionary *)context {
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    NSMutableDictionary *result = [NSMutableDictionary dictionaryWithObject:[context objectForKey:@"request"] forKey:@"request"];
    @try {
        HBWallet *wallet = [context objectForKey:@"wallet"]; NSString *error = nil;
        NSArray *accounts = [HBBalanceHistory accountsForWallet:wallet scope:[context objectForKey:@"scope"] currency:[context objectForKey:@"currency"]];
        HBBalanceHistory *history = [[[HBBalanceHistory alloc] initWithWallet:wallet accounts:accounts today:[[context objectForKey:@"today"] intValue]
            months:[[context objectForKey:@"months"] intValue] error:&error] autorelease];
        if (history) [result setObject:history forKey:@"history"]; else [result setObject:error ? error : @"Rapport indisponible." forKey:@"error"];
    } @catch (NSException *exception) { [result setObject:@"Calcul interrompu. Le portefeuille n'a pas ete modifie." forKey:@"error"]; }
    [self performSelectorOnMainThread:@selector(finished:) withObject:result waitUntilDone:NO]; [pool release];
}
- (void)finished:(NSDictionary *)result {
    _busy = NO;
    if ([[result objectForKey:@"request"] unsignedIntValue] != _request) {
        _needsRefresh = YES; if ([_window isVisible]) [self requestHistory]; return;
    }
    _history = [[result objectForKey:@"history"] retain];
    if (!_history) { [_status setStringValue:[result objectForKey:@"error"]]; [self updateRange]; return; }
    _range = _period >= 0 ? HBHistoryPreset(_history, _period) : HBHistoryClamp(_range, _history);
    NSDecimalNumber *limit = [[[_scope selectedItem] representedObject] hasPrefix:@"account:"] ? HBHistoryOverdraft([[_history accounts] objectAtIndex:0]) : nil;
    [_plot setHistory:_history wallet:_wallet range:_range overdraft:limit]; [self updateRange];
}
- (void)updateRange {
    BOOL available = _history != nil;
    [_from setEnabled:available]; [_to setEnabled:available]; [_previous setEnabled:available && _range.start > [_history start]];
    [_next setEnabled:available && _range.end < [_history end]]; [_zoomIn setEnabled:available && _range.end - _range.start > 1];
    [_zoomOut setEnabled:available && _range.end - _range.start < [_history end] - [_history start]];
    unsigned int i; for (i = 0; i < 6; i++) [_periodControl setSelected:_period == (int)i forSegment:i];
    if (!available) return;
    [_from setStringValue:HWDate(_range.start)]; [_to setStringValue:HWDate(_range.end)];
    NSDictionary *account = [[_history accounts] objectAtIndex:0]; NSDecimalNumber *amount = [_history balanceAt:_range.end];
    [_closingTitle setStringValue:[NSString stringWithFormat:@"%@ au %@", _range.end > [_history today] ? @"Solde previsionnel" : @"Solde", HWDate(_range.end)]];
    [_closing setStringValue:[_wallet formatAmount:amount account:account]];
    [_closing setTextColor:[amount compare:[NSDecimalNumber zero]] == NSOrderedDescending ? [NSColor colorWithCalibratedRed:0.05 green:0.45 blue:0.28 alpha:1] : [NSColor controlTextColor]];
    NSString *legend = @"Solde comptable  /  Solde previsionnel";
    if ([[[_scope selectedItem] representedObject] hasPrefix:@"account:"]) legend = [legend stringByAppendingFormat:@"  /  Decouvert autorise : %@", [_wallet formatAmount:HBHistoryOverdraft(account) account:account]];
    [_legend setStringValue:legend];
    NSArray *issues = [_history issues];
    [_status setStringValue:[issues count] ? [NSString stringWithFormat:@"Prevision incomplete : %@", [[issues subarrayWithRange:NSMakeRange(0, MIN(3, [issues count]))] componentsJoinedByString:@" "]] : @""];
}
- (void)chooseRange:(HBHistoryRange)range {
    if (!_history) return; _period = -1; _range = HBHistoryClamp(range, _history); [_plot setRange:_range]; [self updateRange];
}
- (void)periodChanged:(id)sender {
    _period = [_periodControl selectedSegment]; if (!_history) return;
    _range = HBHistoryPreset(_history, _period); [_plot setRange:_range]; [self updateRange];
}
- (void)datesChanged:(id)sender {
    if (!_history) return;
    int start = HBOrdinalFromFrenchDate([_from stringValue]), end = HBOrdinalFromFrenchDate([_to stringValue]);
    if (!start || !end || start >= end || start < [_history start] || end > [_history end]) {
        [_status setStringValue:[NSString stringWithFormat:@"Dates invalides : JJ/MM/AAAA, entre %@ et %@, avec debut avant fin.", HWDate([_history start]), HWDate([_history end])]]; return;
    }
    HBHistoryRange range = {start, end}; [self chooseRange:range]; [_window makeFirstResponder:_plot];
}
- (void)controlTextDidEndEditing:(NSNotification *)notification {
    if ([notification object] == _from || [notification object] == _to) [self datesChanged:[notification object]];
}
- (void)balanceView:(HBBalanceView *)view selectFrom:(int)start to:(int)end { HBHistoryRange range = {start, end}; [self chooseRange:range]; }
- (void)balanceView:(HBBalanceView *)view zoom:(double)factor { if (_history) [self chooseRange:HBHistoryZoom(_range, _history, factor)]; }
- (void)balanceView:(HBBalanceView *)view shift:(int)direction {
    int width = _range.end - _range.start; HBHistoryRange range = {_range.start + direction * width, _range.end + direction * width}; [self chooseRange:range];
}
- (void)previous:(id)sender { [self balanceView:_plot shift:-1]; }
- (void)next:(id)sender { [self balanceView:_plot shift:1]; }
- (void)zoomIn:(id)sender { [self balanceView:_plot zoom:0.5]; }
- (void)zoomOut:(id)sender { [self balanceView:_plot zoom:2]; }
- (void)dealloc { [_plot setDelegate:nil]; [_window setDelegate:nil]; [_window release]; [_labels release]; [_wallet release]; [_history release]; [super dealloc]; }
@end
