//
//  PpboxSink.m
//  PpboxSink
//
//  Created by pplive on 5/9/13.
//  Copyright (c) 2013 pplive. All rights reserved.
//

#import "PpboxSink.h"

#include "plugins/ppbox/ppbox_static.h"

@implementation PpboxSink
{
    dispatch_queue_t queue;
    
    AVCaptureSession *captureSession;
    AVCaptureDevice *videoDevice;
    AVCaptureDevice *audioDevice;
    AVCaptureDeviceInput *videoDeviceInput;
    AVCaptureDeviceInput *audioDeviceInput;
    AVCaptureVideoPreviewLayer *previewLayer;
    AVCaptureConnection *videoConnection;
    AVCaptureVideoDataOutput *videoDataOutput;
    AVCaptureAudioDataOutput *audioDataOutput;
    
    AVAssetWriter *writer;
    AVAssetWriterInput *videoWriterInput;
    AVAssetWriterInput *audioWriterInput;
    
    NSString *outputFile;
    NSString *outputM3u8;
    CMTime durationSegment;
    
    PP_handle downloader;

    uint writeIndex;
    CMTime thisEndTime;
    uint finishIndex;
}



- (id) init
{
	self = [super init];
    
    outputFile = @"Documents/Movie-%.3d.mp4";
    outputM3u8 = [[NSHomeDirectory() stringByAppendingPathComponent: @"Documents/Movie.m3u8"] retain];
    durationSegment = CMTimeMake(5, 1); // 5 seconds
    
    writeIndex = 0;
    finishIndex = 0;
    
    // --- the queue for sample buffer delegate ---
    
	queue = dispatch_queue_create("com.pplive.ipptv.capture", NULL);
    
    return self;
}



- (void) dealloc
{
    dispatch_release(queue);
    [super dealloc];
}



static void download_callback(PP_context c, PP_err ec)
{
}



- (void) open: (NSString *)dest
{
    [self openCapture];
    
    [self setupPreview];
    
    [self writeM3u8];
    
    PPBOX_StartEngine("12", "161", "08ae1acd062ea3ab65924e07717d5994");
    
    NSString *playlink = @"file://";
    playlink = [playlink stringByAppendingString: outputM3u8];
    downloader = PPBOX_DownloadOpen([playlink UTF8String], "rtm", [dest UTF8String], download_callback);
}



- (void) start
{
    [captureSession startRunning];
}



- (void) stop
{
    PPBOX_DownloadClose(downloader);
    downloader = NULL;
    
    [captureSession stopRunning];
    
    dispatch_async(queue, ^{
        if (writer)
        {
            [self closeWriter];
        }
    });
}



- (void) close
{
    //PPBOX_CaptureDestroy(capture);
}


- (AVCaptureVideoPreviewLayer *) previewLayer
{
    return previewLayer;
}

//- (AVCaptureConnection *)connectionWithMediaType:(NSString *)mediaType fromConnections:(NSArray *)connections;
//- (void) addVideoPreviewLayer;
//- (void) startRunning:(NSString*)rtmpUrl;
//- (void) stopRunning;

- (void) openCapture
{
    // --- create capture session ---
    
    captureSession = [[AVCaptureSession alloc] init];
    captureSession.sessionPreset = AVCaptureSessionPresetMedium;
    //self.captureSession.sessionPreset = AVCaptureSessionPreset640x480;

    // --- add video device input ---
    
	videoDevice = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeVideo];
	if (videoDevice )
    {
        //[videoDevice set]
		NSError *error;
		videoDeviceInput = [AVCaptureDeviceInput deviceInputWithDevice: videoDevice
                                                                 error: &error];
		[captureSession addInput: videoDeviceInput];
	}
    
    // --- add audio device input ---
    
    audioDevice = [AVCaptureDevice defaultDeviceWithMediaType: AVMediaTypeAudio];
    if (audioDevice)
    {
        NSError *error;
        audioDeviceInput = [AVCaptureDeviceInput deviceInputWithDevice: audioDevice
                                                                 error: &error];
        [captureSession addInput: audioDeviceInput];
    }

    // --- add video output ---
    
    videoDataOutput = [[AVCaptureVideoDataOutput alloc] init];
	[videoDataOutput setAlwaysDiscardsLateVideoFrames: YES];
    //videoDataOutput.minFrameDuration = CMTimeMake(1, frameRate);
    //videoDataOutput.minFrameDuration = CMTimeMake(1, 1000);

    
	[videoDataOutput setVideoSettings: [NSDictionary dictionaryWithObject: [NSNumber numberWithInt: kCVPixelFormatType_32BGRA]
                                                                   forKey: (id)kCVPixelBufferPixelFormatTypeKey]]; // BGRA is necessary for manual preview
    
	[videoDataOutput setSampleBufferDelegate: self queue: queue];
    	
	if ([captureSession canAddOutput: videoDataOutput]) {
		[captureSession addOutput: videoDataOutput];
    } else {
		NSLog(@"Couldn't add video data output");
	}
    
    AVCaptureConnection *conn = [videoDataOutput connectionWithMediaType:AVMediaTypeVideo];
    
    if (conn.isVideoMinFrameDurationSupported) {
        conn.videoMinFrameDuration = CMTimeMake(1, 20);
    } else {
		NSLog(@"Couldn't set video frame rate (min)");
   }
    if (conn.isVideoMaxFrameDurationSupported) {
        conn.videoMaxFrameDuration = CMTimeMake(1, 20);
    } else {
		NSLog(@"Couldn't set video frame rate (max)");
    }
    
    // --- add audio output ---
    
    audioDataOutput = [[AVCaptureAudioDataOutput alloc] init];
    [audioDataOutput setSampleBufferDelegate: self queue: queue];
       
    if ([captureSession canAddOutput: audioDataOutput]) {
        [captureSession addOutput: audioDataOutput];
    } else {
        NSLog(@"Couldn't add audio data output");
    }
}



