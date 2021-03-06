//
//  LFVideoCapture.m
//  LFLiveKit
//
//  Created by LaiFeng on 16/5/20.
//  Copyright © 2016年 LaiFeng All rights reserved.
//

#import "LFVideoCapture.h"
#import "LFGPUImageBeautyFilter.h"
#import "LFGPUImageEmptyFilter.h"

#if __has_include(<GPUImage/GPUImage.h>)
#import <GPUImage/GPUImage.h>
#elif __has_include("GPUImage/GPUImage.h")
#import "GPUImage/GPUImage.h"
#else
#import "GPUImage.h"
#endif

@interface LFVideoCapture ()

@property (nonatomic, strong) GPUImageVideoCamera *videoCamera;
@property (nonatomic, strong) LFGPUImageBeautyFilter *beautyFilter;
@property (nonatomic, strong) GPUImageOutput<GPUImageInput> *filter;
@property (nonatomic, strong) GPUImageCropFilter *cropfilter;
@property (nonatomic, strong) GPUImageOutput<GPUImageInput> *output;
@property (nonatomic, strong) GPUImageView *gpuImageView;
@property (nonatomic, strong) LFLiveVideoConfiguration *configuration;

@property (nonatomic, strong) GPUImageAlphaBlendFilter *blendFilter;
@property (nonatomic, strong) GPUImageUIElement *uiElementInput;

@property (nonatomic, strong) UIView *waterMarkContentView;

@property (nonatomic, strong) GPUImageMovieWriter *movieWriter;

@property (nonatomic, strong) GPUImagePicture *filterPicture;
@property (nonatomic, strong) GPUImageChromaKeyBlendFilter *chromaFilter;


@property (nonatomic, strong) GPUImageAlphaBlendFilter *blendFilter2;
@property (nonatomic, strong) GPUImageUIElement *tickerElement;
@property (nonatomic, strong) UIView *tickerContentView;

@end

@implementation LFVideoCapture
@synthesize torch = _torch;
@synthesize beautyLevel = _beautyLevel;
@synthesize brightLevel = _brightLevel;
@synthesize zoomScale = _zoomScale;
@synthesize resolution = _resolution;

#pragma mark -- LifeCycle
- (instancetype)initWithVideoConfiguration:(LFLiveVideoConfiguration *)configuration {
    if (self = [super init]) {
        _configuration = configuration;
        
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(willEnterBackground:) name:UIApplicationWillResignActiveNotification object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(willEnterForeground:) name:UIApplicationDidBecomeActiveNotification object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(statusBarChanged:) name:UIApplicationWillChangeStatusBarOrientationNotification object:nil];
        
        self.beautyFace = YES;
        self.beautyLevel = 0.5;
        self.brightLevel = 0.3;
        self.beautydefault = 0.5;
        self.tonedefault = 0.4;
        self.zoomScale = 1.0;
        self.mirror = YES;
        
    }
    return self;
}

- (void)dealloc {
//    [UIApplication sharedApplication].idleTimerDisabled = NO;
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [_videoCamera stopCameraCapture];
    if(_gpuImageView){
        [_gpuImageView removeFromSuperview];
        _gpuImageView = nil;
    }
}

#pragma mark -- Setter Getter

- (GPUImageVideoCamera *)videoCamera{
    if(!_videoCamera){
        BOOL isFrontCamera = [[NSUserDefaults standardUserDefaults] boolForKey:@"isFrontCamera"];
        if (isFrontCamera) {
            _videoCamera = [[GPUImageVideoCamera alloc] initWithSessionPreset:_configuration.avSessionPreset cameraPosition:AVCaptureDevicePositionFront];
            self.videoCamera.horizontallyMirrorFrontFacingCamera = YES;
        }
        else {
            _videoCamera = [[GPUImageVideoCamera alloc] initWithSessionPreset:_configuration.avSessionPreset cameraPosition:AVCaptureDevicePositionBack];
                _videoCamera.horizontallyMirrorFrontFacingCamera = NO;
                _videoCamera.horizontallyMirrorRearFacingCamera = NO;
        }
        _videoCamera.outputImageOrientation = _configuration.outputImageOrientation;

        _videoCamera.frameRate = (int32_t)_configuration.videoFrameRate;
    }
    return _videoCamera;
}

- (void)setRunning:(BOOL)running {
    if (_running == running) return;
    _running = running;
    
    if (!_running) {
//        [UIApplication sharedApplication].idleTimerDisabled = NO;
        [self.videoCamera stopCameraCapture];
        if(self.saveLocalVideo) [self.movieWriter finishRecording];
    } else {
        [UIApplication sharedApplication].idleTimerDisabled = YES;
        [self.videoCamera startCameraCapture];
        if(self.saveLocalVideo) [self.movieWriter startRecording];
    }
}

