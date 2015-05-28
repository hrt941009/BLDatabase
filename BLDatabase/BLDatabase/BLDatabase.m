//
//  BLDatabase.m
//  BLAlimeiDatabase
//
//  Created by alibaba on 15/5/11.
//  Copyright (c) 2015年 wxw. All rights reserved.
//

#import "BLDatabase.h"
#import "BLDatabase+Private.h"
#import "BLDatabaseConnection.h"
#import "BLDatabaseConnection+Private.h"
#import "FMDatabase.h"
#import "BLDatabaseConfig.h"
#import "BLDatabaseManager.h"

#import <CommonCrypto/CommonDigest.h>
#import <CommonCrypto/CommonCryptor.h>

static NSString * const defaultName = @"default";

@implementation BLDatabase

#pragma mark - init

+ (instancetype)memoryDatabase
{
    NSString *path = @"file::memory:?cache=shared";
    
    return [self databaseWithPath:path];
}

+ (instancetype)memoryDatabaseWithUniqueName:(NSString *)uniqueName
{
    NSString *path = [NSString stringWithFormat:@"file:%@?mode=memory&cache=shared", uniqueName];
    
    return [self databaseWithPath:path];
}

+ (instancetype)defaultDatabase
{
    NSString *path = [[[self class] documentPath] stringByAppendingFormat:@"/%@.sqlite3", [[self class] md5WithString:defaultName]];
    
    return [self databaseWithPath:path];
}

+ (instancetype)databaseWithName:(NSString *)name
{
    NSString *path = nil;
    if (name) {
        path = [[[self class] documentPath] stringByAppendingFormat:@"/%@.sqlite3", [[self class] md5WithString:name]];
    }
    
    return [self databaseWithPath:path];
}

+ (instancetype)databaseWithPath:(NSString *)path
{
    if (![BLDatabaseManager registerDatabaseForPath:path]) {
        BLLogError(@"Only a single database instance is allowed per file. "
                   @"For concurrency you create multiple connections from a single database instance.");
        return nil;
    }
    
    BLDatabase *database = [[BLDatabase alloc] initWithPath:path];
    
    return database;
}

- (id)initWithPath:(NSString *)path
{
    self = [super init];
    if (self) {
        _databasePath = path;
        self->writeQueue = dispatch_queue_create("com.database.write", DISPATCH_QUEUE_SERIAL);
        dispatch_queue_set_specific(self->writeQueue,
                                    &self->writeSpecificKey,
                                    (__bridge void *)self,
                                    NULL);
        _connections = [NSHashTable weakObjectsHashTable];
    }
    
    return self;
}

- (void)dealloc
{
    [BLDatabaseManager deregisterDatabaseForPath:self.databasePath];
}

#pragma mark - migration

- (void)setSchemaVersion:(NSUInteger)version
      withMigrationBlock:(BLMigrationBlock)block
{
    BLDatabaseConnection *databaseConnection = [self newConnection];
    [databaseConnection performReadWriteBlockAndWaitInTransaction:^(BOOL *rollback) {
        int startingSchemaVersion = 0;
        FMResultSet *rs = [databaseConnection.fmdb executeQuery:@"PRAGMA user_version"];
        if ([rs next]) {
            startingSchemaVersion = [rs intForColumnIndex:0];
        }
        [rs close];
        
        if (block) {
            block(databaseConnection, startingSchemaVersion);
        }
        
        if (startingSchemaVersion < version) {
            if (![databaseConnection.fmdb executeUpdate:[NSString stringWithFormat:@"PRAGMA user_version = %lu", (unsigned long)version]]) {
                BLLogError(@"update version failed, Error:%@", [databaseConnection.fmdb lastError]);
            }
        }
    }];
}

#pragma mark - connection

- (BLDatabaseConnection *)newConnection
{
    return [self newConnectionWithType:BLPrivateQueueDatabaseConnectionType];
}

- (BLDatabaseConnection *)newConnectionWithType:(BLDatabaseConnectionType)type
{
    BLDatabaseConnection *connection = [[BLDatabaseConnection alloc] initWithDatabase:self withType:type];
    [self.connections addObject:connection];
    
    return connection;
}

#pragma mark util

+ (NSString *)md5WithString:(NSString *)string
{
    const char* str = [string UTF8String];
    unsigned char result[CC_MD5_DIGEST_LENGTH];
    CC_MD5(str, (CC_LONG)strlen(str), result);
    
    NSMutableString *ret = [NSMutableString stringWithCapacity:CC_MD5_DIGEST_LENGTH*2];
    for(int i = 0; i < CC_MD5_DIGEST_LENGTH; i++) {
        [ret appendFormat:@"%02x",result[i]];
    }
    return ret;
}

+ (NSString *)documentPath
{
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSString *baseDir = ([paths count] > 0) ? [paths objectAtIndex:0] : NSTemporaryDirectory();
    
    return baseDir;
}

@end
