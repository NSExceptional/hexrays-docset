//
//  PDBManager.h
//  Pastie
//  
//  Created by Tanner Bennett on 2021-05-07
//  Copyright © 2021 Tanner Bennett. All rights reserved.
//

#import "PSQLResult.h"

NS_ASSUME_NONNULL_BEGIN

/// ( $name, $type, $path )
extern NSString * const kInsertIndexStatement;
/// ( $name, $type, $path )
extern NSString * const kUpdateIndexStatement;

//@protocol DBInsertable <NSObject> @end
//@interface NSNull (DBInsertable) <DBInsertable> @end
//@interface NSData (DBInsertable) <DBInsertable> @end
//@interface NSString (DBInsertable) <DBInsertable> @end
//@interface NSNumber (DBInsertable) <DBInsertable> @end

/// Pastie database manager
@interface PDBManager : NSObject

+ (instancetype)databaseWithDocset:(NSString *)path NS_SWIFT_NAME(init(docsetPath:));

/// Database path
@property (nonatomic, readonly) NSString *path;

/// Contains the result of the last operation, which may be an error
@property (nonatomic, readonly, nullable) PSQLResult *lastResult;

- (PSQLResult *)executeStatement:(NSString *)sql;
- (PSQLResult *)executeStatement:(NSString *)sql
                       arguments:(nullable NSDictionary<NSString *, id> *)args;

@end

NS_ASSUME_NONNULL_END
