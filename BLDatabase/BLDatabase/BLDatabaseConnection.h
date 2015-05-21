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

- (void)performBlockAndWaitInTransaction:(void(^)(BOOL *rollback))block;

@end
