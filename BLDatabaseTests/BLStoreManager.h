//
//  BLStoreManager.h
//  BLDatabase
//
//  Created by alibaba on 15/5/19.
//  Copyright (c) 2015年 wxw. All rights reserved.
//

#import <Foundation/Foundation.h>

@class BLDatabase, BLDatabaseConnection;

@interface BLStoreManager : NSObject

@property (nonatomic, strong) BLDatabase *mDatabase;
@property (nonatomic, strong) BLDatabaseConnection *mConnection;

@property (nonatomic, strong) BLDatabase *database;
@property (nonatomic, strong) BLDatabaseConnection *connection;
@property (nonatomic, strong) BLDatabaseConnection *connection1;

+ (id)shareInstance;

@end
