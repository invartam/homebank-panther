#import "HBDrive.h"
#include <Security/Security.h>
#include <wolfssl/options.h>
#include <wolfssl/wolfcrypt/asn_public.h>
#include <wolfssl/wolfcrypt/rsa.h>
#include <wolfssl/wolfcrypt/sha256.h>
#include <wolfssl/wolfcrypt/coding.h>
#include "cJSON.h"
#include <sys/stat.h>
#include <fcntl.h>
#include <unistd.h>
#include <errno.h>
#include <math.h>
#include <signal.h>
#include <string.h>
#include <stdlib.h>

static BOOL HBDError(NSString **error, NSString *message) { if (error) *error = message; return NO; }
NSString *HBDriveExceptionMessage(NSException *exception) {
    NSString *name = [exception name], *kind = @"exception interne";
    if ([name isEqualToString:NSInvalidArgumentException]) kind = @"API ou argument non pris en charge";
    else if ([name isEqualToString:NSRangeException]) kind = @"valeur hors limites";
    else if ([name isEqualToString:NSFileHandleOperationException]) kind = @"lecture/ecriture interrompue";
    else if ([name isEqualToString:NSMallocException]) kind = @"memoire insuffisante";
    /* Exception reasons can contain credentials or wallet contents. Never include them. */
    return [NSString stringWithFormat:@"Synchronisation interrompue (%@). Copie locale conservee.", kind];
}
static NSString *const HBKeyService = @"HomeBank Panther Drive";
static NSString *const HBTokenURL = @"https://oauth2.googleapis.com/token";
static NSString *const HBDriveScope = @"https://www.googleapis.com/auth/drive";
static NSString *const HBFileFields = @"id,title,mimeType,fileSize,etag,headRevisionId,editable,labels(trashed)";

static id HBJSONValue(const cJSON *node, unsigned int depth) {
    if (!node || depth > 64) return nil;
    if (cJSON_IsString(node)) return node->valuestring ? [NSString stringWithUTF8String:node->valuestring] : nil;
    if (cJSON_IsBool(node)) return [NSNumber numberWithBool:cJSON_IsTrue(node)];
    if (cJSON_IsNumber(node)) return isfinite(node->valuedouble) ? [NSNumber numberWithDouble:node->valuedouble] : nil;
    if (cJSON_IsNull(node)) return [NSNull null];
    if (cJSON_IsObject(node)) {
        NSMutableDictionary *object = [NSMutableDictionary dictionary]; const cJSON *child;
        for (child = node->child; child; child = child->next) {
            NSString *key = child->string ? [NSString stringWithUTF8String:child->string] : nil;
            id value = HBJSONValue(child, depth + 1);
            if (!key || !value || [object objectForKey:key]) return nil;
            [object setObject:value forKey:key];
        }
        return object;
    }
    if (cJSON_IsArray(node)) {
        NSMutableArray *array = [NSMutableArray array]; const cJSON *child;
        for (child = node->child; child; child = child->next) {
            id value = HBJSONValue(child, depth + 1); if (!value) return nil; [array addObject:value];
        }
        return array;
    }
    return nil;
}

NSDictionary *HBDriveParseJSON(NSData *data, NSString **error) {
    if (error) *error = nil;
    if (![data length] || [data length] > 1024 * 1024 || memchr([data bytes], 0, [data length])) {
        HBDError(error, @"Reponse JSON vide, trop volumineuse ou invalide."); return nil;
    }
    NSString *text = [[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] autorelease];
    if (!text) { HBDError(error, @"Reponse JSON non UTF-8."); return nil; }
    /* cJSON strings are NUL-terminated; do not accept hidden suffixes. */
    if ([text rangeOfString:@"\\u0000"].location != NSNotFound) { HBDError(error, @"Caracteres NUL JSON non pris en charge."); return nil; }
    NSMutableData *terminated = [NSMutableData dataWithData:data]; unsigned char zero = 0; [terminated appendBytes:&zero length:1];
    cJSON *root = cJSON_ParseWithLengthOpts([terminated bytes], [terminated length], NULL, 1);
    id value = HBJSONValue(root, 0); cJSON_Delete(root);
    if (![value isKindOfClass:[NSDictionary class]]) { HBDError(error, @"Reponse JSON invalide ou ambigue."); return nil; }
    return value;
}

