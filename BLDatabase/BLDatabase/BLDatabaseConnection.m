//
//  BLAlimeiDatabase.m
//  BLAlimeiDatabase
//
//  Created by alibaba on 15/1/21.
//  Copyright (c) 2015年 wxw. All rights reserved.
//

#import "BLDatabaseConnection.h"
#import "BLDatabase.h"
#import "BLDatabase+Private.h"
#import "BLBaseDBObject.h"
#import "BLBaseDBObject+Private.h"
#import "BLDBCache.h"
#import "BLDatabaseConfig.h"
#import "FMDatabase+Private.h"
#import "BLDBChangedObject.h"

@interface BLDatabaseConnection () <BLDBCacheDelegate>
{
    void                *readSpecificKey;
    dispatch_queue_t    readQueue;
}

@property (nonatomic, strong) BLDatabase *database;
@property (nonatomic, strong) FMDatabase *fmdb;
@property (nonatomic, strong) BLDBCache *dbCache;

@property (nonatomic, strong) NSMutableArray *changedObjects;

@end

@implementation BLDatabaseConnection

#pragma mark - init

- (instancetype)initWithDatabase:(BLDatabase *)database
{
    return [self initWithDatabase:database withType:BLPrivateQueueDatabaseConnectionType];
}

- (instancetype)initWithDatabase:(BLDatabase *)database withType:(BLDatabaseConnectionType)type
{
    self = [super init];
    if (self) {
        _database = database;
        _type = type;
        _fmdb = [[FMDatabase alloc] initWithPath:database.databasePath];
        int flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_NOMUTEX | SQLITE_OPEN_PRIVATECACHE;
        [_fmdb openWithFlags:flags];
        
        int status;
        
        sqlite3_config(SQLITE_CONFIG_SINGLETHREAD);
        
        status = sqlite3_exec(self.sqlite, "PRAGMA journal_mode = WAL;", NULL, NULL, NULL);
        if (status != SQLITE_OK) {
            BLLogError(@"Error setting PRAGMA journal_mode: %d %s", status, sqlite3_errmsg(self.sqlite));
        }
        
        sqlite3_wal_checkpoint(self.sqlite, NULL);
        
        if (_type == BLMainQueueDatabaseConnectionType) {
            self->readQueue = dispatch_get_main_queue();
        } else {
            self->readQueue = dispatch_queue_create("com.database.read", DISPATCH_QUEUE_SERIAL);
            dispatch_queue_set_specific(self->readQueue,
                                        &self->readSpecificKey,
                                        (__bridge void *)self,
                                        NULL);
        }
        
        _dbCache = [BLDBCache new];
        _dbCache.delegate = self;
        _cacheCountLimit = 500;
        _dbCache.countLimit = _cacheCountLimit;
        _changedObjects = [NSMutableArray array];
    }
    
    return self;
}

#pragma mark - life cycle
 
- (void)dealloc
{
    
}

#pragma mark - getter & private

- (FMDatabase *)fmdb
{
    return _fmdb;
}

- (sqlite3 *)sqlite
{
    return [_fmdb sqlite];
}

- (BLDBCache *)cachedObjects
{
    return _dbCache;
}

- (NSMutableArray *)changedObjects
{
    return _changedObjects;
}

#pragma mark - setter

- (void)setCacheCountLimit:(NSUInteger)cacheCountLimit
{
    _cacheCountLimit = cacheCountLimit;
    _dbCache.countLimit = cacheCountLimit;
}

#pragma mark - perform block

- (BOOL)isInReadQueue
{
    void *context = dispatch_get_specific(&self->readSpecificKey);
    BOOL hasContext = context ? YES : NO;
    
    return (_type == BLMainQueueDatabaseConnectionType && [NSThread isMainThread]) || hasContext;
}

- (BOOL)isInWriteQueue
{
    void *context = dispatch_get_specific(&self.database->writeSpecificKey);
    BOOL hasContext = context ? YES : NO;
    
    return hasContext;
}

- (void)performReadBlockAndWait:(void(^)(void))block
{
    dispatch_block_t newBlock = ^{
        if (block) {
            block();
        }
    };

    if ([self isInReadQueue]) {
        newBlock();
    } else {
        dispatch_sync(self->readQueue, newBlock);
    }
}

- (void)performReadBlock:(void(^)(void))block
{
    dispatch_block_t newBlock = ^{
        if (block) {
            block();
        }
    };
    
    if ([self isInReadQueue]) {
        newBlock();
    } else {
        dispatch_async(self->readQueue, newBlock);
    }
}

- (void)performReadWriteBlockAndWait:(void(^)(void))block
{
    dispatch_block_t newBlock = ^{
        if (block) {
            block();
        }
    };
    
    [self performReadBlockAndWait:^{
        if ([self isInWriteQueue]) {
            newBlock();
        } else {
            dispatch_sync(self.database->writeQueue, ^{
                newBlock();
            });
        }
    }];
}

