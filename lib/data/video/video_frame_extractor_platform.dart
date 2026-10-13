import 'video_frame_extractor.dart';
import 'video_frame_extractor_native.dart'
    if (dart.library.html) 'video_frame_extractor_web.dart'
    as impl;

/// Production facade: [NativeFfmpegFrameExtractor] vs [WebCanvasFrameExtractor]
/// (design D2 / D3). Inject [FakeVideoFrameExtractor] in tests instead.
VideoFrameExtractor createPlatformVideoFrameExtractor() =>
    impl.createVideoFrameExtractor();
