#import "StreamClient.h"
#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>
#import <CoreMediaIO/CMIOHardware.h>
#import <iostream>
#include <sys/socket.h>
#include <TargetConditionals.h>
#include <CoreMedia/CoreMedia.h>
#include <Foundation/Foundation.h>
#include <VideoToolbox/VideoToolbox.h>

#if TARGET_RT_BIG_ENDIAN
#   define FourCC2Str(fourcc) (const char[]){*((char*)&fourcc), *(((char*)&fourcc)+1), *(((char*)&fourcc)+2), *(((char*)&fourcc)+3),0}
#else
#   define FourCC2Str(fourcc) (const char[]){*(((char*)&fourcc)+3), *(((char*)&fourcc)+2), *(((char*)&fourcc)+1), *(((char*)&fourcc)+0),0}
#endif

typedef NS_ENUM(NSUInteger, VEVideoEncoderProfileLevel)
{
    VEVideoEncoderProfileLevelBP,
    VEVideoEncoderProfileLevelMP,
    VEVideoEncoderProfileLevelHP
};



@interface VideoSource : NSObject <AVCaptureVideoDataOutputSampleBufferDelegate>

@property (assign) AVCaptureSession *mSession;
@property (assign) AVCaptureDevice *mDevice;
@property (assign) AVCaptureDeviceInput *mDeviceInput;
@property (assign) AVCaptureVideoDataOutput *mDeviceOutput; //视频输出

@property (assign) StreamClient *mClient;

- (id) init:(StreamClient *)client;

@end

@implementation VideoSource

- (id) init:(StreamClient *)client ; {
    [super init];

    self.mClient = client;
    self.mSession = [[AVCaptureSession alloc] init];

    return self;
}

- (void)dealloc ; {
    [self.mSession release];
    [self.mDevice release];
    [self.mDeviceOutput release];
    [self.mDeviceInput release];
    [super dealloc];
}

- (bool) setupDevice:(NSString *)udid ; {
    // Waiting for iOS devices to appear after enabling DAL plugins.
    // This is a really ugly place and should be refactored
    for (int i = 0 ; i < 10 and [AVCaptureDevice deviceWithUniqueID: udid] == nil ; i++) {
        [[NSRunLoop mainRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.1]];
    }

    NSLog(@"Available devices:");
    for (AVCaptureDevice *device in [AVCaptureDevice devicesWithMediaType: AVMediaTypeMuxed]) {
        NSLog(@"%@", device.uniqueID);
    }
    for (AVCaptureDevice *device in [AVCaptureDevice devicesWithMediaType: AVMediaTypeVideo]) {
        NSLog(@"%@", device.uniqueID);
    }

    self.mDevice = [AVCaptureDevice deviceWithUniqueID: udid];

    if (self.mDevice == nil) {
        NSLog(@"device with udid '%@' not found", udid);
        return false;
    }
    
    [self.mSession beginConfiguration];

    // Add session input
    NSError *error;
    self.mDeviceInput = [AVCaptureDeviceInput deviceInputWithDevice:self.mDevice error:&error];
    //chuanpu 这里设置以下帧率，假如帧率太高会卡captureDeviceInput ===>mDeviceInput,15帧，待测试
    // self.mDeviceInput.device.activeVideoMinFrameDuration = CMTimeMake(1, 15);
    if (self.mDeviceInput == nil) {
        NSLog(@"%@", error);
        return false;
    } else {
        [self.mSession addInput:self.mDeviceInput];
    }
    
    // Add session output
    self.mDeviceOutput = [[AVCaptureVideoDataOutput alloc] init];
    self.mDeviceOutput.alwaysDiscardsLateVideoFrames = YES; // chuanpu 丢弃延迟的帧
    [self updateFrameDuration:CMTimeMake(1, 15) forDevice:self.mDevice];

    // chuanpu 设置视频数据格式
    self.mDeviceOutput.videoSettings = [NSDictionary dictionaryWithObjectsAndKeys:
        AVVideoScalingModeResizeAspect, (id)AVVideoScalingModeKey,
//        [NSNumber numberWithUnsignedInt:400], (id)kCVPixelBufferWidthKey,
//        [NSNumber numberWithUnsignedInt:600], (id)kCVPixelBufferHeightKey,
        [NSNumber numberWithUnsignedInt:kCVPixelFormatType_32BGRA], (id)kCVPixelBufferPixelFormatTypeKey,
        nil];
    
    NSDictionary *videoSetting = [NSDictionary dictionaryWithObjectsAndKeys: [NSNumber numberWithInt:kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange], kCVPixelBufferPixelFormatTypeKey, nil];

    [self.mDeviceOutput setVideoSettings:videoSetting];
    // 设置输出代理、串行队列和数据回调
    dispatch_queue_t videoQueue = dispatch_queue_create("videoQueue", DISPATCH_QUEUE_SERIAL);

    [self.mDeviceOutput setSampleBufferDelegate:self queue:videoQueue];

    [self.mSession addOutput:self.mDeviceOutput];
    [self.mSession commitConfiguration];
    return true;
}

