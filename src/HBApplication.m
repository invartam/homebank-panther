#import "HBApplication.h"
#include <stdlib.h>

#define HB_PAGE_SIZE 100

@interface HBApplication (PrivateMethods)
- (void)layout;
- (void)refreshRecords;
- (BOOL)mayDiscard;
- (void)updateDocumentState;
- (void)filterAccounts:(id)sender;
- (void)filterAccountsSelectingKey:(NSString *)key;
- (void)selectAccount;
- (NSDictionary *)selectedAccount;
- (NSDictionary *)selectedRecord;
- (void)filterRecords;
- (void)updateButtons;
- (BOOL)save;
- (BOOL)drivePending;
- (void)queueLocalSave;
- (void)launchLocalSave:(NSDictionary *)context;
- (void)localSaveWorker:(NSDictionary *)context;
- (void)localSaveFinished:(NSDictionary *)result;
- (void)resumeSync:(id)sender;
- (void)updateDriveStatus;
- (void)consolidateXML:(id)sender;
- (void)adoptCheckpoint:(HBWallet *)wallet;
- (void)disconnectDrive:(id)sender;
- (void)syncDrive:(id)sender;
- (void)reloadDrive:(id)sender;
- (void)configureDrive:(id)sender;
- (void)startDriveAction:(NSString *)action manual:(BOOL)manual;
@end

static NSMenuItem *HBMenuCommand(NSMenu *menu, NSString *title, SEL action, NSString *key, id target) {
    NSMenuItem *item = (NSMenuItem *)[menu addItemWithTitle:title action:action keyEquivalent:key];
    [item setTarget:target]; return item;
}
static NSDictionary *HBDriveRequestResult(NSDictionary *context) {
    NSString *error = nil, *action = [context objectForKey:@"action"], *path = [context objectForKey:@"cachePath"];
    NSMutableDictionary *result = [NSMutableDictionary dictionary];
    HBWallet *local = [context objectForKey:@"localWallet"], *checkpoint = nil;
    if ([action isEqualToString:@"checkpoint"] || (local && [local generation])) {
        checkpoint = HBCheckpointWallet(local, path, &error);
        if (!checkpoint) return [NSDictionary dictionaryWithObject:error ? error : @"Consolidation XML impossible." forKey:@"error"];
        [result setObject:checkpoint forKey:@"checkpointWallet"];
    }
    if ([action isEqualToString:@"checkpoint"]) { [result setObject:[NSNumber numberWithBool:YES] forKey:@"completed"]; return result; }
    if ([action isEqualToString:@"export"]) {
        HBWallet *exported = [[context objectForKey:@"wallet"] walletForHomeBankExport:&error];
        HBWallet *existing = nil;
        if ([[NSFileManager defaultManager] fileExistsAtPath:path]) {
            if (![[context objectForKey:@"replace"] boolValue]) error = @"La destination existe maintenant. Export refuse.";
            else existing = [HBWallet walletAtPath:path error:&error];
            if (!existing) exported = nil;
        }
        if (exported && HBWriteWallet(exported, path, [existing baseSourceData], &error)) [result setObject:[NSNumber numberWithBool:YES] forKey:@"completed"];
        else [result setObject:error ? error : @"Export impossible." forKey:@"error"];
        return result;
    }
    HBDriveClient *client = [context objectForKey:@"client"]; BOOL downloading = [action isEqualToString:@"download"];
    HBWallet *sent = checkpoint ? checkpoint : [context objectForKey:@"wallet"];
    NSDictionary *response = downloading ? [client download:&error] : [client uploadWallet:sent expectedETag:[context objectForKey:@"etag"] error:&error];
    HBWallet *wallet = downloading ? [response objectForKey:@"wallet"] : sent;
    NSDictionary *metadata = downloading ? [response objectForKey:@"metadata"] : response;
    NSData *expected = checkpoint ? [checkpoint baseSourceData] : [context objectForKey:@"expectedCacheData"];
    if (response && downloading && !HBWriteWallet(wallet, path, expected, &error)) response = nil;
    if (response) {
        NSString *hash = HBDriveSHA256([wallet sourceData]);
        NSDictionary *state = hash ? [NSDictionary dictionaryWithObjectsAndKeys:[context objectForKey:@"fileID"], @"fileID", [metadata objectForKey:@"etag"], @"etag", hash, @"syncedSHA256", nil] : nil;
        if (state && HBDriveWriteState(state, [path stringByAppendingString:@".drive-state.plist"], &error)) {
            [result setObject:response forKey:@"response"]; [result setObject:state forKey:@"state"]; [result setObject:wallet forKey:@"confirmedWallet"];
        } else response = nil;
    }
    if (!response) [result setObject:error ? error : @"Synchronisation impossible. Journal et copie locale conserves." forKey:@"error"];
    return result;
}
static NSDictionary *HBLocalSaveResult(NSDictionary *context) {
    NSString *error = nil; HBWallet *wallet = [context objectForKey:@"wallet"]; NSDictionary *expected = [context objectForKey:@"journalState"];
    unsigned int start = [[expected objectForKey:@"count"] intValue]; NSArray *commands = [wallet journalCommands];
    NSDictionary *state = start <= [commands count] ? HBJournalAppend([[context objectForKey:@"path"] stringByAppendingString:@".panther-journal"],
        [context objectForKey:@"baseHash"], [commands subarrayWithRange:NSMakeRange(start, [commands count] - start)], expected, &error) : nil;
    if (state) return [NSDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithBool:YES], @"saved", state, @"journalState", nil];
    return [NSDictionary dictionaryWithObject:error ? error : @"Sauvegarde locale impossible." forKey:@"error"];
}
static BOOL HBModelDirty(HBWallet *wallet, HBWallet *saved) {
    return wallet != saved && (!saved || [wallet generation] != [saved generation] || [wallet baseSourceData] != [saved baseSourceData]);
}

static NSTextField *HBLabel(NSView *view, NSString *text, float size) {
    NSTextField *field = [[[NSTextField alloc] initWithFrame:NSZeroRect] autorelease];
    [field setEditable:NO]; [field setSelectable:YES]; [field setBezeled:NO]; [field setDrawsBackground:NO];
    [field setFont:[NSFont systemFontOfSize:size]]; [field setStringValue:text];
    [view addSubview:field]; return field;
}

static NSButton *HBButton(NSView *view, NSString *title, id target, SEL action) {
    NSButton *button = [[[NSButton alloc] initWithFrame:NSZeroRect] autorelease];
    [button setTitle:title]; [button setBezelStyle:NSRoundedBezelStyle];
    [button setTarget:target]; [button setAction:action]; [view addSubview:button]; return button;
}

static void HBColumn(NSTableView *table, NSString *key, NSString *title, float width, BOOL money) {
    NSTableColumn *column = [[[NSTableColumn alloc] initWithIdentifier:key] autorelease];
    [[column headerCell] setStringValue:title]; [column setWidth:width]; [column setEditable:NO];
    if (money) [[column dataCell] setAlignment:NSRightTextAlignment];
    [table addTableColumn:column];
}

static NSScrollView *HBTable(NSView *view, id delegate, NSTableView **table) {
    NSScrollView *scroll = [[[NSScrollView alloc] initWithFrame:NSZeroRect] autorelease];
    *table = [[[NSTableView alloc] initWithFrame:NSZeroRect] autorelease];
    [*table setDataSource:delegate]; [*table setDelegate:delegate]; [*table setRowHeight:23];
    [*table setAllowsMultipleSelection:NO]; [*table setUsesAlternatingRowBackgroundColors:YES];
    [scroll setHasVerticalScroller:YES]; [scroll setHasHorizontalScroller:YES];
    [scroll setBorderType:NSBezelBorder]; [scroll setDocumentView:*table];
    [view addSubview:scroll]; return scroll;
}

