//
//  FMDatabase+Hook.h
//  HHPodDemo
//
//  Created by lingchen on 9/3/14.
//  Copyright (c) 2014 HH. All rights reserved.
//

#import "FMDB.h"

extern NSString * const kSQLTableInsertNotification;
extern NSString * const kSQLTableUpdateNotification;
extern NSString * const kSQLTableDeleteNotification;

extern NSString * const kSQLRowIDKey;
extern NSString * const kSQLDatabaseNameKey;
extern NSString * const kSQLTableNameKey;

extern NSString * const kSQLTransactionCommitNotification;
extern NSString * const kSQLTransactionRollbackNotification;

@interface FMDatabase (Hook)

@property (nonatomic, strong) NSNotificationCenter *notificationCenter;

- (void)registerNotification:(NSNotificationCenter *)notificationCenter;

- (void)removeNotification;

@end