- (void) closeCapture
{
    [videoDataOutput release];
    [audioDataOutput release];
    [audioDeviceInput release];
    [videoDeviceInput release];
    [audioDevice release];
    [videoDevice release];
    [captureSession release];
}



- (void) setupPreview
{
    previewLayer = [[AVCaptureVideoPreviewLayer alloc] initWithSession: captureSession];
	previewLayer.videoGravity = AVLayerVideoGravityResizeAspectFill;
	[previewLayer setFrame:CGRectMake(0, 0, 360, 480)];
    //[videoDevice ]
    previewLayer.hidden = NO;
}



- (NSString *) videoUrl: (uint) index
{
    NSString * thisOutputFile = [NSString stringWithFormat: outputFile, index];
    thisOutputFile = [NSHomeDirectory() stringByAppendingPathComponent: thisOutputFile];
    return thisOutputFile;
}



- (void) openWriter: (CMTime *) time
{
    // --- create the video input ---
    
    CGSize size = CGSizeMake(480, 360);
    
    NSDictionary *videoCompressionProps = [[NSMutableDictionary alloc] init];
    [videoCompressionProps setValue: AVVideoProfileLevelH264Main41 forKey: AVVideoProfileLevelKey];
    [videoCompressionProps setValue: [NSNumber numberWithDouble: 256.0 * 1024.0] forKey: AVVideoAverageBitRateKey];

    NSDictionary *videoSettings = [[NSMutableDictionary alloc] init];
    [videoSettings setValue: AVVideoCodecH264 forKey: AVVideoCodecKey];
    [videoSettings setValue: [NSNumber numberWithInt:size.width] forKey: AVVideoWidthKey];
    [videoSettings setValue: [NSNumber numberWithInt:size.height] forKey: AVVideoHeightKey];
    [videoSettings setValue: videoCompressionProps forKey: AVVideoCompressionPropertiesKey];
    
    videoWriterInput = [AVAssetWriterInput assetWriterInputWithMediaType: AVMediaTypeVideo
                                                          outputSettings: videoSettings];
    
    NSParameterAssert(videoWriterInput);
    
    videoWriterInput.expectsMediaDataInRealTime = YES;
    
    NSDictionary *sourcePixelBufferAttributesDictionary =
        [NSDictionary dictionaryWithObjectsAndKeys:
         [NSNumber numberWithInt:kCVPixelFormatType_32ARGB], kCVPixelBufferPixelFormatTypeKey,
         nil];	
    
    AVAssetWriterInputPixelBufferAdaptor *pixelBufferAdaptor = [AVAssetWriterInputPixelBufferAdaptor
                    assetWriterInputPixelBufferAdaptorWithAssetWriterInput: videoWriterInput
                    sourcePixelBufferAttributes: sourcePixelBufferAttributesDictionary];
    (void)pixelBufferAdaptor;
    
    // --- create the audio input ---
    
    AudioChannelLayout acl;
    bzero( &acl, sizeof(acl));
    acl.mChannelLayoutTag = kAudioChannelLayoutTag_Mono;
    
    NSDictionary* audioDataOutputSettings = [[NSMutableDictionary alloc] init];
    [audioDataOutputSettings setValue: [NSNumber numberWithInt: kAudioFormatMPEG4AAC] forKey: AVFormatIDKey];
    [audioDataOutputSettings setValue: [NSNumber numberWithInt:64000] forKey: AVEncoderBitRateKey];
    //[audioDataOutputSettings setValue: [NSNumber numberWithInt:16] forKey: AVEncoderBitDepthHintKey];
    [audioDataOutputSettings setValue: [NSNumber numberWithInt:44100] forKey: AVSampleRateKey];
    [audioDataOutputSettings setValue: [NSNumber numberWithInt:1] forKey: AVNumberOfChannelsKey];
    [audioDataOutputSettings setValue: [NSData dataWithBytes: &acl length: sizeof(acl)] forKey: AVChannelLayoutKey];
  
    
    audioWriterInput = [AVAssetWriterInput assetWriterInputWithMediaType: AVMediaTypeAudio
                                                          outputSettings: audioDataOutputSettings ];
    
    audioWriterInput.expectsMediaDataInRealTime = YES;
    
    
    // ---- create writer ---
        
    NSLog(@"start file index: %u", writeIndex);

    NSError *error = nil;
    NSString * thisOutputFile = [self videoUrl: writeIndex];
    unlink([thisOutputFile UTF8String]);
    
    writer = [[AVAssetWriter alloc] initWithURL: [NSURL fileURLWithPath: thisOutputFile]
                                            fileType: AVFileTypeMPEG4
                                               error: &error];
    
    NSParameterAssert(writer);
    
    if (error)
        NSLog(@"error = %@", [error localizedDescription]);
    
    
    // --- add inputs to writer ---
    
    NSParameterAssert([writer canAddInput:videoWriterInput]);
    
    if ([writer canAddInput:videoWriterInput])
        [writer addInput:videoWriterInput];
    else
        NSLog(@"i can't add video write input");
    
    
    NSParameterAssert([writer canAddInput:videoWriterInput]);
    
    if ([writer canAddInput:videoWriterInput])
        [writer addInput:audioWriterInput];
    else
        NSLog(@"Can't add audio write input");
    

    // --- start writing ---
    
    [writer startWriting];
    [writer startSessionAtSourceTime: *time];
}