static HBIndex HBAccountOrder(id a, id b, void *context) {
    unsigned long left = strtoul([[a objectForKey:@"pos"] UTF8String], NULL, 10);
    unsigned long right = strtoul([[b objectForKey:@"pos"] UTF8String], NULL, 10);
    if (left != right) return left < right ? NSOrderedAscending : NSOrderedDescending;
    return [[a objectForKey:@"name"] compare:[b objectForKey:@"name"] options:NSCaseInsensitiveSearch];
}

static NSColor *HBBalanceColor(NSDecimalNumber *value, NSDictionary *account) {
    NSDecimalNumber *minimum = [account objectForKey:@"minimum"];
    BOOL dark = [[[NSColor controlTextColor] colorUsingColorSpaceName:NSCalibratedRGBColorSpace] brightnessComponent] > 0.5;
    if ([value compare:[NSDecimalNumber zero]] == NSOrderedDescending)
        return dark ? [NSColor colorWithCalibratedRed:0.35 green:0.85 blue:0.60 alpha:1]
            : [NSColor colorWithCalibratedRed:0.05 green:0.40 blue:0.22 alpha:1];
    if ([minimum compare:[NSDecimalNumber zero]] == NSOrderedDescending)
        minimum = [minimum decimalNumberByMultiplyingBy:[NSDecimalNumber decimalNumberWithString:@"-1"]];
    if ([value compare:minimum] != NSOrderedAscending)
        return dark ? [NSColor colorWithCalibratedRed:1 green:0.69 blue:0.35 alpha:1]
            : [NSColor colorWithCalibratedRed:0.65 green:0.32 blue:0.03 alpha:1];
    return dark ? [NSColor colorWithCalibratedRed:1 green:0.43 blue:0.45 alpha:1]
        : [NSColor colorWithCalibratedRed:0.72 green:0.08 blue:0.10 alpha:1];
}