- (void)setPreView:(UIView *)preView {
    if (self.gpuImageView.superview) [self.gpuImageView removeFromSuperview];
    [preView insertSubview:self.gpuImageView atIndex:0];
    self.gpuImageView.frame = CGRectMake(0, 0, preView.frame.size.width, preView.frame.size.height);
}

- (UIView *)preView {
    return self.gpuImageView.superview;
}

- (void)setCaptureDevicePosition:(AVCaptureDevicePosition)captureDevicePosition {
    if(captureDevicePosition == self.videoCamera.cameraPosition) return;
    [self.videoCamera rotateCamera];
    self.videoCamera.frameRate = (int32_t)_configuration.videoFrameRate;
    [self reloadMirror];
}

- (AVCaptureDevicePosition)captureDevicePosition {
    return [self.videoCamera cameraPosition];
}

- (void)setVideoFrameRate:(NSInteger)videoFrameRate {
    if (videoFrameRate <= 0) return;
    if (videoFrameRate == self.videoCamera.frameRate) return;
    self.videoCamera.frameRate = (uint32_t)videoFrameRate;
}

- (NSInteger)videoFrameRate {
    return self.videoCamera.frameRate;
}

- (void)setTorch:(BOOL)torch {
    BOOL ret;
    if (!self.videoCamera.captureSession) return;
    AVCaptureSession *session = (AVCaptureSession *)self.videoCamera.captureSession;
    [session beginConfiguration];
    if (self.videoCamera.inputCamera) {
        if (self.videoCamera.inputCamera.torchAvailable) {
            NSError *err = nil;
            if ([self.videoCamera.inputCamera lockForConfiguration:&err]) {
                [self.videoCamera.inputCamera setTorchMode:(torch ? AVCaptureTorchModeOn : AVCaptureTorchModeOff) ];
                [self.videoCamera.inputCamera unlockForConfiguration];
                ret = (self.videoCamera.inputCamera.torchMode == AVCaptureTorchModeOn);
            } else {
                NSLog(@"Error while locking device for torch: %@", err);
                ret = false;
            }
        } else {
            NSLog(@"Torch not available in current camera input");
        }
    }
    [session commitConfiguration];
    _torch = ret;
}

- (BOOL)torch {
    return self.videoCamera.inputCamera.torchMode;
}

- (void)setMirror:(BOOL)mirror {
    _mirror = mirror;
}

- (void)setBeautyFace:(BOOL)beautyFace{
    _beautyFace = beautyFace;
    [self reloadFilter];
}

- (void)setBeautyLevel:(CGFloat)beautyLevel {
    _beautyLevel = beautyLevel;
    if (self.beautyFilter) {
        [self.beautyFilter setBeautyLevel:_beautyLevel];
    }
}

- (CGFloat)beautyLevel {
    return _beautyLevel;
}

- (void)setBrightLevel:(CGFloat)brightLevel {
    _brightLevel = brightLevel;
    if (self.beautyFilter) {
        [self.beautyFilter setBrightLevel:brightLevel];
    }
}

- (CGFloat)brightLevel {
    return _brightLevel;
}

- (void)setZoomScale:(CGFloat)zoomScale {
    if (self.videoCamera && self.videoCamera.inputCamera) {
        AVCaptureDevice *device = (AVCaptureDevice *)self.videoCamera.inputCamera;
        if ([device lockForConfiguration:nil]) {
            device.videoZoomFactor = zoomScale;
            [device unlockForConfiguration];
            _zoomScale = zoomScale;
        }
    }
}

- (CGFloat)zoomScale {
    return _zoomScale;
}

- (void)setWarterMarkView:(UIView *)warterMarkView{
    if(_warterMarkView && _warterMarkView.superview){
        [_warterMarkView removeFromSuperview];
        _warterMarkView = nil;
    }
    _warterMarkView = warterMarkView;
    
    _warterMarkView.transform = CGAffineTransformMakeScale(self.waterMarkContentView.frame.size.width/warterMarkView.frame.size.width, self.waterMarkContentView.frame.size.height/warterMarkView.frame.size.height);
    _warterMarkView.frame = self.waterMarkContentView.frame;
    self.blendFilter.mix = warterMarkView.alpha;
    [self.waterMarkContentView addSubview:_warterMarkView];
    [self reloadFilter];
}

