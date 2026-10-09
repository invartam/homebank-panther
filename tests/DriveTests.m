#import "HBDrive.h"
#import "PantherString.h"
#include <wolfssl/options.h>
#include <wolfssl/wolfcrypt/coding.h>
#include <sys/stat.h>
#include <unistd.h>
#include <stdio.h>

static int failures = 0, checks = 0;
static void check(BOOL ok, const char *message) { checks++; if (!ok) { failures++; fprintf(stderr, "FAIL: %s\n", message); } }
static NSData *utf8(NSString *text) { return [text dataUsingEncoding:NSUTF8StringEncoding]; }
static NSDictionary *response(int status, NSData *data) { return [NSDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithInt:status], @"status", data, @"data", nil]; }
static NSDictionary *decode(NSString *encoded) {
    NSMutableString *text = [[encoded mutableCopy] autorelease];
    [text replaceOccurrencesOfString:@"-" withString:@"+" options:0 range:NSMakeRange(0, [text length])];
    [text replaceOccurrencesOfString:@"_" withString:@"/" options:0 range:NSMakeRange(0, [text length])];
    while ([text length] % 4) [text appendString:@"="];
    unsigned char output[8192]; word32 size = sizeof(output);
    if (Base64_Decode((const unsigned char *)[text UTF8String], (word32)[text length], output, &size) != 0) return nil;
    return HBDriveParseJSON([NSData dataWithBytes:output length:size], NULL);
}

@interface HBMockDrive : NSObject <HBDriveTransport> {
@public
    NSData *remote;
    NSString *etag;
    NSString *revision;
    int puts, tokens, failureStatus, mediaFailureStatus;
    BOOL race, lostResponse, changedDuringRead, malformed, badToken, conditional, authorization;
    BOOL mediaRevisionGuard, missingRevision, changedRevisionDuringRead;
}
- (id)initWithData:(NSData *)data;
@end
@implementation HBMockDrive
- (id)initWithData:(NSData *)data { self = [super init]; if (self) { remote = [data copy]; etag = [@"\"v1\"" copy]; revision = [@"revision-1" copy]; conditional = YES; authorization = YES; mediaRevisionGuard = YES; } return self; }
- (NSData *)metadata {
    return utf8([NSString stringWithFormat:@"{\"id\":\"test-file\",\"title\":\"Test.xhb\",\"mimeType\":\"application/x-homebank+xml\",\"fileSize\":\"%lu\",\"etag\":\"\\\"%@\\\"\",%@\"editable\":true,\"labels\":{\"trashed\":false}}", (unsigned long)[remote length], [etag substringWithRange:NSMakeRange(1, [etag length] - 2)], missingRevision ? @"" : [NSString stringWithFormat:@"\"headRevisionId\":\"%@\",", revision]]);
}
- (NSDictionary *)requestURL:(NSString *)url method:(NSString *)method headers:(NSDictionary *)headers body:(NSData *)body error:(NSString **)error {
    if ([url isEqualToString:@"https://oauth2.googleapis.com/token"]) {
        tokens++; return response(200, utf8(badToken ? @"{\"access_token\":\"test-token\",\"token_type\":\"Bearer\",\"expires_in\":-1}" : @"{\"access_token\":\"test-token\",\"token_type\":\"Bearer\",\"expires_in\":3600}"));
    }
    authorization = authorization && [[headers objectForKey:@"Authorization"] isEqual:@"Bearer test-token"];
    if (failureStatus) { int status = failureStatus; failureStatus = 0; return response(status, utf8(@"{}")); }
    if ([method isEqualToString:@"PUT"]) {
        puts++; conditional = conditional && [[headers objectForKey:@"If-Match"] isEqual:@"\"v1\""] && [url rangeOfString:@"newRevision=true"].location != NSNotFound;
        if (race) { [etag release]; etag = [@"\"external\"" copy]; return response(412, utf8(@"{}")); }
        if (![[headers objectForKey:@"If-Match"] isEqual:etag]) return response(412, utf8(@"{}"));
        [remote release]; remote = [body copy]; [etag release]; etag = [@"\"v2\"" copy];
        [revision release]; revision = [@"revision-2" copy];
        if (lostResponse) { lostResponse = NO; if (error) *error = @"Reponse perdue (test fictif)."; return nil; }
        return response(200, [self metadata]);
    }
    if ([url rangeOfString:@"alt=media"].location != NSNotFound) {
        /* Metadata and media validators are deliberately different. */
        if ([headers objectForKey:@"If-Match"]) { mediaRevisionGuard = NO; return response(412, utf8(@"{}")); }
        NSString *encoded = [revision isEqual:@"rev+1/2"] ? @"rev%2B1%2F2" : revision;
        mediaRevisionGuard = mediaRevisionGuard && [url rangeOfString:[@"revisionId=" stringByAppendingString:encoded]].location != NSNotFound;
        if (!mediaRevisionGuard) return response(400, utf8(@"{}"));
        if (mediaFailureStatus) return response(mediaFailureStatus, utf8(@"{}"));
        NSData *snapshot = [[remote retain] autorelease];
        if (changedDuringRead) { [etag release]; etag = [@"\"external\"" copy]; }
        if (changedRevisionDuringRead) { [revision release]; revision = [@"revision-new" copy]; }
        return response(200, snapshot);
    }
    return response(200, malformed ? utf8(@"{\"labels\":null}") : [self metadata]);
}
- (void)dealloc { [remote release]; [etag release]; [revision release]; [super dealloc]; }
@end

