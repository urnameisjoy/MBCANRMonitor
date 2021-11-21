//
//  MBCCallStack.m
//  tttttt
//
//  Created by xyl on 2021/7/28.
//  Copyright © 2021 xyl. All rights reserved.
//

#import "MBCCallStack.h"
#import "MBCCallLib.h"

typedef struct MBCStackFrame {
    const struct MBCStackFrame *const previous;
    const uintptr_t return_address;
} MBCStackFrame;

static mach_port_t main_thread_id;

@implementation MBCCallStack

+ (void)load {
    main_thread_id = mach_thread_self();
}

+ (NSString *)callStackWithType:(MBCCallStackType)type needSymbolicate:(BOOL)symbolicate {
    NSString *result;
    switch (type) {
        case MBCCallStackTypeAll:
        {
            thread_act_array_t threads;
            mach_msg_type_number_t threadCount = 0;
            kern_return_t kr = task_threads(mach_task_self(), &threads, &threadCount);
            if (kr != KERN_SUCCESS) {
                return @"Fail to get information of all threads";
            }
            NSMutableString *reStr = [NSMutableString stringWithFormat:@"Call Backtrace of %u threads:\n", threadCount];
            for (int i = 0; i < threadCount; i++) {
                [reStr appendString:mbcStackOfThread(threads[i], symbolicate)];
            }
            result = [reStr copy];
            assert(vm_deallocate(mach_task_self(), (vm_address_t)threads, sizeof(thread_t) * threadCount) == KERN_SUCCESS);
        } break;
        case MBCCallStackTypeMain:
        {
            NSString *reStr = mbcStackOfThread((thread_t)main_thread_id, symbolicate);
            assert(vm_deallocate(mach_task_self(), (vm_address_t)main_thread_id, sizeof(thread_t)) == KERN_SUCCESS);
            result = [reStr copy];
        } break;
        case MBCCallStackTypeCurrent:
        {
            char name[256];
            mach_msg_type_number_t count;
            thread_act_array_t list;
            task_threads(mach_task_self(), &list, &count);
            NSTimeInterval currentTimestamp = [[NSDate date] timeIntervalSince1970];
            NSThread *nsthread = [NSThread currentThread];
            if ([nsthread isMainThread]) {
                return [self callStackWithType:MBCCallStackTypeMain needSymbolicate:symbolicate];
            }

            NSString *originName = [nsthread name];
            [nsthread setName:[NSString stringWithFormat:@"%f", currentTimestamp]];
            NSString *reStr = @"";
            for (int i = 0; i < count; i++) {
                pthread_t pt = pthread_from_mach_thread_np(list[i]);
                if (pt) {
                    name[0] = '\0';
                    pthread_getname_np(pt, name, sizeof(name));
                    if (!strcmp(name, [nsthread name].UTF8String)) {
                        [nsthread setName:originName];
                        reStr = mbcStackOfThread(list[i], symbolicate);
                        assert(vm_deallocate(mach_task_self(), (vm_address_t)list[i], sizeof(thread_t)) == KERN_SUCCESS);
                        result = [reStr copy];
                        break;
                    }
                }
            }
        } break;
        default:
            break;
    }
    return result;
}