- (GPUImageUIElement *)uiElementInput{
    if(!_uiElementInput){
        _uiElementInput = [[GPUImageUIElement alloc] initWithView:self.waterMarkContentView];
    }
    return _uiElementInput;
}

- (void)setTickerView:(UIView *)tickerView{
    if(_tickerView && _tickerView.superview){
        [_tickerView removeFromSuperview];
        _tickerView = nil;
    }
    _tickerView = tickerView;
    _tickerView.transform = CGAffineTransformMakeScale(self.tickerContentView.frame.size.width/tickerView.frame.size.width, self.tickerContentView.frame.size.width/tickerView.frame.size.width);
    _tickerView.frame = self.tickerContentView.frame;
    
    self.blendFilter2.mix = _tickerView.alpha;
    [self.tickerContentView addSubview:_tickerView];
    [self reloadFilter];
}
- (GPUImageUIElement *)tickerElement {
    if (!_tickerElement) {
        _tickerElement = [[GPUImageUIElement alloc] initWithView:self.tickerContentView];
    }
    return _tickerElement;
}

- (GPUImageAlphaBlendFilter *)blendFilter{
    if(!_blendFilter){
        _blendFilter = [[GPUImageAlphaBlendFilter alloc] init];
        _blendFilter.mix = 1.0;
        [_blendFilter disableSecondFrameCheck];
    }
    return _blendFilter;
}
- (GPUImageAlphaBlendFilter *)blendFilter2{
    if(!_blendFilter2){
        _blendFilter2 = [[GPUImageAlphaBlendFilter alloc] init];
        _blendFilter2.mix = 1.0;
        [_blendFilter2 disableSecondFrameCheck];
    }
    return _blendFilter2;
}


- (UIView *)waterMarkContentView{
    if(!_waterMarkContentView) {
        _waterMarkContentView = [UIView new];
        _waterMarkContentView.frame = CGRectMake(0, 0, self.configuration.videoSize.width, self.configuration.videoSize.height);
        _waterMarkContentView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    }
    return _waterMarkContentView;
}
- (UIView *)tickerContentView{
    if(!_tickerContentView) {
        _tickerContentView = [UIView new];
        _tickerContentView.frame = CGRectMake(0, 0, self.configuration.videoSize.width, self.configuration.videoSize.height);
        _tickerContentView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    }
    return _tickerContentView;
}

- (GPUImageView *)gpuImageView{
    if(!_gpuImageView){
        _gpuImageView = [[GPUImageView alloc] initWithFrame:[UIScreen mainScreen].bounds];
        [_gpuImageView setFillMode:kGPUImageFillModeStretch];
        [_gpuImageView setAutoresizingMask:UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight];
    }
    return _gpuImageView;
}

-(UIImage *)currentImage{
    if(_filter){
        [_filter useNextFrameForImageCapture];
        return _filter.imageFromCurrentFramebuffer;
    }
    return nil;
}

- (GPUImageMovieWriter*)movieWriter{
    if(!_movieWriter){
        _movieWriter = [[GPUImageMovieWriter alloc] initWithMovieURL:self.saveLocalVideoPath size:self.configuration.videoSize];
        _movieWriter.encodingLiveVideo = YES;
        _movieWriter.shouldPassthroughAudio = YES;
        self.videoCamera.audioEncodingTarget = self.movieWriter;
    }
    return _movieWriter;
}

#pragma mark -- Custom Method
- (void)processVideo:(GPUImageOutput *)output {
    __weak typeof(self) _self = self;
    @autoreleasepool {
        GPUImageFramebuffer *imageFramebuffer = output.framebufferForOutput;
        CVPixelBufferRef pixelBuffer = [imageFramebuffer pixelBuffer];
        if (pixelBuffer && _self.delegate && [_self.delegate respondsToSelector:@selector(captureOutput:pixelBuffer:)]) {
            [_self.delegate captureOutput:_self pixelBuffer:pixelBuffer];
        }
    }
}

