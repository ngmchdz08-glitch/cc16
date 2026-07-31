// CameraHook.x — inject mediaserverd / cameracaptured
// Render: Photo/Video từ file, OBS từ shared memory/IPC với daemon

#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>
#import <CoreVideo/CoreVideo.h>
#import <CoreMedia/CoreMedia.h>
#import <CoreImage/CoreImage.h>
#import <UIKit/UIKit.h>

#define kPrefsPath @"/var/mobile/Media/vcam_prefs.plist"
#define kOBSFramePath @"/var/mobile/Media/vcam_cache/obs_frame.jpg"

// ─────────────────────────────────────────────────────────────
// MARK: Prefs (read mỗi frame để live-update không cần respring)
// ─────────────────────────────────────────────────────────────
static inline NSDictionary *vcam_prefs(void) {
    NSDictionary *p = [NSDictionary dictionaryWithContentsOfFile:kPrefsPath];
    if (!p) p = [NSDictionary dictionaryWithContentsOfFile:@"/var/mobile/Library/Preferences/com.weat.vcamera.plist"];
    return p;
}

// ─────────────────────────────────────────────────────────────
// MARK: CIContext singleton — không tạo mới mỗi frame (expensive)
// ─────────────────────────────────────────────────────────────
static CIContext *sharedCIContext(void) {
    static CIContext *ctx;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        ctx = [CIContext contextWithOptions:@{
            kCIContextUseSoftwareRenderer: @NO,
            kCIContextWorkingColorSpace: (id)kCFNull,
        }];
    });
    return ctx;
}

// ─────────────────────────────────────────────────────────────
// MARK: Core renderer
// ─────────────────────────────────────────────────────────────
static void vcam_renderIntoBuffer(CVPixelBufferRef pixBuf) {
    if (!pixBuf) return;

    NSDictionary *prefs = vcam_prefs();
    if (![prefs[@"isEnabled"] boolValue]) return;
    
    BOOL networkMode = [prefs[@"NetworkMode"] boolValue];
    BOOL imageMode   = [prefs[@"ImageMode"] boolValue];
    
    NSString *imgPath = nil;
    NSInteger mode = 0;
    if (networkMode) {
        imgPath = kOBSFramePath;
        mode = 0; // OBS
    } else if (imageMode) {
        imgPath = prefs[@"ImagePath"];
        mode = 1; // Photo
    } else {
        imgPath = prefs[@"VideoPath"];
        mode = 2; // Video
    }

    if (!imgPath) return;

    // Load ảnh — dùng cache tránh đọc disk mỗi frame với static media
    static NSString *cachedPath;
    static UIImage  *cachedImg;
    UIImage *img = nil;
    if ([imgPath isEqualToString:cachedPath] && cachedImg && mode != 0) {
        img = cachedImg; // static media: dùng cache
    } else {
        img = [UIImage imageWithContentsOfFile:imgPath];
        if (mode != 0) { cachedPath = imgPath; cachedImg = img; }
    }
    if (!img) return;

    size_t w   = CVPixelBufferGetWidth(pixBuf);
    size_t h   = CVPixelBufferGetHeight(pixBuf);
    CGRect rect = CGRectMake(0, 0, w, h);

    CIImage *ci = [[CIImage alloc] initWithCGImage:img.CGImage];
    // Scale to fill (crop center)
    CGFloat scaleX = w / ci.extent.size.width;
    CGFloat scaleY = h / ci.extent.size.height;
    CGFloat scale  = MAX(scaleX, scaleY); // fill, không letterbox
    ci = [ci imageByApplyingTransform:CGAffineTransformMakeScale(scale, scale)];
    // Center crop
    CGFloat dx = (ci.extent.size.width  - w) / 2.0;
    CGFloat dy = (ci.extent.size.height - h) / 2.0;
    ci = [ci imageByApplyingTransform:CGAffineTransformMakeTranslation(-dx, -dy)];

    // Rotation/flip từ prefs
    BOOL hFlip     = [prefs[@"horizontalFlip"] boolValue];
    float rotation = [prefs[@"rotationDegrees"] floatValue];
    if (hFlip)        ci = [ci imageByApplyingTransform:CGAffineTransformMakeScale(-1, 1)];
    if (rotation != 0) {
        CGFloat rad = rotation * M_PI / 180.0;
        ci = [ci imageByApplyingTransform:CGAffineTransformMakeRotation(rad)];
    }

    CVPixelBufferLockBaseAddress(pixBuf, 0);
    [sharedCIContext() render:ci
               toCVPixelBuffer:pixBuf
                         bounds:rect
                     colorSpace:CGColorSpaceCreateDeviceRGB()];
    CVPixelBufferUnlockBaseAddress(pixBuf, 0);
}

