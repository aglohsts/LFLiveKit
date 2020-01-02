#import "GPUImageUIElement.h"

@interface GPUImageUIElement ()
{
    UIView *view;
    CALayer *layer;
    
    CGSize previousLayerSizeInPixels;
    CMTime time;
    NSTimeInterval actualTimeOfLastUpdate;
    GLubyte *imageData;
    CGColorSpaceRef genericRGBColorspace;
    CGContextRef imageContext;
}

@end

@implementation GPUImageUIElement

#pragma mark -
#pragma mark Initialization and teardown

- (void)dealloc {
    if (imageContext != nil) {
        CGContextRelease(imageContext);
        imageContext = nil;
    }
    if (genericRGBColorspace != nil) {
        CGColorSpaceRelease(genericRGBColorspace);
        genericRGBColorspace = nil;
    }
    if (imageData != nil) {
        free(imageData);
        imageData = nil;
    }
}

- (id)initWithView:(UIView *)inputView;
{
    if (!(self = [super init]))
    {
		return nil;
    }
    
    NSLog(@"initWithView");
    view = inputView;
    layer = inputView.layer;

    previousLayerSizeInPixels = CGSizeZero;
    [self update];
    
    return self;
}

- (id)initWithLayer:(CALayer *)inputLayer;
{
    NSLog(@"initWithLayer");
    if (!(self = [super init]))
    {
		return nil;
    }
    
    view = nil;
    layer = inputLayer;

    previousLayerSizeInPixels = CGSizeZero;
    [self update];

    return self;
}

#pragma mark -
#pragma mark Layer management

- (CGSize)layerSizeInPixels;
{
    CGSize pointSize = layer.bounds.size;
    return CGSizeMake(layer.contentsScale * pointSize.width, layer.contentsScale * pointSize.height);
}

- (void)update;
{
    @autoreleasepool {
        [self updateWithTimestamp:kCMTimeIndefinite];
    }
}

- (void)updateUsingCurrentTime;
{
    if(CMTIME_IS_INVALID(time)) {
        time = CMTimeMakeWithSeconds(0, 600);
        actualTimeOfLastUpdate = [NSDate timeIntervalSinceReferenceDate];
    } else {
        NSTimeInterval now = [NSDate timeIntervalSinceReferenceDate];
        NSTimeInterval diff = now - actualTimeOfLastUpdate;
        time = CMTimeAdd(time, CMTimeMakeWithSeconds(diff, 600));
        actualTimeOfLastUpdate = now;
    }

    [self updateWithTimestamp:time];
}

- (void)updateWithTimestamp:(CMTime)frameTime;
{
    [GPUImageContext useImageProcessingContext];
    
    CGSize layerPixelSize = [self layerSizeInPixels];
    
    if (self->imageData != nil) {
        imageData = (GLubyte *) memset(imageData, 0, (int)layerPixelSize.width * (int)layerPixelSize.height * 4);
    }
    else {
        imageData = (GLubyte *) calloc(1, (int)layerPixelSize.width * (int)layerPixelSize.height * 4);
    }
//    GLubyte *imageData = (GLubyte *) calloc(1, (int)layerPixelSize.width * (int)layerPixelSize.height * 4);
//    if (imageContext == nil ) {
//        genericRGBColorspace = CGColorSpaceCreateDeviceRGB();
//        imageContext = CGBitmapContextCreate(imageData, (int)layerPixelSize.width, (int)layerPixelSize.height, 8, (int)layerPixelSize.width * 4, genericRGBColorspace,  kCGBitmapByteOrder32Little | kCGImageAlphaPremultipliedFirst);
//    }
    if (!genericRGBColorspace) {
        genericRGBColorspace = CGColorSpaceCreateDeviceRGB();
        imageContext = CGBitmapContextCreate(imageData, (int)layerPixelSize.width, (int)layerPixelSize.height, 8, (int)layerPixelSize.width * 4, genericRGBColorspace,  kCGBitmapByteOrder32Little | kCGImageAlphaPremultipliedFirst);
        CGContextTranslateCTM(imageContext, 0.0f, layerPixelSize.height);
        CGContextScaleCTM(imageContext, layer.contentsScale, -layer.contentsScale);
    }

//    CGContextRef imageContext = CGBitmapContextCreate(imageData, (int)layerPixelSize.width, (int)layerPixelSize.height, 8, (int)layerPixelSize.width * 4, genericRGBColorspace,  kCGBitmapByteOrder32Little | kCGImageAlphaPremultipliedFirst);
    //    CGContextRotateCTM(imageContext, M_PI_2);
    
    //        CGContextSetBlendMode(imageContext, kCGBlendModeCopy); // From Technical Q&A QA1708: http://developer.apple.com/library/ios/#qa/qa1708/_index.html
    
//    NSDateFormatter *dateFormatter=[[NSDateFormatter alloc] init];
//    [dateFormatter setDateFormat:@"yyyy-MM-dd HH:mm:ssSSS"];
    // or @"yyyy-MM-dd hh:mm:ss a" if you prefer the time with AM/PM
//    NSLog(@"%@",[dateFormatter stringFromDate:[NSDate date]]);
    [layer renderInContext:imageContext];
    
//    CGContextRelease(imageContext);
//    CGColorSpaceRelease(genericRGBColorspace);
    
    // TODO: This may not work
    outputFramebuffer = [[GPUImageContext sharedFramebufferCache] fetchFramebufferForSize:layerPixelSize textureOptions:self.outputTextureOptions onlyTexture:YES];
    [outputFramebuffer disableReferenceCounting]; // Add this line, because GPUImageTwoInputFilter.m frametime updatedMovieFrameOppositeStillImage is YES, but the secondbuffer not lock
    
    glBindTexture(GL_TEXTURE_2D, [outputFramebuffer texture]);
    // no need to use self.outputTextureOptions here, we always need these texture options
    glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, (int)layerPixelSize.width, (int)layerPixelSize.height, 0, GL_BGRA, GL_UNSIGNED_BYTE, imageData);
    
//    free(imageData);
    for (id<GPUImageInput> currentTarget in targets)
    {
        if (currentTarget != self.targetToIgnoreForUpdates)
        {
            NSInteger indexOfObject = [targets indexOfObject:currentTarget];
            NSInteger textureIndexOfTarget = [[targetTextureIndices objectAtIndex:indexOfObject] integerValue];
            
            [currentTarget setInputSize:layerPixelSize atIndex:textureIndexOfTarget];
            [currentTarget setInputFramebuffer:outputFramebuffer atIndex:textureIndexOfTarget]; // add this line, because the outputFramebuffer is update above
            [currentTarget newFrameReadyAtTime:frameTime atIndex:textureIndexOfTarget];
        }
    }
    [outputFramebuffer unlock];
}

@end
