//
//  FMDatabase+Hook.m
//  HHPodDemo
//
//  Created by lingchen on 9/3/14.
//  Copyright (c) 2014 HH. All rights reserved.
//

#import "FMDatabase+Hook.h"
#import <objc/runtime.h>

NSString * const kSQLTableInsertNotification = @"SQLTableInsertNotification";
NSString * const kSQLTableUpdateNotification = @"SQLTableUpdateNotification";
NSString * const kSQLTableDeleteNotification = @"SQLTableDeleteNotification";

NSString * const kSQLRowIDKey = @"SQLRowIDKey";
NSString * const kSQLDatabaseNameKey = @"SQLDatabaseNameKey";
NSString * const kSQLTableNameKey = @"SQLTableNameKey";

NSString * const kSQLTransactionCommitNotification = @"SQLTransactionCommitNotification";
NSString * const kSQLTransactionRollbackNotification = @"SQLTransactionRollbackNotification";

#pragma mark -

void sqldatabase_update_hook(void *object, int type, char const *database, char const *table, sqlite3_int64 rowID);
int sqldatabase_commit_hook(void *object);
void sqldatabase_rollback_hook(void *object);

void sqldatabase_update_hook(void *object, int type, char const *databaseName, char const *tableName, sqlite3_int64 rowID)
{
    FMDatabase *database = (__bridge FMDatabase *)object;
    NSCAssert([database isKindOfClass:[FMDatabase class]] == YES, @"Invalid kind of class.");
    NSString *notificationName = nil;
    
    switch ( type )
    {
        case SQLITE_INSERT:
        {
            notificationName = kSQLTableInsertNotification;
            break;
        }
        case SQLITE_UPDATE:
        {
            notificationName = kSQLTableUpdateNotification;
            break;
        }
        case SQLITE_DELETE:
        {
            notificationName = kSQLTableDeleteNotification;
            break;
        }
        default:
        {
            NSLog(@"Cannot determine the type of the update, call ignored (database = %s, table = %s, type = %d).", databaseName, tableName, type);
        }
    }
    if ( notificationName != nil )
    {
        NSDictionary *userInfoDict = [NSDictionary dictionaryWithObjectsAndKeys:
                                      [NSNumber numberWithLongLong:rowID], kSQLRowIDKey,
                                      [NSString stringWithUTF8String:databaseName], kSQLDatabaseNameKey,
                                      [NSString stringWithUTF8String:tableName], kSQLTableNameKey,
                                      nil];
        
        NSLog(@"Posts notification '%@'.", notificationName);
        [database.notificationCenter postNotificationName:notificationName object:database userInfo:userInfoDict];
    }
}

int sqldatabase_commit_hook(void *object)
{
    FMDatabase *database = (__bridge FMDatabase *)object;
    NSCAssert([database isKindOfClass:[FMDatabase class]] == YES, @"Invalid kind of class.");
    
    NSLog(@"Posts notification '%@'.", kSQLTransactionCommitNotification);
    [database.notificationCenter postNotificationName:kSQLTransactionCommitNotification object:database];
    return 0;
}

void sqldatabase_rollback_hook(void *object)
{
    FMDatabase *database = (__bridge FMDatabase *)object;
    NSCAssert([database isKindOfClass:[FMDatabase class]] == YES, @"Invalid kind of class.");
    
    NSLog(@"Posts notification '%@'.", kSQLTransactionRollbackNotification);
    [database.notificationCenter postNotificationName:kSQLTransactionRollbackNotification object:database];
}

@implementation FMDatabase (Hook)


- (NSNotificationCenter *)notificationCenter
{
    return objc_getAssociatedObject(self, @"kNotificationCenter");
}

- (void)setNotificationCenter:(NSNotificationCenter *)notificationCenter_
{
    objc_setAssociatedObject(self,
                             @"kNotificationCenter",
                             notificationCenter_,
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

- (void)registerNotification:(NSNotificationCenter *)notificationCenter __attribute__ ((nonnull(1)));
{
    if ( self.notificationCenter != nil )
    {
        if ( [self.notificationCenter isEqual:notificationCenter] == YES )
        {
            return;
        }
        [self removeNotification];
    }
    self.notificationCenter = notificationCenter;
    sqlite3_update_hook([self sqliteHandle], &sqldatabase_update_hook, (__bridge void *)(self));
    sqlite3_commit_hook([self sqliteHandle], &sqldatabase_commit_hook, (__bridge void *)(self));
    sqlite3_rollback_hook([self sqliteHandle], &sqldatabase_rollback_hook, (__bridge void *)(self));
}

- (void)removeNotification;
{
    if ( self.notificationCenter != nil )
    {
        sqlite3_update_hook([self sqliteHandle], NULL, NULL);
        sqlite3_commit_hook([self sqliteHandle], NULL, NULL);
        sqlite3_rollback_hook([self sqliteHandle], NULL, NULL);
        self.notificationCenter = nil;
    }
}

@end
