//
//  BLDatabaseConfig.h
//  BLAlimeiDatabase
//
//  Created by surewxw on 15/3/15.
//  Copyright (c) 2015年 wxw. All rights reserved.
//

#ifndef BLAlimeiDatabase_BLDatabaseConfig_h
#define BLAlimeiDatabase_BLDatabaseConfig_h

#define    BLDatabaseLogModeNone            0
#define    BLDatabaseLogModeVerbose         1
#define    BLDatabaseLogModeDebug           2
#define    BLDatabaseLogModeInfo            3
#define    BLDatabaseLogModeWarn            4
#define    BLDatabaseLogModeError           5

#ifdef DEBUG
#define     LogMode     BLDatabaseLogModeInfo
#else
#define     LogMode     BLDatabaseLogModeNone
#endif

#if LogMode <= BLDatabaseLogModeError
#define BLLogError( s, ... ) NSLog( @"<%p %@:(%d)> [ERROR] %@", self, [[NSString stringWithUTF8String:__FILE__] lastPathComponent], __LINE__, [NSString stringWithFormat:(s), ##__VA_ARGS__] )
#else
#define BLLogError( s, ... )
#endif

#if LogMode <= BLDatabaseLogModeWarn
#define BLLogWarn( s, ... ) NSLog( @"<%p %@:(%d)> [WARN] %@", self, [[NSString stringWithUTF8String:__FILE__] lastPathComponent], __LINE__, [NSString stringWithFormat:(s), ##__VA_ARGS__] )
#else
#define BLLogWarn( s, ... )
#endif

#if LogMode <= BLDatabaseLogModeInfo
#define BLLogInfo( s, ... ) NSLog( @"<%p %@:(%d)> [INFO] %@", self, [[NSString stringWithUTF8String:__FILE__] lastPathComponent], __LINE__, [NSString stringWithFormat:(s), ##__VA_ARGS__] )
#else
#define BLLogInfo( s, ... )
#endif

#if LogMode <= BLDatabaseLogModeDebug
#define BLLogDebug( s, ... ) NSLog( @"<%p %@:(%d)> [DEBUG] %@", self, [[NSString stringWithUTF8String:__FILE__] lastPathComponent], __LINE__, [NSString stringWithFormat:(s), ##__VA_ARGS__] )
#else
#define BLLogDebug( s, ... )
#endif

#if LogMode <= BLDatabaseLogModeVerbose
#define BLLogVerbose( s, ... ) NSLog( @"<%p %@:(%d)> [VERBOSE] %@", self, [[NSString stringWithUTF8String:__FILE__] lastPathComponent], __LINE__, [NSString stringWithFormat:(s), ##__VA_ARGS__] )
#else
#define BLLogVerbose( s, ... )
#endif

#endif