- (void) didFinishWrite: (AVAssetWriter *)thisWriter ofIndex:(uint) thisIndex
{
    [thisWriter release];
    ++finishIndex;
    
    [self writeM3u8];
    
    if (finishIndex > 5) {
        NSLog(@"remove file index: %u", finishIndex - 6);
        NSString * toRemoveFile = [self videoUrl: finishIndex - 6];
        unlink([toRemoveFile UTF8String]);
    }
    
    if (downloader == NULL) {
        uint startIndex = finishIndex > 5 ? finishIndex - 5 : 0;
        for (; startIndex < finishIndex; ++startIndex) {
            NSLog(@"remove file index: %u", startIndex);
            NSString * toRemoveFile = [self videoUrl: startIndex];
            unlink([toRemoveFile UTF8String]);
        }
    }
    
    [self release];
}



- (void) closeWriter
{
    NSLog(@"finish file index: %u", writeIndex);
    
    PpboxSink * thisSink = [self retain];
    AVAssetWriter * thisWriter = [writer retain];
    uint thisIndex = writeIndex;
    [writer finishWritingWithCompletionHandler: ^(){
        [thisSink didFinishWrite: thisWriter ofIndex: thisIndex];
    }];
    
    ++writeIndex;
    
    //[videoWriterInput release];
    //[audioWriterInput release];
    [writer release];
}



- (void) writeM3u8
{
    char const * filename = [outputM3u8  UTF8String];
    char const * filename_tmp = [[outputM3u8 stringByAppendingString: @".tmp"] UTF8String];
    FILE * file = fopen(filename_tmp, "w+");
    uint startIndex = finishIndex > 5 ? finishIndex - 5 : 0;
    fprintf(file, "#EXTM3U\r\nEXT-X-TARGETDURATION:5\r\n#EXT-X-MEDIA-SEQUENCE:%u\r\n", startIndex + 1);
    for (uint i = startIndex; i < finishIndex; ++i)
    {
        fprintf(file, "#EXTINF:5,\r\nMovie-%.3u.mp4\r\n", i);
    }
    fclose(file);
    unlink(filename);
    rename(filename_tmp, filename);		
}



- (void)captureOutput:(AVCaptureOutput *)captureOutput didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer fromConnection:(AVCaptureConnection *)connection
{
    //CVPixelBufferRef pixelBuffer = (CVPixelBufferRef)CMSampleBufferGetImageBuffer(sampleBuffer);
    
    NSAutoreleasePool * pool = [[NSAutoreleasePool alloc] init];
    
    CMTime lastSampleTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer);
        
    if (CMTIME_IS_INVALID(thisEndTime))
    {
        thisEndTime = CMTimeAdd(lastSampleTime, durationSegment);
        
        [self openWriter: &lastSampleTime];
    }
    
    if (CMTimeCompare(lastSampleTime, thisEndTime) >= 0)
    {
        [self closeWriter];
                
        thisEndTime = CMTimeAdd(thisEndTime, durationSegment);
        
        [self openWriter: &lastSampleTime];
    }
    
    if (writer.status > AVAssetWriterStatusWriting )
    {
        NSLog(@"Warning: writer status is %d", writer.status);
        if (writer.status == AVAssetWriterStatusFailed)
            NSLog(@"Error: %@", writer.error);
        return;
    }
    
    if (captureOutput == videoDataOutput)
    {
        if ([videoWriterInput isReadyForMoreMediaData])
        {
            if( ![videoWriterInput appendSampleBuffer:sampleBuffer] )
                NSLog(@"Unable to write to video input");
        }
    }
    else if (captureOutput == audioDataOutput)
    {
        if ([audioWriterInput isReadyForMoreMediaData])
        {
            if( ![audioWriterInput appendSampleBuffer:sampleBuffer] )
                NSLog(@"Unable to write to audio input");
        }
    }
    
    [pool drain];
}


@end
