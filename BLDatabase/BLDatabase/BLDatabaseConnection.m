//
//  BLAlimeiDatabase.m
//  BLAlimeiDatabase
//
//  Created by surewxw on 15/1/21.
//  Copyright (c) 2015年 wxw. All rights reserved.
//

#import "BLDatabaseConnection.h"
#import "BLDatabase.h"
#import "BLDatabase+Private.h"
#import "BLBaseDBObject.h"
#import "BLBaseDBObject+Private.h"
#import "BLDBCache.h"
#import "BLDatabaseConfig.h"
#import "BLDBChangedObject.h"
#import "FMDB.h"
#import "FMDatabase+Hook.h"

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
    self = [super init];
    if (self) {
        _database = database;
        _fmdb = [[FMDatabase alloc] initWithPath:database.databasePath];
        int flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_NOMUTEX | SQLITE_OPEN_PRIVATECACHE;
        [_fmdb openWithFlags:flags];
        
        int status;
        
        sqlite3_config(SQLITE_CONFIG_SINGLETHREAD);
        
        status = sqlite3_exec(_fmdb.sqliteHandle, "PRAGMA journal_mode = WAL;", NULL, NULL, NULL);
        if (status != SQLITE_OK) {
            BLLogError(@"Error setting PRAGMA journal_mode: %d %s", status, sqlite3_errmsg(_fmdb.sqliteHandle));
        }
        
        sqlite3_wal_checkpoint(_fmdb.sqliteHandle, NULL);
        
        self->readQueue = dispatch_queue_create("com.database.read", DISPATCH_QUEUE_SERIAL);
        dispatch_queue_set_specific(self->readQueue,
                                    &self->readSpecificKey,
                                    (__bridge void *)self,
                                    NULL);
        
        _dbCache = [BLDBCache new];
        _dbCache.delegate = self;
        _cacheCountLimit = 500;
        _dbCache.countLimit = _cacheCountLimit;
        _changedObjects = [NSMutableArray array];
        
        //[_fmdb registerNotification:[NSNotificationCenter defaultCenter]];
        //[self addDatabaseObserver];
    }
    
    return self;
}

#pragma mark - life cycle

- (void)dealloc
{
    [self removeDatabaseObserver];
}

#pragma mark - getter & private

- (FMDatabase *)fmdb
{
    return _fmdb;
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
    void(^block)(void) = ^(void){
        _cacheCountLimit = cacheCountLimit;
        _dbCache.countLimit = cacheCountLimit;
    };
    
    if ([self isInWriteQueue]) {
        block();
    } else {
        [self performReadBlockAndWait:^{
            block();
        }];
    }
}

#pragma mark - perform block

- (BOOL)isInReadQueue
{
    void *context = dispatch_get_specific(&self->readSpecificKey);
    BOOL hasContext = context ? YES : NO;
    
    return hasContext;
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
        NSAssert(false, @"you must be excute in read queue");
    }
}

- (void)validateReadWriteInTransaction
{
    BOOL inTransaction = [self.fmdb inTransaction];
    if (!inTransaction || ![self isInWriteQueue]) {
        NSAssert(false, @"you must be excute in write queue and in transaction");
    }
}

- (void)touchedObject:(id)object error:(NSError **)error
{
    if (object) {
        [self touchedObjects:@[object] error:error];
    }
}

- (void)touchedObjects:(id)objects error:(NSError **)error
{
    [BLBaseDBObject touchedObjects:objects inConnection:self error:error];
}

- (void)insertOrUpdateObject:(BLBaseDBObject *)object error:(NSError **)error
{
    if (object) {
        [self insertOrUpdateObjects:@[object] error:error];
    }
}

- (void)insertOrUpdateObjects:(NSArray *)objects error:(NSError **)error
{
    [BLBaseDBObject insertOrUpdateObjects:objects inConnection:self error:error];
}

- (void)insertObject:(id)object error:(NSError **)error
{
    if (object) {
        [self insertObjects:@[object] error:error];
    }
}

- (void)insertObjects:(NSArray *)objects error:(NSError **)error
{
    [BLBaseDBObject insertObjects:objects inConnection:self error:error];
}

- (void)updateObject:(BLBaseDBObject *)object error:(NSError **)error
{
    if (object) {
        [self updateObjects:@[object] error:error];
    }
}

- (void)updateObjects:(NSArray *)objects error:(NSError **)error
{
    [BLBaseDBObject updateObjects:objects inConnection:self error:error];
}

