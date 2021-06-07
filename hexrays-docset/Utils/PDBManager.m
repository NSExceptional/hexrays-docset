//
//  PDBManager.m
//  Pastie
//  
//  Created by Tanner Bennett on 2021-05-07
//  Copyright © 2021 Tanner Bennett. All rights reserved.
//

#import "PDBManager.h"
#import "NSArray+Map.h"
#import <sqlite3.h>

typedef NS_ENUM(char, TypeEncoding) {
    TypeEncodingNull             = '\0',
    TypeEncodingUnknown          = '?',
    TypeEncodingChar             = 'c',
    TypeEncodingInt              = 'i',
    TypeEncodingShort            = 's',
    TypeEncodingLong             = 'l',
    TypeEncodingLongLong         = 'q',
    TypeEncodingUnsignedChar     = 'C',
    TypeEncodingUnsignedInt      = 'I',
    TypeEncodingUnsignedShort    = 'S',
    TypeEncodingUnsignedLong     = 'L',
    TypeEncodingUnsignedLongLong = 'Q',
    TypeEncodingFloat            = 'f',
    TypeEncodingDouble           = 'd',
    TypeEncodingLongDouble       = 'D',
    TypeEncodingCBool            = 'B',
    TypeEncodingVoid             = 'v',
    TypeEncodingCString          = '*',
    TypeEncodingObjcObject       = '@',
    TypeEncodingObjcClass        = '#',
    TypeEncodingSelector         = ':',
    TypeEncodingArrayBegin       = '[',
    TypeEncodingArrayEnd         = ']',
    TypeEncodingStructBegin      = '{',
    TypeEncodingStructEnd        = '}',
    TypeEncodingUnionBegin       = '(',
    TypeEncodingUnionEnd         = ')',
    TypeEncodingQuote            = '\"',
    TypeEncodingBitField         = 'b',
    TypeEncodingPointer          = '^',
    TypeEncodingConst            = 'r'
};

NSString * const kPDBCreateTableStatement = @"CREATE TABLE IF NOT EXISTS searchIndex(id INTEGER PRIMARY KEY, name TEXT, type TEXT, path TEXT);";
NSString * const kInsertIndexStatement = @"INSERT OR IGNORE INTO searchIndex(name, type, path) VALUES ( $name, $type, $path );";
NSString * const kUpdateIndexStatement = @"UPDATE searchIndex SET type = $type WHERE name = $name AND path = $path;";
NSString * const kClearTable = @"DELETE FROM searchIndex";

@interface PDBManager ()
@property (nonatomic) sqlite3 *db;
@property (nonatomic, readonly) NSString *creation;
@end

@implementation PDBManager

- (NSString *)creation { return kPDBCreateTableStatement; }

+ (instancetype)databaseWithDocset:(NSString *)path {
    return [[self alloc] initWithDocsetPath:path];
}

- (id)initWithDocsetPath:(NSString *)docsetFolder {
    self = [super init];
    
    if (self) {
//        [NSFileManager.defaultManager
//            createDirectoryAtPath:?
//            withIntermediateDirectories:YES
//            attributes:nil
//            error:nil
//        ];
        
        NSString *resources = [docsetFolder stringByAppendingPathComponent:@"Contents/Resources"];
        _path = [resources stringByAppendingPathComponent:@"docSet.dsidx"];
        [self executeStatement:self.creation];
        [self executeStatement:kClearTable];
    }
    
    return self;
}

- (void)dealloc {
    [self close];
}

- (BOOL)open {
    if (self.db) {
        return YES;
    }
    
    int err = sqlite3_open(self.path.UTF8String, &_db);

    if (err != SQLITE_OK) {
        return NO;
    }
    
    return YES;
}
    
- (BOOL)close {
    if (!self.db) {
        return YES;
    }
    
    int  rc;
    BOOL retry, triedFinalizingOpenStatements = NO;
    
    do {
        retry = NO;
        rc    = sqlite3_close(_db);
        if (SQLITE_BUSY == rc || SQLITE_LOCKED == rc) {
            if (!triedFinalizingOpenStatements) {
                triedFinalizingOpenStatements = YES;
                sqlite3_stmt *pStmt;
                while ((pStmt = sqlite3_next_stmt(_db, nil)) != 0) {
                    sqlite3_finalize(pStmt);
                    retry = YES;
                }
            }
        } else if (SQLITE_OK != rc) {
            self.db = nil;
            return NO;
        }
    } while (retry);
    
    self.db = nil;
    return YES;
}