- (BOOL)updateFrameDuration:(CMTime)frameDuration forDevice:(AVCaptureDevice *)device {
    __block BOOL support = NO;
    [device.activeFormat.videoSupportedFrameRateRanges enumerateObjectsUsingBlock:^(AVFrameRateRange * _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
        if (CMTimeCompare(frameDuration, obj.minFrameDuration) >= 0 &&
            CMTimeCompare(frameDuration, obj.maxFrameDuration) <= 0) {
            support = YES;
            *stop = YES;
        }
    }];
    
    if (support) {
        [device setActiveVideoMinFrameDuration:frameDuration];
        [device setActiveVideoMaxFrameDuration:frameDuration];
        return YES;
    }
    
    return NO;
}

- (void) captureOutput:(AVCaptureOutput *)captureOutput didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer fromConnection:(AVCaptureConnection *)connection {
//    NSLog(@"初始化：captureOutput");
    int value = (arc4random() % 2) +1;
    if(value == 1) {
        self.mClient->captureOutput(sampleBuffer);
    }
}

@end

//-------------------------------------------------------------------

@interface VEVideoEncoderParam : NSObject

/** ProfileLevel 默认为BP */
@property (nonatomic, assign) VEVideoEncoderProfileLevel profileLevel;
/** 编码内容的宽度 */
@property (nonatomic, assign) NSInteger encodeWidth;
/** 编码内容的高度 */
@property (nonatomic, assign) NSInteger encodeHeight;
/** 编码类型 */
@property (nonatomic, assign) CMVideoCodecType encodeType;
/** 码率 单位kbps */
@property (nonatomic, assign) NSInteger bitRate;
/** 帧率 单位为fps，缺省为15fps */
@property (nonatomic, assign) NSInteger frameRate;
/** 最大I帧间隔，单位为秒，缺省为240秒一个I帧 */
@property (nonatomic, assign) NSInteger maxKeyFrameInterval;
/** 是否允许产生B帧 缺省为NO */
@property (nonatomic, assign) BOOL allowFrameReordering;

@end

@implementation VEVideoEncoderParam

- (instancetype)init
{
    self = [super init];
    if (self)
    {
        self.profileLevel = VEVideoEncoderProfileLevelBP;
        self.encodeType = kCMVideoCodecType_H264;
        self.bitRate = 100 * 100;
        self.frameRate = 15; //帧率15
        self.maxKeyFrameInterval = 30;
        self.allowFrameReordering = NO;
    }
    return self;
}

@end

 @protocol VEVideoEncoderDelegate <NSObject>

 /**
  编码输出数据

  @param data 输出数据
  @param isKeyFrame 是否为关键帧
  */
 - (void)videoEncodeOutputDataCallback:(NSData *)data isKeyFrame:(BOOL)isKeyFrame;

 @end


 @interface VEVideoEncoder : NSObject

 /** 代理 */
 @property (nonatomic, weak) id<VEVideoEncoderDelegate> delegate;
 /** 编码参数 */
 @property (nonatomic, strong) VEVideoEncoderParam *videoEncodeParam;

 @property (assign) StreamClient *mClient;

