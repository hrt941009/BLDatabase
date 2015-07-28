//
//  BLBaseDBObject+Private.h
//  BLAlimeiDatabase
//
//  Created by surewxw on 15/1/26.
//  Copyright (c) 2015年 wxw. All rights reserved.
//

#import "BLBaseDBObject.h"

@class BLDatabaseConnection, FMDatabaseQueue;

@interface BLBaseDBObject (Private)

+ (void)commitChangedNotificationInConnection:(BLDatabaseConnection *)connection;

+ (void)rollbackChangedNotificationInConnection:(BLDatabaseConnection *)connection;

+ (NSString *)cacheKeyWithUniqueId:(NSString *)uniqueId;

#pragma mark - touched/insert/update/delete object/objects

- (void)touchedInConnection:(BLDatabaseConnection *)connection
                      error:(NSError **)error;
+ (void)touchedObjects:(NSArray *)objects
          inConnection:(BLDatabaseConnection *)connection
                 error:(NSError **)error;

- (void)insertOrUpdateInConnection:(BLDatabaseConnection *)connection
                             error:(NSError **)error;
+ (void)insertOrUpdateObjects:(NSArray *)objects
                 inConnection:(BLDatabaseConnection *)connection
                        error:(NSError **)error;

- (void)insertInConnection:(BLDatabaseConnection *)connection
                     error:(NSError **)error;
+ (void)insertObjects:(NSArray *)objects
         inConnection:(BLDatabaseConnection *)connection
                error:(NSError **)error;

- (void)updateInConnection:(BLDatabaseConnection *)connection
                     error:(NSError **)error;
+ (void)updateObjects:(NSArray *)objects
         inConnection:(BLDatabaseConnection *)connection
                error:(NSError **)error;

- (void)deleteInConnection:(BLDatabaseConnection *)connection
                     error:(NSError **)error;
+ (void)deleteObjects:(NSArray *)objects
         inConnection:(BLDatabaseConnection *)connection
                error:(NSError **)error;

@end