static HBDriveClient *client(HBMockDrive *mock, NSDictionary *credentials) {
    NSDictionary *settings = [NSDictionary dictionaryWithObject:@"test-file" forKey:@"fileID"];
    return [[[HBDriveClient alloc] initWithSettings:settings transport:mock credentials:credentials] autorelease];
}
static HBMockDrive *mock(NSData *data) { return [[[HBMockDrive alloc] initWithData:data] autorelease]; }

@interface HBDriveClient (LegacyTestSurface)
- (NSDictionary *)metadataFromData:(NSData *)data error:(NSString **)error;
@end
@interface HBLegacyDriveClient : HBDriveClient
@end
@implementation HBLegacyDriveClient
- (NSDictionary *)metadataFromData:(NSData *)data error:(NSString **)error {
    NSDictionary *parsed = [super metadataFromData:data error:error]; if (!parsed) return nil;
    NSMutableDictionary *metadata = [NSMutableDictionary dictionaryWithDictionary:parsed];
    [metadata setObject:[[[HBPString alloc] initWithValue:[parsed objectForKey:@"fileSize"]] autorelease] forKey:@"fileSize"];
    return metadata;
}
@end

int main(void) {
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init]; NSString *error = nil;
    NSString *pem = [[[NSString alloc] initWithContentsOfFile:@"tests/fixtures/drive-rsa-test-key.txt"] autorelease];
    NSDictionary *credentials = [NSDictionary dictionaryWithObjectsAndKeys:@"service_account", @"type", @"fictional@test-project.iam.gserviceaccount.com", @"client_email", @"public-test-key", @"private_key_id", pem, @"private_key", @"https://oauth2.googleapis.com/token", @"token_uri", nil];
    NSData *data = [NSData dataWithContentsOfFile:@"tests/demo.xhb"];
    HBWallet *wallet = [[[HBWallet alloc] initWithData:data error:&error] autorelease];
    check(wallet != nil && pem != nil, "fictive wallet/key fixtures load; no real credentials are read");
    NSException *privateException = [NSException exceptionWithName:NSInvalidArgumentException reason:@"private-token and private-wallet" userInfo:nil];
    NSString *safeMessage = HBDriveExceptionMessage(privateException);
    check([safeMessage rangeOfString:@"API ou argument"].location != NSNotFound && [safeMessage rangeOfString:@"private"].location == NSNotFound, "exception diagnostics identify the failure class without including sensitive reasons");
    safeMessage = HBDriveExceptionMessage([NSException exceptionWithName:@"private-token" reason:@"private-wallet" userInfo:nil]);
    check([safeMessage rangeOfString:@"private"].location == NSNotFound, "unknown exception names are never echoed");
    check(HBDriveParseJSON(utf8(@"{\"ok\":true}"), &error) != nil, "JSON object parses");
    check(HBDriveParseJSON(utf8(@"{\"same\":1,\"same\":2}"), &error) == nil, "duplicate JSON keys rejected");
    check(HBDriveParseJSON(utf8(@"{} trailing"), &error) == nil, "JSON trailing input rejected");
    check(HBDriveParseJSON(utf8(@"[]"), &error) == nil, "non-object API root rejected");
    check(HBDriveParseJSON(utf8(@"{\"id\":\"ok\\u0000hidden\"}"), &error) == nil, "escaped NUL suffix rejected");
    NSMutableString *deep = [NSMutableString stringWithString:@"{\"a\":"]; unsigned int i;
    for (i = 0; i < 70; i++) [deep appendString:@"["]; [deep appendString:@"0"];
    for (i = 0; i < 70; i++) [deep appendString:@"]"]; [deep appendString:@"}"];
    check(HBDriveParseJSON(utf8(deep), &error) == nil, "JSON recursion bounded");
    check([HBDriveSHA256(utf8(@"abc")) isEqual:@"ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"], "SHA256 uses proven crypto library");
    NSString *jwt = HBDriveAssertion(credentials, [NSDate dateWithTimeIntervalSince1970:1791398400], &error);
    check(jwt != nil, "RSA PKCS8 service account assertion signs");
    if (!jwt) fprintf(stderr, "JWT test error: %s\n", [error UTF8String]);
    NSArray *parts = [jwt componentsSeparatedByString:@"."];
    NSDictionary *header = [parts count] == 3 ? decode([parts objectAtIndex:0]) : nil;
    NSDictionary *claims = [parts count] == 3 ? decode([parts objectAtIndex:1]) : nil;
    check([[header objectForKey:@"alg"] isEqual:@"RS256"] && [[header objectForKey:@"kid"] isEqual:@"public-test-key"], "JWT algorithm and key ID are explicit");
    check([[claims objectForKey:@"iss"] isEqual:[credentials objectForKey:@"client_email"]] && [[claims objectForKey:@"aud"] isEqual:@"https://oauth2.googleapis.com/token"] && ![claims objectForKey:@"sub"], "JWT has service identity and fixed token audience, no user impersonation");
    check([[claims objectForKey:@"exp"] doubleValue] - [[claims objectForKey:@"iat"] doubleValue] == 3600, "JWT lifetime limited to one hour");
    check(HBDriveAssertion(credentials, [NSDate dateWithTimeIntervalSince1970:0], &error) == nil, "implausible system clock refuses authorization");
    NSMutableDictionary *bad = [NSMutableDictionary dictionaryWithDictionary:credentials]; [bad setObject:@"https://attacker.invalid/token" forKey:@"token_uri"];
    check(HBDriveAssertion(bad, [NSDate date], &error) == nil, "foreign credential token URI refused");
    [bad setObject:@"https://oauth2.googleapis.com/token" forKey:@"token_uri"]; [bad setObject:@"-----BEGIN PRIVATE KEY-----\nbroken\n-----END PRIVATE KEY-----\n" forKey:@"private_key"];
    check(HBDriveAssertion(bad, [NSDate date], &error) == nil, "invalid RSA key refused before network");
    if (jwt) [utf8(jwt) writeToFile:@"build/drive-test-jwt.txt" atomically:YES];

    HBMockDrive *transport = mock(data); HBDriveClient *drive = client(transport, credentials);
    NSDictionary *downloaded = [drive download:&error];
    check([[[downloaded objectForKey:@"wallet"] sourceData] isEqualToData:data], "Drive loads valid XML without changing it");
    check(transport->mediaRevisionGuard && transport->authorization && transport->tokens == 1, "media GET selects a revision without metadata If-Match; bearer remains in headers");
    [drive download:&error]; check(transport->tokens == 1, "valid access token reused in memory");

    NSDictionary *record = [[wallet records] objectAtIndex:0];
    HBWallet *edited = [wallet walletByChangingStatus:@"1" record:record error:&error];
    HBMockDrive *legacyTransport = mock(data);
    HBDriveClient *legacyClient = [[[HBLegacyDriveClient alloc] initWithSettings:[NSDictionary dictionaryWithObject:@"test-file" forKey:@"fileID"] transport:legacyTransport credentials:credentials] autorelease];
    @try { check([legacyClient download:&error] != nil, "download handles Panther strings without longLongValue"); }
    @catch (NSException *exception) { check(NO, "download used an unsupported Panther selector"); }
    @try { check([legacyClient uploadWallet:edited expectedETag:@"\"v1\"" error:&error] != nil, "upload verification handles Panther strings without longLongValue"); }
    @catch (NSException *exception) { check(NO, "upload used an unsupported Panther selector"); }
    transport = mock(data); drive = client(transport, credentials);
    NSDictionary *uploaded = [drive uploadWallet:edited expectedETag:@"\"v1\"" error:&error];
    check(uploaded != nil && transport->puts == 1 && transport->conditional && [transport->remote isEqualToData:[edited sourceData]], "upload uses conditional PUT, requests a new revision and verifies saved bytes");
    check([drive uploadWallet:edited expectedETag:nil error:&error] == nil && transport->puts == 1, "missing remote baseline never uploads");

    transport = mock(data); [transport->etag release]; transport->etag = [@"\"external\"" copy]; drive = client(transport, credentials);
    check([drive uploadWallet:edited expectedETag:@"\"v1\"" error:&error] == nil && transport->puts == 0 && ![drive retryable], "remote conflict blocks upload, never force-overwrites");
    transport = mock([edited sourceData]); [transport->etag release]; transport->etag = [@"\"external\"" copy]; drive = client(transport, credentials);
    check([drive uploadWallet:edited expectedETag:@"\"v1\"" error:&error] != nil && transport->puts == 0, "already-uploaded identical bytes reconcile without duplicate revision");
    transport = mock(data); transport->race = YES; drive = client(transport, credentials);
    check([drive uploadWallet:edited expectedETag:@"\"v1\"" error:&error] == nil && [transport->remote isEqualToData:data], "HTTP 412 from write-time race does not replace remote bytes");
    transport = mock(data); transport->lostResponse = YES; drive = client(transport, credentials);
    check([drive uploadWallet:edited expectedETag:@"\"v1\"" error:&error] == nil && [drive retryable], "lost upload response remains pending");
    check([drive uploadWallet:edited expectedETag:@"\"v1\"" error:&error] != nil && transport->puts == 1, "retry reconciles lost response through content verification");
    transport = mock(data); transport->changedDuringRead = YES; drive = client(transport, credentials);
    check([drive download:&error] == nil, "remote change during download rejected");
    transport = mock(data); transport->changedRevisionDuringRead = YES; drive = client(transport, credentials);
    check([drive download:&error] == nil && [drive retryable], "changed head revision rejected even when metadata ETag remains the same");
    transport = mock(data); transport->missingRevision = YES; drive = client(transport, credentials);
    check([drive download:&error] == nil && transport->puts == 0, "missing head revision never falls back to an unversioned download");
    transport = mock(data); [transport->revision release]; transport->revision = [@"rev+1/2" copy]; drive = client(transport, credentials);
    check([drive download:&error] != nil && transport->mediaRevisionGuard, "opaque revision identifier is URL encoded");
    transport = mock(data); transport->mediaFailureStatus = 412; drive = client(transport, credentials);
    check([drive download:&error] == nil && [drive retryable] && [error rangeOfString:@"Exporter"].location == NSNotFound, "read precondition failure is a retryable loading error, not a local edit conflict");
    transport = mock(utf8(@"<homebank v='1.7'/>")); drive = client(transport, credentials);
    check([drive download:&error] == nil, "unsupported HomeBank version from Drive refused");
    transport = mock(data); transport->malformed = YES; drive = client(transport, credentials);
    check([drive download:&error] == nil, "malformed metadata rejected without exception");
    transport = mock(data); transport->failureStatus = 404; drive = client(transport, credentials);
    check([drive download:&error] == nil && [drive fileUnavailable] && ![drive retryable], "missing file identified without repeated retries");
    transport = mock(data); transport->failureStatus = 403; drive = client(transport, credentials);
    check([drive download:&error] == nil && ![drive retryable], "permission failure is actionable, not endlessly retried");
    transport = mock(data); transport->failureStatus = 503; drive = client(transport, credentials);
    check([drive download:&error] == nil && [drive retryable], "temporary server failure allows bounded retry");
    transport = mock(data); transport->failureStatus = 401; drive = client(transport, credentials);
    check([drive download:&error] != nil && transport->tokens == 2, "expired GET authorization refreshed once");
    transport = mock(data); transport->badToken = YES; drive = client(transport, credentials);
    check([drive download:&error] == nil && transport->puts == 0, "invalid token expiry rejected");

    char directory[] = "/tmp/homebank-drive-tests-XXXXXX"; check(mkdtemp(directory) != NULL, "private test directory created");
    NSString *root = [NSString stringWithUTF8String:directory], *statePath = [root stringByAppendingPathComponent:@"state.plist"];
    NSDictionary *state = [NSDictionary dictionaryWithObjectsAndKeys:@"test-file", @"fileID", @"\"v1\"", @"etag", HBDriveSHA256(data), @"syncedSHA256", nil];
    check(HBDriveWriteState(state, statePath, &error) && [HBDriveReadState(statePath) isEqual:state], "sync baseline persists atomically without credentials");
    struct stat info; stat([statePath fileSystemRepresentation], &info); check((info.st_mode & 0777) == 0600, "sync state is private");
    NSString *link = [root stringByAppendingPathComponent:@"symlink"];
    symlink([statePath fileSystemRepresentation], [link fileSystemRepresentation]);
    check(HBDriveReadPrivateFile(link, 65536, &error) == nil && !HBDriveWriteState(state, link, &error), "state read/write reject symlinks");
    check(HBDriveReadPrivateFile(statePath, 1, &error) == nil, "file read size is bounded");

    NSString *fakeCurl = [root stringByAppendingPathComponent:@"curl"];
    [[NSFileManager defaultManager] copyPath:@"tests/fixtures/drive-curl.sh" toPath:fakeCurl handler:nil]; chmod([fakeCurl fileSystemRepresentation], 0700);
    NSDictionary *settings = [NSDictionary dictionaryWithObjectsAndKeys:@"test-file", @"fileID", @"test:public-test-key", @"keyAlias", fakeCurl, @"curlPath", statePath, @"caPath", nil];
    check(HBDriveValidSettings(settings, &error), "settings accept explicit local curl and CA paths");
    HBCurlTransport *curl = [[[HBCurlTransport alloc] initWithSettings:settings] autorelease];
    check([curl requestURL:@"https://attacker.invalid" method:@"GET" headers:[NSDictionary dictionary] body:nil error:&error] == nil, "transport refuses foreign destinations");
    NSDictionary *curlResult = [curl requestURL:@"https://www.googleapis.com/drive/v2/files/test-file" method:@"GET" headers:[NSDictionary dictionaryWithObject:@"Bearer dummy-token" forKey:@"Authorization"] body:nil error:&error];
    check([[curlResult objectForKey:@"status"] intValue] == 200 && HBDriveParseJSON([curlResult objectForKey:@"data"], &error) != nil, "mock curl validates TLS flags, private files and stdin-only secrets without network");
    check([curl requestURL:@"https://www.googleapis.com/drive/v2/files/test-file" method:@"GET" headers:[NSDictionary dictionaryWithObject:@"bad\r\nX: injection" forKey:@"Authorization"] body:nil error:&error] == nil, "header injection refused");
    check(HBDriveWriteState(state, statePath, &error), "state replacement succeeds");
    [[NSFileManager defaultManager] removeFileAtPath:root handler:nil];
    printf("%d/%d Drive checks passed (fictive credentials and transport; no network or Keychain access)\n", checks - failures, checks);
    [pool release]; return failures ? 1 : 0;
}
