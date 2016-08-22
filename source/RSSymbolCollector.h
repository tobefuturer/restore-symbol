//
//  RSSymbolCollector.h
//  restore-symbol
//
//  Created by EugeneYang on 16/8/19.
//
//

#import <Foundation/Foundation.h>
#import "RSSymbol.h"
#import "CDMachOFile.h"

@interface RSSymbolCollector : NSObject

@property (nonatomic, weak) CDMachOFile * machOFile;
@property (nonatomic, strong) NSMutableArray *symbols;


- (void)addSymbol:(RSSymbol *)symbol;
- (void)addSymbols:(NSArray<RSSymbol *> *)symbols;


- (void)generateAppendStringTable:(NSData **)stringTable appendSymbolTable:(NSData **)nlist;
@end
