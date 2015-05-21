//
//  BLStoreManager.m
//  BLDatabase
//
//  Created by alibaba on 15/5/19.
//  Copyright (c) 2015年 wxw. All rights reserved.
//

#import "BLStoreManager.h"
#import "BLDatabase.h"
#import "BLDatabaseConnection.h"

static BLStoreManager *shareInstance = nil;

@implementation BLStoreManager

+ (id)shareInstance
{
    static dispatch_once_t once_t;
    dispatch_once(&once_t, ^{
        shareInstance = [[self alloc] init];
    });
    
    return shareInstance;
}

- (id)init
{
    self = [super init];
    if (self) {
        _mDatabase = [BLDatabase memoryDatabase];
        _mConnection = [_mDatabase newConnection];
        
        _database = [BLDatabase defaultDatabase];
        _connection = [_database newConnection];
        _connection1 = [_database newConnection];
    }
    
    return self;
}

@end