static NSString *HBString(NSDictionary *object, NSString *key) {
    id value = [object objectForKey:key]; return [value isKindOfClass:[NSString class]] ? value : nil;
}
static BOOL HBASCII(NSString *text, unsigned int minimum, unsigned int maximum, NSString *allowed) {
    unsigned int i, count = [text length]; if (count < minimum || count > maximum) return NO;
    for (i = 0; i < count; i++) {
        unichar c = [text characterAtIndex:i];
        if (c < 33 || c > 126 || (allowed && [allowed rangeOfString:[NSString stringWithCharacters:&c length:1]].location == NSNotFound)) return NO;
    }
    return YES;
}
static NSString *const HBIDCharacters = @"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_-";
NSDictionary *HBDriveCredentials(NSData *data, NSString **error) {
    if ([data length] > 65536) { HBDError(error, @"Cle JSON trop volumineuse."); return nil; }
    NSDictionary *key = HBDriveParseJSON(data, error);
    NSString *email = HBString(key, @"client_email"), *pem = HBString(key, @"private_key"), *kid = HBString(key, @"private_key_id");
    if (![[key objectForKey:@"type"] isEqual:@"service_account"] || !HBASCII(email, 10, 254, nil) ||
        ![email hasSuffix:@".gserviceaccount.com"] || !HBASCII(kid, 1, 128, HBIDCharacters) ||
        ![pem hasPrefix:@"-----BEGIN PRIVATE KEY-----\n"] || [pem length] > 16384 ||
        ![pem hasSuffix:@"-----END PRIVATE KEY-----\n"] ||
        ![HBString(key, @"token_uri") isEqualToString:HBTokenURL]) {
        HBDError(error, @"Cle de compte de service Google invalide (JSON, RSA PKCS#8 ou endpoint)."); return nil;
    }
    return key;
}
BOOL HBDriveValidSettings(NSDictionary *settings, NSString **error) {
    if (!HBASCII(HBString(settings, @"fileID"), 1, 200, HBIDCharacters) ||
        !HBASCII(HBString(settings, @"keyAlias"), 1, 400, nil)) return HBDError(error, @"Identifiant de fichier ou cle Drive absent/invalide.");
    NSArray *paths = [NSArray arrayWithObjects:@"curlPath", @"caPath", nil]; unsigned int i;
    for (i = 0; i < [paths count]; i++) {
        NSString *path = HBString(settings, [paths objectAtIndex:i]); struct stat info;
        if (![path isAbsolutePath] || lstat([path fileSystemRepresentation], &info) != 0 || !S_ISREG(info.st_mode) ||
            (i == 0 && access([path fileSystemRepresentation], X_OK) != 0) || (i == 1 && access([path fileSystemRepresentation], R_OK) != 0))
            return HBDError(error, @"Chemin curl ou certificats invalide. Choisir les fichiers du kit HTTPS, pas un lien symbolique.");
    }
    return YES;
}

static NSString *HBBase64URL(NSData *data) {
    if (!data) return nil;
    word32 size = (word32)(([data length] + 2) / 3 * 4 + 1); NSMutableData *output = [NSMutableData dataWithLength:size];
    if (Base64_Encode_NoNl([data bytes], (word32)[data length], [output mutableBytes], &size) != 0) return nil;
    NSMutableString *text = [[[[NSString alloc] initWithBytes:[output bytes] length:size encoding:NSASCIIStringEncoding] autorelease] mutableCopy];
    [text autorelease];
    [text replaceOccurrencesOfString:@"+" withString:@"-" options:0 range:NSMakeRange(0, [text length])];
    [text replaceOccurrencesOfString:@"/" withString:@"_" options:0 range:NSMakeRange(0, [text length])];
    while ([text hasSuffix:@"="]) [text deleteCharactersInRange:NSMakeRange([text length] - 1, 1)];
    return text;
}
static NSData *HBJSONData(NSDictionary *object) {
    cJSON *root = cJSON_CreateObject(); NSEnumerator *enumerator = [object keyEnumerator]; NSString *key;
    while ((key = [enumerator nextObject])) {
        id value = [object objectForKey:key]; cJSON *item = nil;
        if ([value isKindOfClass:[NSString class]]) item = cJSON_CreateString([value UTF8String]);
        else if ([value isKindOfClass:[NSNumber class]]) item = cJSON_CreateNumber([value doubleValue]);
        if (!item || !cJSON_AddItemToObject(root, [key UTF8String], item)) { cJSON_Delete(item); cJSON_Delete(root); return nil; }
    }
    char *printed = cJSON_PrintUnformatted(root); NSData *data = printed ? [NSData dataWithBytes:printed length:strlen(printed)] : nil;
    cJSON_free(printed); cJSON_Delete(root); return data;
}
static NSString *HBHex(const unsigned char *bytes, unsigned int count) {
    NSMutableString *text = [NSMutableString string]; unsigned int i; for (i = 0; i < count; i++) [text appendFormat:@"%02x", bytes[i]]; return text;
}
NSString *HBDriveSHA256(NSData *data) { unsigned char hash[WC_SHA256_DIGEST_SIZE]; return data && wc_Sha256Hash([data bytes], (word32)[data length], hash) == 0 ? HBHex(hash, sizeof(hash)) : nil; }

