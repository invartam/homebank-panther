#import "HBCalendarWindow.h"

@interface HBCalendarWindow (PrivateMethods)
- (void)refresh:(id)sender;
- (void)modeChanged:(id)sender;
- (void)layout;
@end

static NSCalendarDate *HCCivil(int y, int m, int d) { return [NSCalendarDate dateWithYear:y month:m day:d hour:12 minute:0 second:0 timeZone:[NSTimeZone timeZoneForSecondsFromGMT:0]]; }
static NSTextField *HCLabel(NSView *view, NSString *text, float size) {
    NSTextField *label = [[[NSTextField alloc] initWithFrame:NSZeroRect] autorelease];
    [label setStringValue:text]; [label setEditable:NO]; [label setSelectable:YES]; [label setBezeled:NO]; [label setDrawsBackground:NO];
    [label setFont:[NSFont systemFontOfSize:size]]; [[label cell] setWraps:YES]; [view addSubview:label]; return label;
}
static NSButton *HCButton(NSView *view, NSString *title, id target, SEL action) {
    NSButton *button = [[[NSButton alloc] initWithFrame:NSZeroRect] autorelease];
    [button setTitle:title]; [button setTarget:target]; [button setAction:action]; [button setBezelStyle:NSRoundedBezelStyle];
    [view addSubview:button]; return button;
}
static NSScrollView *HCTable(NSView *view, id owner, NSTableView **table) {
    NSScrollView *scroll = [[[NSScrollView alloc] initWithFrame:NSZeroRect] autorelease];
    *table = [[[NSTableView alloc] initWithFrame:NSZeroRect] autorelease]; [*table setDataSource:owner]; [*table setDelegate:owner];
    [*table setUsesAlternatingRowBackgroundColors:YES]; [*table setRowHeight:25];
    NSArray *keys = [NSArray arrayWithObjects:@"date", @"account", @"name", @"origin", @"amount", nil];
    NSArray *titles = [NSArray arrayWithObjects:@"Date", @"Compte", @"Tiers / Memo", @"Origine / Frequence", @"Montant", nil];
    float widths[] = {82, 160, 270, 190, 140}; unsigned int i;
    for (i = 0; i < [keys count]; i++) {
        NSTableColumn *column = [[[NSTableColumn alloc] initWithIdentifier:[keys objectAtIndex:i]] autorelease];
        [[column headerCell] setStringValue:[titles objectAtIndex:i]]; [column setWidth:widths[i]]; [column setEditable:NO];
        if (i == 4) [[column dataCell] setAlignment:NSRightTextAlignment]; [*table addTableColumn:column];
    }
    [scroll setHasVerticalScroller:YES]; [scroll setHasHorizontalScroller:YES]; [scroll setBorderType:NSBezelBorder];
    [scroll setDocumentView:*table]; [view addSubview:scroll]; return scroll;
}
static NSString *HCMonthName(int month) {
    NSArray *names = [NSArray arrayWithObjects:@"Janvier", @"Fevrier", @"Mars", @"Avril", @"Mai", @"Juin", @"Juillet", @"Aout", @"Septembre", @"Octobre", @"Novembre", @"Decembre", nil];
    return [names objectAtIndex:month - 1];
}
static NSString *HCFrequency(NSDictionary *entry) {
    unsigned int every = [entry objectForKey:@"every"] ? [[entry objectForKey:@"every"] intValue] : 1;
    unsigned int flags = [entry objectForKey:@"recflg"] ? [[entry objectForKey:@"recflg"] intValue] : ([[entry objectForKey:@"flags"] intValue] & 128) ? 3 : 1;
    NSString *frequency;
    if (flags & 4) {
        NSArray *orders = [NSArray arrayWithObjects:@"", @"Premier", @"Deuxieme", @"Troisieme", @"Quatrieme", @"Dernier", nil];
        NSArray *weekdays = [NSArray arrayWithObjects:@"", @"lundi", @"mardi", @"mercredi", @"jeudi", @"vendredi", @"samedi", @"dimanche", @"jour", nil];
        frequency = [NSString stringWithFormat:@"%@ %@ / %u mois", [orders objectAtIndex:[[entry objectForKey:@"ordn"] intValue]], [weekdays objectAtIndex:[[entry objectForKey:@"wkdy"] intValue]], every];
    } else {
        NSArray *units = [NSArray arrayWithObjects:@"jours", @"semaines", @"mois", @"ans", nil];
        frequency = [NSString stringWithFormat:@"Tous les %u %@", every, [units objectAtIndex:[[entry objectForKey:@"unit"] intValue]]];
    }
    return flags & 2 ? [NSString stringWithFormat:@"%@ / %@ restantes", frequency, [entry objectForKey:@"limit"]] : frequency;
}

