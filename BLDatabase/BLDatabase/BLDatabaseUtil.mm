//
//  BLDatabaseUtil.cpp
//  BLAlimeiDatabase
//
//  Created by surewxw on 15/4/28.
//  Copyright (c) 2015年 wxw. All rights reserved.
//

#import "BLDatabaseUtil.h"

NSString * const BLDatabaseExceptionName = @"BLDatabaseExceptionName";
NSString * const BLDatabaseErrorDomain = @"BLDatabaseErrorDomain";

const NSInteger BLDatabaseErrorCode = 0;

NSError *BLDatabaseError(NSString *message)
{
    return [NSError errorWithDomain:BLDatabaseErrorDomain
                               code:BLDatabaseErrorCode
                           userInfo:@{@"message" : (message ? message : @"")}];
}