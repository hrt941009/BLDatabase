//
//  BLDBChangedObject.m
//  BLAlimeiDatabase
//
//  Created by surewxw on 15/4/17.
//  Copyright (c) 2015年 wxw. All rights reserved.
//

#import "BLDBChangedObject.h"

@class BLBaseDBObject;

@interface BLDBChangedObject ()

@property (nonatomic, strong) BLBaseDBObject *object;

@end

@implementation BLDBChangedObject

@synthesize object = _object;

- (BLBaseDBObject *)object
{
    return _object;
}

- (void)setObject:(BLBaseDBObject *)object
{
    _object = object;
}

@end