@implementation HBApplication
- (void)buildInterface {
    NSView *view;
    NSMenu *menu, *appMenu, *fileMenu, *editMenu, *driveMenu;
    NSMenuItem *item;
    NSArray *titles;
    unsigned int i;
    if (_window) return;
    _window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 940, 600)
        styleMask:NSTitledWindowMask | NSClosableWindowMask | NSMiniaturizableWindowMask | NSResizableWindowMask
        backing:NSBackingStoreBuffered defer:NO];
    [_window setReleasedWhenClosed:NO]; [_window setMinSize:NSMakeSize(900, 480)];
    [_window setTitle:@"HomeBank Panther"]; [_window setDelegate:(id)self]; [_window center];
    view = [_window contentView];
    _openButton = HBButton(view, @"Ouvrir un fichier...", self, @selector(openFile:));
    _ownerLabel = HBLabel(view, @"HomeBank Panther", 17);
    _newButton = HBButton(view, @"+ Nouvelle", self, @selector(newRecord:));
    _editButton = HBButton(view, @"Modifier", self, @selector(editRecord:));
    _saveButton = HBButton(view, @"Enregistrer", self, @selector(saveFile:));
    [_saveButton setToolTip:@"Confirmer les modifications dans le journal local"];
    _exportButton = HBButton(view, @"Exporter...", self, @selector(exportFile:));
    _calendarButton = HBButton(view, @"Planifications", self, @selector(showCalendar:));
    _driveButton = HBButton(view, @"Google Drive", self, @selector(openDrive:));
    _syncButton = HBButton(view, @"Synchroniser", self, @selector(syncDrive:));
    [_syncButton setToolTip:@"Envoyer les modifications locales, ou charger Drive si aucune modification n'est en attente"];
    _driveLabel = HBLabel(view, @"Drive : non configure", 11);
    _deleteButton = HBButton(view, @"Supprimer", self, @selector(deleteRecord:));
    _pointButton = HBButton(view, @"Pointer", self, @selector(pointRecord:));
    _reconcileButton = HBButton(view, @"Rapprocher", self, @selector(reconcileRecord:));
    _search = [[[NSSearchField alloc] initWithFrame:NSZeroRect] autorelease]; [_search setDelegate:(id)self]; [view addSubview:_search];
    _group = [[[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO] autorelease];
    [_group addItemsWithTitles:[NSArray arrayWithObjects:@"Tous les comptes ouverts", @"Banque", @"Epargne", nil]];
    [_group setTarget:self]; [_group setAction:@selector(filterAccounts:)]; [view addSubview:_group];
    _accountLabel = HBLabel(view, @"", 16);
    _accountsScroll = HBTable(view, self, &_accountsTable);
    HBColumn(_accountsTable, @"name", @"Compte", 130, NO);
    HBColumn(_accountsTable, @"balance", @"Rapproche", 115, YES);
    _recordsScroll = HBTable(view, self, &_recordsTable);
    HBColumn(_recordsTable, @"date", @"Date", 82, NO);
    HBColumn(_recordsTable, @"payee", @"Tiers / Memo", 165, NO);
    HBColumn(_recordsTable, @"category", @"Categorie", 120, NO);
    HBColumn(_recordsTable, @"status", @"Etat", 86, NO);
    HBColumn(_recordsTable, @"amount", @"Montant", 110, YES);
    [_recordsTable setTarget:self]; [_recordsTable setDoubleAction:@selector(editRecord:)];
    [_recordsTable setToolTip:@"Modifier l'operation"];
    _balanceTitles = [[NSMutableArray alloc] init]; _balanceLabels = [[NSMutableArray alloc] init];
    titles = [NSArray arrayWithObjects:@"Rapproche", @"Pointe", @"Futur", nil];
    for (i = 0; i < [titles count]; i++) {
        [_balanceTitles addObject:HBLabel(view, [titles objectAtIndex:i], 12)];
        [_balanceLabels addObject:HBLabel(view, @"", 19)];
    }
    _previous = HBButton(view, @"<", self, @selector(previousPage:)); [_previous setToolTip:@"Page precedente"];
    _next = HBButton(view, @">", self, @selector(nextPage:)); [_next setToolTip:@"Page suivante"];
    _pageLabel = HBLabel(view, @"", 12); _statusLabel = HBLabel(view, @"Aucun fichier ouvert", 12);
    [[_statusLabel cell] setWraps:YES];
    menu = [[[NSMenu alloc] initWithTitle:@"Menu"] autorelease];
    appMenu = [[[NSMenu alloc] initWithTitle:@"HomeBank Panther"] autorelease];
    item = [[[NSMenuItem alloc] initWithTitle:@"HomeBank Panther" action:NULL keyEquivalent:@""] autorelease];
    [item setSubmenu:appMenu]; [menu addItem:item];
    [appMenu addItemWithTitle:@"Quitter HomeBank Panther" action:@selector(terminate:) keyEquivalent:@"q"];
    fileMenu = [[[NSMenu alloc] initWithTitle:@"Fichier"] autorelease];
    item = [[[NSMenuItem alloc] initWithTitle:@"Fichier" action:NULL keyEquivalent:@""] autorelease];
    [item setSubmenu:fileMenu]; [menu addItem:item];
    HBMenuCommand(fileMenu, @"Ouvrir...", @selector(openFile:), @"o", self);
    HBMenuCommand(fileMenu, @"Recharger", @selector(reloadFile:), @"r", self);
    HBMenuCommand(fileMenu, @"Enregistrer", @selector(saveFile:), @"s", self);
    HBMenuCommand(fileMenu, @"Consolider le fichier XML", @selector(consolidateXML:), @"", self);
    HBMenuCommand(fileMenu, @"Exporter une copie...", @selector(exportFile:), @"e", self);
    HBMenuCommand(fileMenu, @"Reparer la compatibilite HomeBank...", @selector(repairHomeBank:), @"", self);
    HBMenuCommand(fileMenu, @"Nouvelle operation", @selector(newRecord:), @"n", self);
    HBMenuCommand(fileMenu, @"Planifications", @selector(showCalendar:), @"p", self);
    editMenu = [[[NSMenu alloc] initWithTitle:@"Edition"] autorelease];
    item = [[[NSMenuItem alloc] initWithTitle:@"Edition" action:NULL keyEquivalent:@""] autorelease]; [item setSubmenu:editMenu]; [menu addItem:item];
    [editMenu addItemWithTitle:@"Couper" action:@selector(cut:) keyEquivalent:@"x"];
    [editMenu addItemWithTitle:@"Copier" action:@selector(copy:) keyEquivalent:@"c"];
    [editMenu addItemWithTitle:@"Coller" action:@selector(paste:) keyEquivalent:@"v"];
    [editMenu addItemWithTitle:@"Tout selectionner" action:@selector(selectAll:) keyEquivalent:@"a"];
    driveMenu = [[[NSMenu alloc] initWithTitle:@"Drive"] autorelease];
    item = [[[NSMenuItem alloc] initWithTitle:@"Drive" action:NULL keyEquivalent:@""] autorelease]; [item setSubmenu:driveMenu]; [menu addItem:item];
    HBMenuCommand(driveMenu, @"Configurer le compte de service...", @selector(configureDrive:), @"", self);
    HBMenuCommand(driveMenu, @"Ouvrir le fichier Drive", @selector(openDrive:), @"", self);
    HBMenuCommand(driveMenu, @"Synchroniser maintenant", @selector(syncDrive:), @"", self);
    HBMenuCommand(driveMenu, @"Recharger depuis Drive...", @selector(reloadDrive:), @"", self);
    HBMenuCommand(driveMenu, @"Desactiver la synchronisation", @selector(disconnectDrive:), @"", self);
    HBMenuCommand(driveMenu, @"Oublier la configuration et la cle...", @selector(forgetDrive:), @"", self);
    [NSApp setMainMenu:menu];
    [self layout]; [self refreshRecords];
    [_window makeKeyAndOrderFront:nil]; [NSApp activateIgnoringOtherApps:YES];
    NSDictionary *settings = [[NSUserDefaults standardUserDefaults] dictionaryForKey:@"HBPantherDrive"];
    if (settings) { _driveSettings = [settings copy]; _drive = [[HBDriveClient alloc] initWithSettings:settings transport:nil credentials:nil]; [_driveLabel setStringValue:@"Drive : configure, non ouvert"]; }
}
- (void)layout {
    NSRect bounds = [[_window contentView] bounds];
    float h = bounds.size.height, w = bounds.size.width, right = w - 288;
    unsigned int i;
    [_ownerLabel setFrame:NSMakeRect(12, h - 34, w - 340, 24)];
    [_driveLabel setFrame:NSMakeRect(w - 320, h - 31, 308, 21)];
    [_openButton setFrame:NSMakeRect(12, h - 72, 145, 28)];
    [_newButton setFrame:NSMakeRect(169, h - 72, 110, 28)]; [_editButton setFrame:NSMakeRect(291, h - 72, 90, 28)];
    [_saveButton setFrame:NSMakeRect(393, h - 72, 110, 28)]; [_exportButton setFrame:NSMakeRect(515, h - 72, 110, 28)];
    [_calendarButton setFrame:NSMakeRect(637, h - 72, 130, 28)];
    [_driveButton setFrame:NSMakeRect(775, h - 72, 113, 28)];
    [_syncButton setFrame:NSMakeRect(w - 142, 50, 130, 28)];
    [_group setFrame:NSMakeRect(12, h - 112, 260, 26)];
    [_accountsScroll setFrame:NSMakeRect(12, 86, 260, h - 208)];
    [_accountLabel setFrame:NSMakeRect(288, h - 112, right - 240, 26)];
    [_search setFrame:NSMakeRect(w - 240, h - 112, 228, 26)];
    for (i = 0; i < 3; i++) {
        float x = 288 + i * right / 3;
        [[_balanceTitles objectAtIndex:i] setFrame:NSMakeRect(x, h - 138, right / 3 - 12, 19)];
        [[_balanceLabels objectAtIndex:i] setFrame:NSMakeRect(x, h - 166, right / 3 - 12, 27)];
    }
    [_recordsScroll setFrame:NSMakeRect(288, 86, right - 12, h - 262)];
    [_pointButton setFrame:NSMakeRect(288, 50, 120, 28)]; [_reconcileButton setFrame:NSMakeRect(420, 50, 150, 28)];
    [_deleteButton setFrame:NSMakeRect(582, 50, 110, 28)];
    [_previous setFrame:NSMakeRect(288, 16, 34, 28)]; [_next setFrame:NSMakeRect(328, 16, 34, 28)];
    [_pageLabel setFrame:NSMakeRect(374, 22, right - 98, 20)];
    [_statusLabel setFrame:NSMakeRect(12, 16, 260, 56)];
}
- (void)applicationDidFinishLaunching:(NSNotification *)notification { [self buildInterface]; [self performSelector:@selector(restoreDrive:) withObject:nil afterDelay:0.5]; }
- (void)windowDidResize:(NSNotification *)notification { [self layout]; }
- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)application { return YES; }
- (NSApplicationTerminateReply)applicationShouldTerminate:(NSApplication *)application { return [NSApp modalWindow] == nil && !_driveBusy && [self mayDiscard] ? NSTerminateNow : NSTerminateCancel; }
- (BOOL)windowShouldClose:(id)sender { return [NSApp modalWindow] == nil && !_driveBusy && [self mayDiscard]; }
- (BOOL)application:(NSApplication *)application openFile:(NSString *)filename { return [self openPath:filename]; }
- (void)openFile:(id)sender {
    if (_driveBusy || _saveBusy || _saveTimer || _syncRequested) return;
    NSOpenPanel *panel = [NSOpenPanel openPanel];
    [panel setAllowsMultipleSelection:NO]; [panel setCanChooseDirectories:NO];
    if ([panel runModalForDirectory:nil file:nil types:[NSArray arrayWithObjects:@"xhb", @"xml", nil]] == NSOKButton)
        [self openPath:[[panel filenames] objectAtIndex:0]];
}
- (void)reloadFile:(id)sender { if (_path) [self openPath:_path]; }
- (BOOL)openPath:(NSString *)path {
    NSString *error = nil;
    HBWallet *wallet;
    [self buildInterface];
    if (_driveBusy || [NSApp modalWindow] != nil || ![self mayDiscard]) return NO;
    NSDictionary *journal = nil; wallet = HBRestoreWallet(path, &journal, &error);
    if (!wallet) {
        [_statusLabel setStringValue:error ? error : @"Import impossible."];
        NSRunAlertPanel(@"Fichier non charge", @"%@", @"OK", nil, nil, error ? error : @"Import impossible.");
        return NO;
    }
    [wallet retain]; [_wallet release]; _wallet = wallet;
    [_path release]; _path = [path copy];
    [_savedData release]; _savedData = [[wallet baseSourceData] copy]; _dirty = NO;
    [_savedWallet release]; _savedWallet = [wallet retain]; [_journalState release]; _journalState = [journal copy];
    [_savedHash release]; _savedHash = [HBDriveSHA256(_savedData) copy]; [_saveError release]; _saveError = nil;
    _driveActive = NO;
    if (_drive) [_driveLabel setStringValue:@"Drive : inactif pour ce fichier local"];
    [_search setStringValue:@""];
    [_ownerLabel setStringValue:[wallet owner]];
    [self updateDocumentState]; if (_calendar) [_calendar setWallet:_wallet];
    [self filterAccounts:nil]; [_window makeKeyAndOrderFront:nil]; return YES;
}
- (NSDictionary *)selectedAccount {
    HBRow row = [_accountsTable selectedRow];
    return row >= 0 && (unsigned long)row < [_visibleAccounts count] ? [_visibleAccounts objectAtIndex:row] : nil;
}
- (void)filterAccounts:(id)sender { [self filterAccountsSelectingKey:nil]; }
- (void)filterAccountsSelectingKey:(NSString *)key {
    NSMutableArray *accounts = [NSMutableArray array];
    unsigned int i;
    for (i = 0; i < [[_wallet accounts] count]; i++) {
        NSDictionary *account = [[_wallet accounts] objectAtIndex:i];
        int type = [[account objectForKey:@"type"] intValue];
        BOOL savings = type == 3 || type == 7;
        HBRow filter = [_group indexOfSelectedItem];
        if ((strtoul([[account objectForKey:@"flags"] UTF8String], NULL, 10) & 2) != 0) continue;
        if ((filter == 1 && savings) || (filter == 2 && !savings)) continue;
        [accounts addObject:account];
    }
    [accounts sortUsingFunction:HBAccountOrder context:NULL];
    [_visibleAccounts release]; _visibleAccounts = [accounts copy];
    _refreshingSelection = YES;
    [_accountsTable deselectAll:nil]; [_accountsTable reloadData];
    HBRow selected = 0;
    for (i = 0; key && i < [accounts count]; i++) if ([[[accounts objectAtIndex:i] objectForKey:@"key"] isEqualToString:key]) { selected = i; break; }
    if ([accounts count]) [_accountsTable selectRow:selected byExtendingSelection:NO];
    _refreshingSelection = NO;
    [self selectAccount];
}
- (void)selectAccount {
    NSDictionary *account = [self selectedAccount];
    NSDictionary *balances = [_wallet balancesForAccount:account];
    NSArray *keys = [NSArray arrayWithObjects:@"reconciled", @"cleared", @"future", nil];
    unsigned int i;
    _page = 0;
    [_accountLabel setStringValue:account ? [account objectForKey:@"name"] : @"Aucun compte ouvert"];
    for (i = 0; i < 3; i++) {
        NSDecimalNumber *balance = [balances objectForKey:[keys objectAtIndex:i]];
        NSTextField *label = [_balanceLabels objectAtIndex:i];
        [label setStringValue:balance ? [_wallet formatAmount:balance account:account] : @""];
        if (balance) [label setTextColor:HBBalanceColor(balance, account)];
    }
    [self filterRecords];
}
- (void)tableViewSelectionDidChange:(NSNotification *)notification {
    if (_refreshingSelection) return;
    if ([notification object] == _accountsTable) [self selectAccount];
    else [self updateButtons];
}
- (void)refreshRecords {
    unsigned int total = [_visibleRecords count], start = _page * HB_PAGE_SIZE;
    unsigned int end = start + HB_PAGE_SIZE > total ? total : start + HB_PAGE_SIZE;
    [_recordsTable reloadData]; [_recordsTable scrollPoint:NSZeroPoint];
    [_previous setEnabled:_page > 0]; [_next setEnabled:end < total];
    [_pageLabel setStringValue:[NSString stringWithFormat:@"%u-%u / %u operations", total ? start + 1 : 0, end, total]];
    [self updateButtons];
}
- (void)controlTextDidChange:(NSNotification *)notification { if ([notification object] == _search) [self filterRecords]; }
- (void)filterRecords {
    NSDictionary *account = [self selectedAccount];
    NSArray *records = [_wallet recordsForAccount:account]; NSMutableArray *filtered = nil;
    NSString *query = [_search stringValue]; unsigned int i;
    if ([query length]) filtered = [NSMutableArray array];
    for (i = 0; filtered && i < [records count]; i++) {
        NSDictionary *record = [records objectAtIndex:i];
        NSString *text = [NSString stringWithFormat:@"%@ %@ %@ %@ %@", [_wallet payeeForRecord:record], [_wallet categoryForRecord:record],
            [record objectForKey:@"wording"] ? [record objectForKey:@"wording"] : @"", [record objectForKey:@"info"] ? [record objectForKey:@"info"] : @"", [_wallet formatAmount:[record objectForKey:@"amount"] account:account]];
        if ([text rangeOfString:query options:NSCaseInsensitiveSearch].location != NSNotFound) [filtered addObject:record];
    }
    [_visibleRecords release]; _visibleRecords = [(filtered ? filtered : records) copy]; _page = 0;
    _refreshingSelection = YES; [_recordsTable deselectAll:nil]; _refreshingSelection = NO; [self refreshRecords];
}
- (NSDictionary *)selectedRecord {
    HBRow row = [_recordsTable selectedRow];
    return row >= 0 && (unsigned int)row < [self numberOfRowsInTableView:_recordsTable] ? [_visibleRecords objectAtIndex:_page * HB_PAGE_SIZE + row] : nil;
}
- (void)updateButtons {
    NSDictionary *record = [self selectedRecord];
    [_newButton setEnabled:[self selectedAccount] != nil]; [_editButton setEnabled:record != nil]; [_deleteButton setEnabled:record != nil];
    [_pointButton setEnabled:record != nil && [[record objectForKey:@"st"] intValue] != 2]; [_reconcileButton setEnabled:record != nil];
    [_pointButton setTitle:[[record objectForKey:@"st"] intValue] == 1 ? @"Depointer" : @"Pointer"];
    [_reconcileButton setTitle:[[record objectForKey:@"st"] intValue] == 2 ? @"Derapprocher" : @"Rapprocher"];
    [_saveButton setEnabled:_dirty && !_saveBusy]; [_exportButton setEnabled:_wallet != nil && !_saveBusy && !_saveTimer && !_syncRequested && !_driveBusy]; [_calendarButton setEnabled:_wallet != nil];
    [_syncButton setEnabled:_driveActive && !_driveBusy && !_syncRequested];
    if (_driveBusy) {
        [_newButton setEnabled:NO]; [_editButton setEnabled:NO]; [_deleteButton setEnabled:NO]; [_pointButton setEnabled:NO]; [_reconcileButton setEnabled:NO]; [_saveButton setEnabled:NO]; [_openButton setEnabled:NO]; [_driveButton setEnabled:NO];
    } else { [_openButton setEnabled:!_saveBusy && !_saveTimer && !_syncRequested]; [_driveButton setEnabled:!_saveBusy && !_saveTimer && !_syncRequested]; }
}
- (void)updateDocumentState {
    [_window setTitle:[NSString stringWithFormat:@"%@%@ - HomeBank Panther", [_path lastPathComponent], _dirty ? @" *" : @""]];
    [_window setDocumentEdited:_dirty];
    [_statusLabel setStringValue:_saveError ? @"Sauvegarde locale echouee : Enregistrer pour reessayer" :
        (_saveBusy || _saveTimer) ? @"Journal local en cours d'enregistrement..." : _dirty ? @"Modifications non enregistrees" : [_wallet generation] ? @"Modifications conservees dans le journal local" : @"Fichier enregistre localement"];
    [_statusLabel setToolTip:_saveError]; [self updateDriveStatus];
    [self updateButtons];
}
- (void)applyWallet:(HBWallet *)wallet {
    NSString *key = [[[self selectedAccount] objectForKey:@"key"] retain];
    NSNumber *recordIndex = [[[self selectedRecord] objectForKey:@"__index"] retain];
    if ([[wallet records] count] < [[_wallet records] count]) { [recordIndex release]; recordIndex = nil; }
    else if ([[wallet records] count] > [[_wallet records] count]) {
        [recordIndex release]; recordIndex = [[wallet createdIdentifier] retain]; [_search setStringValue:@""];
    }
    if (recordIndex && [wallet recordWithIdentifier:recordIndex]) {
        [key release]; key = [[[wallet recordWithIdentifier:recordIndex] objectForKey:@"account"] retain];
        NSDictionary *account = [wallet accountWithKey:key]; int type = [[account objectForKey:@"type"] intValue]; BOOL savings = type == 3 || type == 7;
        if (([_group indexOfSelectedItem] == 1 && savings) || ([_group indexOfSelectedItem] == 2 && !savings)) [_group selectItemAtIndex:0];
    }
    [wallet retain]; [_wallet release]; _wallet = wallet; _dirty = HBModelDirty(wallet, _savedWallet);
    [self filterAccountsSelectingKey:key]; unsigned int i;
    [key release];
    if (recordIndex) for (i = 0; i < [_visibleRecords count]; i++) if ([[[_visibleRecords objectAtIndex:i] objectForKey:@"__index"] isEqual:recordIndex]) {
        unsigned int page = i / HB_PAGE_SIZE;
        if (_page != page) { _page = page; [self refreshRecords]; }
        [_recordsTable selectRow:i % HB_PAGE_SIZE byExtendingSelection:NO]; [_recordsTable scrollRowToVisible:i % HB_PAGE_SIZE]; break;
    }
    [recordIndex release]; [self updateDocumentState]; if (_calendar) [_calendar setWallet:_wallet];
    if (_dirty) [self queueLocalSave];
}
- (void)edit:(NSDictionary *)record {
    if (_driveBusy || !_wallet || ![self selectedAccount] || [NSApp modalWindow]) return;
    HBWallet *original = [_wallet retain]; HBOperationEditor *editor = [[HBOperationEditor alloc] initWithWallet:_wallet record:record account:[self selectedAccount]];
    HBWallet *result = [editor run];
    if (result && _wallet == original) [self applyWallet:result];
    [editor release]; [original release];
}
- (void)newRecord:(id)sender { [self edit:nil]; }
- (void)editRecord:(id)sender { NSDictionary *record = [self selectedRecord]; if (record) [self edit:record]; }
- (void)changeStatus:(NSString *)status {
    NSString *error = nil; NSDictionary *record = [self selectedRecord]; if (_driveBusy || !record || [NSApp modalWindow]) return;
    HBWallet *result = [_wallet walletByChangingStatus:status record:record error:&error];
    if (result) [self applyWallet:result]; else NSRunAlertPanel(@"Modification refusee", @"%@", @"OK", nil, nil, error);
}
- (void)pointRecord:(id)sender { [self changeStatus:[[[self selectedRecord] objectForKey:@"st"] intValue] == 1 ? @"0" : @"1"]; }
- (void)reconcileRecord:(id)sender { [self changeStatus:[[[self selectedRecord] objectForKey:@"st"] intValue] == 2 ? @"0" : @"2"]; }
- (void)deleteRecord:(id)sender {
    NSDictionary *record = [self selectedRecord]; if (_driveBusy || !record || [NSApp modalWindow]) return;
    if (NSRunAlertPanel(@"Supprimer l'operation ?", HBIsTransfer(record) ? @"Les deux mouvements du virement seront supprimes." : @"La suppression sera appliquee au fichier lors de l'enregistrement.", @"Annuler", @"Supprimer", nil) != NSAlertAlternateReturn) return;
    NSString *error = nil; HBWallet *result = [_wallet walletByDeletingRecord:record error:&error];
    if (result) [self applyWallet:result]; else NSRunAlertPanel(@"Suppression refusee", @"%@", @"OK", nil, nil, error);
}
- (BOOL)save {
    if (!_wallet || !_path || _driveBusy) return NO;
    [_saveTimer invalidate]; [_saveTimer release]; _saveTimer = nil;
    if (_saveBusy || !_dirty) { [self updateDocumentState]; return YES; }
    [_saveError release]; _saveError = nil; _saveBusy = YES;
    NSMutableDictionary *context = [NSMutableDictionary dictionaryWithObjectsAndKeys:_wallet, @"wallet", _path, @"path", nil];
    if (!_journalState) _journalState = [[NSDictionary dictionaryWithObjectsAndKeys:@"0", @"count", @"0", @"length", nil] retain];
    if (!_savedHash) _savedHash = [HBDriveSHA256([_wallet baseSourceData]) copy];
    [context setObject:_journalState forKey:@"journalState"]; [context setObject:_savedHash forKey:@"baseHash"];
    [self updateDocumentState]; [self launchLocalSave:context]; return YES;
}
- (void)queueLocalSave {
    if (_saveBusy || _driveBusy) return;
    [_saveTimer invalidate]; [_saveTimer release];
    [_saveError release]; _saveError = nil;
    _saveTimer = [[NSTimer scheduledTimerWithTimeInterval:0.35 target:self selector:@selector(saveFile:) userInfo:nil repeats:NO] retain];
    [self updateDocumentState];
}
- (void)saveFile:(id)sender { if (!_driveBusy && (_dirty || _saveTimer)) [self save]; }
- (void)launchLocalSave:(NSDictionary *)context {
    [NSThread detachNewThreadSelector:@selector(localSaveWorker:) toTarget:self withObject:context];
}
- (void)localSaveWorker:(NSDictionary *)context {
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    NSMutableDictionary *result = [NSMutableDictionary dictionaryWithDictionary:context];
    @try { [result addEntriesFromDictionary:HBLocalSaveResult(context)]; }
    @catch (NSException *exception) { [result setObject:@"Erreur interne pendant la sauvegarde locale. Copie en memoire conservee." forKey:@"error"]; }
    [self performSelectorOnMainThread:@selector(localSaveFinished:) withObject:result waitUntilDone:NO]; [pool release];
}
- (void)localSaveFinished:(NSDictionary *)result {
    _saveBusy = NO;
    if (![[result objectForKey:@"path"] isEqualToString:_path]) { _syncRequested = NO; return; }
    [_saveError release]; _saveError = [[result objectForKey:@"error"] copy];
    if ([[result objectForKey:@"saved"] boolValue]) {
        [_savedWallet release]; _savedWallet = [[result objectForKey:@"wallet"] retain];
        [_journalState release]; _journalState = [[result objectForKey:@"journalState"] copy];
    } else { _syncRequested = NO; _checkpointRequested = NO; }
    _dirty = HBModelDirty(_wallet, _savedWallet); [self updateDocumentState];
    // Only one writer runs at a time; later edits use the successful snapshot as their baseline.
    if (!_saveError && _dirty) [self save];
    else if (_checkpointRequested) [self consolidateXML:nil];
    else if (_syncRequested) [self resumeSync:nil];
}
- (void)exportFile:(id)sender {
    if (!_wallet || _driveBusy || _saveBusy || _saveTimer || _syncRequested || [NSApp modalWindow]) return;
    NSSavePanel *panel = [NSSavePanel savePanel]; [panel setRequiredFileType:@"xhb"];
    if ([panel runModalForDirectory:nil file:[NSString stringWithFormat:@"%@-copie.xhb", [[_path lastPathComponent] stringByDeletingPathExtension]]] != NSOKButton) return;
    NSString *path = [panel filename]; BOOL exists = [[NSFileManager defaultManager] fileExistsAtPath:path];
    if ([[path stringByStandardizingPath] isEqualToString:[_path stringByStandardizingPath]]) { [self consolidateXML:nil]; return; }
    if (exists) {
        if (NSRunAlertPanel(@"Remplacer ce fichier ?", @"Une sauvegarde de sa version actuelle sera conservee.", @"Annuler", @"Remplacer", nil) != NSAlertAlternateReturn) return;
    }
    _driveBusy = YES; [_statusLabel setStringValue:@"Export XML en arriere-plan..."]; [self updateButtons];
    NSDictionary *context = [NSDictionary dictionaryWithObjectsAndKeys:@"export", @"action", _wallet, @"wallet", path, @"cachePath", [NSNumber numberWithBool:exists], @"replace", nil];
    [NSThread detachNewThreadSelector:@selector(driveWorker:) toTarget:self withObject:context];
}
- (void)consolidateXML:(id)sender {
    if (!_wallet || _driveBusy || _syncRequested || [NSApp modalWindow]) return;
    if (_dirty || _saveBusy || _saveTimer) { _checkpointRequested = YES; [self save]; return; }
    _checkpointRequested = NO; _driveBusy = YES; [_statusLabel setStringValue:@"Consolidation XML en arriere-plan..."]; [self updateButtons];
    NSDictionary *context = [NSDictionary dictionaryWithObjectsAndKeys:@"checkpoint", @"action", _wallet, @"localWallet", _path, @"cachePath", nil];
    [NSThread detachNewThreadSelector:@selector(driveWorker:) toTarget:self withObject:context];
}
- (void)adoptCheckpoint:(HBWallet *)wallet {
    [wallet retain]; [_wallet release]; _wallet = wallet;
    [_savedWallet release]; _savedWallet = [wallet retain]; [_savedData release]; _savedData = [[wallet baseSourceData] copy];
    [_savedHash release]; _savedHash = [HBDriveSHA256(_savedData) copy];
    [_journalState release]; _journalState = [[NSDictionary dictionaryWithObjectsAndKeys:@"0", @"count", @"0", @"length", nil] retain];
    _dirty = NO; [_saveError release]; _saveError = nil;
    if (_calendar) [_calendar setWallet:wallet]; [_ownerLabel setStringValue:[wallet owner]]; [self filterAccounts:nil]; [self updateDocumentState];
}
- (void)repairHomeBank:(id)sender {
    if (!_wallet || _driveBusy || [NSApp modalWindow]) return;
    if (NSRunAlertPanel(@"Reparer le format XML ?", @"Les comptes, montants et operations ne seront pas changes. La demande sera conservee dans le journal. Consolider le XML ou Synchroniser pour produire le fichier compatible.", @"Annuler", @"Reparer", nil) != NSAlertAlternateReturn) return;
    NSString *error = nil; HBWallet *compatible = [_wallet commitRecords:[NSArray array] deleting:[NSArray array] payee:nil command:[_wallet command:@"normalize" record:nil values:nil] error:&error];
    if (compatible) [self applyWallet:compatible]; else NSRunAlertPanel(@"Reparation refusee", @"%@", @"OK", nil, nil, error);
}
- (BOOL)mayDiscard {
    if (_saveBusy || _saveTimer || _syncRequested || _checkpointRequested) {
        [_statusLabel setStringValue:@"Attendre la fin de la sauvegarde locale avant de fermer ou changer de fichier."]; return NO;
    }
    if (!_dirty) return YES;
    int answer = NSRunAlertPanel(@"Modifications non enregistrees", @"Enregistrer les modifications avant de continuer ?", @"Enregistrer", @"Annuler", @"Abandonner");
    if (answer == NSAlertDefaultReturn) { [self save]; return NO; }
    if (answer == NSAlertOtherReturn) {
        HBWallet *saved = [[_savedWallet retain] autorelease];
        if (saved) [self applyWallet:saved];
        return saved != nil;
    }
    return NO;
}
- (void)showCalendar:(id)sender {
    if (!_wallet || [NSApp modalWindow]) return;
    if (!_calendar) _calendar = [[HBCalendarWindow alloc] initWithWallet:_wallet account:[[self selectedAccount] objectForKey:@"key"]];
    [_calendar show];
}
- (BOOL)validateMenuItem:(NSMenuItem *)item {
    if ([NSApp modalWindow]) return NO;
    SEL action = [item action];
    if (_driveBusy && action != @selector(showCalendar:)) return NO;
    if ((_saveBusy || _saveTimer || _syncRequested) && (action == @selector(openFile:) || action == @selector(reloadFile:) ||
        action == @selector(openDrive:) || action == @selector(reloadDrive:) || action == @selector(configureDrive:) ||
        action == @selector(disconnectDrive:) || action == @selector(forgetDrive:) || action == @selector(exportFile:))) return NO;
    if (action == @selector(syncDrive:) || action == @selector(reloadDrive:) || action == @selector(disconnectDrive:)) return _driveActive;
    if (action == @selector(forgetDrive:)) return _driveSettings != nil;
    if (action == @selector(saveFile:)) return _dirty && !_saveBusy;
    if (action == @selector(consolidateXML:)) return _wallet != nil && !_checkpointRequested && !_syncRequested;
    if (action == @selector(exportFile:) || action == @selector(showCalendar:) || action == @selector(repairHomeBank:)) return _wallet != nil;
    if (action == @selector(newRecord:)) return [self selectedAccount] != nil;
    return YES;
}
- (void)previousPage:(id)sender { if (_page) { _page--; [self refreshRecords]; } }
- (void)nextPage:(id)sender { if ((_page + 1) * HB_PAGE_SIZE < [_visibleRecords count]) { _page++; [self refreshRecords]; } }
- (HBRow)numberOfRowsInTableView:(NSTableView *)table {
    if (table == _accountsTable) return [_visibleAccounts count];
    unsigned int remaining = [_visibleRecords count] - _page * HB_PAGE_SIZE;
    return remaining > HB_PAGE_SIZE ? HB_PAGE_SIZE : remaining;
}
- (id)tableView:(NSTableView *)table objectValueForTableColumn:(NSTableColumn *)column row:(HBRow)row {
    NSString *key = [column identifier];
    if (table == _accountsTable) {
        NSDictionary *account = [_visibleAccounts objectAtIndex:row];
        if ([key isEqualToString:@"name"]) return [account objectForKey:@"name"];
        return [_wallet formatAmount:[[_wallet balancesForAccount:account] objectForKey:@"reconciled"] account:account];
    }
    NSDictionary *record = [_visibleRecords objectAtIndex:_page * HB_PAGE_SIZE + row];
    if ([key isEqualToString:@"date"]) return [HBDateFromOrdinal([[record objectForKey:@"date"] intValue]) descriptionWithCalendarFormat:@"%d/%m/%Y"];
    if ([key isEqualToString:@"payee"]) {
        NSString *payee = [_wallet payeeForRecord:record], *memo = [record objectForKey:@"wording"];
        return [memo length] && ![payee isEqualToString:memo] ? [NSString stringWithFormat:@"%@ - %@", payee, memo] : payee;
    }
    if ([key isEqualToString:@"category"]) return [_wallet categoryForRecord:record];
    if ([key isEqualToString:@"memo"]) return [record objectForKey:@"wording"];
    if ([key isEqualToString:@"amount"]) return [_wallet formatAmount:[record objectForKey:@"amount"] account:[self selectedAccount]];
    int status = [[record objectForKey:@"st"] intValue];
    return status == 2 ? @"Rapproche" : status == 1 ? @"Pointe" : status == 3 ? @"Annule" : @"";
}
- (void)tableView:(NSTableView *)table willDisplayCell:(id)cell forTableColumn:(NSTableColumn *)column row:(HBRow)row {
    NSColor *color = [NSColor controlTextColor];
    if (table == _accountsTable && [[column identifier] isEqualToString:@"balance"]) {
        NSDictionary *account = [_visibleAccounts objectAtIndex:row];
        color = HBBalanceColor([[_wallet balancesForAccount:account] objectForKey:@"reconciled"], account);
    } else if (table == _recordsTable) {
        NSDictionary *record = [_visibleRecords objectAtIndex:_page * HB_PAGE_SIZE + row];
        if ([[record objectForKey:@"st"] intValue] == 3 || [HBDateFromOrdinal([[record objectForKey:@"date"] intValue]) compare:HBToday()] == NSOrderedDescending)
            color = [[NSColor controlTextColor] blendedColorWithFraction:0.35 ofColor:[NSColor controlBackgroundColor]];
    }
    if (row == [table selectedRow]) color = [NSColor selectedControlTextColor];
    if ([cell respondsToSelector:@selector(setTextColor:)]) [cell setTextColor:color];
}
- (void)showRecord:(id)sender {
    HBRow row = [_recordsTable clickedRow];
    if (row < 0 || (unsigned long)row >= (unsigned long)[self numberOfRowsInTableView:_recordsTable]) return;
    NSDictionary *record = [_visibleRecords objectAtIndex:_page * HB_PAGE_SIZE + row];
    NSRunAlertPanel(@"Operation", @"Date : %@\nTiers : %@\nCategorie : %@\nMemo : %@\nNumero de paiement : %@\nMontant : %@",
        @"OK", nil, nil, [HBDateFromOrdinal([[record objectForKey:@"date"] intValue]) descriptionWithCalendarFormat:@"%d/%m/%Y"],
        [_wallet payeeForRecord:record], [_wallet categoryForRecord:record], [record objectForKey:@"wording"] ? [record objectForKey:@"wording"] : @"",
        [record objectForKey:@"info"] ? [record objectForKey:@"info"] : @"", [_wallet formatAmount:[record objectForKey:@"amount"] account:[self selectedAccount]]);
}
- (BOOL)drivePending {
    if (!_driveActive || ![_path isEqualToString:_driveCachePath] || !_wallet) return NO;
    if ([_wallet generation] || _dirty || ![_driveState objectForKey:@"syncedSHA256"]) return YES;
    if (!_savedHash) _savedHash = [HBDriveSHA256([_wallet baseSourceData]) copy];
    return ![_savedHash isEqual:[_driveState objectForKey:@"syncedSHA256"]];
}
- (void)updateDriveStatus {
    if (!_driveActive || _driveBusy) return;
    [_driveLabel setStringValue:_syncRequested ? @"Drive : attente de sauvegarde locale" :
        [self drivePending] ? @"Drive : modifications a synchroniser" : @"Drive : copie locale a jour"];
}
- (void)configureDrive:(id)sender {
    if (_driveBusy || [NSApp modalWindow] || ![self mayDiscard]) return;
    HBDrivePanel *panel = [[HBDrivePanel alloc] initWithSettings:_driveSettings]; NSDictionary *settings = [[panel run] retain]; [panel release];
    if (!settings) return;
    [self disconnectDrive:nil]; [_driveSettings release]; _driveSettings = [settings copy]; [_drive release];
    _drive = [[HBDriveClient alloc] initWithSettings:settings transport:nil credentials:nil];
    [[NSUserDefaults standardUserDefaults] setObject:settings forKey:@"HBPantherDrive"]; [[NSUserDefaults standardUserDefaults] synchronize]; [settings release];
    [_driveLabel setStringValue:@"Drive : configure, non ouvert"];
}
- (BOOL)prepareDriveCache {
    NSString *error = nil;
    if (!HBDriveValidSettings(_driveSettings, &error)) { NSRunAlertPanel(@"Drive non configure", @"%@", @"OK", nil, nil, error); return NO; }
    NSString *directory = HBDriveDirectory(&error); if (!directory) { NSRunAlertPanel(@"Cache Drive indisponible", @"%@", @"OK", nil, nil, error); return NO; }
    [_driveCachePath release]; _driveCachePath = [[directory stringByAppendingPathComponent:[NSString stringWithFormat:@"Drive-%@.xhb", [_driveSettings objectForKey:@"fileID"]]] copy];
    [_driveState release]; _driveState = [HBDriveReadState([_driveCachePath stringByAppendingString:@".drive-state.plist"]) retain];
    NSString *etag = [_driveState objectForKey:@"etag"], *hash = [_driveState objectForKey:@"syncedSHA256"];
    if (![[_driveState objectForKey:@"fileID"] isEqual:[_driveSettings objectForKey:@"fileID"]] || ![etag isKindOfClass:[NSString class]] ||
        ![etag hasPrefix:@"\""] || ![etag hasSuffix:@"\""] || [etag length] > 512 || [etag length] < 3 ||
        [etag rangeOfCharacterFromSet:[NSCharacterSet controlCharacterSet]].location != NSNotFound || ![hash isKindOfClass:[NSString class]] || [hash length] != 64) {
        [_driveState release]; _driveState = nil;
    }
    return YES;
}
- (void)openDrive:(id)sender {
    if (_driveBusy || _saveBusy || _saveTimer || _syncRequested || [NSApp modalWindow]) return;
    if (!_driveSettings) { [self configureDrive:nil]; if (!_driveSettings) return; }
    if (_driveActive) { [self updateDriveStatus]; return; }
    if (![self mayDiscard] || ![self prepareDriveCache]) return;
    BOOL exists = [[NSFileManager defaultManager] fileExistsAtPath:_driveCachePath];
    if (exists && ![self openPath:_driveCachePath]) return;
    _driveActive = YES; [self updateButtons];
    [[NSUserDefaults standardUserDefaults] setBool:YES forKey:@"HBPantherDriveRestore"]; [[NSUserDefaults standardUserDefaults] synchronize];
    if (exists && !_driveState) {
        [_driveLabel setStringValue:@"Drive : copie locale sans reference"];
        NSRunAlertPanel(@"Reference Drive absente", @"La copie locale est conservee. Exporter une copie avant de recharger depuis Drive. Aucun envoi automatique n'est autorise.", @"OK", nil, nil); return;
    }
    [self updateDocumentState];
    if (!exists) [self startDriveAction:@"download" manual:YES];
}
- (void)restoreDrive:(id)sender {
    if (_wallet || !_drive || ![[NSUserDefaults standardUserDefaults] boolForKey:@"HBPantherDriveRestore"] || _driveBusy || [NSApp modalWindow]) return;
    if (![self prepareDriveCache]) return;
    BOOL exists = [[NSFileManager defaultManager] fileExistsAtPath:_driveCachePath];
    if (exists && ![self openPath:_driveCachePath]) return;
    _driveActive = YES; [self updateButtons];
    if (exists && !_driveState) { [_driveLabel setStringValue:@"Drive : reference locale a verifier"]; return; }
    [self updateDocumentState];
    if (!exists) [_driveLabel setStringValue:@"Drive : cliquer sur Synchroniser pour charger"];
}
- (void)disconnectDrive:(id)sender {
    if (_driveBusy || _saveBusy || _saveTimer || _syncRequested) return;
    _driveActive = NO;
    [[NSUserDefaults standardUserDefaults] setBool:NO forKey:@"HBPantherDriveRestore"]; [[NSUserDefaults standardUserDefaults] synchronize];
    [_driveLabel setStringValue:@"Drive : synchronisation desactivee"]; [self updateButtons];
}
- (void)forgetDrive:(id)sender {
    if (_driveBusy || _saveBusy || _saveTimer || _syncRequested || [NSApp modalWindow] || !_driveSettings) return;
    if (NSRunAlertPanel(@"Oublier Drive ?", @"La cle sera retiree du trousseau. Les copies locales et sauvegardes seront conservees. Le partage Google devra etre retire separement.", @"Annuler", @"Oublier", nil) != NSAlertAlternateReturn) return;
    NSString *error = nil;
    if (!HBDriveDeleteKey([_driveSettings objectForKey:@"keyAlias"], &error)) { NSRunAlertPanel(@"Cle conservee", @"%@", @"OK", nil, nil, error); return; }
    [self disconnectDrive:nil]; [_driveSettings release]; _driveSettings = nil; [_drive release]; _drive = nil;
    [[NSUserDefaults standardUserDefaults] removeObjectForKey:@"HBPantherDrive"]; [[NSUserDefaults standardUserDefaults] synchronize];
    [_driveLabel setStringValue:@"Drive : non configure"];
}
- (void)syncDrive:(id)sender {
    if (!_driveActive || _driveBusy || _syncRequested || _checkpointRequested || [NSApp modalWindow]) return;
    if (![_path isEqualToString:_driveCachePath] && ![self mayDiscard]) return;
    _syncRequested = YES;
    if (_dirty || _saveBusy || _saveTimer) { [self save]; [self updateDocumentState]; return; }
    [self resumeSync:nil];
}
- (void)resumeSync:(id)sender {
    if (!_syncRequested || _saveBusy || _saveTimer || _dirty || _driveBusy) return;
    if ([NSApp modalWindow]) { [self performSelector:@selector(resumeSync:) withObject:nil afterDelay:0.3]; return; }
    _syncRequested = NO;
    if ([self drivePending] && !_driveState) { [self reloadDrive:nil]; return; }
    [self startDriveAction:[self drivePending] ? @"upload" : @"download" manual:YES];
}
- (void)reloadDrive:(id)sender {
    if (!_driveActive || _driveBusy || _saveBusy || _saveTimer || _syncRequested || [NSApp modalWindow]) return;
    if (![_path isEqualToString:_driveCachePath] && ![self mayDiscard]) return;
    if (_dirty) { [self save]; return; }
    if ([self drivePending]) {
        int answer = NSRunAlertPanel(@"Remplacer la copie locale ?", @"Des modifications ne sont pas synchronisees. Exporter une copie pour les fusionner manuellement. La version locale actuelle sera aussi sauvegardee avant remplacement.", @"Annuler", @"Charger Drive", @"Exporter une copie");
        if (answer == NSAlertOtherReturn) [self exportFile:nil];
        if (answer != NSAlertAlternateReturn) return;
    }
    [self startDriveAction:@"download" manual:YES];
}
- (void)startDriveAction:(NSString *)action manual:(BOOL)manual {
    if (_driveBusy || _saveBusy || _saveTimer || _dirty || !_drive || !_driveActive || [NSApp modalWindow]) return;
    if ([action isEqualToString:@"upload"] && (!_driveState || ![_path isEqualToString:_driveCachePath])) { [_driveLabel setStringValue:@"Drive : reference distante absente"]; return; }
    _driveBusy = YES; _driveLoading = [action isEqualToString:@"download"]; _driveManual = manual;
    [_driveLabel setStringValue:_driveLoading ? @"Drive : chargement..." : @"Drive : sauvegarde..."]; [self updateButtons];
    NSMutableDictionary *context = [NSMutableDictionary dictionaryWithObjectsAndKeys:action, @"action", _drive, @"client", nil];
    [context setObject:_driveCachePath forKey:@"cachePath"]; [context setObject:[_driveSettings objectForKey:@"fileID"] forKey:@"fileID"];
    if ([_path isEqualToString:_driveCachePath] && _wallet) [context setObject:_wallet forKey:@"localWallet"];
    if (!_driveLoading) { [context setObject:_wallet forKey:@"wallet"]; [context setObject:[_driveState objectForKey:@"etag"] forKey:@"etag"]; }
    else if ([_path isEqualToString:_driveCachePath] && _savedData) [context setObject:_savedData forKey:@"expectedCacheData"];
    [NSThread detachNewThreadSelector:@selector(driveWorker:) toTarget:self withObject:context];
}
- (void)driveWorker:(NSDictionary *)context {
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init]; NSMutableDictionary *result = [NSMutableDictionary dictionaryWithDictionary:context];
    HBDriveClient *client = [context objectForKey:@"client"];
    @try {
        [result addEntriesFromDictionary:HBDriveRequestResult(context)];
    } @catch (NSException *exception) { [result setObject:HBDriveExceptionMessage(exception) forKey:@"error"]; }
    [result setObject:[NSNumber numberWithBool:[client retryable]] forKey:@"retryable"];
    [result setObject:[NSNumber numberWithBool:[client fileUnavailable]] forKey:@"fileUnavailable"];
    [self performSelectorOnMainThread:@selector(driveFinished:) withObject:result waitUntilDone:NO]; [pool release];
}
- (void)driveFinished:(NSDictionary *)result {
    BOOL downloading = [[result objectForKey:@"action"] isEqualToString:@"download"], manual = _driveManual;
    _driveBusy = NO; _driveLoading = NO;
    NSString *action = [result objectForKey:@"action"], *failure = [result objectForKey:@"error"];
    if ([result objectForKey:@"checkpointWallet"]) [self adoptCheckpoint:[result objectForKey:@"checkpointWallet"]];
    if ([action isEqualToString:@"checkpoint"] || [action isEqualToString:@"export"]) {
        [self updateButtons];
        if (failure) { [_statusLabel setStringValue:@"Export XML echoue. Journal local conserve."]; NSRunAlertPanel(@"Fichier XML non genere", @"%@", @"OK", nil, nil, failure); }
        else [_statusLabel setStringValue:[action isEqualToString:@"export"] ? @"Copie XML exportee" : @"XML consolide et journal confirme"];
        return;
    }
    NSDictionary *response = [result objectForKey:@"response"], *metadata = downloading ? [response objectForKey:@"metadata"] : response;
    NSString *error = [result objectForKey:@"error"];
    HBWallet *wallet = [result objectForKey:@"confirmedWallet"];
    if (response) {
        [_driveState release]; _driveState = [[result objectForKey:@"state"] copy];
    }
    if (response && downloading) {
        [_path release]; _path = [_driveCachePath copy];
        [_search setStringValue:@""]; [self adoptCheckpoint:wallet];
    }
    if (response) {
        [_driveLabel setStringValue:@"Drive : synchronise"]; [_driveLabel setToolTip:[metadata objectForKey:@"title"]];
    } else {
        [_driveLabel setStringValue:@"Drive : non synchronise"]; [_driveLabel setToolTip:error];
        if (manual) {
            if ([[result objectForKey:@"fileUnavailable"] boolValue]) {
                if (NSRunAlertPanel(@"Fichier Drive introuvable", @"%@", @"Fermer", @"Configurer un autre fichier", nil, error) == NSAlertAlternateReturn) [self configureDrive:nil];
            } else NSRunAlertPanel(@"Drive non synchronise", @"%@", @"OK", nil, nil, error);
        }
    }
    [self updateButtons];
}
- (void)dealloc {
    [_window release]; [_wallet release]; [_path release]; [_visibleAccounts release]; [_visibleRecords release];
    [_saveTimer invalidate]; [_saveTimer release]; [_saveError release]; [_drive release]; [_driveSettings release]; [_driveState release]; [_driveCachePath release];
    [_balanceTitles release]; [_balanceLabels release]; [_savedData release]; [_savedHash release]; [_savedWallet release]; [_journalState release]; [_calendar release]; [super dealloc];
}
@end
