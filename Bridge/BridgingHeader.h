/*
 * Copyright 2025 Hiroki Kawakami
 */

#pragma once
#import <Foundation/Foundation.h>
#import <IOKit/i2c/IOI2CInterface.h>
#import <CoreGraphics/CoreGraphics.h>

typedef CFTypeRef IOAVService;
extern IOAVService IOAVServiceCreate(CFAllocatorRef allocator);
extern IOAVService IOAVServiceCreateWithService(CFAllocatorRef allocator, io_service_t service);
extern IOReturn IOAVServiceReadI2C(IOAVService service, uint32_t chipAddress, uint32_t offset, void *outputBuffer, uint32_t outputBufferSize);
extern IOReturn IOAVServiceWriteI2C(IOAVService service, uint32_t chipAddress, uint32_t dataAddress, const void *inputBuffer, uint32_t inputBufferSize);
extern CFDictionaryRef CoreDisplay_DisplayCreateInfoDictionary(CGDirectDisplayID);

typedef union {
    uint8_t rawData[0xDC];
    struct {
        uint32_t mode;
        uint32_t flags;        // 0x4
        uint32_t width;        // 0x8
        uint32_t height;    // 0xC
        uint32_t depth;        // 0x10
        uint32_t dc2[42];
        uint16_t dc3;
        uint16_t freq;        // 0xBC
        uint32_t dc4[4];
        float density;        // 0xD0
    } derived;
} modes_D4;

extern void CGSGetCurrentDisplayMode(CGDirectDisplayID display, int* modeNum);
extern void CGSGetNumberOfDisplayModes(CGDirectDisplayID display, int* nModes);
extern void CGSGetDisplayModeDescriptionOfLength(CGDirectDisplayID display, int idx, modes_D4* mode, int length);
extern void CGSConfigureDisplayMode(CGDisplayConfigRef config, CGDirectDisplayID display, int modeNum);
extern CGError CGSConfigureDisplayEnabled(CGDisplayConfigRef config, CGDirectDisplayID display, bool enabled);