NSString *mbcStackOfThread(thread_t thread, bool symbolicate) {
    uintptr_t buffer[50];
    int i = 0;
    NSMutableString *reStr = [NSMutableString stringWithFormat:@"Stack of thread: %u%@", thread, thread == main_thread_id ? @"(main)" : @""];
    
    _STRUCT_MCONTEXT machineContext;
    mach_msg_type_number_t state_count = mbcThreadStateCountByCPU();
    kern_return_t kr = thread_get_state(thread, mbcThreadStateByCPU(), (thread_state_t)&machineContext.__ss, &state_count);
    if (kr != KERN_SUCCESS) {
        return [NSString stringWithFormat:@"Fail to get information about thread: %u\n", thread];
    }
    const uintptr_t instructionAddress = mbcMachInstructionPointerByCPU(&machineContext);
    buffer[i] = instructionAddress;
    ++i;
    
    uintptr_t linkRegisterPtr = mbcMachThreadGetLinkRegisterPointerByCPU(&machineContext);
    if (linkRegisterPtr) {
        buffer[i] = linkRegisterPtr;
        i++;
    }
    
    if (instructionAddress == 0) {
        return @"Fail to get instruction address";
    }
    
    MBCStackFrame stackFrame = {0};
    const uintptr_t framePtr = mbcMachStackBasePointerByCPU(&machineContext);
    if (framePtr == 0 || mbcMachMemCopy((void *)framePtr, &stackFrame, sizeof((stackFrame))) != KERN_SUCCESS) {
        return @"Fail to get frame pointer";
    }
    
    for (; i < 50; i++) {
        buffer[i] = stackFrame.return_address;
        if (buffer[i] == 0 ||
            stackFrame.previous == 0 ||
            mbcMachMemCopy(stackFrame.previous, &stackFrame, sizeof(stackFrame)) != KERN_SUCCESS) {
            break;;
        }
    }
    int stackLength = i;
    Dl_info symbolicated[stackLength];
    mbcSymbolicate(buffer, symbolicated, stackLength, 0, symbolicate);
    NSMutableString *stacks = [NSMutableString string];
    for (int i = 0; i < stackLength; i++) {
        [stacks appendString:mbcOutputLog(i, buffer[i], &symbolicated[i], symbolicate)];
    }
    if (!symbolicate) {
        [stacks insertString:@"[" atIndex:0];
        [stacks replaceCharactersInRange:NSMakeRange(stacks.length - 1, 1) withString:@"]"];
        [reStr appendFormat:@"%@", stacks];
    } else {
        [reStr appendFormat:@"\n%@", stacks];
    }
    return [reStr copy];
}

#pragma mark - Symbolicate log

NSString *mbcOutputLog(const int entryNum, const uintptr_t address, const Dl_info* const dlInfo, bool symbolicate) {
    const char* name = dlInfo->dli_fname;
    const char* sname = dlInfo->dli_sname;
    if (name == NULL ||
        (sname == NULL &&
         symbolicate)) {
        return @"";
    }
    char* lastFile = strrchr(dlInfo->dli_fname, '/');
    NSString *fname = @"";
    NSString *format = symbolicate ? @"%-30s" : @"%s";
    if (lastFile == NULL) {
        fname = [NSString stringWithFormat:format, name];
    } else {
        fname = [NSString stringWithFormat:format, lastFile + 1];
    }
    uintptr_t offset = address - (uintptr_t)dlInfo->dli_saddr;
    NSString *result = nil;
    if (symbolicate) {
        result = [NSString stringWithFormat:@"%d %@ 0x%lx %s + %lu\n", entryNum, fname, (uintptr_t)address, sname, offset];
    } else {
        uintptr_t fbase = (uintptr_t)dlInfo->dli_fbase;
        result = [NSString stringWithFormat:@"%d %@ 0x%lx 0x%lx,", entryNum, fname, fbase, (uintptr_t)address];
    }
    return result;
}

void mbcSymbolicate(const uintptr_t* const stackBuffer, Dl_info* const symbolsBuffer, const int stackLength, const int skippedEntries, bool symbolicate) {
    int i = 0;
    if (!skippedEntries && i < stackLength) {
        mbcDladder(stackBuffer[i], &symbolsBuffer[i], symbolicate);
        i++;
    }
    for (; i < stackLength; i++) {
        mbcDladder(mbcInstructionAddressByCPU(stackBuffer[i]), &symbolsBuffer[i], symbolicate);
    }
}

