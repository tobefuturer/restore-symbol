//
//  RSSymbol.h
//  restore-symbol
//
//  Created by EugeneYang on 16/8/19.
//
//

#import <Foundation/Foundation.h>


#define RS_JSON_KEY_ADDRESS @"address"
#define RS_JSON_KEY_SYMBOL_NAME @"name"

@interface RSSymbol : NSObject


@property (nonatomic, strong) NSString * name;
@property (nonatomic) uint64 address;


+ (NSArray<RSSymbol *> *)symbolsWithJson:(NSData *)json;

+ (RSSymbol *)symbolWithName:(NSString *)name address:(uint64)addr;



@end
