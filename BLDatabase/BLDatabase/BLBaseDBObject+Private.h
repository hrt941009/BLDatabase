//
//  BLBaseDBObject+Private.h
//  BLAlimeiDatabase
//
//  Created by alibaba on 15/1/26.
//  Copyright (c) 2015年 wxw. All rights reserved.
//

#import "BLBaseDBObject.h"

@class BLDatabaseConnection, FMDatabaseQueue;

@interface BLBaseDBObject (Private)

+ (void)beginChangedNotificationInDatabaseConnection:(BLDatabaseConnection *)databaseConnection;

+ (void)endChangedNotificationInDatabaseConnection:(BLDatabaseConnection *)databaseConnection;

+ (void)rollbackChangedNotificationInDatabaseConnection:(BLDatabaseConnection *)databaseConnection;

+ (NSString *)cacheKeyWithValueForObjectID:(NSString *)valueForObjectID;

#pragma mark - touched object

- (void)touchedInDatabaseConnection:(BLDatabaseConnection *)databaseConnection;

#pragma mark - insert/update/delete

- (void)insertOrUpdateInDatabaseConnection:(BLDatabaseConnection *)databaseConnection;
- (void)insertInDatabaseConnection:(BLDatabaseConnection *)databaseConnection;
- (void)updateInDatabaseConnection:(BLDatabaseConnection *)databaseConnection;
- (void)deleteInDatabaseConnection:(BLDatabaseConnection *)databaseConnection;

@end
