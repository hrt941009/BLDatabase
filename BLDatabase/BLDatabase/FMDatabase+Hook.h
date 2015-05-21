//
//  FMDatabase+Hook.h
//  HHPodDemo
//
//  Created by lingchen on 9/3/14.
//  Copyright (c) 2014 HH. All rights reserved.
//

#import "FMDB.h"

@interface FMDatabase (Hook)

@property (nonatomic, strong) NSNotificationCenter *notificationCenter;

- (void)registerNotification:(NSNotificationCenter *)notificationCenter;

- (void)removeNotification;

@end
