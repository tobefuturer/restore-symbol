//
//  main.m
//  class-dump
//
//  Created by EugeneYang on 16/8/22.
//
//

#include <stdio.h>

#include <unistd.h>
#include <getopt.h>
#include <stdlib.h>
#include <mach-o/arch.h>



#define RESTORE_SYMBOL_BASE_VERSION "1.0 (64 bit)"

#ifdef DEBUG
#define RESTORE_SYMBOL_VERSION RESTORE_SYMBOL_BASE_VERSION //" (Debug version compiled " __DATE__ " " __TIME__ ")"
#else
#define RESTORE_SYMBOL_VERSION RESTORE_SYMBOL_BASE_VERSION
#endif

#define RS_OPT_DISABLE_OC_DETECT 1
#define RS_OPT_VERSION 2



void print_usage(void)
{
    fprintf(stderr,
            "\n"
            "restore-symbol %s\n"
            "\n"
            "Usage: restore-symbol -o <output-file> [-j <json-symbol-file>] <mach-o-file>\n"
            "\n"
            "  where options are:\n"
            "        -o <output-file>           New mach-o-file path\n"
            "        --disable-oc-detect        Disable auto detect and add oc method into symbol table,\n"
            "                                   only add symbol in json file\n"
            "        -j <json-symbol-file>      Json file containing extra symbol info, the key is \"name\",\"address\"\n                                   like this:\n                                   \n"
            "                                        [\n                                         {\n                                          \"name\": \"main\", \n                                          \"address\": \"0xXXXXXX\"\n                                         }, \n                                         {\n                                          \"name\": \"-[XXXX XXXXX]\", \n                                          \"address\": \"0xXXXXXX\"\n                                         },\n                                         .... \n                                        ]\n"
            
            ,
            RESTORE_SYMBOL_VERSION
            );
}



void restore_symbol(NSString * inpath, NSString * output, NSString *jsonPath, bool oc_detect_enable);

int main(int argc, char * argv[]) {
    
    
    
    
    bool oc_detect_enable = true;
    NSString *inpath = nil;
    NSString * outpath = nil;
    NSString *jsonPath = nil;
    
    BOOL shouldPrintVersion = NO;
    
    int ch;
    
    struct option longopts[] = {
        { "disable-oc-detect",       no_argument,       NULL, RS_OPT_DISABLE_OC_DETECT },
        { "output",                  required_argument, NULL, 'o' },
        { "json",                    required_argument, NULL, 'j' },
        { "version",                 no_argument,       NULL, RS_OPT_VERSION },
        { NULL,                      0,                 NULL, 0 },
        
    };
    
    
    if (argc == 1) {
        print_usage();
        exit(0);
    }
    
    
    
    while ( (ch = getopt_long(argc, argv, "o:j:", longopts, NULL)) != -1) {
        switch (ch) {
            case 'o':
                outpath = [NSString stringWithUTF8String:optarg];
                break;
            case 'j':
                jsonPath = [NSString stringWithUTF8String:optarg];
                break;
                
            case RS_OPT_VERSION:
                shouldPrintVersion = YES;
                break;
                
            case RS_OPT_DISABLE_OC_DETECT:
                oc_detect_enable = false;
                break;
                
            default:
                break;
        }
    }
    
    if (shouldPrintVersion) {
        printf("restore-symbol %s compiled %s\n", RESTORE_SYMBOL_VERSION, __DATE__ " " __TIME__);
        exit(0);
    }
    
    if (optind < argc) {
        inpath = [NSString stringWithUTF8String:argv[optind]];
    }
    
    
    restore_symbol(inpath, outpath, jsonPath, oc_detect_enable);
    
}