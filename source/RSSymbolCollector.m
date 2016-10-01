//
//  RSSymbolCollector.m
//  restore-symbol
//
//  Created by EugeneYang on 16/8/19.
//
//

#import "RSSymbolCollector.h"

#import <mach-o/nlist.h>
#import "CDLCSymbolTable.h"
#import "CDLCSegment.h"
#import "CDSection.h"

@implementation RSSymbolCollector



- (instancetype)init
{
    self = [super init];
    if (self) {
        _symbols = [NSMutableArray array];
    }
    return self;
}


- (void)addSymbol:(RSSymbol *)symbol{
    if (symbol == nil) {
        return ;
    }
    [_symbols addObject:symbol];
}


- (void)addSymbols:(NSArray<RSSymbol *> *)symbols{
    if (symbols == nil)
        return ;
    [_symbols addObjectsFromArray:symbols];
}


- (void)generateAppendStringTable:(NSData **)stringTable appendSymbolTable:(NSData **)symbolTable{
    
    const bool is32Bit = ! _machOFile.uses64BitABI;
    
    NSMutableData * symbolNames = [NSMutableData new];
    
    NSMutableData * nlistsData = [NSMutableData dataWithLength:_symbols.count * ( is32Bit ? sizeof(struct nlist) : sizeof(struct nlist_64))];
    
    memset(nlistsData.mutableBytes, 0, nlistsData.length);
    
    uint32 origin_string_table_size = _machOFile.symbolTable.strsize;
    
    
    for (int i = 0; i < _symbols.count; i ++) {
        
        
        RSSymbol * symbol = _symbols[i];
        if (symbol.address == 0) {
            continue;
        }
        
        
        if (is32Bit) {
            struct nlist * list = nlistsData.mutableBytes;
            bool isThumb = symbol.address & 1;
            list[i].n_desc = isThumb ? N_ARM_THUMB_DEF : 0;
            list[i].n_type = N_PEXT | N_SECT;
            list[i].n_sect = [self n_sectForAddress:symbol.address];
            list[i].n_value = (uint32_t)symbol.address & ~ 1;
            list[i].n_un.n_strx = origin_string_table_size + (uint32)symbolNames.length;
            
        } else {
            struct nlist_64 * list = nlistsData.mutableBytes;
            list[i].n_desc =  0;
            list[i].n_type = N_PEXT | N_SECT;
            list[i].n_sect = [self n_sectForAddress:symbol.address];
            list[i].n_value = symbol.address;
            list[i].n_un.n_strx = origin_string_table_size + (uint32)symbolNames.length;
        }
        
        [symbolNames appendBytes:symbol.name.UTF8String length:symbol.name.length];
        [symbolNames appendBytes:"\0" length:1];
    }
    
    
    *stringTable = symbolNames;
    *symbolTable = nlistsData;
    
    
}

- (uint8)n_sectForAddress:(uint64)address{
    

    uint8 n_sect = 0;
    
    for (id loadCommand in _machOFile.loadCommands) {
        if ([loadCommand isKindOfClass:[CDLCSegment class]]){
            CDLCSegment * seg = (CDLCSegment *)loadCommand;
            if(![loadCommand containsAddress:address]) {
                n_sect += [[seg sections] count];
            } else {
                for (CDSection * section in [seg sections]){
                    n_sect ++;
                    if ([section containsAddress:address]) {
                        return n_sect;
                    }
                    
                }
                
            }
        }
    }
    
    NSLog(@"Address(%llx) not found in the image", address);
    exit(1);
    return 1;
}


@end
