//
//  BLBaseDBObject+Find.h
//  BLAlimeiDatabase
//
//  Created by alibaba on 15/4/10.
//  Copyright (c) 2015年 wxw. All rights reserved.
//

#import "BLBaseDBObject.h"

@interface BLBaseDBObject (Common)

+ (void)createTableAndIndexIfNeededInConnection:(BLDatabaseConnection *)connection;

+ (void)addColumnName:(NSString *)columnName
         inConnection:(BLDatabaseConnection *)connection;

+ (void)addColumnNames:(NSArray *)columnNames
          inConnection:(BLDatabaseConnection *)connection;

+ (void)addColumnName:(NSString *)columnName
         defaultValue:(id)defaultValue
         inConnection:(BLDatabaseConnection *)connection;

+ (void)addColumnNameAndValues:(NSDictionary *)columnNameAndValues
                  inConnection:(BLDatabaseConnection *)connection;

+ (void)deleteColumnName:(NSString *)columnName
            inConnection:(BLDatabaseConnection *)connection;

+ (void)deleteColumnNames:(NSArray *)columnNames
             inConnection:(BLDatabaseConnection *)connection;

+ (void)createIndexWithColumnName:(NSString *)columnName
                     inConnection:(BLDatabaseConnection *)connection;

+ (void)createIndexWithColumnNames:(NSArray *)columnNames
                      inConnection:(BLDatabaseConnection *)connection;

+ (void)createUnionIndexWithColumnNames:(NSArray *)columnNames
                           inConnection:(BLDatabaseConnection *)connection;

+ (void)dropIndexWithColumnName:(NSString *)columnName
                   inConnection:(BLDatabaseConnection *)connection;

+ (void)dropIndexWithColumnNames:(NSArray *)columnNames
                    inConnection:(BLDatabaseConnection *)connection;

+ (void)dropUnionIndexWithColumnNames:(NSArray *)columnNames
                         inConnection:(BLDatabaseConnection *)connection;

#pragma mark - find count

+ (int64_t)numberOfObjectsInConnection:(BLDatabaseConnection *)connection;

+ (int64_t)numberOfObjectsInConnection:(BLDatabaseConnection *)connection
                                 where:(NSString *)where, ...;

#pragma mark - find object with sql

+ (id)findFirstObjectInConnection:(BLDatabaseConnection *)connection
                            rowid:(int64_t)rowid;

+ (id)findFirstObjectInConnection:(BLDatabaseConnection *)connection
                         uniqueId:(NSString *)uniqueId;

+ (id)findFirstObjectInConnection:(BLDatabaseConnection *)connection
               valueForPrimaryKey:(NSString *)value;

+ (id)findFirstObjectInConnection:(BLDatabaseConnection *)connection
                            where:(NSString *)where, ...;

+ (id)findFirstObjectInConnection:(BLDatabaseConnection *)connection
                          orderBy:(NSString *)orderBy
                            where:(NSString *)where, ...;

+ (id)findFirstObjectInConnection:(BLDatabaseConnection *)connection
                       fieldNames:(NSArray *)fieldNames
                            rowid:(int64_t)rowid;

+ (id)findFirstObjectInConnection:(BLDatabaseConnection *)connection
                       fieldNames:(NSArray *)fieldNames
                         uniqueId:(NSString *)uniqueId;

+ (id)findFirstObjectInConnection:(BLDatabaseConnection *)connection
                       fieldNames:(NSArray *)fieldNames
               valueForPrimaryKey:(NSString *)value;

+ (id)findFirstObjectInConnection:(BLDatabaseConnection *)connection
                       fieldNames:(NSArray *)fieldNames
                            where:(NSString *)where, ...;

+ (id)findFirstObjectInConnection:(BLDatabaseConnection *)connection
                       fieldNames:(NSArray *)fieldNames
                          orderBy:(NSString *)orderBy
                            where:(NSString *)where, ...;

#pragma mark - find objects with sql

+ (NSArray *)findObjectsInConnection:(BLDatabaseConnection *)connection;

+ (NSArray *)findObjectsInConnection:(BLDatabaseConnection *)connection
                             orderBy:(NSString *)orderBy;

+ (NSArray *)findObjectsInConnection:(BLDatabaseConnection *)connection
                               where:(NSString *)where, ...;

+ (NSArray *)findObjectsInConnection:(BLDatabaseConnection *)connection
                             orderBy:(NSString *)orderBy
                               where:(NSString *)where, ...;

+ (NSArray *)findObjectsInConnection:(BLDatabaseConnection *)connection
                             orderBy:(NSString *)orderBy
                              length:(u_int64_t)length
                              offset:(u_int64_t)offset
                               where:(NSString *)where, ...;

