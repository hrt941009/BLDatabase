//
//  FMDatabase+Private.m
//  BLAlimeiDatabase
//
//  Created by alibaba on 15/4/10.
//  Copyright (c) 2015年 wxw. All rights reserved.
//

#import "FMDatabase+Private.h"

@implementation FMDatabase (Private)

- (sqlite3 *)sqlite
{
    return _db;
}

@end