NSString *HBDriveAssertion(NSDictionary *credentials, NSDate *date, NSString **error) {
    NSDictionary *validated = HBDriveCredentials(HBJSONData(credentials), error); if (!validated) return nil;
    double seconds = floor([date timeIntervalSince1970]);
    if (seconds < 1735689600 || seconds > 4102441200) { HBDError(error, @"Corriger la date du systeme avant la connexion Google."); return nil; }
    NSData *header = HBJSONData([NSDictionary dictionaryWithObjectsAndKeys:@"RS256", @"alg", @"JWT", @"typ", HBString(validated, @"private_key_id"), @"kid", nil]);
    NSData *claims = HBJSONData([NSDictionary dictionaryWithObjectsAndKeys:HBString(validated, @"client_email"), @"iss", HBDriveScope, @"scope", HBTokenURL, @"aud",
        [NSNumber numberWithDouble:seconds], @"iat", [NSNumber numberWithDouble:seconds + 3600], @"exp", nil]);
    if (!header || !claims) { HBDError(error, @"Impossible de preparer l'autorisation."); return nil; }
    NSString *unsignedJWT = [NSString stringWithFormat:@"%@.%@", HBBase64URL(header), HBBase64URL(claims)];
    NSData *payload = [unsignedJWT dataUsingEncoding:NSASCIIStringEncoding], *pem = [HBString(validated, @"private_key") dataUsingEncoding:NSASCIIStringEncoding];
    unsigned char der[16384], hash[WC_SHA256_DIGEST_SIZE], digest[128], signature[512];
    RsaKey rsa; WC_RNG rng; word32 index = 0; BOOL rsaReady = NO, rngReady = NO; int length = -1;
    int derSize = wc_KeyPemToDer([pem bytes], (int)[pem length], der, sizeof(der), NULL);
    if (derSize > 0 && wc_InitRsaKey(&rsa, NULL) == 0) {
        rsaReady = YES;
        if (wc_RsaPrivateKeyDecode(der, &index, &rsa, (word32)derSize) == 0 && wc_RsaEncryptSize(&rsa) >= 256 && wc_RsaEncryptSize(&rsa) <= 512 && wc_InitRng(&rng) == 0) {
            rngReady = YES;
            if (wc_Sha256Hash([payload bytes], (word32)[payload length], hash) == 0) {
                word32 digestSize = wc_EncodeSignature(digest, hash, sizeof(hash), SHA256h);
                length = wc_RsaSSL_Sign(digest, digestSize, signature, sizeof(signature), &rsa, &rng);
            }
        }
    }
    if (rngReady) wc_FreeRng(&rng); if (rsaReady) wc_FreeRsaKey(&rsa);
    volatile unsigned char *wipe = der; unsigned int i; for (i = 0; i < sizeof(der); i++) wipe[i] = 0;
    if (length <= 0) { HBDError(error, @"Signature RSA-SHA256 impossible : verifier la cle Google et la bibliotheque HTTPS."); return nil; }
    return [NSString stringWithFormat:@"%@.%@", unsignedJWT, HBBase64URL([NSData dataWithBytes:signature length:length])];
}

