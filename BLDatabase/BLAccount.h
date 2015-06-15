//
//  BLAccount.h
//  BLAlimeiDatabase
//
//  Created by alibaba on 15/3/16.
//  Copyright (c) 2015年 wxw. All rights reserved.
//

#import "BLBaseDBObject.h"

BL_ARRAY_TYPE(BLAccount);

@interface BLAccount : BLBaseDBObject

@property (nonatomic, copy) NSString *accessToken;
@property (nonatomic, copy) NSString *userId;
@property (nonatomic, copy) NSString *nickname;

@property (nonatomic, strong) BLAccount *relationship;
@property (nonatomic, copy) NSString *relationshipId;

@property (nonatomic, strong) NSArray<BLAccount> *relationships;
@property (nonatomic, copy) NSArray *relationshipsIds;

@end
