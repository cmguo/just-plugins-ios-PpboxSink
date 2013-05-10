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
    AVAssetWriterInputPixelBufferAdaptor *pixelBufferAdaptor;
    AVAssetWriterInput *videoWriterInput;
    AVAssetWriterInput *audioWriterInput;
    
    NSString *outputFile;
    CMTime durationSegment;
    
    PPBOX_HANDLE capture;

    uint writeIndex;
    CMTime thisEndTime;
    uint finishIndex;
}



- (id) init
{
	self = [super init];
    
    outputFile = @"Documents/Movie-%.3d.mp4";
    durationSegment = CMTimeMake(5, 1); // 5 seconds
    
    writeIndex = 0;
    finishIndex = 0;
    
    return self;
}



- (void) open: (NSString *)dest
{
    [self openCapture];
    
    [self setupPreview];
    
    [self openWriter];
    
    //PPBOX_StartP2PEngine("12", "161", "08ae1acd062ea3ab65924e07717d5994");
    
    //capture = PPBOX_CaptureCreate("", [dest UTF8String]);
    
    PPBOX_CaptureConfigData config = {
        2,
        NULL,
        NULL
    };
    //PPBOX_CaptureInit(capture, &config);
    
    
}



- (void) start
{
    [captureSession startRunning];
}



- (void) stop
{
    [captureSession stopRunning];
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

    // --- add video input ---
    
	videoDevice = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeVideo];
	if (videoDevice )
    {
		NSError *error;
		videoDeviceInput = [AVCaptureDeviceInput deviceInputWithDevice: videoDevice
                                                                 error: &error];
		[captureSession addInput: videoDeviceInput];
	}
    
    // --- add audio input ---
    
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
    
	dispatch_queue_t video_queue = dispatch_queue_create("com.pplive.ipptv.video", NULL);
	[videoDataOutput setSampleBufferDelegate: self queue: video_queue];
	dispatch_release(video_queue);
    	
	if ([captureSession canAddOutput: videoDataOutput]) {
		[captureSession addOutput: videoDataOutput];
    } else {
		NSLog(@"Couldn't add video data output");
	}
    
    // --- add audio output ---
    
    audioDataOutput = [[AVCaptureAudioDataOutput alloc] init];
    dispatch_queue_t audio_queue = dispatch_queue_create("com.pplive.ipptv.audio", NULL);
    [audioDataOutput setSampleBufferDelegate: self queue: audio_queue];
 	dispatch_release(audio_queue);
       
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
	[previewLayer setFrame:CGRectMake(0, 0, 320*352/288, 320)];
    //[videoDevice ]
    previewLayer.hidden = NO;
}


- (void) openWriter
{
    // --- create the video input ---
    
    CGSize size = CGSizeMake(480, 320);
    
    NSDictionary *videoCompressionProps =[NSDictionary dictionaryWithObjectsAndKeys:
                                          [NSNumber numberWithDouble:128.0*1024.0], AVVideoAverageBitRateKey,
                                          nil ];

    NSDictionary *videoSettings = [NSDictionary dictionaryWithObjectsAndKeys:
                                   AVVideoCodecH264, AVVideoCodecKey,
                                   [NSNumber numberWithInt:size.width], AVVideoWidthKey,
                                   [NSNumber numberWithInt:size.height], AVVideoHeightKey,
                                   videoCompressionProps, AVVideoCompressionPropertiesKey,
                                   nil];
    
    videoWriterInput = [AVAssetWriterInput assetWriterInputWithMediaType: AVMediaTypeVideo
                                                               outputSettings: videoSettings];
    
    NSParameterAssert(videoWriterInput);
    
    videoWriterInput.expectsMediaDataInRealTime = YES;
    
    NSDictionary *sourcePixelBufferAttributesDictionary =
        [NSDictionary dictionaryWithObjectsAndKeys:
         [NSNumber numberWithInt:kCVPixelFormatType_32ARGB], kCVPixelBufferPixelFormatTypeKey,
         nil];
    
    pixelBufferAdaptor = [AVAssetWriterInputPixelBufferAdaptor
                    assetWriterInputPixelBufferAdaptorWithAssetWriterInput: videoWriterInput
                    sourcePixelBufferAttributes: sourcePixelBufferAttributesDictionary];
        
    // --- create the audio input ---
    
    AudioChannelLayout acl;
    bzero( &acl, sizeof(acl));
    acl.mChannelLayoutTag = kAudioChannelLayoutTag_Mono;
    
    NSDictionary* audioDataOutputSettings = [ NSDictionary dictionaryWithObjectsAndKeys:
                                         [ NSNumber numberWithInt: kAudioFormatMPEG4AAC ], AVFormatIDKey,
                                         [ NSNumber numberWithInt:64000], AVEncoderBitRateKey,
                                         //[ NSNumber numberWithInt: 16 ], AVEncoderBitDepthHintKey,
                                         [ NSNumber numberWithFloat: 44100.0 ], AVSampleRateKey,
                                         [ NSNumber numberWithInt: 1 ], AVNumberOfChannelsKey,
                                         [ NSData dataWithBytes: &acl length: sizeof( acl ) ], AVChannelLayoutKey,
                                         nil ];
    
    audioWriterInput = [AVAssetWriterInput assetWriterInputWithMediaType: AVMediaTypeAudio
                                                                outputSettings: audioDataOutputSettings ];
    
    audioWriterInput.expectsMediaDataInRealTime = YES;
    
    
    // ---- create writer ---
        
    NSError *error = nil;
    NSString * thisOutputFile = [NSString stringWithFormat: outputFile, writeIndex];
    thisOutputFile = [NSHomeDirectory() stringByAppendingPathComponent: thisOutputFile];
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
    
}



- (void) closeWriter
{
    [videoWriterInput release];
    [audioWriterInput release];
    [pixelBufferAdaptor release];
    [writer release];
}



- (void) didFinishWrite: (AVAssetWriter *)thisWriter ofIndex:(uint) thisIndex
{
    [thisWriter release];
    ++finishIndex;
}



- (void)captureOutput:(AVCaptureOutput *)captureOutput didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer fromConnection:(AVCaptureConnection *)connection
{
    //CVPixelBufferRef pixelBuffer = (CVPixelBufferRef)CMSampleBufferGetImageBuffer(sampleBuffer);
    
    NSAutoreleasePool * pool = [[NSAutoreleasePool alloc] init];
    
    CMTime lastSampleTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer);
        
    if (CMTIME_IS_INVALID(thisEndTime))
    {
        [self openWriter];
        [writer startWriting];
        [writer startSessionAtSourceTime: lastSampleTime];
        
        thisEndTime = CMTimeAdd(lastSampleTime, durationSegment);
    }
    
    if (CMTimeCompare(lastSampleTime, thisEndTime) >= 0)
    {
        AVAssetWriter * thisWriter = [writer retain];
        uint thisIndex = writeIndex;
        [writer finishWritingWithCompletionHandler: ^{
            [self didFinishWrite: thisWriter ofIndex: thisIndex];
        }];
        
        [self closeWriter];
        ++writeIndex;
        
        [self openWriter];
        [writer startWriting];
        [writer startSessionAtSourceTime: lastSampleTime];
       
        thisEndTime = CMTimeAdd(thisEndTime, durationSegment);
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
