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

@interface BLDatabaseConnection ()
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
    self = [super init];
    if (self) {
        _database = database;
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
        
        self->readQueue = dispatch_queue_create("com.database.read", DISPATCH_QUEUE_SERIAL);
        dispatch_queue_set_specific(self->readQueue,
                                    &self->readSpecificKey,
                                    (__bridge void *)self,
                                    NULL);
        
        _dbCache = [BLDBCache new];
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
    [self performReadWriteBlockAndWait:^{
        _cacheCountLimit = cacheCountLimit;
        _dbCache.countLimit = cacheCountLimit;
    }];
}

#pragma mark - perform block

- (void)performReadBlockAndWait:(void(^)(void))block
{
    dispatch_block_t newBlock = ^{
        if (block) {
            block();
        }
    };
    
    /*
     dispatch_sync(readQueue, ...) {
        dispatch_sync(writeQueue, ...) {
        }
     }
     */

    void *context1 = dispatch_get_specific(&self->readSpecificKey);
    void *context2 = dispatch_get_specific(&self.database->writeSpecificKey);
    
    if (context1 || context2) {
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
    
    /*
     dispatch_sync(readQueue, ...) {
        dispatch_sync(writeQueue, ...) {
        }
     }
     */
    void *context1 = dispatch_get_specific(&self->readSpecificKey);
    void *context2 = dispatch_get_specific(&self.database->writeSpecificKey);
    
    if (context1 || context2) {
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
        void *context = dispatch_get_specific(&self.database->writeSpecificKey);
        
        if (context) {
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
        void *context = dispatch_get_specific(&self.database->writeSpecificKey);
        
        if (context) {
            newBlock();
        } else {
            dispatch_sync(self.database->writeQueue, ^{
                newBlock();
            });
        }
    }];
}

#pragma mark - public

- (void)validateInTransaction
{
    BOOL inTransaction = [self.fmdb inTransaction];
    if (!inTransaction) {
        BLLogError(@"you must be excute in performBlockAndWaitInTransaction or in performBlockInTransaction");
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
    [self validateInTransaction];
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
    [self validateInTransaction];
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
    [self validateInTransaction];
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
    [self validateInTransaction];
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
    [self validateInTransaction];
    for (id object in objects) {
        [object deleteInDatabaseConnection:self];
    }
}

- (void)performBlockAndWaitInTransaction:(void(^)(BOOL *rollback))block;
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

- (void)performBlockInTransaction:(void(^)(BOOL *rollback))block
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

@end
