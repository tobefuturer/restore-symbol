import types
import os
import operator
import csv
import sys
import json
import traceback

doc = Document.getCurrentDocument()

def alert(val):
    if type(val) is types.LongType:
        doc.message(hex(val), ['OK'])
    else:
        doc.message(str(val), ['OK'])

def log(val):
    if type(val) is types.LongType:
        doc.log(hex(val) + '\n')
    else:
        doc.log(str(val) + '\n')

TextSeg = doc.getSegmentByName('__TEXT')
DataSeg = doc.getSegmentByName('__DATA')
SymbolSeg = doc.getSegmentByName('External Symbols')

IS32BIT = not doc.is64Bits()

doc_entry = doc.getEntryPoint()

IS_MAC = 'x86_64' in Instruction.stringForArchitecture(TextSeg.getInstructionAtAddress(doc_entry).getArchitecture())


log("Start analyze binary for " + ("Mac" if IS_MAC else "iOS"))

def isInText(x):
    return doc.getSegmentAtAddress(x).getName() == '__TEXT'

def isInData(x):
    return doc.getSegmentAtAddress(x).getName() == '__DATA'

GlobalBlockAddr = doc.getAddressForName("__NSConcreteGlobalBlock")


class GlobalBlockInfo:
    pass

AllGlobalBlockMap = {}


def funcIsGlobalBlockFunc(block_func):
    return block_func in AllGlobalBlockMap

def isPossibleStackBlockForFunc(block_func):
    if not isInText(block_func):
        return False

    proc = TextSeg.getProcedureAtAddress(block_func)
    if not proc or proc.getEntryPoint() != (block_func & ~ 1):
        return False

    #block addr cannot be called directly
    refsTo = TextSeg.getReferencesOfAddress(block_func)
    codeRefs = []
    if IS_MAC:
        codeRefs = filter(lambda x: TextSeg.getInstructionAtAddress(x).getInstructionString() == 'call', refsTo)
    else:
        codeRefs = filter(lambda x: TextSeg.getInstructionAtAddress(x).getInstructionString() == 'bl', refsTo)
    if len(codeRefs) !=0 :
        return False

    # block func should be ref in only 1 function
    superFuncs = []
    for ref in refsTo:
        proc = TextSeg.getProcedureAtAddress(ref)
        if not proc:
            continue
        superFuncs.append(proc.getEntryPoint())
    superFuncs = list (set (superFuncs))
    if len(superFuncs) != 1:
        # print '%x is not block because be not ref from  1 function' % block_func
        return False

    return True

def superFuncForStackBlock(block_func):
    refsTo = TextSeg.getReferencesOfAddress(block_func)
    superFuncs = [TextSeg.getProcedureAtAddress(x).getEntryPoint() for x in refsTo]
    superFuncs = list (set (superFuncs))
    if len(superFuncs) != 1:
        return None
    super_func_addr = superFuncs[0]
    if IS_MAC:
        return super_func_addr
    else:
        return super_func_addr | TextSeg.isThumbAtAddress(block_func) # thumb


def superFuncForBlockFunc(block_func):
    if funcIsGlobalBlockFunc(block_func):
        return AllGlobalBlockMap[block_func].superFunc

    superStackFunc = superFuncForStackBlock(block_func)
    return superStackFunc # maybe None

resultDict = {}


def findBlockName(block_func):
    # print "find block name  %X" % block_func
    proc = TextSeg.getProcedureAtAddress(block_func)
    if not proc:
        return ""
    funcName = doc.getNameAtAddress(proc.getEntryPoint())

    if len(funcName) != 0 and funcName[0] in ('-', '+'):
        return funcName

    # maybe nested block
    superBlockFuncAddr = superFuncForBlockFunc(block_func)
    if superBlockFuncAddr == None:
        return "";
    if not IS_MAC:
        superBlockFuncAddr = superBlockFuncAddr | TextSeg.isThumbAtAddress(superBlockFuncAddr) # thumb

    superBlockName = findBlockName(superBlockFuncAddr)

    if len(superBlockName) == 0:
        return ""
    else:
        return superBlockName + "_block"

