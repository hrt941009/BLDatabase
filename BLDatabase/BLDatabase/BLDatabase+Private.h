//
//  BLDatabase+Private.h
//  BLAlimeiDatabase
//
//  Created by surewxw on 15/5/11.
//  Copyright (c) 2015年 wxw. All rights reserved.
//

#import "BLDatabase.h"

@interface BLDatabase ()
{
  @public
    void                    *writeSpecificKey;
    dispatch_queue_t        writeQueue;
}

@end