+ (NSArray *)findObjectsInConnection:(BLDatabaseConnection *)connection
                          fieldNames:(NSArray *)fieldNames;

+ (NSArray *)findObjectsInConnection:(BLDatabaseConnection *)connection
                          fieldNames:(NSArray *)fieldNames
                             orderBy:(NSString *)orderBy;

+ (NSArray *)findObjectsInConnection:(BLDatabaseConnection *)connection
                          fieldNames:(NSArray *)fieldNames
                               where:(NSString *)where, ...;

+ (NSArray *)findObjectsInConnection:(BLDatabaseConnection *)connection
                          fieldNames:(NSArray *)fieldNames
                             orderBy:(NSString *)orderBy
                               where:(NSString *)where, ...;

+ (NSArray *)findObjectsInConnection:(BLDatabaseConnection *)connection
                          fieldNames:(NSArray *)fieldNames
                             orderBy:(NSString *)orderBy
                              length:(u_int64_t)length
                              offset:(u_int64_t)offset
                               where:(NSString *)where, ...;

#pragma mark - find object with predicate

+ (id)findFirstObjectInConnection:(BLDatabaseConnection *)connection
                        predicate:(NSPredicate *)predicate;

// sortTerm eg:"rowid:1,uuid:0", 1 asc 0 desc, @"rowid" mean rowid desc
+ (id)findFirstObjectInConnection:(BLDatabaseConnection *)connection
                        predicate:(NSPredicate *)predicate
                         sortTerm:(NSString *)sortTerm;

+ (id)findFirstObjectInConnection:(BLDatabaseConnection *)connection
                        predicate:(NSPredicate *)predicate
                  sortDescriptors:(NSArray *)sortDescriptors;

+ (id)findFirstObjectInConnection:(BLDatabaseConnection *)connection
                        predicate:(NSPredicate *)predicate
                       fieldNames:(NSArray *)fieldNames;

+ (id)findFirstObjectInConnection:(BLDatabaseConnection *)connection
                        predicate:(NSPredicate *)predicate
                       fieldNames:(NSArray *)fieldNames
                         sortTerm:(NSString *)sortTerm;

+ (id)findFirstObjectInConnection:(BLDatabaseConnection *)connection
                        predicate:(NSPredicate *)predicate
                       fieldNames:(NSArray *)fieldNames
                  sortDescriptors:(NSArray *)sortDescriptors;

#pragma mark - find objects with predicate

+ (NSArray *)findObjectsInConnection:(BLDatabaseConnection *)connection
                           predicate:(NSPredicate *)predicate;

+ (NSArray *)findObjectsInConnection:(BLDatabaseConnection *)connection
                           predicate:(NSPredicate *)predicate
                            sortTerm:(NSString *)sortTerm;

+ (NSArray *)findObjectsInConnection:(BLDatabaseConnection *)connection
                           predicate:(NSPredicate *)predicate
                     sortDescriptors:(NSArray *)sortDescriptors;

+ (NSArray *)findObjectsInConnection:(BLDatabaseConnection *)connection
                           predicate:(NSPredicate *)predicate
                            sortTerm:(NSString *)sortTerm
                              length:(u_int64_t)length
                              offset:(u_int64_t)offset;

+ (NSArray *)findObjectsInConnection:(BLDatabaseConnection *)connection
                           predicate:(NSPredicate *)predicate
                     sortDescriptors:(NSArray *)sortDescriptors
                              length:(u_int64_t)length
                              offset:(u_int64_t)offset;

+ (NSArray *)findObjectsInConnection:(BLDatabaseConnection *)connection
                           predicate:(NSPredicate *)predicate
                          fieldNames:(NSArray *)fieldNames;

+ (NSArray *)findObjectsInConnection:(BLDatabaseConnection *)connection
                           predicate:(NSPredicate *)predicate
                          fieldNames:(NSArray *)fieldNames
                            sortTerm:(NSString *)sortTerm;

+ (NSArray *)findObjectsInConnection:(BLDatabaseConnection *)connection
                           predicate:(NSPredicate *)predicate
                          fieldNames:(NSArray *)fieldNames
                     sortDescriptors:(NSArray *)sortDescriptors;

+ (NSArray *)findObjectsInConnection:(BLDatabaseConnection *)connection
                           predicate:(NSPredicate *)predicate
                          fieldNames:(NSArray *)fieldNames
                            sortTerm:(NSString *)sortTerm
                              length:(u_int64_t)length
                              offset:(u_int64_t)offset;

+ (NSArray *)findObjectsInConnection:(BLDatabaseConnection *)connection
                           predicate:(NSPredicate *)predicate
                          fieldNames:(NSArray *)fieldNames
                     sortDescriptors:(NSArray *)sortDescriptors
                              length:(u_int64_t)length
                              offset:(u_int64_t)offset;

@end