NSData *HBDriveReadPrivateFile(NSString *path, unsigned long maximum, NSString **error) {
    int fd = open([path fileSystemRepresentation], O_RDONLY | O_NOFOLLOW); struct stat info;
    if (fd < 0 || fstat(fd, &info) != 0 || !S_ISREG(info.st_mode) || info.st_size <= 0 || (unsigned long long)info.st_size > maximum) {
        if (fd >= 0) close(fd); HBDError(error, @"Fichier absent, trop volumineux ou non regulier."); return nil;
    }
    NSMutableData *data = [NSMutableData dataWithLength:(unsigned long)info.st_size]; unsigned long offset = 0;
    while (offset < [data length]) { ssize_t n = read(fd, (char *)[data mutableBytes] + offset, [data length] - offset); if (n < 0 && errno == EINTR) continue; if (n <= 0) break; offset += n; }
    close(fd); if (offset != [data length]) { HBDError(error, @"Lecture incomplete."); return nil; } return data;
}
static BOOL HBWriteFD(int fd, NSData *data) {
    unsigned long offset = 0; while (offset < [data length]) { ssize_t n = write(fd, (const char *)[data bytes] + offset, [data length] - offset); if (n < 0 && errno == EINTR) continue; if (n <= 0) return NO; offset += n; }
    return fsync(fd) == 0;
}
BOOL HBDriveWriteState(NSDictionary *state, NSString *path, NSString **error) {
    NSString *description = nil;
    NSData *data = [NSPropertyListSerialization dataFromPropertyList:state format:NSPropertyListXMLFormat_v1_0 errorDescription:&description]; [description release];
    struct stat info; BOOL exists = lstat([path fileSystemRepresentation], &info) == 0;
    if (!data || (exists && (!S_ISREG(info.st_mode) || info.st_uid != getuid())) || (!exists && errno != ENOENT)) return HBDError(error, @"Etat Drive non enregistrable.");
    char *temporary = strdup([[path stringByAppendingString:@".tmp-XXXXXX"] fileSystemRepresentation]); if (!temporary) return HBDError(error, @"Memoire insuffisante.");
    int fd = mkstemp(temporary); BOOL ok = fd >= 0 && fchmod(fd, 0600) == 0 && HBWriteFD(fd, data);
    if (fd >= 0 && close(fd) != 0) ok = NO;
    if (ok) ok = rename(temporary, [path fileSystemRepresentation]) == 0;
    unlink(temporary); free(temporary); return ok ? YES : HBDError(error, @"Etat Drive non enregistre. La copie locale est conservee.");
}
NSDictionary *HBDriveReadState(NSString *path) {
    NSData *data = HBDriveReadPrivateFile(path, 65536, NULL); if (!data) return nil;
    NSString *error = nil; id object = [NSPropertyListSerialization propertyListFromData:data mutabilityOption:NSPropertyListImmutable format:NULL errorDescription:&error]; [error release];
    return [object isKindOfClass:[NSDictionary class]] ? object : nil;
}
NSString *HBDriveDirectory(NSString **error) {
    NSString *path = [NSHomeDirectory() stringByAppendingPathComponent:@"Library/Application Support/HomeBank Panther"];
    NSFileManager *manager = [NSFileManager defaultManager]; struct stat info;
    if (![manager fileExistsAtPath:[path stringByDeletingLastPathComponent]])
        [manager createDirectoryAtPath:[path stringByDeletingLastPathComponent] attributes:[NSDictionary dictionary]];
    if (lstat([path fileSystemRepresentation], &info) != 0) {
        if (errno != ENOENT || ![manager createDirectoryAtPath:path attributes:[NSDictionary dictionaryWithObject:[NSNumber numberWithInt:0700] forKey:NSFilePosixPermissions]]) {
            HBDError(error, @"Dossier de cache Drive inaccessible."); return nil;
        }
    }
    if (lstat([path fileSystemRepresentation], &info) != 0 || !S_ISDIR(info.st_mode) || info.st_uid != getuid() || chmod([path fileSystemRepresentation], 0700) != 0) {
        HBDError(error, @"Dossier de cache Drive non prive ou lien symbolique."); return nil;
    }
    return path;
}
static NSData *HBLoadKey(NSString *alias, NSString **error) {
    UInt32 count = 0; void *bytes = NULL;
    OSStatus status = SecKeychainFindGenericPassword(NULL, (UInt32)[HBKeyService length], [HBKeyService UTF8String], (UInt32)strlen([alias UTF8String]), [alias UTF8String], &count, &bytes, NULL);
    NSData *data = status == noErr && count <= 65536 ? [NSData dataWithBytes:bytes length:count] : nil;
    if (bytes) SecKeychainItemFreeContent(NULL, bytes);
    if (!data) HBDError(error, @"Cle Drive absente ou trousseau verrouille. Importer de nouveau la cle."); return data;
}
BOOL HBDriveStoreKey(NSData *data, NSString **alias, NSString **error) {
    NSDictionary *key = HBDriveCredentials(data, error); if (!key || !HBDriveAssertion(key, [NSDate date], error)) return NO;
    NSString *account = [NSString stringWithFormat:@"%@:%@", HBString(key, @"client_email"), HBString(key, @"private_key_id")];
    SecKeychainItemRef item = NULL;
    OSStatus status = SecKeychainFindGenericPassword(NULL, (UInt32)[HBKeyService length], [HBKeyService UTF8String], (UInt32)[account length], [account UTF8String], NULL, NULL, &item);
    if (status == noErr) status = SecKeychainItemModifyAttributesAndData(item, NULL, (UInt32)[data length], [data bytes]);
    else if (status == errSecItemNotFound) status = SecKeychainAddGenericPassword(NULL, (UInt32)[HBKeyService length], [HBKeyService UTF8String], (UInt32)[account length], [account UTF8String], (UInt32)[data length], [data bytes], NULL);
    if (item) CFRelease(item); if (status != noErr) return HBDError(error, @"La cle n'a pas pu etre protegee dans le trousseau. Configuration refusee.");
    if (alias) *alias = account; return YES;
}
BOOL HBDriveDeleteKey(NSString *alias, NSString **error) {
    if (!HBASCII(alias, 1, 400, nil)) return HBDError(error, @"Cle non configuree.");
    SecKeychainItemRef item = NULL;
    OSStatus status = SecKeychainFindGenericPassword(NULL, (UInt32)[HBKeyService length], [HBKeyService UTF8String], (UInt32)strlen([alias UTF8String]), [alias UTF8String], NULL, NULL, &item);
    if (status == noErr) status = SecKeychainItemDelete(item);
    if (item) CFRelease(item);
    return status == noErr || status == errSecItemNotFound ? YES : HBDError(error, @"Impossible de retirer la cle du trousseau.");
}

