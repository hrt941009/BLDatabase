//
//  BLAlimeiDatabase.h
//  BLAlimeiDatabase
//
//  Created by alibaba on 15/1/21.
//  Copyright (c) 2015年 wxw. All rights reserved.
//

#import <Foundation/Foundation.h>

typedef NS_ENUM(NSInteger, BLDatabaseConnectionType)
{
    BLMainQueueDatabaseConnectionType = 0,
    BLPrivateQueueDatabaseConnectionType = 1,
};

@class BLDatabase, BLBaseDBObject;

@interface BLDatabaseConnection : NSObject

@property (nonatomic, strong, readonly) BLDatabase *database;
@property (nonatomic, assign) NSUInteger cacheCountLimit; //default is 500;
@property (nonatomic, assign, readonly) BLDatabaseConnectionType type; //default is 500;

// type is BLPrivateQueueDatabaseConnectionType
- (instancetype)initWithDatabase:(BLDatabase *)database;
- (instancetype)initWithDatabase:(BLDatabase *)database withType:(BLDatabaseConnectionType)type;

- (void)touchedObject:(id)object;
- (void)touchedObjects:(id)objects;

- (void)insertOrUpdateObject:(BLBaseDBObject *)object;
- (void)insertOrUpdateObjects:(NSArray *)objects;

- (void)insertObject:(BLBaseDBObject *)object;
- (void)insertObjects:(NSArray *)objects;

- (void)updateObject:(BLBaseDBObject *)object;
- (void)updateObjects:(NSArray *)objects;

- (void)deleteObject:(BLBaseDBObject *)object;
- (void)deleteObjects:(NSArray *)objects;

- (void)performReadBlockAndWait:(void(^)(void))block;
- (void)performReadBlock:(void(^)(void))block;

- (void)performReadWriteBlockAndWaitInTransaction:(void(^)(BOOL *rollback))block;
- (void)performReadWriteBlockInTransaction:(void(^)(BOOL *rollback))block;

@end
