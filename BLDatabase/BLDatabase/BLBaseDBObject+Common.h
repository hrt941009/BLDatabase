//
//  BLBaseDBObject+Find.h
//  BLAlimeiDatabase
//
//  Created by alibaba on 15/4/10.
//  Copyright (c) 2015年 wxw. All rights reserved.
//

#import "BLBaseDBObject.h"

@interface BLBaseDBObject (Common)

+ (void)createTableAndIndexInDatabaseConnection:(BLDatabaseConnection *)databaseConnection;

+ (void)addColumnName:(NSString *)columnName
 inDatabaseConnection:(BLDatabaseConnection *)databaseConnection;

+ (void)addColumnNames:(NSArray *)columnNames
  inDatabaseConnection:(BLDatabaseConnection *)databaseConnection;

+ (void)addColumnName:(NSString *)columnName
         defaultValue:(id)defaultValue
 inDatabaseConnection:(BLDatabaseConnection *)databaseConnection;

+ (void)addColumnNameAndValues:(NSDictionary *)columnNameAndValues
          inDatabaseConnection:(BLDatabaseConnection *)databaseConnection;

+ (void)deleteColumnName:(NSString *)columnName
    inDatabaseConnection:(BLDatabaseConnection *)databaseConnection;

+ (void)deleteColumnNames:(NSArray *)columnNames
     inDatabaseConnection:(BLDatabaseConnection *)databaseConnection;

+ (void)createIndexWithColumnName:(NSString *)columnName
             inDatabaseConnection:(BLDatabaseConnection *)databaseConnection;

+ (void)createIndexWithColumnNames:(NSArray *)columnNames
              inDatabaseConnection:(BLDatabaseConnection *)databaseConnection;

+ (void)createUnionIndexWithColumnNames:(NSArray *)columnNames
                   inDatabaseConnection:(BLDatabaseConnection *)databaseConnection;

+ (void)dropIndexWithColumnName:(NSString *)columnName
           inDatabaseConnection:(BLDatabaseConnection *)databaseConnection;

+ (void)dropIndexWithColumnNames:(NSArray *)columnNames
            inDatabaseConnection:(BLDatabaseConnection *)databaseConnection;

+ (void)dropUnionIndexWithColumnNames:(NSArray *)columnNames
                 inDatabaseConnection:(BLDatabaseConnection *)databaseConnection;

#pragma mark - find count

+ (int64_t)numberOfObjectsInDatabaseConnection:(BLDatabaseConnection *)databaseConnection;

+ (int64_t)numberOfObjectsInDatabaseConnection:(BLDatabaseConnection *)databaseConnection
                                         where:(NSString *)where, ...;

#pragma mark - find object with sql

+ (id)findFirstObjectInDatabaseConnection:(BLDatabaseConnection *)databaseConnection
                                    rowid:(int64_t)rowid;

+ (id)findFirstObjectInDatabaseConnection:(BLDatabaseConnection *)databaseConnection
                       valueForPrimaryKey:(NSString *)value;

+ (id)findFirstObjectInDatabaseConnection:(BLDatabaseConnection *)databaseConnection
                         valueForObjectID:(NSString *)value;

+ (id)findFirstObjectInDatabaseConnection:(BLDatabaseConnection *)databaseConnection
                                    where:(NSString *)where, ...;

+ (id)findFirstObjectInDatabaseConnection:(BLDatabaseConnection *)databaseConnection
                                  orderBy:(NSString *)orderBy
                                    where:(NSString *)where, ...;

+ (id)findFirstObjectInDatabaseConnection:(BLDatabaseConnection *)databaseConnection
                               fieldNames:(NSArray *)fieldNames
                                    rowid:(int64_t)rowid;

+ (id)findFirstObjectInDatabaseConnection:(BLDatabaseConnection *)databaseConnection
                               fieldNames:(NSArray *)fieldNames
                       valueForPrimaryKey:(NSString *)value;

+ (id)findFirstObjectInDatabaseConnection:(BLDatabaseConnection *)databaseConnection
                               fieldNames:(NSArray *)fieldNames
                         valueForObjectID:(NSString *)value;

+ (id)findFirstObjectInDatabaseConnection:(BLDatabaseConnection *)databaseConnection
                               fieldNames:(NSArray *)fieldNames
                                    where:(NSString *)where, ...;

+ (id)findFirstObjectInDatabaseConnection:(BLDatabaseConnection *)databaseConnection
                               fieldNames:(NSArray *)fieldNames
                                  orderBy:(NSString *)orderBy
                                    where:(NSString *)where, ...;

#pragma mark - find objects with sql

+ (NSArray *)findObjectsInDatabaseConnection:(BLDatabaseConnection *)databaseConnection;

+ (NSArray *)findObjectsInDatabaseConnection:(BLDatabaseConnection *)databaseConnection
                                     orderBy:(NSString *)orderBy;

+ (NSArray *)findObjectsInDatabaseConnection:(BLDatabaseConnection *)databaseConnection
                                       where:(NSString *)where, ...;

+ (NSArray *)findObjectsInDatabaseConnection:(BLDatabaseConnection *)databaseConnection
                                     orderBy:(NSString *)orderBy
                                       where:(NSString *)where, ...;

+ (NSArray *)findObjectsInDatabaseConnection:(BLDatabaseConnection *)databaseConnection
                                     orderBy:(NSString *)orderBy
                                      length:(u_int64_t)length
                                      offset:(u_int64_t)offset
                                       where:(NSString *)where, ...;