- (void)reloadFilter{
    [self.filter removeAllTargets];
    [self.blendFilter removeAllTargets];
    [self.blendFilter2 removeAllTargets];
    [self.uiElementInput removeAllTargets];
    [self.videoCamera removeAllTargets];
    [self.output removeAllTargets];
    [self.cropfilter removeAllTargets];
    
    [self.tickerElement removeAllTargets];
    //    [self.chromaFilter removeAllTargets];
    //    [self.filterPicture removeAllTargets];
    
    if (self.beautyFace) {
        self.output = [[LFGPUImageEmptyFilter alloc] init];
        self.filter = [[LFGPUImageBeautyFilter alloc] init];
        self.beautyFilter = (LFGPUImageBeautyFilter*)self.filter;
    } else {
        self.output = [[LFGPUImageEmptyFilter alloc] init];
        self.filter = [[LFGPUImageEmptyFilter alloc] init];
        self.beautyFilter = nil;
    }
    
    ///< 调节镜像
    [self reloadMirror];
    
    //< 480*640 比例为4:3  强制转换为16:9
    if([self.configuration.avSessionPreset isEqualToString:AVCaptureSessionPreset640x480]){
        CGRect cropRect = self.configuration.landscape ? CGRectMake(0, 0.125, 1, 0.75) : CGRectMake(0.125, 0, 0.75, 1);
        self.cropfilter = [[GPUImageCropFilter alloc] initWithCropRegion:cropRect];
        [self.videoCamera addTarget:self.cropfilter];
        [self.cropfilter addTarget:self.filter];
    }
    else if (self.configuration.sessionPreset == LFCaptureSessionPreset720x720) {
        //        [self.videoCamera addTarget:self.filter];
        CGRect cropRect = CGRectMake(0, 0.218, 1, 0.562);
        self.cropfilter = [[GPUImageCropFilter alloc] initWithCropRegion:cropRect];
        [self.videoCamera addTarget:self.cropfilter];
        [self.cropfilter addTarget:self.filter];
    }
    else if (self.configuration.sessionPreset == LFCaptureSessionPresetScreen) {
        CGFloat width = self.configuration.videoSize.width;
        CGRect cropRect;
        
        if (width > 0) {
            
            cropRect = CGRectMake(0, 0, 1, 1);
            
        } else {
            
            if (width > 720) {
                cropRect = CGRectMake(0, (1-720/width)/2, 1, 720/width);
            }
            else {
                cropRect = CGRectMake((1.0 - width/720)/2, 0, width/720, 1);
            }
        }
        self.cropfilter = [[GPUImageCropFilter alloc] initWithCropRegion:cropRect];
        [self.videoCamera addTarget:self.cropfilter];
        [self.cropfilter addTarget:self.filter];
    }
    else {
        [self.videoCamera addTarget:self.filter];
    }
    
    //< 添加水印
    if(self.warterMarkView){
        if (self.chromaFilter!=nil) {
            // filter color
            [self.filter addTarget:self.chromaFilter];
            [self.chromaFilter addTarget:self.blendFilter];
            [self.filterPicture addTarget:self.chromaFilter];
            [self.uiElementInput addTarget:self.blendFilter];
            
            [self.blendFilter addTarget:self.blendFilter2];
            [self.tickerElement addTarget:self.blendFilter2];
            [self.blendFilter2 addTarget:self.gpuImageView];
            [self.filter addTarget:self.output];
        }
        else {
            [self.filter addTarget:self.blendFilter];
//            [self.tickerElement addTarget:self.blendFilter];
            [self.uiElementInput addTarget:self.blendFilter];
            [self.blendFilter addTarget:self.blendFilter2];
            [self.tickerElement addTarget:self.blendFilter2];
            
            [self.blendFilter2 addTarget:self.gpuImageView];
            [self.filter addTarget:self.output];
        }
        
        if(self.saveLocalVideo) [self.blendFilter addTarget:self.movieWriter];
        [self.uiElementInput update];
    }
    else {
        [self.filter addTarget:self.output];
        [self.output addTarget:self.gpuImageView];
        if(self.saveLocalVideo) [self.output addTarget:self.movieWriter];
    }
    
    [self.filter forceProcessingAtSize:self.configuration.videoSize];
    [self.output forceProcessingAtSize:self.configuration.videoSize];
    [self.blendFilter forceProcessingAtSize:self.configuration.videoSize];
    [self.blendFilter2 forceProcessingAtSize:self.configuration.videoSize];
    [self.uiElementInput forceProcessingAtSize:self.configuration.videoSize];
    
    
    //< 输出数据
    __weak typeof(self) _self = self;
    [self.output setFrameProcessingCompletionBlock:^(GPUImageOutput *output, CMTime time) {
        [_self processVideo:output];
    }];
    
}

- (void)reloadMirror{
    if(self.mirror && self.captureDevicePosition == AVCaptureDevicePositionFront){
        self.videoCamera.horizontallyMirrorFrontFacingCamera = YES;
    }else{
        BOOL isFrontCamera = [[NSUserDefaults standardUserDefaults] boolForKey:@"isFrontCamera"];
        if (!isFrontCamera) {
            self.videoCamera.horizontallyMirrorFrontFacingCamera = NO;
        }
    }
}

