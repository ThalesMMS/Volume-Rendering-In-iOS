#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Contém os dados volumétricos carregados via GDCM.
@interface DICOMSeriesVolume : NSObject

@property (nonatomic, readonly) NSData *voxels;
@property (nonatomic, readonly) NSUInteger width;
@property (nonatomic, readonly) NSUInteger height;
@property (nonatomic, readonly) NSUInteger depth;
@property (nonatomic, readonly) double spacingX;
@property (nonatomic, readonly) double spacingY;
@property (nonatomic, readonly) double spacingZ;
@property (nonatomic, readonly) double rescaleSlope;
@property (nonatomic, readonly) double rescaleIntercept;
@property (nonatomic, readonly, getter=isSignedPixel) BOOL signedPixel;
@property (nonatomic, readonly) NSUInteger bitsAllocated;
@property (nonatomic, readonly, copy) NSString *seriesDescription;

- (instancetype)initWithVoxels:(NSData *)voxels
                          width:(NSUInteger)width
                         height:(NSUInteger)height
                         depth:(NSUInteger)depth
                      spacingX:(double)spacingX
                      spacingY:(double)spacingY
                      spacingZ:(double)spacingZ
                   rescaleSlope:(double)rescaleSlope
               rescaleIntercept:(double)rescaleIntercept
                    bitsAllocated:(NSUInteger)bitsAllocated
                      signedPixel:(BOOL)signedPixel
                seriesDescription:(NSString *)description NS_DESIGNATED_INITIALIZER;

- (instancetype)init NS_UNAVAILABLE;

@end

/// Wrapper Objective-C++ que utiliza GDCM para carregar uma série DICOM.
@interface DICOMSeriesLoader : NSObject
- (nullable DICOMSeriesVolume *)loadSeriesAtURL:(NSURL *)url error:(NSError **)error;
@end

FOUNDATION_EXPORT NSErrorDomain const DICOMSeriesLoaderErrorDomain;
FOUNDATION_EXPORT NSInteger const DICOMSeriesLoaderErrorNoFiles;
FOUNDATION_EXPORT NSInteger const DICOMSeriesLoaderErrorUnsupportedFormat;
FOUNDATION_EXPORT NSInteger const DICOMSeriesLoaderErrorNative;
FOUNDATION_EXPORT NSInteger const DICOMSeriesLoaderErrorUnavailable;

NS_ASSUME_NONNULL_END
