//
//  BLDatabase+Private.h
//  BLAlimeiDatabase
//
//  Created by alibaba on 15/2/11.
//  Copyright (c) 2015年 wxw. All rights reserved.
//

#import "BLDatabaseConnection.h"
#import "sqlite3.h"

@class BLDatabase, FMDatabase, BLDBCache;

@interface BLDatabaseConnection (Private)

- (instancetype)initWithDatabase:(BLDatabase *)database;

- (FMDatabase *)fmdb;
- (sqlite3 *)sqlite;
- (BLDBCache *)cachedObjects;
- (NSMutableArray *)changedObjects;
- (void)validateRead;
- (void)validateReadWriteInTransaction;

- (void)refreshWithInsertObjects:(NSArray *)insertObjects
                   updateObjects:(NSArray *)updateObjects
                   deleteObjects:(NSArray *)deleteObjects;

@end