def main():
    for struct in SymbolSeg.getReferencesOfAddress(GlobalBlockAddr):
        func = 0L
        FUNC_OFFSET_IN_BLOCK = 12 if IS32BIT else 16
        if IS32BIT:
            func = DataSeg.readUInt32LE(struct + FUNC_OFFSET_IN_BLOCK)
        else:
            func = DataSeg.readUInt64LE(struct + FUNC_OFFSET_IN_BLOCK)


        info = GlobalBlockInfo()
        info.func = func
        info.struct = struct
        if len(DataSeg.getReferencesOfAddress(struct)) == 0:
            continue
        refTo = DataSeg.getReferencesOfAddress(struct)[0]
        if isInText(refTo):
            info.superFunc = TextSeg.getProcedureAtAddress(refTo).getEntryPoint()
        elif isInData(refTo):
            ref = DataSeg.getReferencesOfAddress(refTo)[0]
            info.superFunc = TextSeg.getProcedureAtAddress(ref).getEntryPoint()

        AllGlobalBlockMap[func] = info

#find all possible Stack Block 
    allPossibleStackBlockFunc = []
    allRefToBlock=[]
    StackBlockAddr = doc.getAddressForName("__NSConcreteStackBlock")
    # if IS32BIT:
    allRefToBlock = DataSeg.getReferencesOfAddress(SymbolSeg.getReferencesOfAddress(StackBlockAddr)[0])
    allRefToBlock = filter(lambda x:isInText(x), allRefToBlock)

    for addr in allRefToBlock:
        proc = TextSeg.getProcedureAtAddress(addr)
        if not proc:
            continue
        LineNumAround = 30 #Around 30 instruction
        instr_size = 15 if IS_MAC else 4
        scan_addr_min = max (addr - LineNumAround * instr_size, proc.getEntryPoint())
        scan_addr_max = min (addr + LineNumAround * instr_size, proc.getBasicBlockAtAddress(addr).getEndingAddress())
        for scan_addr in range(scan_addr_min, scan_addr_max):
            allPossibleStackBlockFunc += TextSeg.getReferencesFromAddress(scan_addr) # all function pointer used around __NSConcreteStackBlock

    allPossibleStackBlockFunc = list (set (allPossibleStackBlockFunc))

    allPossibleStackBlockFunc = filter(lambda x:isPossibleStackBlockForFunc(x) , allPossibleStackBlockFunc )


#process all Global Block 
    for block_func in AllGlobalBlockMap:
        block_name = findBlockName(block_func)
        resultDict[block_func] =  block_name

    for block_func in allPossibleStackBlockFunc:
        block_name = findBlockName(block_func)
        resultDict[block_func] = block_name

    log('Success!')
    output_file = doc.askFile('~/', 'block_symbol.json', 'save')
    list_output = []
    error_num = 0
    for addr in resultDict:
        name = resultDict[addr]
        if len(name) == 0 or name[0] not in ('-', '+'):
            error_num += 1
            continue

        list_output += [{"address":("0x%X" % addr), "name":name}]

    encodeJson = json.dumps(list_output, indent=1)
    f = open(output_file if output_file else "~/block_symbol.json" , "w")
    f.write(encodeJson)
    f.close()
    log('\nrestore block num %d ' % len(list_output))
    log('\norigin  block num: %d(GlobalBlock: %d, StackBlock: %d)' % (len(allRefToBlock) + len(AllGlobalBlockMap), len(AllGlobalBlockMap), len(allRefToBlock)))


try:
    main()
    log('Done!')
except Exception as e:
    log('-----------------\n\033[1;31mException Occured For:\033[0m\n' + str(e) + '\nStack Info:\n' +  traceback.format_exc() + '\n------------------')