- (void)performReadWriteBlock:(void(^)(void))block
{
    dispatch_block_t newBlock = ^{
        if (block) {
            block();
        }
    };
    
    [self performReadBlock:^{
        if ([self isInWriteQueue]) {
            newBlock();
        } else {
            dispatch_sync(self.database->writeQueue, ^{
                newBlock();
            });
        }
    }];
}

- (void)performReadWriteBlockAndWaitInTransaction:(void(^)(BOOL *rollback))block
{
    [self performReadWriteBlockAndWait:^{
        BOOL shouldRollback = NO;
        
        BOOL inTransaction = [self.fmdb inTransaction];
        if (!inTransaction) {
            [self beginTransaction];
        }
        
        if (block) {
            block(&shouldRollback);
        }
        
        if (!inTransaction) {
            if (shouldRollback) {
                [self rollback];
            } else {
                [self commit];
            }
        }
    }];
}

- (void)performReadWriteBlockInTransaction:(void(^)(BOOL *rollback))block;
{
    [self performReadWriteBlock:^{
        BOOL shouldRollback = NO;
        
        BOOL inTransaction = [self.fmdb inTransaction];
        if (!inTransaction) {
            [self beginTransaction];
        }
        
        if (block) {
            block(&shouldRollback);
        }
        
        if (!inTransaction) {
            if (shouldRollback) {
                [self rollback];
            } else {
                [self commit];
            }
        }
    }];
}

#pragma mark - public

- (void)validateRead
{
    if (![self isInReadQueue] && ![self isInWriteQueue]) {
        BLLogError(@"you must be excute in read queue");
        assert(false);
    }
}

- (void)validateReadWriteInTransaction
{
    BOOL inTransaction = [self.fmdb inTransaction];
    if (!inTransaction || ![self isInWriteQueue]) {
        BLLogError(@"you must be excute in write queue and in transaction");
        assert(false);
    }
}

- (void)touchedObject:(id)object
{
    if (object) {
        [self touchedObjects:@[object]];
    }
}

- (void)touchedObjects:(id)objects
{
    for (id object in objects) {
        [object touchedInDatabaseConnection:self];
    }
}

- (void)insertOrUpdateObject:(BLBaseDBObject *)object
{
    if (object) {
        [self insertOrUpdateObjects:@[object]];
    }
}

- (void)insertOrUpdateObjects:(NSArray *)objects
{
    for (id object in objects) {
        [object insertOrUpdateInDatabaseConnection:self];
    }
}

- (void)insertObject:(id)object
{
    if (object) {
        [self insertObjects:@[object]];
    }
}

- (void)insertObjects:(NSArray *)objects
{
    for (id object in objects) {
        [object insertInDatabaseConnection:self];
    }
}

- (void)updateObject:(BLBaseDBObject *)object
{
    if (object) {
        [self updateObjects:@[object]];
    }
}

- (void)updateObjects:(NSArray *)objects
{
    for (id object in objects) {
        [object updateInDatabaseConnection:self];
    }
}

- (void)deleteObject:(id)object
{
    if (object) {
        [self deleteObjects:@[object]];
    }
}

- (void)deleteObjects:(NSArray *)objects
{
    for (id object in objects) {
        [object deleteInDatabaseConnection:self];
    }
}

- (void)beginTransaction
{
    [BLBaseDBObject beginChangedNotificationInDatabaseConnection:self];
    [self.fmdb beginTransaction];
}

- (void)commit
{
    [self.fmdb commit];
    [BLBaseDBObject endChangedNotificationInDatabaseConnection:self];
}

- (void)rollback
{
    [self.fmdb rollback];
    [BLBaseDBObject rollbackChangedNotificationInDatabaseConnection:self];
}

#pragma mark - refresh

- (void)refreshWithInsertObjects:(NSArray *)insertObjects
                   updateObjects:(NSArray *)updateObjects
                   deleteObjects:(NSArray *)deleteObjects
{
    // 因为已经在write thread，所以此处只需调用到read thread
    [self performReadBlockAndWait:^{
        for (BLDBChangedObject *object in insertObjects) {
            [self.dbCache removeObjectForKey:[object.objectClass cacheKeyWithValueForObjectID:object.objectID]];
        }
        for (BLDBChangedObject *object in updateObjects) {
            [self.dbCache removeObjectForKey:[object.objectClass cacheKeyWithValueForObjectID:object.objectID]];
        }
        for (BLDBChangedObject *object in deleteObjects) {
            [self.dbCache removeObjectForKey:[object.objectClass cacheKeyWithValueForObjectID:object.objectID]];
        }
    }];
}

#pragma mark - BLDBCacheDelegate

- (void)cache:(BLDBCache *)cache willEvictObject:(BLDBCacheItem *)obj
{
    
}

@end