+ (NSArray *)findObjectsInDatabaseConnection:(BLDatabaseConnection *)databaseConnection
                                  fieldNames:(NSArray *)fieldNames;

+ (NSArray *)findObjectsInDatabaseConnection:(BLDatabaseConnection *)databaseConnection
                                  fieldNames:(NSArray *)fieldNames
                                     orderBy:(NSString *)orderBy;

+ (NSArray *)findObjectsInDatabaseConnection:(BLDatabaseConnection *)databaseConnection
                                  fieldNames:(NSArray *)fieldNames
                                       where:(NSString *)where, ...;

+ (NSArray *)findObjectsInDatabaseConnection:(BLDatabaseConnection *)databaseConnection
                                  fieldNames:(NSArray *)fieldNames
                                     orderBy:(NSString *)orderBy
                                       where:(NSString *)where, ...;

+ (NSArray *)findObjectsInDatabaseConnection:(BLDatabaseConnection *)databaseConnection
                                  fieldNames:(NSArray *)fieldNames
                                     orderBy:(NSString *)orderBy
                                      length:(u_int64_t)length
                                      offset:(u_int64_t)offset
                                       where:(NSString *)where, ...;

#pragma mark - find object with predicate

+ (id)findFirstObjectInDatabaseConnection:(BLDatabaseConnection *)databaseConnection
                                predicate:(NSPredicate *)predicate;

// sortTerm eg:"rowid:1,uuid:0", 1 asc 0 desc, @"rowid" mean rowid desc
+ (id)findFirstObjectInDatabaseConnection:(BLDatabaseConnection *)databaseConnection
                                predicate:(NSPredicate *)predicate
                                 sortTerm:(NSString *)sortTerm;

+ (id)findFirstObjectInDatabaseConnection:(BLDatabaseConnection *)databaseConnection
                                predicate:(NSPredicate *)predicate
                          sortDescriptors:(NSArray *)sortDescriptors;

+ (id)findFirstObjectInDatabaseConnection:(BLDatabaseConnection *)databaseConnection
                                predicate:(NSPredicate *)predicate
                               fieldNames:(NSArray *)fieldNames;

+ (id)findFirstObjectInDatabaseConnection:(BLDatabaseConnection *)databaseConnection
                                predicate:(NSPredicate *)predicate
                               fieldNames:(NSArray *)fieldNames
                                 sortTerm:(NSString *)sortTerm;

+ (id)findFirstObjectInDatabaseConnection:(BLDatabaseConnection *)databaseConnection
                                predicate:(NSPredicate *)predicate
                               fieldNames:(NSArray *)fieldNames
                          sortDescriptors:(NSArray *)sortDescriptors;

#pragma mark - find objects with predicate

+ (NSArray *)findObjectsInDatabaseConnection:(BLDatabaseConnection *)databaseConnection
                                   predicate:(NSPredicate *)predicate;

+ (NSArray *)findObjectsInDatabaseConnection:(BLDatabaseConnection *)databaseConnection
                                   predicate:(NSPredicate *)predicate
                                    sortTerm:(NSString *)sortTerm;

+ (NSArray *)findObjectsInDatabaseConnection:(BLDatabaseConnection *)databaseConnection
                                   predicate:(NSPredicate *)predicate
                             sortDescriptors:(NSArray *)sortDescriptors;

+ (NSArray *)findObjectsInDatabaseConnection:(BLDatabaseConnection *)databaseConnection
                                   predicate:(NSPredicate *)predicate
                                    sortTerm:(NSString *)sortTerm
                                      length:(u_int64_t)length
                                      offset:(u_int64_t)offset;

+ (NSArray *)findObjectsInDatabaseConnection:(BLDatabaseConnection *)databaseConnection
                                   predicate:(NSPredicate *)predicate
                             sortDescriptors:(NSArray *)sortDescriptors
                                      length:(u_int64_t)length
                                      offset:(u_int64_t)offset;

+ (NSArray *)findObjectsInDatabaseConnection:(BLDatabaseConnection *)databaseConnection
                                   predicate:(NSPredicate *)predicate
                                  fieldNames:(NSArray *)fieldNames;

+ (NSArray *)findObjectsInDatabaseConnection:(BLDatabaseConnection *)databaseConnection
                                   predicate:(NSPredicate *)predicate
                                  fieldNames:(NSArray *)fieldNames
                                    sortTerm:(NSString *)sortTerm;

+ (NSArray *)findObjectsInDatabaseConnection:(BLDatabaseConnection *)databaseConnection
                                   predicate:(NSPredicate *)predicate
                                  fieldNames:(NSArray *)fieldNames
                             sortDescriptors:(NSArray *)sortDescriptors;

+ (NSArray *)findObjectsInDatabaseConnection:(BLDatabaseConnection *)databaseConnection
                                   predicate:(NSPredicate *)predicate
                                  fieldNames:(NSArray *)fieldNames
                                    sortTerm:(NSString *)sortTerm
                                      length:(u_int64_t)length
                                      offset:(u_int64_t)offset;

+ (NSArray *)findObjectsInDatabaseConnection:(BLDatabaseConnection *)databaseConnection
                                   predicate:(NSPredicate *)predicate
                                  fieldNames:(NSArray *)fieldNames
                             sortDescriptors:(NSArray *)sortDescriptors
                                      length:(u_int64_t)length
                                      offset:(u_int64_t)offset;

@end
