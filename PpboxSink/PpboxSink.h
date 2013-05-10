//
//  PpboxSink.h
//  PpboxSink
//
//  Created by pplive on 5/9/13.
//  Copyright (c) 2013 pplive. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>

@interface PpboxSink : NSObject <
    AVCaptureVideoDataOutputSampleBufferDelegate,
    AVCaptureAudioDataOutputSampleBufferDelegate,
    NSStreamDelegate>

- (id) init;

- (void) open: (NSString *)dest;

- (void) start;

- (void) stop;

- (void) close;

- (AVCaptureVideoPreviewLayer *)previewLayer;

@end
