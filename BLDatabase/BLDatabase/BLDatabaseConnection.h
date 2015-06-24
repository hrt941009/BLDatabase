//
//  BLAlimeiDatabase.h
//  BLAlimeiDatabase
//
//  Created by alibaba on 15/1/21.
//  Copyright (c) 2015年 wxw. All rights reserved.
//

#import <Foundation/Foundation.h>

@class BLDatabase, BLBaseDBObject;

@interface BLDatabaseConnection : NSObject

@property (nonatomic, strong, readonly) BLDatabase *database;
@property (nonatomic, assign) NSUInteger cacheCountLimit; //default is 500;

- (instancetype)initWithDatabase:(BLDatabase *)database;

- (void)touchedObject:(id)object error:(NSError **)error;
- (void)touchedObjects:(id)objects error:(NSError **)error;

- (void)insertOrUpdateObject:(BLBaseDBObject *)object error:(NSError **)error;
- (void)insertOrUpdateObjects:(NSArray *)objects error:(NSError **)error;

- (void)insertObject:(BLBaseDBObject *)object error:(NSError **)error;
- (void)insertObjects:(NSArray *)objects error:(NSError **)error;

- (void)updateObject:(BLBaseDBObject *)object error:(NSError **)error;
- (void)updateObjects:(NSArray *)objects error:(NSError **)error;

- (void)deleteObject:(BLBaseDBObject *)object error:(NSError **)error;
- (void)deleteObjects:(NSArray *)objects error:(NSError **)error;

- (void)performReadBlockAndWait:(void(^)(void))block;
- (void)performReadBlock:(void(^)(void))block;

- (void)performReadWriteBlockAndWaitInTransaction:(void(^)(BOOL *rollback))block;
- (void)performReadWriteBlockInTransaction:(void(^)(BOOL *rollback))block;

@end