/// @return YES on success, NO if an error was encountered and stored in \c lastResult
- (BOOL)bindParameters:(NSDictionary *)args toStatement:(sqlite3_stmt *)pstmt {
    for (NSString *param in args.allKeys) {
        int status = SQLITE_OK, idx = sqlite3_bind_parameter_index(pstmt, param.UTF8String);
        id value = args[param];
        
        if (idx == 0) {
            // No parameter matching that arg
            @throw NSInternalInconsistencyException;
        }
        
        // Null
        if ([value isKindOfClass:[NSNull class]]) {
            status = sqlite3_bind_null(pstmt, idx);
        }
        // String params
        else if ([value isKindOfClass:[NSString class]]) {
            const char *str = [value UTF8String];
            status = sqlite3_bind_text(pstmt, idx, str, (int)strlen(str), SQLITE_TRANSIENT);
        }
        // Data params
        else if ([value isKindOfClass:[NSData class]]) {
            const void *blob = [value bytes];
            status = sqlite3_bind_blob64(pstmt, idx, blob, [value length], SQLITE_TRANSIENT);
        }
        // Primitive params
        else if ([value isKindOfClass:[NSNumber class]]) {
            TypeEncoding type = [value objCType][0];
            switch (type) {
                case TypeEncodingCBool:
                case TypeEncodingChar:
                case TypeEncodingUnsignedChar:
                case TypeEncodingShort:
                case TypeEncodingUnsignedShort:
                case TypeEncodingInt:
                case TypeEncodingUnsignedInt:
                case TypeEncodingLong:
                case TypeEncodingUnsignedLong:
                case TypeEncodingLongLong:
                case TypeEncodingUnsignedLongLong:
                    status = sqlite3_bind_int64(pstmt, idx, (sqlite3_int64)[value longValue]);
                    break;
                
                case TypeEncodingFloat:
                case TypeEncodingDouble:
                    status = sqlite3_bind_double(pstmt, idx, [value doubleValue]);
                    break;
                    
                default:
                    @throw NSInternalInconsistencyException;
                    break;
            }
        }
        // Unsupported type
        else {
            @throw NSInternalInconsistencyException;
        }
        
        if (status != SQLITE_OK) {
            return [self storeErrorForLastTask:
                [NSString stringWithFormat:@"Binding param named '%@'", param]
            ];
        }
    }
    
    return YES;
}

- (BOOL)storeErrorForLastTask:(NSString *)action {
    _lastResult = [self errorResult:action];
    return NO;
}

- (PSQLResult *)errorResult:(NSString *)description {
    const char *error = sqlite3_errmsg(_db);
    NSString *message = error ? @(error) : [NSString
        stringWithFormat:@"(%@: empty error)", description
    ];
    
    return [PSQLResult error:message];
}

- (id)objectForColumnIndex:(int)columnIdx stmt:(sqlite3_stmt*)stmt {
    int columnType = sqlite3_column_type(stmt, columnIdx);
    
    switch (columnType) {
        case SQLITE_INTEGER:
            return @(sqlite3_column_int64(stmt, columnIdx)).stringValue;
        case SQLITE_FLOAT:
            return  @(sqlite3_column_double(stmt, columnIdx)).stringValue;
        case SQLITE_BLOB:
            return [NSString stringWithFormat:@"Data (%@ bytes)",
                @([self dataForColumnIndex:columnIdx stmt:stmt].length)
            ];
            
        default:
            // Default to a string for everything else
            return [self stringForColumnIndex:columnIdx stmt:stmt] ?: NSNull.null;
    }
}
                
- (NSString *)stringForColumnIndex:(int)columnIdx stmt:(sqlite3_stmt *)stmt {
    if (sqlite3_column_type(stmt, columnIdx) == SQLITE_NULL || columnIdx < 0) {
        return nil;
    }
    
    const char *text = (const char *)sqlite3_column_text(stmt, columnIdx);
    return text ? @(text) : nil;
}

- (NSData *)dataForColumnIndex:(int)columnIdx stmt:(sqlite3_stmt *)stmt {
    if (sqlite3_column_type(stmt, columnIdx) == SQLITE_NULL || (columnIdx < 0)) {
        return nil;
    }
    
    const void *blob = sqlite3_column_blob(stmt, columnIdx);
    NSInteger size = (NSInteger)sqlite3_column_bytes(stmt, columnIdx);
    
    return blob ? [NSData dataWithBytes:blob length:size] : nil;
}

- (PSQLResult *)executeStatement:(NSString *)sql {
    return [self executeStatement:sql arguments:nil];
}

- (PSQLResult *)executeStatement:(NSString *)sql arguments:(NSDictionary *)args {
    [self open];
    
    PSQLResult *result = nil;
    
    sqlite3_stmt *pstmt;
    int status;
    if ((status = sqlite3_prepare_v2(_db, sql.UTF8String, -1, &pstmt, 0)) == SQLITE_OK) {
        NSMutableArray<NSArray *> *rows = [NSMutableArray new];
        
        // Bind parameters, if any
        if (![self bindParameters:args toStatement:pstmt]) {
            return self.lastResult;
        }
        
        // Grab columns
        int columnCount = sqlite3_column_count(pstmt);
        NSArray<NSString *> *columns = [NSArray pastie_forEachUpTo:columnCount map:^id(NSUInteger i) {
            return @(sqlite3_column_name(pstmt, (int)i));
        }];
        
        // Execute statement
        while ((status = sqlite3_step(pstmt)) == SQLITE_ROW) {
            // Grab rows if this is a selection query
            int dataCount = sqlite3_data_count(pstmt);
            if (dataCount > 0) {
                [rows addObject:[NSArray pastie_forEachUpTo:columnCount map:^id(NSUInteger i) {
                    return [self objectForColumnIndex:(int)i stmt:pstmt];
                }]];
            }
        }
        
        if (status == SQLITE_DONE) {
            if (rows.count) {
                // We selected some rows
                result = _lastResult = [PSQLResult columns:columns rows:rows];
            } else {
                // We executed a query like INSERT, UDPATE, or DELETE
                int rowsAffected = sqlite3_changes(_db);
                NSString *message = [NSString stringWithFormat:@"%d row(s) affected", rowsAffected];
                result = _lastResult = [PSQLResult message:message];
            }
        } else {
            // An error occured executing the query
            result = _lastResult = [self errorResult:@"Execution"];
        }
    } else {
        // An error occurred creating the prepared statement
        result = _lastResult = [self errorResult:@"Prepared statement"];
    }
    
    sqlite3_finalize(pstmt);
    return result;
}

@end
