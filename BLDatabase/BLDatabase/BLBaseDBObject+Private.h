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

+ (void)commitChangedNotificationInConnection:(BLDatabaseConnection *)connection;

+ (void)rollbackChangedNotificationInConnection:(BLDatabaseConnection *)connection;

+ (NSString *)cacheKeyWithUniqueId:(NSString *)uniqueId;

- (void)setRowid:(int64_t)rowid;

#pragma mark - touched object

- (void)touchedInConnection:(BLDatabaseConnection *)connection;

#pragma mark - insert/update/delete

- (void)insertOrUpdateInConnection:(BLDatabaseConnection *)connection;
- (void)insertInConnection:(BLDatabaseConnection *)connection;
- (void)updateInConnection:(BLDatabaseConnection *)connection;
- (void)deleteInConnection:(BLDatabaseConnection *)connection;

@end
