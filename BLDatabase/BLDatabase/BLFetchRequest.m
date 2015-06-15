//
//  BLFetchedRequest.m
//  BLAlimeiDatabase
//
//  Created by alibaba on 15/1/29.
//  Copyright (c) 2015年 wxw. All rights reserved.
//

#import "BLFetchRequest.h"

@implementation BLFetchRequest

- (id)init
{
    self = [super init];
    if (self) {
        _fetchBatchSize = 50;
    }
    
    return self;
}

@end