// ─────────────────────────────────────────────────────────────
// MARK: Hooks — BW nodes (mediaserverd camera pipeline)
// ─────────────────────────────────────────────────────────────
static void vcam_hookNodeRender(CMSampleBufferRef sbuf) {
    if (!sbuf) return;
    CVPixelBufferRef pixBuf = CMSampleBufferGetImageBuffer(sbuf);
    if (!pixBuf) return;
    OSType format = CVPixelBufferGetPixelFormatType(pixBuf);
    if (format == kCVPixelFormatType_32BGRA || format == kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange || format == kCVPixelFormatType_420YpCbCr8BiPlanarFullRange) {
        CFTypeRef alreadyRendered = NULL;
        if (@available(iOS 15.0, *)) {
            alreadyRendered = CVBufferCopyAttachment(pixBuf, CFSTR("vcam_rendered"), NULL);
        } else {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
            alreadyRendered = CVBufferGetAttachment(pixBuf, CFSTR("vcam_rendered"), NULL);
#pragma clang diagnostic pop
        }
        
        if (!alreadyRendered) {
            CVBufferSetAttachment(pixBuf, CFSTR("vcam_rendered"), kCFBooleanTrue, kCVAttachmentMode_ShouldPropagate);
            vcam_renderIntoBuffer(pixBuf);
        } else if (@available(iOS 15.0, *)) {
            CFRelease(alreadyRendered);
        }
    }
}

%group MediaServerHooks

%hook BWVideoDataOutputNode
- (void)renderSampleBuffer:(CMSampleBufferRef)sbuf forInput:(id)input { vcam_hookNodeRender(sbuf); %orig; }
%end

%hook BWPreviewNode
- (void)renderSampleBuffer:(CMSampleBufferRef)sbuf forInput:(id)input { vcam_hookNodeRender(sbuf); %orig; }
%end

%hook BWPreviewTimeMachineSinkNode
- (void)renderSampleBuffer:(CMSampleBufferRef)sbuf forInput:(id)input { vcam_hookNodeRender(sbuf); %orig; }
%end

%hook BWPhotoEncoderNode
- (void)renderSampleBuffer:(CMSampleBufferRef)sbuf forInput:(id)input { vcam_hookNodeRender(sbuf); %orig; }
%end

%hook BWStillImageSampleBufferSinkNode
- (void)renderSampleBuffer:(CMSampleBufferRef)sbuf forInput:(id)input { vcam_hookNodeRender(sbuf); %orig; }
%end

%hook BWImageQueueSinkNode
- (void)renderSampleBuffer:(CMSampleBufferRef)sbuf forInput:(id)input { vcam_hookNodeRender(sbuf); %orig; }
%end

%hook BWRemoteQueueSinkNode
- (void)renderSampleBuffer:(CMSampleBufferRef)sbuf forInput:(id)input { vcam_hookNodeRender(sbuf); %orig; }
%end

%hook BWNode
- (void)renderSampleBuffer:(CMSampleBufferRef)sbuf forInput:(id)input { vcam_hookNodeRender(sbuf); %orig; }
%end

%end

%ctor {
    NSString *proc = [[NSProcessInfo processInfo] processName];
    if ([proc isEqualToString:@"mediaserverd"] || [proc isEqualToString:@"cameracaptured"]) {
        NSLog(@"[Vcam_Mch/Camera] ACTIVE in %@", proc);
        %init(MediaServerHooks);
    }
}