@implementation HBCalendarWindow
- (id)initWithWallet:(HBWallet *)wallet account:(NSString *)key {
    self = [super init]; if (!self) return nil;
    NSCalendarDate *today = HBToday(); _year = [today yearOfCommonEra]; _month = [today monthOfYear];
    _window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 940, 660)
        styleMask:NSTitledWindowMask | NSClosableWindowMask | NSMiniaturizableWindowMask | NSResizableWindowMask backing:NSBackingStoreBuffered defer:NO];
    [_window setReleasedWhenClosed:NO]; [_window setTitle:@"Echeancier et recurrences"]; [_window setMinSize:NSMakeSize(900, 640)]; [_window setDelegate:(id)self]; [_window center];
    NSView *view = [_window contentView]; unsigned int i;
    _mode = [[[NSSegmentedControl alloc] initWithFrame:NSZeroRect] autorelease]; [_mode setSegmentCount:3];
    [_mode setLabel:@"Mois" forSegment:0]; [_mode setLabel:@"Annee" forSegment:1]; [_mode setLabel:@"Recurrences" forSegment:2];
    [_mode setSelectedSegment:0]; [_mode setTarget:self]; [_mode setAction:@selector(modeChanged:)]; [view addSubview:_mode];
    _account = [[[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO] autorelease];
    [_account setTarget:self]; [_account setAction:@selector(refresh:)]; [view addSubview:_account];
    _closed = HCButton(view, @"Comptes clos", self, @selector(modeChanged:)); [_closed setButtonType:NSSwitchButton];
    _previous = HCButton(view, @"<", self, @selector(previous:)); [_previous setToolTip:@"Periode precedente"];
    _next = HCButton(view, @">", self, @selector(next:)); [_next setToolTip:@"Periode suivante"];
    _today = HCButton(view, @"Aujourd'hui", self, @selector(today:));
    _heading = HCLabel(view, @"", 20); _totals = HCLabel(view, @"", 12); _issues = HCLabel(view, @"", 11);
    _cells = [[NSMutableArray alloc] init]; _weekdays = [[NSMutableArray alloc] init];
    NSArray *days = [NSArray arrayWithObjects:@"Lun", @"Mar", @"Mer", @"Jeu", @"Ven", @"Sam", @"Dim", nil];
    for (i = 0; i < 7; i++) [_weekdays addObject:HCLabel(view, [days objectAtIndex:i], 12)];
    for (i = 0; i < 42; i++) {
        NSButton *cell = HCButton(view, @"", self, @selector(openPeriod:));
        [cell setBezelStyle:NSShadowlessSquareBezelStyle]; [cell setFont:[NSFont systemFontOfSize:10]];
        [[cell cell] setWraps:YES]; [_cells addObject:cell];
    }
    _recurrenceScroll = HCTable(view, self, &_recurrenceTable);
    [_recurrenceTable setTarget:self]; [_recurrenceTable setDoubleAction:@selector(openRecurrence:)];
    _agenda = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 940, 480) styleMask:NSTitledWindowMask | NSClosableWindowMask | NSResizableWindowMask backing:NSBackingStoreBuffered defer:NO];
    [_agenda setReleasedWhenClosed:NO]; [_agenda setTitle:@"Operations de la periode"]; [_agenda setDelegate:(id)self]; [_agenda setMinSize:NSMakeSize(900, 400)]; [_agenda center];
    _agendaTitle = HCLabel([_agenda contentView], @"", 18); _agendaTotals = HCLabel([_agenda contentView], @"", 12);
    _agendaScroll = HCTable([_agenda contentView], self, &_agendaTable);
    _monthButton = HCButton([_agenda contentView], @"Afficher le mois", self, @selector(showMonth:));
    [self setWallet:wallet];
    for (i = 0; i < [_account numberOfItems]; i++) if ([[[_account itemAtIndex:i] representedObject] isEqualToString:key]) [_account selectItemAtIndex:i];
    [self refresh:nil]; return self;
}
- (void)show { if (_needsRefresh) [self modeChanged:nil]; [_window makeKeyAndOrderFront:nil]; }
- (void)setWallet:(HBWallet *)wallet {
    BOOL initial = _wallet == nil;
    [wallet retain]; [_wallet release]; _wallet = wallet; [_agenda orderOut:nil];
    if (initial || [_window isVisible]) [self modeChanged:nil]; else _needsRefresh = YES;
}
- (void)modeChanged:(id)sender {
    _needsRefresh = NO;
    NSString *selected = [[[_account selectedItem] representedObject] retain];
    BOOL recurring = [_mode selectedSegment] == 2, closed = !recurring && [_closed state] == NSOnState;
    [_closed setEnabled:!recurring]; [_account removeAllItems]; [_account addItemWithTitle:@"Tous les comptes"];
    [[_account itemAtIndex:0] setRepresentedObject:@""];
    unsigned int i;
    for (i = 0; i < [[_wallet accounts] count]; i++) {
        NSDictionary *account = [[_wallet accounts] objectAtIndex:i]; BOOL isClosed = ([[account objectForKey:@"flags"] intValue] & 2) != 0;
        if (!closed && isClosed) continue;
        NSMenuItem *item = [[[NSMenuItem alloc] initWithTitle:isClosed ? [[account objectForKey:@"name"] stringByAppendingString:@" (clos)"] : [account objectForKey:@"name"] action:NULL keyEquivalent:@""] autorelease];
        [item setRepresentedObject:[account objectForKey:@"key"]]; [[_account menu] addItem:item];
        if ([[account objectForKey:@"key"] isEqualToString:selected]) [_account selectItemAtIndex:[_account numberOfItems] - 1];
    }
    [selected release]; [self refresh:nil];
}
- (NSString *)summary:(NSArray *)entries compact:(BOOL)compact {
    if ([entries count] == 0) return compact ? @"" : @"Aucune operation sur la periode";
    NSMutableArray *lines = [NSMutableArray array]; NSArray *totals = [_wallet totalsForEntries:entries]; unsigned int i;
    for (i = 0; i < [totals count]; i++) {
        NSDictionary *total = [totals objectAtIndex:i], *account = [_wallet accountWithKey:[total objectForKey:@"account"]];
        if ([total objectForKey:@"error"]) { [lines addObject:@"Total hors precision"]; continue; }
        if (compact) {
            NSArray *fields = [NSArray arrayWithObjects:@"income", @"expenses", @"transferIn", @"transferOut", nil];
            NSArray *prefixes = [NSArray arrayWithObjects:@"+", @"-", @"V+", @"V-", nil]; unsigned int j;
            for (j = 0; j < [fields count]; j++) {
                NSDecimalNumber *amount = [total objectForKey:[fields objectAtIndex:j]];
                if ([amount compare:[NSDecimalNumber zero]] != NSOrderedSame)
                    [lines addObject:[NSString stringWithFormat:@"%@%@", [prefixes objectAtIndex:j], [_wallet formatAmount:amount account:account]]];
            }
        } else [lines addObject:[NSString stringWithFormat:@"Revenus %@    Depenses %@    Virements +%@ / -%@", [_wallet formatAmount:[total objectForKey:@"income"] account:account],
            [_wallet formatAmount:[total objectForKey:@"expenses"] account:account], [_wallet formatAmount:[total objectForKey:@"transferIn"] account:account], [_wallet formatAmount:[total objectForKey:@"transferOut"] account:account]]];
    }
    return [lines componentsJoinedByString:@"\n"];
}
- (NSArray *)entriesFrom:(int)start to:(int)end {
    NSMutableArray *result = [NSMutableArray array]; unsigned int i;
    for (i = 0; i < [_entries count]; i++) { NSDictionary *entry = [_entries objectAtIndex:i]; int date = [[entry objectForKey:@"date"] intValue]; if (date >= start && date <= end) [result addObject:entry]; }
    return result;
}
- (void)refresh:(id)sender {
    BOOL recurring = [_mode selectedSegment] == 2, yearly = [_mode selectedSegment] == 1;
    NSString *key = [[_account selectedItem] representedObject]; if (![key length]) key = nil;
    NSArray *issues = nil;
    int start = HBOrdinalFromDate(HCCivil(_year, yearly ? 1 : _month, 1));
    int end = HBOrdinalFromDate(HCCivil(yearly || _month == 12 ? _year + 1 : _year, yearly || _month == 12 ? 1 : _month + 1, 1)) - 1;
    [_entries release]; _entries = recurring ? [[NSArray alloc] init] : [[_wallet calendarEntriesFrom:start to:end today:HBOrdinalFromDate(HBToday()) account:key includeClosed:[_closed state] == NSOnState issues:&issues] retain];
    [_recurrences release]; _recurrences = nil;
    if (recurring) _recurrences = [[_wallet recurringEntriesForAccount:key includeClosed:NO issues:&issues] retain];
    [_heading setStringValue:recurring ? @"Recurrences" : yearly ? [NSString stringWithFormat:@"%d", _year] : [NSString stringWithFormat:@"%@ %d", HCMonthName(_month), _year]];
    [_totals setStringValue:[self summary:recurring ? _recurrences : _entries compact:NO]];
    [_totals setToolTip:[_totals stringValue]];
    [_issues setStringValue:[issues count] ? [NSString stringWithFormat:@"%lu avertissement(s) : %@", (unsigned long)[issues count], [issues objectAtIndex:0]] : @""];
    [_issues setToolTip:[issues componentsJoinedByString:@"\n"]];
    [_recurrenceScroll setHidden:!recurring]; [_recurrenceTable reloadData];
    int offset = ([HCCivil(_year, _month, 1) dayOfWeek] + 6) % 7;
    unsigned int i;
    for (i = 0; i < 42; i++) {
        NSButton *cell = [_cells objectAtIndex:i]; [cell setHidden:recurring || (yearly && i >= 12)];
        if (recurring || (yearly && i >= 12)) continue;
        int first = yearly ? HBOrdinalFromDate(HCCivil(_year, i + 1, 1)) : start + (int)i - offset;
        int last = yearly ? HBOrdinalFromDate(HCCivil(i == 11 ? _year + 1 : _year, i == 11 ? 1 : i + 2, 1)) - 1 : first;
        BOOL inside = yearly || (first >= start && first <= end);
        [cell setEnabled:inside]; [cell setTag:yearly ? i + 1 : first];
        NSString *title = yearly ? HCMonthName(i + 1) : [NSString stringWithFormat:HBOrdinalFromDate(HBToday()) == first ? @"[%d]" : @"%d", (int)[HBDateFromOrdinal(first) dayOfMonth]];
        NSString *numbers = inside ? [self summary:[self entriesFrom:first to:last] compact:YES] : @"";
        [cell setTitle:[NSString stringWithFormat:@"%@\n%@", title, numbers]]; [cell setToolTip:[cell title]];
    }
    for (i = 0; i < 7; i++) [[_weekdays objectAtIndex:i] setHidden:recurring || yearly];
    [_previous setEnabled:!recurring && (_year > 1 || (!yearly && _month > 1))];
    [_next setEnabled:!recurring && (_year < 9999 || (!yearly && _month < 12))]; [_today setEnabled:!recurring];
    [self layout];
}
- (void)layout {
    NSSize size = [[_window contentView] bounds].size; float w = size.width, h = size.height;
    [_mode setFrame:NSMakeRect(12, h - 42, 280, 28)]; [_account setFrame:NSMakeRect(304, h - 42, w - 460, 28)]; [_closed setFrame:NSMakeRect(w - 148, h - 42, 136, 28)];
    [_heading setFrame:NSMakeRect(12, h - 83, w - 260, 28)]; [_previous setFrame:NSMakeRect(w - 230, h - 80, 34, 28)];
    [_today setFrame:NSMakeRect(w - 190, h - 80, 130, 28)]; [_next setFrame:NSMakeRect(w - 50, h - 80, 34, 28)];
    [_totals setFrame:NSMakeRect(12, h - 151, w - 24, 62)]; [_issues setFrame:NSMakeRect(12, 8, w - 24, 28)];
    [_recurrenceScroll setFrame:NSMakeRect(12, 42, w - 24, h - 198)];
    BOOL yearly = [_mode selectedSegment] == 1; int columns = yearly ? 3 : 7, rows = yearly ? 4 : 6; float cw = (w - 24) / columns, ch = (h - 220) / rows;
    unsigned int i;
    for (i = 0; i < 42; i++) {
        NSButton *cell = [_cells objectAtIndex:i];
        [cell setFrame:NSMakeRect(12 + (i % columns) * cw, h - 188 - (i / columns + 1) * ch, cw - 2, ch - 2)];
        NSString *full = [cell toolTip]; NSArray *lines = [full componentsSeparatedByString:@"\n"];
        unsigned int maximum = (unsigned int)((ch - 16) / 13); if (maximum < 2) maximum = 2;
        if ([lines count] > maximum) {
            NSMutableArray *shortened = [NSMutableArray arrayWithArray:[lines subarrayWithRange:NSMakeRange(0, maximum - 1)]];
            [shortened addObject:[NSString stringWithFormat:@"+%lu lignes", (unsigned long)[lines count] - maximum + 1]];
            [cell setTitle:[shortened componentsJoinedByString:@"\n"]];
        } else if (full) [cell setTitle:full];
    }
    for (i = 0; i < 7; i++) [[_weekdays objectAtIndex:i] setFrame:NSMakeRect(12 + i * (w - 24) / 7, h - 183, (w - 24) / 7, 22)];
    NSSize agenda = [[_agenda contentView] bounds].size;
    [_agendaTitle setFrame:NSMakeRect(12, agenda.height - 44, agenda.width - 190, 26)];
    [_monthButton setFrame:NSMakeRect(agenda.width - 172, agenda.height - 44, 160, 28)];
    [_agendaTotals setFrame:NSMakeRect(12, agenda.height - 106, agenda.width - 24, 56)];
    [_agendaScroll setFrame:NSMakeRect(12, 12, agenda.width - 24, agenda.height - 124)];
}
- (void)windowDidResize:(NSNotification *)notification { [self layout]; }
- (void)previous:(id)sender { if ([_mode selectedSegment] == 1) _year--; else if (--_month == 0) { _month = 12; _year--; } [self refresh:nil]; }
- (void)next:(id)sender { if ([_mode selectedSegment] == 1) _year++; else if (++_month == 13) { _month = 1; _year++; } [self refresh:nil]; }
- (void)today:(id)sender { NSCalendarDate *date = HBToday(); _year = [date yearOfCommonEra]; _month = [date monthOfYear]; [self refresh:nil]; }
- (void)openPeriod:(id)sender {
    int start = [sender tag], end = start; BOOL yearly = [_mode selectedSegment] == 1;
    if (yearly) { _agendaMonth = start; start = HBOrdinalFromDate(HCCivil(_year, _agendaMonth, 1)); end = HBOrdinalFromDate(HCCivil(_agendaMonth == 12 ? _year + 1 : _year, _agendaMonth == 12 ? 1 : _agendaMonth + 1, 1)) - 1; }
    [_agendaEntries release]; _agendaEntries = [[self entriesFrom:start to:end] retain];
    [_agendaTitle setStringValue:yearly ? [NSString stringWithFormat:@"%@ %d", HCMonthName(_agendaMonth), _year] : [HBDateFromOrdinal(start) descriptionWithCalendarFormat:@"%d/%m/%Y"]];
    [_agendaTotals setStringValue:[self summary:_agendaEntries compact:NO]]; [_agendaTotals setToolTip:[_agendaTotals stringValue]];
    [_monthButton setHidden:!yearly]; [_agendaTable reloadData]; [self layout]; [_agenda makeKeyAndOrderFront:nil];
}
- (void)showMonth:(id)sender { _month = _agendaMonth; [_mode setSelectedSegment:0]; [self modeChanged:nil]; [_agenda orderOut:nil]; }
- (HBIndex)numberOfRowsInTableView:(NSTableView *)table { return table == _agendaTable ? [_agendaEntries count] : [_recurrences count]; }
- (id)tableView:(NSTableView *)table objectValueForTableColumn:(NSTableColumn *)column row:(HBIndex)row {
    NSDictionary *entry = [(table == _agendaTable ? _agendaEntries : _recurrences) objectAtIndex:row]; NSString *key = [column identifier];
    if ([key isEqualToString:@"date"]) return [HBDateFromOrdinal([[entry objectForKey:@"date"] intValue]) descriptionWithCalendarFormat:@"%d/%m/%Y"];
    if ([key isEqualToString:@"account"]) return [[_wallet accountWithKey:[entry objectForKey:@"account"]] objectForKey:@"name"];
    if ([key isEqualToString:@"amount"]) return [_wallet formatAmount:[entry objectForKey:@"amount"] account:[_wallet accountWithKey:[entry objectForKey:@"account"]]];
    if ([key isEqualToString:@"name"]) return [_wallet payeeForRecord:entry];
    if (table == _agendaTable) return [entry objectForKey:@"__planned"] ? @"Prevision" : @"Inscrite";
    return HCFrequency(entry);
}
- (void)openRecurrence:(id)sender {
    HBIndex row = [_recurrenceTable clickedRow]; if (row < 0 || (unsigned long)row >= [_recurrences count]) return;
    NSDictionary *entry = [_recurrences objectAtIndex:row];
    NSArray *weekends = [NSArray arrayWithObjects:@"Date inchangee", @"Vendredi precedent", @"Lundi suivant", @"Week-end saute", nil];
    NSString *memo = [entry objectForKey:@"wording"] ? [entry objectForKey:@"wording"] : @"";
    if ([memo length] > 256) memo = [[memo substringToIndex:256] stringByAppendingString:@"..."];
    NSRunAlertPanel(@"Planification", @"%@\n%@\nReport : %@\nMemo : %@\nNumero : %@", @"OK", nil, nil,
        [self tableView:_recurrenceTable objectValueForTableColumn:[_recurrenceTable tableColumnWithIdentifier:@"name"] row:row], HCFrequency(entry),
        [weekends objectAtIndex:[[entry objectForKey:@"weekend"] intValue]], memo, [entry objectForKey:@"info"] ? [entry objectForKey:@"info"] : @"");
}
- (void)dealloc {
    [_wallet release]; [_window release]; [_agenda release]; [_cells release]; [_weekdays release]; [_entries release]; [_recurrences release]; [_agendaEntries release]; [super dealloc];
}
@end