bool mbcDladder(const uintptr_t address, Dl_info* const info, bool symbolicate) {
    info->dli_fname = NULL;
    info->dli_fbase = NULL;
    info->dli_sname = NULL;
    info->dli_saddr = NULL;
    const uint32_t idx = mbcDyldImageIndexFromAddress(address);
    if (idx == UINT_MAX) {
        return false;
    }
    
    const struct mach_header* machHeader = _dyld_get_image_header(idx);
    const uintptr_t imageVMAddressSlider = (uintptr_t)_dyld_get_image_vmaddr_slide(idx);
    const uintptr_t addressWithSlider = address - imageVMAddressSlider;
    const uintptr_t segmentBase = mbcSegmentBaseOfImageIndex(idx) + imageVMAddressSlider;
    if (segmentBase == 0) {
        return false;
    }
    info->dli_fname = _dyld_get_image_name(idx);
    info->dli_fbase = (void *)machHeader;
    
    if (!symbolicate) {
        return true;
    }

    const nlistByCPU* bestMatch = NULL;
    uintptr_t bestDistance = ULONG_MAX;
    uintptr_t cmdPtr = mbcCmdFirstPointerFromMachHeader(machHeader);
    if (cmdPtr == 0) {
        return false;
    }
    for (uint32_t iCmd = 0; iCmd < machHeader->ncmds; iCmd++) {
        const struct load_command* loadCmd = (struct load_command*)cmdPtr;
        if (loadCmd->cmd == LC_SYMTAB) {
            const struct symtab_command* symTabCmd = (struct symtab_command*)cmdPtr;
            const nlistByCPU* symbolTable = (nlistByCPU*)(segmentBase + symTabCmd->symoff);
            const uintptr_t stringTable = segmentBase + symTabCmd->stroff;
            
            for (uint32_t iSym = 0; iSym < symTabCmd->nsyms; iSym++) {
                if (symbolTable[iSym].n_value != 0) {
                    uintptr_t symbolBase = symbolTable[iSym].n_value;
                    uintptr_t currentDistance = addressWithSlider - symbolBase;
                    if ((addressWithSlider >= symbolBase) && (currentDistance <= bestDistance)) {
                        bestMatch = symbolTable + iSym;
                        bestDistance = currentDistance;
                    }
                }
            }
            if (bestMatch != NULL) {
                info->dli_saddr = (void *)(bestMatch->n_value + imageVMAddressSlider);
                info->dli_sname = (char *)((intptr_t)stringTable + (intptr_t)bestMatch->n_un.n_strx);
                if (*info->dli_sname == '_') {
                    info->dli_sname++;
                }
                if (info->dli_saddr == info->dli_fbase && bestMatch->n_type == 3) {
                    info->dli_sname = NULL;
                }
                break;
            }
        }
        cmdPtr += loadCmd->cmdsize;
    }
    return true;
}

uint32_t mbcDyldImageIndexFromAddress(const uintptr_t address) {
    const uint32_t imageCount = _dyld_image_count();
    const struct mach_header* machHeader = 0;
    for (uint32_t iImg = 0; iImg < imageCount; iImg++) {
        machHeader = _dyld_get_image_header(iImg);
        if (machHeader != NULL) {
            uintptr_t addressWSlider = address - (uintptr_t)_dyld_get_image_vmaddr_slide(iImg);
            uintptr_t cmdPtr = mbcCmdFirstPointerFromMachHeader(machHeader);
            if (cmdPtr == 0) {
                continue;
            }
            for (uint32_t iCmd = 0; iCmd < machHeader->ncmds; iCmd++) {
                const struct load_command* loadCmd = (struct load_command*)cmdPtr;
                if (loadCmd->cmd == LC_SEGMENT ||
                    loadCmd->cmd == LC_SEGMENT_64) {
                    const segmentComandByCPU* segCmd = (segmentComandByCPU*)cmdPtr;
                    if (addressWSlider >= segCmd->vmaddr &&
                        addressWSlider < segCmd->vmaddr + segCmd->vmsize) {
                        return iImg;
                    }
                }
                cmdPtr += loadCmd->cmdsize;
            }
        }
    }
    return UINT_MAX;
}

uintptr_t mbcCmdFirstPointerFromMachHeader(const struct mach_header* const machHeader) {
    switch (machHeader->magic) {
        case MH_MAGIC:
        case MH_CIGAM:
        case MH_MAGIC_64:
        case MH_CIGAM_64:
            return (uintptr_t)(((machHeaderByCPU*)machHeader) + 1);
        default:
            return 0;
    }
}

uintptr_t mbcSegmentBaseOfImageIndex(const uint32_t idx) {
    const struct mach_header* machHeader = _dyld_get_image_header(idx);
    uintptr_t cmdPtr = mbcCmdFirstPointerFromMachHeader(machHeader);
    if (cmdPtr == 0) {
        return 0;
    }
    for (uint32_t i = 0; i < machHeader->ncmds; i++) {
        const struct load_command* loadCmd = (struct load_command*)cmdPtr;
        if (loadCmd->cmd == LC_SEGMENT ||
            loadCmd->cmd == LC_SEGMENT_64) {
            const segmentComandByCPU* segmentCmd = (segmentComandByCPU*)cmdPtr;
            if (strcmp(segmentCmd->segname, SEG_LINKEDIT) == 0) {
                return (uintptr_t)(segmentCmd->vmaddr - segmentCmd->fileoff);
            }
        }
        cmdPtr += loadCmd->cmdsize;
    }
    return 0;
}

