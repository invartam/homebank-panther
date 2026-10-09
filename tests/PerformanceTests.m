#import "HBWallet.h"
#import "HBJournal.h"
#import "HBDrive.h"
#include <stdio.h>
#include <stdlib.h>
#include <sys/time.h>

static double milliseconds(void) {
    struct timeval time; gettimeofday(&time, NULL);
    return time.tv_sec * 1000.0 + time.tv_usec / 1000.0;
}

int main(void) {
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    unsigned long count = 3000, i;
    const char *setting = getenv("HB_BENCH_RECORDS");
    if (setting) { char *end; count = strtoul(setting, &end, 10); if (*end || count < 1 || count > 30000) return 1; }
    NSMutableString *xml = [NSMutableString stringWithString:@"<homebank v=\"1.6\"><account key=\"1\" name=\"Fictive benchmark\"/>\n"];
    for (i = 0; i < count; i++) [xml appendFormat:@"<ope account=\"1\" date=\"%lu\" amount=\"-1.25\" st=\"0\" wording=\"Fictive operation %lu\"/>\n", 739891UL + i % 365, i];
    [xml appendString:@"</homebank>"];
    NSData *bytes = [xml dataUsingEncoding:NSUTF8StringEncoding]; NSString *error = nil;
    double start = milliseconds(); HBWallet *wallet = [[[HBWallet alloc] initWithData:bytes error:&error] autorelease];
    double parse = milliseconds() - start;
    if (!wallet) { fprintf(stderr, "Fictive parse failed\n"); return 1; }
    start = milliseconds(); HBWallet *edited = [wallet walletByChangingStatus:@"2" record:[[wallet records] objectAtIndex:count / 2] error:&error];
    double edit = milliseconds() - start;
    if (!edited) { fprintf(stderr, "Fictive mutation failed\n"); return 1; }
    char directory[] = "/tmp/homebank-performance-XXXXXX";
    if (!mkdtemp(directory)) return 1;
    NSString *folder = [NSString stringWithUTF8String:directory], *path = [folder stringByAppendingPathComponent:@"fictive.xhb"];
    if (!HBWriteWallet(wallet, path, nil, &error)) return 1;
    NSString *journalPath = [path stringByAppendingString:@".panther-journal"], *hash = HBDriveSHA256([wallet baseSourceData]);
    NSDictionary *empty = HBJournalRead(journalPath, hash, &error);
    start = milliseconds(); NSDictionary *journal = HBJournalAppend(journalPath, hash, [edited journalCommands], empty, &error);
    double journalTime = milliseconds() - start;
    start = milliseconds(); BOOL saved = HBWriteWallet(edited, path, [wallet sourceData], &error);
    double save = milliseconds() - start;
    start = milliseconds();
    for (i = 0; i < count; i++) {
        NSAutoreleasePool *iteration = [[NSAutoreleasePool alloc] init];
        [wallet formatAmount:[[[wallet records] objectAtIndex:i] objectForKey:@"amount"] account:[[wallet accounts] objectAtIndex:0]];
        [iteration release];
    }
    double format = milliseconds() - start;
    start = milliseconds(); NSArray *list = [[wallet recordsForAccount:[[wallet accounts] objectAtIndex:0]] copy];
    double unfiltered = milliseconds() - start; [list release];
    printf("Fictive benchmark: %lu operations, %lu XML bytes\n", count, (unsigned long)[bytes length]);
    printf("Import/model: %.1f ms\nMutation/status (no XML): %.3f ms\nDurable journal append: %.3f ms (%s bytes)\nExplicit XML replacement: %.1f ms\nFormat every operation: %.1f ms\nUnfiltered list snapshot: %.3f ms\n", parse, edit, journalTime, [[journal objectForKey:@"length"] UTF8String], save, format, unfiltered);
    BOOL valid = journal && saved && [[[HBWallet walletAtPath:path error:NULL] sourceData] isEqualToData:[edited sourceData]];
    [[NSFileManager defaultManager] removeFileAtPath:folder handler:nil];
    [pool release]; return valid ? 0 : 1;
}