@property (nonatomic, assign) BOOL needsps;

@property (nonatomic, assign) int frameID;


 /**
  初始化方法

  @param param 编码参数
  @return 实例
  */
 - (instancetype)initWithParam:(VEVideoEncoderParam *)param;

 /**
  开始编码

  @return 结果
  */
 - (BOOL)startVideoEncode;

 /**
  停止编码

  @return 结果
  */
 - (BOOL)stopVideoEncode;

 /**
  输入待编码数据

  @param sampleBuffer 待编码数据
  @param forceKeyFrame 是否强制I帧
  @return 结果
  */
 - (BOOL)videoEncodeInputData:(CMSampleBufferRef)sampleBuffer forceKeyFrame:(BOOL)forceKeyFrame;
 /**
  编码过程中调整码率

  @param bitRate 码率
  @return 结果
  */
 - (BOOL)adjustBitRate:(NSInteger)bitRate;

 @end

@interface VEVideoEncoder ()

@property (assign, nonatomic) VTCompressionSessionRef compressionSessionRef;

@property (nonatomic, strong) dispatch_queue_t operationQueue;

@end

@implementation VEVideoEncoder


- (void)dealloc
{
    NSLog(@"%s", __func__);
    if (NULL == _compressionSessionRef)
    {
        return;
    }
    VTCompressionSessionCompleteFrames(_compressionSessionRef, kCMTimeInvalid);
    VTCompressionSessionInvalidate(_compressionSessionRef);
    CFRelease(_compressionSessionRef);
    _compressionSessionRef = NULL;
}

/**
 初始化方法

 @param param 编码参数
 @return 实例
 */