#pragma mark - MachineContext

kern_return_t mbcMachMemCopy(const void *const src, void *const dst, const size_t byteSize) {
    vm_size_t bytesCopied = 0;
    return vm_read_overwrite(mach_task_self(), (vm_address_t)src, (vm_size_t)byteSize, (vm_address_t)dst, &bytesCopied);
}

#pragma mark - Deal with CPU seperate

/*
 //X86 for example
 SP/ESP/RSP: 栈顶部地址的栈指针
 BP/EBP/RBP: 栈基地址指针
 IP/EIP/RIP: 指令指针保留程序计数当前指令地址
 */
uintptr_t mbcMachStackBasePointerByCPU(mcontext_t const machineContext) {
    //Stack base pointer for holding the address of the current stack frame.
#if defined(__arm64__)
    return machineContext->__ss.__fp;
#elif defined(__arm__)
    return machineContext->__ss.__r[7];
#elif defined(__x86_64__)
    return machineContext->__ss.__rbp;
#elif defined(__i386__)
    return machineContext->__ss.__ebp;
#endif
}
uintptr_t mbcMachInstructionPointerByCPU(mcontext_t const machineContext) {
    //Instruction pointer. Holds the program counter, the current instruction address.
#if defined(__arm64__)
    return machineContext->__ss.__pc;
#elif defined(__arm__)
    return machineContext->__ss.__pc;
#elif defined(__x86_64__)
    return machineContext->__ss.__rip;
#elif defined(__i386__)
    return machineContext->__ss.__eip;
#endif
}
uintptr_t mbcInstructionAddressByCPU(const uintptr_t address) {
#if defined(__arm64__)
    const uintptr_t reAddress = ((address) & ~(3UL));
#elif defined(__arm__)
    const uintptr_t reAddress = ((address) & ~(1UL));
#elif defined(__x86_64__)
    const uintptr_t reAddress = (address);
#elif defined(__i386__)
    const uintptr_t reAddress = (address);
#endif
    return reAddress - 1;
}
mach_msg_type_number_t mbcThreadStateCountByCPU(void) {
#if defined(__arm64__)
    return ARM_THREAD_STATE64_COUNT;
#elif defined(__arm__)
    return ARM_THREAD_STATE_COUNT;
#elif defined(__x86_64__)
    return x86_THREAD_STATE64_COUNT;
#elif defined(__i386__)
    return x86_THREAD_STATE32_COUNT;
#endif
}
/*
 * target_thread 的执行状态，比如机器寄存器
 * THREAD_STATE_FLAVOR_LIST 0
 * these are the supported flavors
 #define x86_THREAD_STATE32      1
 #define x86_FLOAT_STATE32       2
 #define x86_EXCEPTION_STATE32   3
 #define x86_THREAD_STATE64      4
 #define x86_FLOAT_STATE64       5
 #define x86_EXCEPTION_STATE64   6
 #define x86_THREAD_STATE        7
 #define x86_FLOAT_STATE         8
 #define x86_EXCEPTION_STATE     9
 #define x86_DEBUG_STATE32       10
 #define x86_DEBUG_STATE64       11
 #define x86_DEBUG_STATE         12
 #define THREAD_STATE_NONE       13
 14 and 15 are used for the internal x86_SAVED_STATE flavours
 #define x86_AVX_STATE32         16
 #define x86_AVX_STATE64         17
 #define x86_AVX_STATE           18
*/
thread_state_flavor_t mbcThreadStateByCPU(void) {
#if defined(__arm64__)
    return ARM_THREAD_STATE64;
#elif defined(__arm__)
    return ARM_THREAD_STATE;
#elif defined(__x86_64__)
    return x86_THREAD_STATE64;
#elif defined(__i386__)
    return x86_THREAD_STATE32;
#endif
}
uintptr_t mbcMachThreadGetLinkRegisterPointerByCPU(mcontext_t const machineContext) {
#if defined(__i386__)
    return 0;
#elif defined(__x86_64__)
    return 0;
#else
    return machineContext->__ss.__lr;
#endif
}

@end
