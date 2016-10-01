// -*- mode: ObjC -*-

//  This file is part of class-dump, a utility for examining the Objective-C segment of Mach-O files.
//  Copyright (C) 1997-1998, 2000-2001, 2004-2015 Steve Nygard.

#import "RSScanMethodVisitor.h"

#import "CDClassDump.h"
#import "CDObjectiveC1Processor.h"
#import "CDMachOFile.h"
#import "CDOCProtocol.h"
#import "CDLCDylib.h"
#import "CDOCClass.h"
#import "CDOCCategory.h"
#import "CDOCClassReference.h"
#import "CDOCMethod.h"
//#import "CDTypeController.h"

@interface RSScanMethodVisitor ()

@property (nonatomic, strong) CDOCProtocol *context;

@property (nonatomic, weak) RSSymbolCollector * collector;

@end

#pragma mark -

@implementation RSScanMethodVisitor
{
    CDOCProtocol *_context;

}

- (id)initWithSymbolCollector:(RSSymbolCollector *)collector
{
    if ((self = [super init])) {
        _context = nil;
        _collector = collector;
    }

    return self;
}

#pragma mark -

- (void)willVisitProtocol:(CDOCProtocol *)protocol;
{
    [self setContext:protocol];
}

- (void)willVisitClass:(CDOCClass *)aClass;
{
    [self setContext:aClass];
}


- (void)willVisitCategory:(CDOCCategory *)category;
{
    [self setContext:category];
}


- (NSString *)getCurrentClassName{
    if ([_context isKindOfClass:[CDOCClass class]]) {
        return _context.name;
    } else if([_context isKindOfClass:[CDOCCategory class]]) {
        NSString * className = [[(CDOCCategory *)_context classRef] className];
        if (!className) className = @"";
        return [NSString stringWithFormat:@"%@(%@)", className ,_context.name];
    }
    return _context.name;
}

- (void)visitClassMethod:(CDOCMethod *)method;
{
    if (method.address == 0 ) {
        return;
    }
    
    NSString *name = [NSString stringWithFormat:@"+[%@ %@]", [self getCurrentClassName], method.name];
    
    RSSymbol *s = [RSSymbol symbolWithName:name address:method.address];
    
    [self.collector addSymbol:s];
    
}

- (void)visitInstanceMethod:(CDOCMethod *)method propertyState:(CDVisitorPropertyState *)propertyState;
{
    if (method.address == 0 ) {
        return;
    }
    NSString *name = [NSString stringWithFormat:@"-[%@ %@]", [self getCurrentClassName], method.name];
    
    RSSymbol *s = [RSSymbol symbolWithName:name address:method.address];
    
    [self.collector addSymbol:s];
    
}


#pragma mark -

- (void)setContext:(CDOCProtocol *)newContext;
{
    if (newContext != _context) {
        _context = newContext;
    }
}



@end