- (instancetype)initWithParam:(VEVideoEncoderParam *)param
{
//    VEVideoEncoderParam *param = [[VEVideoEncoderParam alloc] init];
//    param.encodeWidth = 180;
//    param.encodeHeight = 320;
//    param.bitRate = 512 * 1024;
    if (self = [super init])
    {
        self.videoEncodeParam = param;
        
        self.needsps = YES;
        
        self.frameID = 0;
        
        // 创建硬编码器
        OSStatus status = VTCompressionSessionCreate(NULL, (int)self.videoEncodeParam.encodeWidth, (int)self.videoEncodeParam.encodeHeight, self.videoEncodeParam.encodeType, NULL, NULL, NULL, encodeOutputDataCallback, (__bridge void *)(self), &_compressionSessionRef);
        if (noErr != status)
        {
            NSLog(@"VEVideoEncoder::VTCompressionSessionCreate:failed status:%d", (int)status);
            return nil;
        }
        if (NULL == self.compressionSessionRef)
        {
            NSLog(@"VEVideoEncoder::调用顺序错误");
            return nil;
        }

        // 设置码率 平均码率
        if (![self adjustBitRate:self.videoEncodeParam.bitRate])
        {
            return nil;
        }
        
//        int bitRate = self.videoEncodeParam.bitRate;
//        CFNumberRef bitRateRef = CFNumberCreate(kCFAllocatorDefault, kCFNumberSInt32Type, &bitRate);
//        VTSessionSetProperty(_compressionSessionRef, kVTCompressionPropertyKey_AverageBitRate, bitRateRef);
//        NSArray *limit = @[@(self.videoEncodeParam.bitRate * 1.5/4), @(1)];
//        VTSessionSetProperty(_compressionSessionRef, kVTCompressionPropertyKey_DataRateLimits, (__bridge CFArrayRef)limit);


        // ProfileLevel，h264的协议等级，不同的清晰度使用不同的ProfileLevel。
        CFStringRef profileRef = kVTProfileLevel_H264_Baseline_AutoLevel;
        switch (self.videoEncodeParam.profileLevel)
        {
            case VEVideoEncoderProfileLevelBP:
                profileRef = kVTProfileLevel_H264_Baseline_3_1;
                break;
            case VEVideoEncoderProfileLevelMP:
                profileRef = kVTProfileLevel_H264_Main_3_1;
                break;
            case VEVideoEncoderProfileLevelHP:
                profileRef = kVTProfileLevel_H264_High_3_1;
                break;
        }
        status = VTSessionSetProperty(_compressionSessionRef, kVTCompressionPropertyKey_ProfileLevel,kVTProfileLevel_H264_High_3_1);
        CFRelease(profileRef);
        if (noErr != status)
        {
            NSLog(@"VEVideoEncoder::kVTCompressionPropertyKey_ProfileLevel failed status:%d", (int)status);
            return nil;
        }

        // 设置实时编码输出（避免延迟）
        status = VTSessionSetProperty(_compressionSessionRef, kVTCompressionPropertyKey_RealTime, kCFBooleanTrue);
        if (noErr != status)
        {
            NSLog(@"VEVideoEncoder::kVTCompressionPropertyKey_RealTime failed status:%d", (int)status);
            return nil;
        }

        // 配置是否产生B帧
        status = VTSessionSetProperty(_compressionSessionRef, kVTCompressionPropertyKey_AllowFrameReordering, NO ? kCFBooleanTrue : kCFBooleanFalse);
        if (noErr != status)
        {
            NSLog(@"VEVideoEncoder::kVTCompressionPropertyKey_AllowFrameReordering failed status:%d", (int)status);
            return nil;
        }

        // 配置I帧间隔
        status = VTSessionSetProperty(_compressionSessionRef,
                                      kVTCompressionPropertyKey_MaxKeyFrameInterval, (__bridge CFTypeRef)@(self.videoEncodeParam.frameRate * self.videoEncodeParam.maxKeyFrameInterval));
        if (noErr != status)
        {
            NSLog(@"VEVideoEncoder::kVTCompressionPropertyKey_MaxKeyFrameInterval failed status:%d", (int)status);
            return nil;
        }
        status = VTSessionSetProperty(_compressionSessionRef,
                                      kVTCompressionPropertyKey_MaxKeyFrameIntervalDuration,
                                      (__bridge CFTypeRef)@(self.videoEncodeParam.maxKeyFrameInterval));
        if (noErr != status)
        {
            NSLog(@"VEVideoEncoder::kVTCompressionPropertyKey_MaxKeyFrameIntervalDuration failed status:%d", (int)status);
            return nil;
        }
        
//        int fps = 10;
//        CFNumberRef fpsRef = CFNumberCreate(kCFAllocatorDefault, kCFNumberIntType, &fps);
//        VTSessionSetProperty(_compressionSessionRef, kVTCompressionPropertyKey_ExpectedFrameRate, fpsRef);
//
        // 编码器准备编码
        status = VTCompressionSessionPrepareToEncodeFrames(_compressionSessionRef);

        if (noErr != status)
        {
            NSLog(@"VEVideoEncoder::VTCompressionSessionPrepareToEncodeFrames failed status:%d", (int)status);
            return nil;
        }
    }
    return self;
}

/**
 开始编码

 @return 结果
 */
- (BOOL)startVideoEncode
{
    if (NULL == self.compressionSessionRef)
    {
        NSLog(@"VEVideoEncoder::调用顺序错误");
        return NO;
    }
   
    // 编码器准备编码
    OSStatus status = VTCompressionSessionPrepareToEncodeFrames(_compressionSessionRef);
    if (noErr != status)
    {
        NSLog(@"VEVideoEncoder::VTCompressionSessionPrepareToEncodeFrames failed status:%d", (int)status);
        return NO;
    }
    return YES;
}

/**
 停止编码

 @return 结果
 */
- (BOOL)stopVideoEncode
{
    if (NULL == _compressionSessionRef)
    {
        return NO;
    }
    
    
    OSStatus status = VTCompressionSessionCompleteFrames(_compressionSessionRef, kCMTimeInvalid);
    
    if (noErr != status)
    {
        NSLog(@"VEVideoEncoder::VTCompressionSessionCompleteFrames failed! status:%d", (int)status);
        return NO;
    }
    return YES;
}

/**
 编码过程中调整码率

 @param bitRate 码率
 @return 结果
 */