- (void)setPicture:(UIImage *)image {
    if( image!=nil ) {
        if(self.chromaFilter == nil) {
            self.chromaFilter = [[GPUImageChromaKeyBlendFilter alloc] init];
            [self.chromaFilter setColorToReplaceRed:0.0 green:1.0 blue:0.0];
        }
        [self.chromaFilter useNextFrameForImageCapture];
        self.filterPicture = [[GPUImagePicture alloc] initWithImage:image smoothlyScaleOutput:YES];
        [self.filterPicture processImage];
    }
    else {
        self.filterPicture = nil;
        self.chromaFilter = nil;
    }
    [self reloadFilter];
}

#pragma mark Notification

- (void)willEnterBackground:(NSNotification *)notification {
    [UIApplication sharedApplication].idleTimerDisabled = NO;
    [self.videoCamera pauseCameraCapture];
    runSynchronouslyOnVideoProcessingQueue(^{
        glFinish();
    });
}

- (void)willEnterForeground:(NSNotification *)notification {
    [self.videoCamera resumeCameraCapture];
    [UIApplication sharedApplication].idleTimerDisabled = YES;
}

- (void)statusBarChanged:(NSNotification *)notification {
    NSLog(@"UIApplicationWillChangeStatusBarOrientationNotification. UserInfo: %@", notification.userInfo);
    UIInterfaceOrientation statusBar = [[UIApplication sharedApplication] statusBarOrientation];
    
    if(self.configuration.autorotate){
        if (self.configuration.landscape) {
            if (statusBar == UIInterfaceOrientationLandscapeLeft) {
                self.videoCamera.outputImageOrientation = UIInterfaceOrientationLandscapeRight;
            } else if (statusBar == UIInterfaceOrientationLandscapeRight) {
                self.videoCamera.outputImageOrientation = UIInterfaceOrientationLandscapeLeft;
            }
        } else {
            if (statusBar == UIInterfaceOrientationPortrait) {
                self.videoCamera.outputImageOrientation = UIInterfaceOrientationPortraitUpsideDown;
            } else if (statusBar == UIInterfaceOrientationPortraitUpsideDown) {
                self.videoCamera.outputImageOrientation = UIInterfaceOrientationPortrait;
            }
        }
    }
}
- (void)updateUI {
    if (self.uiElementInput!=nil) {
        [self.uiElementInput update];
    }
}
- (void)updateTicker {
    if (self.tickerElement!=nil) {
        @autoreleasepool {
            [self.tickerElement update];
        }
    }
}

- (CGFloat)beauty {
    return self.beautydefault;
}

- (void)setBeauty:(CGFloat)beauty {
    self.beautydefault = beauty;
    if (self.beautyFilter) {
        self.beautyFilter.toneLevel = self.tonedefault;
        self.beautyFilter.beautyLevel = self.beautydefault;
        [self.beautyFilter setBeautyLevel:beauty];
    }
}

- (CGFloat)tone {
    return self.tonedefault;
}

- (void)setTone:(CGFloat)tone {
    self.tonedefault = tone;
    if (self.beautyFilter) {
        self.beautyFilter.toneLevel = self.tonedefault;
        self.beautyFilter.beautyLevel = self.beautydefault;
        [self.beautyFilter setBeautyLevel:self.beautydefault];
    }
}

- (CGFloat)resolution {
    
    return _resolution ? _resolution : 720;
}

- (void)setResolution:(CGFloat)resolution {
    
    _resolution = resolution;
}

- (void)updateCropRect: (CGFloat)resolution {
    
    if (self.configuration.sessionPreset == LFCaptureSessionPreset720x720) {
        //        [self.videoCamera addTarget:self.filter];
        CGRect cropRect = CGRectMake(0, 0.218, 1, 0.562);
        [self.cropfilter setCropRegion:cropRect];
        [self.videoCamera addTarget:self.cropfilter];
        [self.cropfilter addTarget:self.filter];
    }
    else if (self.configuration.sessionPreset == LFCaptureSessionPresetScreen) {
        CGFloat width = self.configuration.videoSize.width;
        CGRect cropRect;
        
        NSLog(@"!!!!!%f", resolution);
        
        if (width > resolution) {
            
            cropRect = CGRectMake(0, (1-resolution/width)/2, 1, resolution/width);
        }
        else {
            cropRect = CGRectMake((1.0 - width/resolution)/2, 0, width/resolution, 1);
        }

        [self.cropfilter setCropRegion:cropRect];
        [self.videoCamera addTarget:self.cropfilter];
        [self.cropfilter addTarget:self.filter];
    }
}

@end
