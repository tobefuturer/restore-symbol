# -*- coding: utf-8 -*-

import idautils
import idc
from idaapi import PluginForm
import operator
import csv
import sys
import json


IS32BIT = not idaapi.get_inf_structure().is_64bit()

IS_MAC = 'X86_64' in idaapi.get_file_type_name()

print "Start analyze binary for " + ("Mac" if IS_MAC else "iOS")


def isInText(x):
    return SegName(x) == '__text'


GlobalBlockAddr = LocByName("__NSConcreteGlobalBlock")

class GlobalBlockInfo:
    pass

AllGlobalBlockMap = {}
for struct in list(DataRefsTo(GlobalBlockAddr)):
    func = 0L
    FUNC_OFFSET_IN_BLOCK = 12 if IS32BIT else 16
    if IS32BIT:
        func = Dword(struct + FUNC_OFFSET_IN_BLOCK)
    else:
        func = Qword(struct + FUNC_OFFSET_IN_BLOCK)


    info = GlobalBlockInfo()
    info.func = func
    info.struct = struct
    if len(list(DataRefsTo(struct))) == 0:
        continue
    refTo = list(DataRefsTo(struct))[0]
    info.superFuncName = GetFunctionName(refTo)
    info.superFunc = LocByName(info.superFuncName)

    AllGlobalBlockMap[func] = info

def funcIsGlobalBlockFunc(block_func):
    return block_func in AllGlobalBlockMap


def isPossibleStackBlockForFunc(block_func):
# def superFuncForStackBlock(block_func):

    if not isInText(block_func):
        return False

    if GetFunctionAttr(block_func,FUNCATTR_START) != (block_func & ~ 1):
        return False

    #block addr cannot be called directly
    if len(list(CodeRefsTo(block_func, 0))) !=0 :
        # print '%x is not block because be call by %x' % (block_func ,list(CodeRefsTo(block_func, 0))[0])
        return False

    # ref to block should be in text section
    refsTo = list(DataRefsTo(block_func))
    for addr in refsTo:
        if not isInText(addr):
            # print '%x is not block because be ref from %x' % (block_func, addr)
            return False

    # block func should be ref in only 1 function
    superFuncs = [GetFunctionAttr(x,FUNCATTR_START) for x in refsTo]
    superFuncs = list (set (superFuncs))
    if len(superFuncs) != 1:
        # print '%x is not block because be not ref from  1 function' % block_func
        return False

    return True

def superFuncForStackBlock(block_func):
    refsTo = list(DataRefsTo(block_func))
    superFuncs = [GetFunctionAttr(x,FUNCATTR_START) for x in refsTo]
    superFuncs = list (set (superFuncs))
    if len(superFuncs) != 1:
        return None
    super_func_addr = superFuncs[0]
    if IS_MAC:
        return super_func_addr
    else:
        return super_func_addr | GetReg(super_func_addr, "T") # thumb


def superFuncForBlockFunc(block_func):
    if funcIsGlobalBlockFunc(block_func):
        return AllGlobalBlockMap[block_func].superFunc

    superStackFunc = superFuncForStackBlock(block_func)
    return superStackFunc # maybe None



resultDict = {}


def findBlockName(block_func):
    # print "find block name  %X" % block_func
    funcName = GetFunctionName(block_func)

    if len(funcName) != 0 and funcName[0] in ('-', '+'):
        return funcName

    # maybe nested block
    superBlockFuncAddr = superFuncForBlockFunc(block_func)
    if superBlockFuncAddr == None:
        return "";
    if not IS_MAC:
        superBlockFuncAddr = superBlockFuncAddr | GetReg(superBlockFuncAddr, "T") # thumb
        
    superBlockName = findBlockName(superBlockFuncAddr)

    if len(superBlockName) == 0:
        return ""
    else:
        return superBlockName + "_block"



#find all possible Stack Block 
allPossibleStackBlockFunc = []
allRefToBlock=[]
if IS32BIT:
    allRefToBlock = list(DataRefsTo(LocByName("__NSConcreteStackBlock")))
else:
    allRefToBlock = list(DataRefsTo(LocByName("__NSConcreteStackBlock_ptr")))
    allRefToBlock.sort()

    '''
    2 ref (@PAGE , @PAGEOFF) to __NSConcreteStackBlock_ptr , 
    but once actual
    filter the list
    __text:0000000102D9979C                 ADRP            X8, #__NSConcreteStackBlock_ptr@PAGE
    __text:0000000102D997A0                 LDR             X8, [X8,#__NSConcreteStackBlock_ptr@PAGEOFF]
    '''
    tmp_array = allRefToBlock[:1]
    for i in range(1, len(allRefToBlock)):
        if allRefToBlock[i] - allRefToBlock[i - 1] <= 8:
            pass
        else:
            tmp_array.append(allRefToBlock[i])
    allRefToBlock = tmp_array

allRefToBlock = filter(lambda x:isInText(x), allRefToBlock)

for addr in allRefToBlock:
    LineNumAround = 30 #Around 30 arm instruction
    scan_addr_min= max (addr - LineNumAround * 4, GetFunctionAttr(addr,FUNCATTR_START))
    scan_addr_max= min (addr + LineNumAround * 4, GetFunctionAttr(addr,FUNCATTR_END))
    for scan_addr in range(scan_addr_min, scan_addr_max):
        allPossibleStackBlockFunc += list(DataRefsFrom(scan_addr)) # all function pointer used around __NSConcreteStackBlock

allPossibleStackBlockFunc = list (set (allPossibleStackBlockFunc))

allPossibleStackBlockFunc = filter(lambda x:isPossibleStackBlockForFunc(x) , allPossibleStackBlockFunc )




#process all Global Block 
for block_func in AllGlobalBlockMap:
    block_name = findBlockName(block_func)
    resultDict[block_func] =  block_name

for block_func in allPossibleStackBlockFunc:
    block_name = findBlockName(block_func)
    resultDict[block_func] = block_name


output_file = './block_symbol.json'
list_output = []
error_num = 0
for addr in resultDict:
    name = resultDict[addr]
    if len(name) == 0 or name[0] not in ('-', '+'):
        error_num += 1
        continue
       
    list_output += [{"address":("0x%X" % addr), "name":name}]


encodeJson = json.dumps(list_output, indent=1)
f = open(output_file, "w")
f.write(encodeJson)
f.close()

print 'restore block num %d ' % len(list_output)
print 'origin  block num: %d(GlobalBlock: %d, StackBlock: %d)' % (len(allRefToBlock) + len(AllGlobalBlockMap), len(AllGlobalBlockMap), len(allRefToBlock))