- (BOOL)adjustBitRate:(NSInteger)bitRate
{
    if (bitRate <= 0)
    {
        NSLog(@"VEVideoEncoder::adjustBitRate failed! bitRate <= 0");
        return NO;
    }
    OSStatus status = VTSessionSetProperty(_compressionSessionRef, kVTCompressionPropertyKey_AverageBitRate, (__bridge CFTypeRef)@(bitRate));
    if (noErr != status)
    {
        NSLog(@"VEVideoEncoder::kVTCompressionPropertyKey_AverageBitRate failed status:%d", (int)status);
        return NO;
    }
    
    // 参考webRTC 限制最大码率不超过平均码率的1.5倍
    int64_t dataLimitBytesPerSecondValue = bitRate * 1.5 / 8;
    CFNumberRef bytesPerSecond = CFNumberCreate(kCFAllocatorDefault, kCFNumberSInt64Type, &dataLimitBytesPerSecondValue);
    int64_t oneSecondValue = 1;
    CFNumberRef oneSecond = CFNumberCreate(kCFAllocatorDefault, kCFNumberSInt64Type, &oneSecondValue);
    const void* nums[2] = {bytesPerSecond, oneSecond};
    CFArrayRef dataRateLimits = CFArrayCreate(NULL, nums, 2, &kCFTypeArrayCallBacks);
    status = VTSessionSetProperty( _compressionSessionRef, kVTCompressionPropertyKey_DataRateLimits, dataRateLimits);
    if (noErr != status)
    {
        NSLog(@"VEVideoEncoder::kVTCompressionPropertyKey_DataRateLimits failed status:%d", (int)status);
        return NO;
    }
    return YES;
}

/**
 输入待编码数据

 @param sampleBuffer 待编码数据
 @param forceKeyFrame 是否强制I帧
 @return 结果
 */
- (BOOL)videoEncodeInputData:(CMSampleBufferRef)sampleBuffer forceKeyFrame:(BOOL)forceKeyFrame
{
//    NSLog(@"进入 videoEncodeInputData");
    if (NULL == _compressionSessionRef)
    {
        return NO;
    }
    
    if (nil == sampleBuffer)
    {
        return NO;
    }
    
    CMTime presentationTimeStamp = CMTimeMake(self.frameID++, 1000);
    CVImageBufferRef pixelBuffer = (CVImageBufferRef)CMSampleBufferGetImageBuffer(sampleBuffer);
    NSDictionary *frameProperties = @{(__bridge NSString *)kVTEncodeFrameOptionKey_ForceKeyFrame: @(forceKeyFrame)};
    
    OSStatus status = VTCompressionSessionEncodeFrame(_compressionSessionRef, pixelBuffer, presentationTimeStamp, kCMTimeInvalid, (__bridge CFDictionaryRef)frameProperties, NULL, NULL);
    if (noErr != status)
    {
        //新增，待测试 出错释放
        VTCompressionSessionInvalidate(_compressionSessionRef);
        CFRelease(_compressionSessionRef);
        _compressionSessionRef = NULL;
        NSLog(@"VEVideoEncoder::VTCompressionSessionEncodeFrame failed! status:%d", (int)status);
        return NO;
    }
    return YES;
}