static NSString *HBCurlQuote(NSString *text) {
    NSMutableString *escaped = [[text mutableCopy] autorelease];
    [escaped replaceOccurrencesOfString:@"\\" withString:@"\\\\" options:0 range:NSMakeRange(0, [escaped length])];
    [escaped replaceOccurrencesOfString:@"\"" withString:@"\\\"" options:0 range:NSMakeRange(0, [escaped length])];
    [escaped replaceOccurrencesOfString:@"\n" withString:@"\\n" options:0 range:NSMakeRange(0, [escaped length])];
    [escaped replaceOccurrencesOfString:@"\r" withString:@"\\r" options:0 range:NSMakeRange(0, [escaped length])];
    return [NSString stringWithFormat:@"\"%@\"", escaped];
}
@implementation HBCurlTransport
- (id)initWithSettings:(NSDictionary *)settings {
    self = [super init]; if (self) { _curlPath = [[settings objectForKey:@"curlPath"] copy]; _caPath = [[settings objectForKey:@"caPath"] copy]; } return self;
}
- (NSDictionary *)requestURL:(NSString *)url method:(NSString *)method headers:(NSDictionary *)headers body:(NSData *)body error:(NSString **)error {
    if (error) *error = nil;
    if (!([url isEqualToString:HBTokenURL] || [url hasPrefix:@"https://www.googleapis.com/drive/v2/files/"] || [url hasPrefix:@"https://www.googleapis.com/upload/drive/v2/files/"])) {
        HBDError(error, @"Destination reseau refusee."); return nil;
    }
    char directory[] = "/tmp/homebank-drive-XXXXXX"; if (!mkdtemp(directory)) { HBDError(error, @"Dossier temporaire indisponible."); return nil; }
    NSString *root = [NSString stringWithUTF8String:directory], *output = [root stringByAppendingPathComponent:@"response"], *input = [root stringByAppendingPathComponent:@"payload"];
    NSDictionary *result = nil; NSTask *task = [[[NSTask alloc] init] autorelease];
    NSPipe *configuration = [NSPipe pipe], *statusPipe = [NSPipe pipe];
    @try {
        int fd = open([output fileSystemRepresentation], O_WRONLY | O_CREAT | O_EXCL, 0600); if (fd < 0) [NSException raise:@"HBDriveIO" format:@"response"]; close(fd);
        NSMutableString *config = [NSMutableString stringWithFormat:@"url = %@\nrequest = %@\ncacert = %@\n", HBCurlQuote(url), HBCurlQuote(method), HBCurlQuote(_caPath)];
        NSEnumerator *keys = [headers keyEnumerator]; NSString *key;
        while ((key = [keys nextObject])) {
            NSString *value = [headers objectForKey:key];
            if (![value isKindOfClass:[NSString class]] || [value rangeOfCharacterFromSet:[NSCharacterSet controlCharacterSet]].location != NSNotFound || [key rangeOfCharacterFromSet:[NSCharacterSet controlCharacterSet]].location != NSNotFound)
                [NSException raise:@"HBDriveHeader" format:@"header"];
            [config appendFormat:@"header = %@\n", HBCurlQuote([NSString stringWithFormat:@"%@: %@", key, value])];
        }
        if (body) {
            if ([body length] > HB_MAX_FILE_BYTES) [NSException raise:@"HBDriveSize" format:@"payload"];
            fd = open([input fileSystemRepresentation], O_WRONLY | O_CREAT | O_EXCL, 0600);
            BOOL written = fd >= 0 && HBWriteFD(fd, body); if (fd >= 0) close(fd);
            if (!written) [NSException raise:@"HBDriveIO" format:@"payload"];
            [config appendFormat:@"data-binary = %@\n", HBCurlQuote([@"@" stringByAppendingString:input])];
        }
        NSData *configData = [config dataUsingEncoding:NSUTF8StringEncoding];
        if ([configData length] > 16384) [NSException raise:@"HBDriveSize" format:@"config"];
        [task setLaunchPath:_curlPath];
        [task setArguments:[NSArray arrayWithObjects:@"-q", @"--config", @"-", @"--proto", @"=https", @"--tlsv1.2", @"--proxy", @"", @"--connect-timeout", @"10", @"--max-time", @"45", @"--max-filesize", @"8388608", @"--silent", @"--output", output, @"--write-out", @"%{http_code}", nil]];
        [task setEnvironment:[NSDictionary dictionaryWithObjectsAndKeys:@"/usr/bin:/bin", @"PATH", @"C", @"LC_ALL", nil]];
        [task setStandardInput:configuration]; [task setStandardOutput:statusPipe]; [task setStandardError:[NSFileHandle fileHandleWithNullDevice]];
        [task launch]; [[configuration fileHandleForReading] closeFile]; [[statusPipe fileHandleForWriting] closeFile];
        [[configuration fileHandleForWriting] writeData:configData]; [[configuration fileHandleForWriting] closeFile];
        NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:50];
        while ([task isRunning] && [deadline timeIntervalSinceNow] > 0) [NSThread sleepUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
        if ([task isRunning]) { [task terminate]; kill([task processIdentifier], SIGKILL); }
        [task waitUntilExit];
        if ([task terminationStatus] == 0) {
            NSData *statusData = [[statusPipe fileHandleForReading] readDataToEndOfFile];
            NSString *statusText = [[[NSString alloc] initWithData:statusData encoding:NSASCIIStringEncoding] autorelease];
            NSData *data = HBDriveReadPrivateFile(output, HB_MAX_FILE_BYTES, NULL);
            if ([statusText length] == 3 && [statusText intValue] >= 100 && [statusText intValue] <= 599 && data)
                result = [NSDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithInt:[statusText intValue]], @"status", data, @"data", nil];
        }
        if (!result) HBDError(error, @"Connexion HTTPS interrompue ou client curl incompatible. Copie locale conservee ; verifier reseau, date et certificats.");
    } @catch (NSException *exception) {
        if ([task isRunning]) { [task terminate]; kill([task processIdentifier], SIGKILL); [task waitUntilExit]; }
        HBDError(error, @"Requete Drive impossible. Verifier le client HTTPS et les chemins configures.");
    }
    @try { [[configuration fileHandleForWriting] closeFile]; [[statusPipe fileHandleForReading] closeFile]; } @catch (NSException *exception) { }
    unlink([output fileSystemRepresentation]); unlink([input fileSystemRepresentation]); rmdir([root fileSystemRepresentation]); return result;
}
- (void)dealloc { [_curlPath release]; [_caPath release]; [super dealloc]; }
@end

