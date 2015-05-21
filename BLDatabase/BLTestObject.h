//
//  BLTestObject.h
//  BLAlimeiDatabase
//
//  Created by alibaba on 15/1/29.
//  Copyright (c) 2015年 wxw. All rights reserved.
//

#import "BLBaseDBObject.h"

@interface BLTestObject : BLBaseDBObject

@property (nonatomic, copy) NSString *groupName;
@property (nonatomic, copy) NSString *name;
@property (nonatomic, assign) int age;

@end