void encodeOutputDataCallback(void * CM_NULLABLE outputCallbackRefCon, void * CM_NULLABLE sourceFrameRefCon, OSStatus status, VTEncodeInfoFlags infoFlags, CM_NULLABLE CMSampleBufferRef sampleBuffer)
{
//    NSLog(@"进入 encodeOutputDataCallback");

    if (noErr != status || nil == sampleBuffer)
    {
        NSLog(@"VEVideoEncoder::encodeOutputCallback Error : %d!", (int)status);
        return;
    }
    
    if (nil == outputCallbackRefCon)
    {
        return;
    }
    
    if (!CMSampleBufferDataIsReady(sampleBuffer))
    {
        return;
    }
    
    if (infoFlags & kVTEncodeInfo_FrameDropped)
    {
        NSLog(@"VEVideoEncoder::H264 encode dropped frame.");
        return;
    }
    
    VEVideoEncoder *encoder = (__bridge VEVideoEncoder *)outputCallbackRefCon;
    const char header[] = "\x00\x00\x00\x01";
    size_t headerLen = (sizeof header) - 1;
    NSData *headerData = [NSData dataWithBytes:header length:headerLen];
    
    // 判断是否是关键帧
    bool isKeyFrame = !CFDictionaryContainsKey((CFDictionaryRef)CFArrayGetValueAtIndex(CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, true), 0), (const void *)kCMSampleAttachmentKey_NotSync);
    
    if (isKeyFrame)
    {
        NSLog(@"VEVideoEncoder::编码了一个关键帧");
//        encoder.needsps = NO;
        CMFormatDescriptionRef formatDescriptionRef = CMSampleBufferGetFormatDescription(sampleBuffer);
        
        // 关键帧需要加上SPS、PPS信息
        size_t sParameterSetSize, sParameterSetCount;
        const uint8_t *sParameterSet;
        OSStatus spsStatus = CMVideoFormatDescriptionGetH264ParameterSetAtIndex(formatDescriptionRef, 0, &sParameterSet, &sParameterSetSize, &sParameterSetCount, 0);
        
        size_t pParameterSetSize, pParameterSetCount;
        const uint8_t *pParameterSet;
        OSStatus ppsStatus = CMVideoFormatDescriptionGetH264ParameterSetAtIndex(formatDescriptionRef, 1, &pParameterSet, &pParameterSetSize, &pParameterSetCount, 0);
        
        NSLog(@"spsStatus Error : %d!", (int)spsStatus);
        NSLog(@"ppsStatus Error : %d!", (int)ppsStatus);
        if (noErr == spsStatus && noErr == ppsStatus)
        {
            NSLog(@"进入sps和pps编码");
            NSData *sps = [NSData dataWithBytes:sParameterSet length:sParameterSetSize];
            NSData *pps = [NSData dataWithBytes:pParameterSet length:pParameterSetSize];
            NSMutableData *spsData = [NSMutableData data];
            [spsData appendData:headerData];
            [spsData appendData:sps];
            NSUInteger len = [spsData length];
            Byte *byteData = (Byte*)malloc(len);
            memcpy(byteData, [spsData bytes], len);
            encoder.mClient->videoEncodeOutputDataCallback(byteData, isKeyFrame, len);
            NSMutableData *ppsData = [NSMutableData data];
            [ppsData appendData:headerData];
            [ppsData appendData:pps];
            
            NSUInteger lenppsData = [ppsData length];
            Byte *byteDatapps = (Byte*)malloc(lenppsData);
            memcpy(byteDatapps, [ppsData bytes], lenppsData);
            encoder.mClient->videoEncodeOutputDataCallback(byteDatapps, isKeyFrame, lenppsData);
        }
    
    }
    CMBlockBufferRef blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer);
    size_t length, totalLength;
    char *dataPointer;
    status = CMBlockBufferGetDataPointer(blockBuffer, 0, &length, &totalLength, &dataPointer);
    if (noErr != status)
    {
        NSLog(@"VEVideoEncoder::CMBlockBufferGetDataPointer Error : %d!", (int)status);
        return;
    }
    
    size_t bufferOffset = 0;
    static const int avcHeaderLength = 4;
    while (bufferOffset < totalLength - avcHeaderLength)
    {
        //        NSLog(@"读取 NAL 单元长度");
        uint32_t nalUnitLength = 0;
        memcpy(&nalUnitLength, dataPointer + bufferOffset, avcHeaderLength);

        // 大端转小端
        nalUnitLength = CFSwapInt32BigToHost(nalUnitLength);

        NSData *frameData = [[NSData alloc] initWithBytes:(dataPointer + bufferOffset + avcHeaderLength) length:nalUnitLength];

        NSMutableData *outputFrameData = [NSMutableData data];
        [outputFrameData appendData:headerData];
        [outputFrameData appendData:frameData];

        bufferOffset += avcHeaderLength + nalUnitLength;
//        NSLog(@"data,%@",outputFrameData);
        NSUInteger len = [outputFrameData length];
        Byte *byteData = (Byte*)malloc(len);
        memcpy(byteData, [outputFrameData bytes], len);
        encoder.mClient->videoEncodeOutputDataCallback(byteData, isKeyFrame, len);
    }
    
}

