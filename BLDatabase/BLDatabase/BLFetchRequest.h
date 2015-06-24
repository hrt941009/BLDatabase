//
//  BLFetchedRequest.h
//  BLAlimeiDatabase
//
//  Created by alibaba on 15/1/29.
//  Copyright (c) 2015年 wxw. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface BLFetchRequest : NSObject

@property (nonatomic, copy) NSString *sqlAfterWhere;
@property (nonatomic, strong) NSPredicate *predicate;
@property (nonatomic, strong) NSArray *fieldNames;

// 下面二选一
@property (nonatomic, strong) NSArray *sortDescriptors;
// sortTerm eg:"rowid:1,uuid:0", 1 asc 0 desc, @"rowid" mean rowid desc
@property (nonatomic, copy) NSString *sortTerm;


@end