static NSString *HBForm(NSString *text) {
    const unsigned char *bytes = (const unsigned char *)[text UTF8String]; NSMutableString *escaped = [NSMutableString string]; unsigned long i;
    for (i = 0; bytes && bytes[i]; i++) {
        unsigned char c = bytes[i]; if ((c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9') || c == '-' || c == '_' || c == '.' || c == '~') [escaped appendFormat:@"%c", c];
        else [escaped appendFormat:@"%%%02X", c];
    }
    return escaped;
}
static BOOL HBHTTPError(int status, NSString **error) {
    if (status == 404 || status == 410) return HBDError(error, @"Fichier Drive introuvable ou inaccessible. Verifier l'identifiant et le partage, ou choisir un autre fichier.");
    if (status == 412 || status == 409) return HBDError(error, @"Conflit Drive : le fichier distant a change. Aucun remplacement force. Exporter la copie locale puis recharger Drive.");
    if (status == 401) return HBDError(error, @"Autorisation Drive expiree ou cle revoquee. Verifier le compte de service.");
    if (status == 403) return HBDError(error, @"Drive refuse l'acces. Verifier partage en modification, API activee, quota et restrictions du compte.");
    return HBDError(error, [NSString stringWithFormat:@"Drive indisponible (HTTP %d). Copie locale conservee.", status]);
}
static unsigned long HBMetadataSize(NSDictionary *metadata) {
    unsigned long size = 0;
    HBParseUnsigned(HBString(metadata, @"fileSize"), HB_MAX_FILE_BYTES, &size);
    return size;
}
@implementation HBDriveClient
- (id)initWithSettings:(NSDictionary *)settings transport:(id<HBDriveTransport>)transport credentials:(NSDictionary *)credentials {
    self = [super init]; if (self) { _settings = [settings copy]; _testCredentials = [credentials copy]; _transport = transport ? [transport retain] : [[HBCurlTransport alloc] initWithSettings:settings]; } return self;
}
- (BOOL)authorize:(NSString **)error {
    if (_token && [_expires timeIntervalSinceNow] > 60) return YES;
    NSData *keyData = _testCredentials ? nil : HBLoadKey([_settings objectForKey:@"keyAlias"], error);
    if (!_testCredentials && !keyData) return NO;
    NSDictionary *credentials = _testCredentials ? _testCredentials : HBDriveCredentials(keyData, error);
    NSString *assertion = credentials ? HBDriveAssertion(credentials, [NSDate date], error) : nil; if (!assertion) return NO;
    NSData *form = [[NSString stringWithFormat:@"grant_type=%@&assertion=%@", HBForm(@"urn:ietf:params:oauth:grant-type:jwt-bearer"), HBForm(assertion)] dataUsingEncoding:NSASCIIStringEncoding];
    NSDictionary *response = [_transport requestURL:HBTokenURL method:@"POST" headers:[NSDictionary dictionaryWithObject:@"application/x-www-form-urlencoded" forKey:@"Content-Type"] body:form error:error];
    if (!response) { _retryable = YES; return NO; }
    int status = [[response objectForKey:@"status"] intValue];
    if (status != 200) { _retryable = status == 429 || status >= 500; return HBDError(error, @"Authentification du compte de service refusee. Verifier cle, API, date et droits Google Cloud."); }
    NSDictionary *tokens = HBDriveParseJSON([response objectForKey:@"data"], error); id expires = [tokens objectForKey:@"expires_in"];
    NSString *token = HBString(tokens, @"access_token");
    if (!HBASCII(token, 1, 4096, nil) || ![HBString(tokens, @"token_type") isEqualToString:@"Bearer"] || ![expires isKindOfClass:[NSNumber class]] || [expires intValue] < 120 || [expires intValue] > 7200)
        return HBDError(error, @"Reponse d'autorisation Google invalide.");
    [_token release]; _token = [token copy]; [_expires release]; _expires = [[NSDate dateWithTimeIntervalSinceNow:[expires intValue]] retain]; return YES;
}
- (NSDictionary *)api:(NSString *)url method:(NSString *)method extra:(NSDictionary *)extra body:(NSData *)body error:(NSString **)error {
    if (![self authorize:error]) return nil;
    NSMutableDictionary *headers = [NSMutableDictionary dictionaryWithDictionary:extra]; [headers setObject:[@"Bearer " stringByAppendingString:_token] forKey:@"Authorization"];
    NSDictionary *response = [_transport requestURL:url method:method headers:headers body:body error:error];
    if (!response) _retryable = YES;
    if ([[response objectForKey:@"status"] intValue] == 401) {
        [_token release]; _token = nil; [_expires release]; _expires = nil;
        if ([method isEqualToString:@"GET"] && [self authorize:error]) {
            [headers setObject:[@"Bearer " stringByAppendingString:_token] forKey:@"Authorization"];
            response = [_transport requestURL:url method:method headers:headers body:body error:error];
        }
    }
    if (!response) _retryable = YES;
    if (response && [[response objectForKey:@"status"] intValue] != 200) {
        int status = [[response objectForKey:@"status"] intValue]; _retryable = status == 429 || status >= 500; _fileUnavailable = status == 404 || status == 410;
        if ([method isEqualToString:@"GET"] && (status == 412 || status == 409)) {
            _retryable = YES;
            HBDError(error, @"Lecture Drive interrompue par une condition de version. Reessayer le chargement ; aucune copie locale n'a ete remplacee."); return nil;
        }
        HBHTTPError(status, error); return nil;
    }
    return response;
}
- (NSString *)fileURL {
    return [NSString stringWithFormat:@"https://www.googleapis.com/drive/v2/files/%@", [_settings objectForKey:@"fileID"]];
}
- (NSDictionary *)metadataFromData:(NSData *)data error:(NSString **)error {
    NSDictionary *metadata = HBDriveParseJSON(data, error); unsigned long size = 0;
    NSString *etag = HBString(metadata, @"etag");
    if (![HBString(metadata, @"id") isEqualToString:[_settings objectForKey:@"fileID"]] ||
        !HBParseUnsigned(HBString(metadata, @"fileSize"), HB_MAX_FILE_BYTES, &size) || !size ||
        !HBASCII(etag, 3, 512, nil) || ![etag hasPrefix:@"\""] || ![etag hasSuffix:@"\""] ||
        !HBASCII(HBString(metadata, @"headRevisionId"), 1, 512, nil) ||
        !HBString(metadata, @"title") || [HBString(metadata, @"title") length] > 1024 ||
        [HBString(metadata, @"mimeType") hasPrefix:@"application/vnd.google-apps."] ||
        ![[metadata objectForKey:@"labels"] isKindOfClass:[NSDictionary class]] ||
        ![[[metadata objectForKey:@"labels"] objectForKey:@"trashed"] isKindOfClass:[NSNumber class]] ||
        [[[metadata objectForKey:@"labels"] objectForKey:@"trashed"] boolValue]) {
        HBDError(error, @"Fichier Drive non pris en charge, supprime, trop volumineux ou sans version verifiable."); return nil;
    }
    return metadata;
}
- (NSDictionary *)metadata:(NSString **)error {
    NSDictionary *response = [self api:[NSString stringWithFormat:@"%@?supportsAllDrives=true&fields=%@", [self fileURL], HBForm(HBFileFields)] method:@"GET" extra:[NSDictionary dictionary] body:nil error:error];
    return response ? [self metadataFromData:[response objectForKey:@"data"] error:error] : nil;
}
- (NSDictionary *)download:(NSString **)error {
    _retryable = NO; _fileUnavailable = NO;
    NSDictionary *before = [self metadata:error]; if (!before) return nil;
    /* A metadata validator is not a media validator. Read the immutable revision. */
    NSString *url = [NSString stringWithFormat:@"%@?alt=media&revisionId=%@&supportsAllDrives=true", [self fileURL], HBForm([before objectForKey:@"headRevisionId"])];
    NSDictionary *response = [self api:url method:@"GET" extra:[NSDictionary dictionary] body:nil error:error];
    if (!response) return nil; NSData *data = [response objectForKey:@"data"];
    HBWallet *wallet = [[[HBWallet alloc] initWithData:data error:error] autorelease]; if (!wallet) return nil;
    NSDictionary *after = [self metadata:error]; if (!after) return nil;
    if (![[before objectForKey:@"etag"] isEqual:[after objectForKey:@"etag"]] ||
        ![[before objectForKey:@"headRevisionId"] isEqual:[after objectForKey:@"headRevisionId"]] ||
        [data length] != HBMetadataSize(after)) {
        _retryable = YES;
        HBDError(error, @"Le fichier Drive a change pendant le chargement. Reessayer sans remplacer la copie locale."); return nil;
    }
    return [NSDictionary dictionaryWithObjectsAndKeys:wallet, @"wallet", after, @"metadata", nil];
}
- (NSDictionary *)uploadWallet:(HBWallet *)wallet expectedETag:(NSString *)etag error:(NSString **)error {
    _retryable = NO; _fileUnavailable = NO;
    NSData *data = [wallet sourceData];
    if (![etag length] || ![[[HBWallet alloc] initWithData:data error:error] autorelease]) { HBDError(error, @"Aucune version distante de reference. Charger le fichier Drive avant toute sauvegarde."); return nil; }
    NSDictionary *current = [self metadata:error]; if (!current) return nil;
    /* Also reconciles a previous upload whose HTTP response was lost. */
    if (![[current objectForKey:@"etag"] isEqual:etag]) {
        NSDictionary *downloaded = [self download:error]; if (!downloaded) return nil;
        if ([[[downloaded objectForKey:@"wallet"] sourceData] isEqualToData:data]) return [downloaded objectForKey:@"metadata"];
        HBHTTPError(412, error); return nil;
    }
    if (![[current objectForKey:@"editable"] boolValue]) { HBHTTPError(403, error); return nil; }
    NSString *url = [NSString stringWithFormat:@"https://www.googleapis.com/upload/drive/v2/files/%@?uploadType=media&newRevision=true&supportsAllDrives=true&fields=%@", [_settings objectForKey:@"fileID"], HBForm(HBFileFields)];
    NSDictionary *headers = [NSDictionary dictionaryWithObjectsAndKeys:etag, @"If-Match", @"application/x-homebank+xml", @"Content-Type", nil];
    NSDictionary *response = [self api:url method:@"PUT" extra:headers body:data error:error]; if (!response) return nil;
    NSDictionary *updated = [self metadataFromData:[response objectForKey:@"data"] error:error]; if (!updated) return nil;
    if ([data length] != HBMetadataSize(updated)) {
        HBDError(error, @"Resultat de sauvegarde Drive incertain. Copie locale conservee ; verifier avant de reessayer."); return nil;
    }
    NSDictionary *confirmed = [self download:error]; if (!confirmed) return nil;
    if (![[updated objectForKey:@"etag"] isEqual:[[confirmed objectForKey:@"metadata"] objectForKey:@"etag"]] || ![[[confirmed objectForKey:@"wallet"] sourceData] isEqualToData:data]) {
        HBDError(error, @"Le contenu Drive a change apres l'envoi. Copie locale conservee ; verifier les versions distantes."); return nil;
    }
    return [confirmed objectForKey:@"metadata"];
}
- (void)dealloc { [_settings release]; [_testCredentials release]; [_transport release]; [_token release]; [_expires release]; [super dealloc]; }
- (BOOL)retryable { return _retryable; }
- (BOOL)fileUnavailable { return _fileUnavailable; }
@end
