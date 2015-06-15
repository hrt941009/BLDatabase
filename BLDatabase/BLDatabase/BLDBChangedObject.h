//
//  BLDBChangedObject.h
//  BLAlimeiDatabase
//
//  Created by alibaba on 15/4/17.
//  Copyright (c) 2015年 wxw. All rights reserved.
//

#import <Foundation/Foundation.h>

typedef NS_ENUM(NSUInteger, BLDBChangedObjectType) {
    BLDBChangedObjectInsert = 1,
    BLDBChangedObjectDelete = 2,
    BLDBChangedObjectUpdate = 3
};

@interface BLDBChangedObject : NSObject

@property (nonatomic, copy) NSString *uniqueId;
//@property (nonatomic, assign) int64_t rowid;
@property (nonatomic, copy) NSString *tableName;
@property (nonatomic, strong) Class objectClass;
@property (nonatomic, copy) NSArray *changedFiledNames; // just for update
@property (nonatomic, assign) BLDBChangedObjectType type;

@end
