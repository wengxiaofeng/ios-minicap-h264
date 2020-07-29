#ifndef IOS_MINICAP_STREAMCLIENT_HPP
#define IOS_MINICAP_STREAMCLIENT_HPP

typedef struct opaqueCMSampleBuffer *CMSampleBufferRef;

#include <cstdio>
#include <cstdint>
//#include <Foundation/Foundation.h>
#include <VideoToolbox/VideoToolbox.h>
#include "FrameListener.hpp"
#include "Frame.hpp"

struct StreamClientImpl;

class StreamClient {
public:
    StreamClient();
    ~StreamClient();
    void start();
    void stop();
    void captureOutput(CMSampleBufferRef buffer);
    bool setupDevice(const char *udid);
    void setResolution(uint32_t width, uint32_t height);
    void setFrameListener(FrameListener *listener);
    void videoEncodeOutputDataCallback(Byte *data, bool isKeyFrame, int length);
    void setSocket(int s);
    void lockFrame(Frame *frame);
    void releaseFrame(Frame *frame);

private:
    StreamClientImpl *impl;
    FrameListener *mFrameListener;
    int socket;
    std::mutex mMutex;
    CMSampleBufferRef mBuffer;
    CMSampleBufferRef mLockedBuffer;
};


#endif //IOS_MINICAP_STREAMCLIENT_HPP
