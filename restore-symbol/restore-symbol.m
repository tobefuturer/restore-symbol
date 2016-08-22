//
//  main.m
//  restore-symbol
//
//  Created by EugeneYang on 16/8/16.
//
//

#import <Foundation/Foundation.h>
#include <sys/types.h>
#include <sys/stat.h>
#import "CDFile.h"
#import "CDMachOFile.h"
#import "CDLCSymbolTable.h"
#import "CDLCSegment.h"
#import "CDSymbol.h"
#import "CDLCDynamicSymbolTable.h"
#import "CDLCLinkeditData.h"
#import "CDClassDump.h"
#import "CDFindMethodVisitor.h"
#import "RSScanMethodVisitor.h"
#import "CDFatFile.h"



#define IntSize (Is32Bit? sizeof(uint32_t) : sizeof(uint64_t) )
#define NListSize (Is32Bit? sizeof(struct nlist) : sizeof(struct nlist_64) )


#define vm_addr_round(v,r) ( (v + (r-1) ) & (-r) )





void restore_symbol(NSString * inpath, NSString *outpath, NSString *jsonPath, bool oc_detect_enable){
    
    
    
    
    if (![[NSFileManager defaultManager] fileExistsAtPath:inpath]) {
        fprintf(stderr, "Error: Input file doesn't exist!\n");
        exit(1);
    }
    
    
    fprintf(stderr, "=========== Start =============\n");
    
    
    
    
    [[NSFileManager defaultManager] removeItemAtPath:outpath error:nil];
    
    NSMutableData * outData = [[NSMutableData alloc] initWithContentsOfFile:inpath];
    
    CDFile * ofile = [CDFile fileWithContentsOfFile:inpath searchPathState:nil];
    
    if ([ofile isKindOfClass:[CDFatFile class]] ) {
        fprintf(stderr,"Restore-symbol supports armv7 and arm64 archtecture, but not support fat file. Please use lipo to thin the image file first.");
        exit(1);
    }
    
    
    CDMachOFile * machOFile = (CDMachOFile *)ofile;
    const bool Is32Bit = ! machOFile.uses64BitABI;
    

    RSSymbolCollector *collector = [RSSymbolCollector new];
    collector.machOFile = machOFile;
    
    if (oc_detect_enable) {
        fprintf(stderr, "Scan OC methoc in mach-o-file.\n");

        CDClassDump *classDump = [[CDClassDump alloc] init];
        CDArch targetArch;
        if ([machOFile bestMatchForLocalArch:&targetArch] == NO) {
            fprintf(stderr, "Error: Couldn't get local architecture!\n");
            exit(1);
        }
        classDump.targetArch = targetArch;
        [classDump processObjectiveCData];
        [classDump registerTypes];
        
        NSError *error;
        if (![classDump loadFile:machOFile error:&error]) {
            fprintf(stderr, "Error: %s\n", [[error localizedFailureReason] UTF8String]);
            exit(1);
        } else {
            [classDump processObjectiveCData];
            [classDump registerTypes];
            
            RSScanMethodVisitor *visitor = [[RSScanMethodVisitor alloc] initWithSymbolCollector:collector];
            visitor.classDump = classDump;
            [classDump recursivelyVisit:visitor];
            
        }
 
        fprintf(stderr, "Scan OC methoc finish.\n");
    }
    
    
    if (jsonPath != nil && jsonPath.length != 0) {
        fprintf(stderr, "Parse symbols in json file.\n");
        NSArray *jsonSymbols = [RSSymbol symbolsWithJson:[NSData dataWithContentsOfFile:jsonPath]];
        if (jsonSymbols == nil) {
            fprintf(stderr,"Error: Json file cann't parse!");
            exit(1);
        } else {
            [collector addSymbols:jsonSymbols];
        }
        fprintf(stderr, "Parse finish.\n");
    }
    
    
    NSData *string_table_append_data = nil;
    NSData *symbol_table_append_data = nil;
    [collector generateAppendStringTable:&string_table_append_data appendSymbolTable:&symbol_table_append_data];
    
    
    uint32 increase_symbol_num = (uint32)collector.symbols.count;
    uint32 increase_size_string_tab = (uint32)string_table_append_data.length;
    uint32 increase_size_symtab = (uint32)symbol_table_append_data.length;
    uint32 increase_size_all_without_padding = increase_size_symtab + increase_size_string_tab;
    
    
    
    uint32 origin_string_table_offset = machOFile.symbolTable.stroff;
    uint32 origin_string_table_size = machOFile.symbolTable.strsize;
    uint32 origin_symbol_table_offset = machOFile.symbolTable.symoff;
    uint32 origin_symbol_table_num = machOFile.symbolTable.nsyms;
    
    //LC_CODE_SIGNATURE need align 16 byte, so add padding at end of string table.
    uint32 string_table_padding = 0;
    {
        CDLCLinkeditData * codesignature = nil;
        for (CDLoadCommand *command in machOFile.loadCommands) {
            if (command.cmd == LC_CODE_SIGNATURE){
                codesignature = (CDLCLinkeditData *)command;
            }
        }
        
        struct linkedit_data_command *command = (struct linkedit_data_command *)((char *)outData.mutableBytes + codesignature.commandOffset);
        uint32_t tmp_offset =  command -> dataoff + increase_size_all_without_padding;
        uint32_t final_offset = vm_addr_round(tmp_offset, 16);
        
        string_table_padding = final_offset - tmp_offset;
        command -> dataoff = final_offset;
        
    }
    
    
    {
        CDLCSymbolTable *symtab = [machOFile symbolTable];
        struct symtab_command *symtab_out = (struct symtab_command *)((char *)outData.mutableBytes + symtab.commandOffset);
        symtab_out -> nsyms += increase_symbol_num;
        symtab_out -> stroff += increase_size_symtab;
        symtab_out -> strsize += increase_size_string_tab + string_table_padding;
    }
    
    {
        CDLCDynamicSymbolTable *dysymtabCommand = [machOFile dynamicSymbolTable];
        struct dysymtab_command *command = (struct dysymtab_command *)((char *)outData.mutableBytes + dysymtabCommand.commandOffset);
        command -> indirectsymoff += increase_size_symtab;
    }
    
    
    
    {
        CDLCSegment * linkeditSegment = [machOFile segmentWithName:@"__LINKEDIT"];
        if (Is32Bit) {
            struct segment_command *linkedit_segment_command = (struct segment_command *)((char *)outData.mutableBytes + linkeditSegment.commandOffset);
            linkedit_segment_command -> filesize += increase_size_all_without_padding + string_table_padding;
            linkedit_segment_command -> vmsize = (uint32) vm_addr_round((linkedit_segment_command -> filesize), 0x4000);
            
            
        } else {
            
            struct segment_command_64 *linkedit_segment_command = (struct segment_command_64  *)((char *)outData.mutableBytes + linkeditSegment.commandOffset);
            linkedit_segment_command -> filesize += increase_size_all_without_padding + string_table_padding;
            linkedit_segment_command -> vmsize = vm_addr_round((linkedit_segment_command -> filesize), 0x4000);
        }
    }
    
    
    
    
    // must first insert string
    [outData replaceBytesInRange:NSMakeRange(origin_string_table_offset + origin_string_table_size , 0) withBytes:(const void *)string_table_append_data.bytes   length:increase_size_string_tab + string_table_padding];
    
    [outData replaceBytesInRange:NSMakeRange(origin_symbol_table_offset + origin_symbol_table_num * NListSize , 0) withBytes:(const void *)symbol_table_append_data.bytes   length:increase_size_symtab];
    
    [outData writeToFile:outpath atomically:true];
    chmod(outpath.UTF8String, 0755);
    fprintf(stderr,"=========== Finish ============\n");
    
}