@end


struct StreamClientImpl {
    VideoSource* mVideoSource;
    VEVideoEncoder* mVEVideoEncoder;
};

void EnableDALDevices()
{
    std::cout << "EnableDALDevices" << std::endl;
    CMIOObjectPropertyAddress prop = {
            kCMIOHardwarePropertyAllowScreenCaptureDevices,
            kCMIOObjectPropertyScopeGlobal,
            kCMIOObjectPropertyElementMaster
    };
    UInt32 allow = 1;
    CMIOObjectSetPropertyData(kCMIOObjectSystemObject,
                              &prop, 0, NULL,
                              sizeof(allow), &allow );
}


StreamClient::StreamClient() {
    EnableDALDevices();

    impl = new StreamClientImpl();
    impl->mVideoSource = [[VideoSource alloc] init: this];
    //chuanpu 初始化VideoEncoder
    VEVideoEncoderParam *encodeParam = [[VEVideoEncoderParam alloc] init];
    encodeParam.encodeWidth = 1080;
    encodeParam.encodeHeight = 1920;
    encodeParam.bitRate = 10000 * 1024 ;
    impl->mVEVideoEncoder = [[VEVideoEncoder alloc] initWithParam:encodeParam];
//    std::cout << "VEVideoEncoder 初始化" << std::endl;
    [impl->mVEVideoEncoder startVideoEncode];
    impl->mVEVideoEncoder.mClient = impl->mVideoSource.mClient;
    mBuffer = 0;
    mLockedBuffer = 0;
}

StreamClient::~StreamClient() {
    if (impl) {
        [impl->mVideoSource release];
    }
    delete impl;
    if (mBuffer) {
        CFRetain(mBuffer);
    }
    if (mLockedBuffer) {
        CFRetain(mLockedBuffer);
    }
}

bool StreamClient::setupDevice(const char *udid) {
    NSString *_udid = [NSString stringWithUTF8String:udid];
    return [impl->mVideoSource setupDevice:_udid];
}

void StreamClient::start() {
    [impl->mVideoSource.mSession startRunning];
}

void StreamClient::stop() {
    [impl->mVideoSource.mSession stopRunning];
}

void StreamClient::captureOutput(CMSampleBufferRef buffer) {
    [impl->mVEVideoEncoder videoEncodeInputData:buffer forceKeyFrame:NO];
}

void StreamClient::setFrameListener(FrameListener *listener) {
    mFrameListener = listener;
}

void StreamClient::setSocket(int s) {
    socket = s;
}

void StreamClient::lockFrame(Frame *frame) {

}

void StreamClient::releaseFrame(Frame *frame) {
}

void StreamClient::setResolution(uint32_t width, uint32_t height) {
    [impl->mVideoSource.mSession beginConfiguration];
    NSMutableDictionary *settings = [impl->mVideoSource.mDeviceOutput.videoSettings mutableCopy];
    [settings setObject:[NSNumber numberWithUnsignedInt:width] forKey:(id)kCVPixelBufferWidthKey];
    [settings setObject:[NSNumber numberWithUnsignedInt:height] forKey:(id)kCVPixelBufferHeightKey];
    impl->mVideoSource.mDeviceOutput.videoSettings = settings;
    [impl->mVideoSource.mSession commitConfiguration];
}

void StreamClient::videoEncodeOutputDataCallback(Byte *data1, bool isKeyFrame, int length) {

    char* data = (char*)data1;
//    char* data = reinterpret_cast<unsigned char *>(data1)

    do {
        // SIGPIPE is set to ignored so we will just get EPIPE instead
        ssize_t wrote = send(socket, data, length, 0);

        if (wrote < 0) {
            break;
        }

        data += wrote;
        length -= wrote;
    }
    while (length > 0);
    
}