- (void)deleteObject:(id)object error:(NSError **)error
{
    if (object) {
        [self deleteObjects:@[object] error:error];
    }
}

- (void)deleteObjects:(NSArray *)objects error:(NSError **)error
{
    [BLBaseDBObject deleteObjects:objects inConnection:self error:error];
}

- (void)beginTransaction
{
    [self.fmdb beginTransaction];
}

- (void)commit
{
    [self.fmdb commit];
    [BLBaseDBObject commitChangedNotificationInConnection:self];
}

- (void)rollback
{
    [self.fmdb rollback];
    [BLBaseDBObject rollbackChangedNotificationInConnection:self];
}

#pragma mark - refresh

- (void)refreshWithInsertObjects:(NSArray *)insertObjects
                   updateObjects:(NSArray *)updateObjects
                   deleteObjects:(NSArray *)deleteObjects
{
    [self performReadBlock:^{
//        for (BLDBChangedObject *object in insertObjects) {
//            [self.dbCache removeObjectForKey:[BLBaseDBObject cacheKeyWithUniqueId:object.uniqueId]];
//        }
        
        for (BLDBChangedObject *object in updateObjects) {
            [self.dbCache removeObjectForKey:[BLBaseDBObject cacheKeyWithUniqueId:object.uniqueId]];
        }
        
        for (BLDBChangedObject *object in deleteObjects) {
            [self.dbCache removeObjectForKey:[BLBaseDBObject cacheKeyWithUniqueId:object.uniqueId]];
        }
    }];
}

#pragma mark - DB notification

- (void)addDatabaseObserver
{
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(insertObjectNotification:)
                                                 name:kSQLTableInsertNotification
                                               object:_fmdb];
    
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(updateObjectNotification:)
                                                 name:kSQLTableUpdateNotification
                                               object:_fmdb];
    
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(deleteObjectNotification:)
                                                 name:kSQLTableUpdateNotification
                                               object:_fmdb];
    
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(commitNotification:)
                                                 name:kSQLTransactionCommitNotification
                                               object:_fmdb];
    
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(rollbackNotification:)
                                                 name:kSQLTransactionRollbackNotification
                                               object:_fmdb];
}

- (void)removeDatabaseObserver
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)insertObjectNotification:(NSNotification *)notification
{
    //NSNumber *rowid = [notification userInfo][kSQLRowIDKey];
    NSString *tableName = [notification userInfo][kSQLTableNameKey];
    //NSString *dbName = [notification userInfo][kSQLDatabaseNameKey];
    
    BLDBChangedObject *object = [BLDBChangedObject new];
    //object.rowid = [rowid longLongValue];
    object.tableName = tableName;
    object.type = BLDBChangedObjectInsert;
    
    [self.changedObjects addObject:object];
}

- (void)updateObjectNotification:(NSNotification *)notification
{
    //NSNumber *rowid = [notification userInfo][kSQLRowIDKey];
    NSString *tableName = [notification userInfo][kSQLTableNameKey];
    //NSString *dbName = [notification userInfo][kSQLDatabaseNameKey];
    
    BLDBChangedObject *object = [BLDBChangedObject new];
    //object.rowid = [rowid longLongValue];
    object.tableName = tableName;
    object.type = BLDBChangedObjectUpdate;
    
    [self.changedObjects addObject:object];
}

- (void)deleteObjectNotification:(NSNotification *)notification
{
    //NSNumber *rowid = [notification userInfo][kSQLRowIDKey];
    NSString *tableName = [notification userInfo][kSQLTableNameKey];
    //NSString *dbName = [notification userInfo][kSQLDatabaseNameKey];
    
    BLDBChangedObject *object = [BLDBChangedObject new];
    //object.rowid = [rowid longLongValue];
    object.tableName = tableName;
    object.type = BLDBChangedObjectDelete;
    
    [self.changedObjects addObject:object];
}

-(void)commitNotification:(NSNotification *)notification
{
    [BLBaseDBObject commitChangedNotificationInConnection:self];
}

-(void)rollbackNotification:(NSNotification *)notification
{
    [BLBaseDBObject rollbackChangedNotificationInConnection:self];
}

#pragma mark - BLDBCacheDelegate

- (void)cache:(BLDBCache *)cache willEvictObject:(BLDBCacheItem *)obj
{
    
}

@end
