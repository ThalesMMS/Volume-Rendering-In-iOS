#import "DICOMSeriesLoader.h"

#if __has_include(<gdcmImageReader.h>)
#define HAS_GDCM 1
#include <string>
#include <vector>
#import <gdcmAttribute.h>
#import <gdcmDataElement.h>
#import <gdcmDataSet.h>
#import <gdcmDirectory.h>
#import <gdcmImage.h>
#import <gdcmImageReader.h>
#import <gdcmIPPSorter.h>
#import <gdcmPixelFormat.h>
#import <gdcmReader.h>
#import <gdcmStringFilter.h>
#else
#define HAS_GDCM 0
#endif

NSErrorDomain const DICOMSeriesLoaderErrorDomain = @"br.thalesmms.dicom.loader";
NSInteger const DICOMSeriesLoaderErrorNoFiles = 1;
NSInteger const DICOMSeriesLoaderErrorUnsupportedFormat = 2;
NSInteger const DICOMSeriesLoaderErrorNative = 3;
NSInteger const DICOMSeriesLoaderErrorUnavailable = 4;

@implementation DICOMSeriesVolume

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
                seriesDescription:(NSString *)description {
    self = [super init];
    if (self) {
        _voxels = [voxels copy];
        _width = width;
        _height = height;
        _depth = depth;
        _spacingX = spacingX;
        _spacingY = spacingY;
        _spacingZ = spacingZ;
        _rescaleSlope = rescaleSlope;
        _rescaleIntercept = rescaleIntercept;
        _bitsAllocated = bitsAllocated;
        _signedPixel = signedPixel;
        _seriesDescription = [description copy];
    }
    return self;
}

@end

@implementation DICOMSeriesLoader

- (nullable DICOMSeriesVolume *)loadSeriesAtURL:(NSURL *)url error:(NSError **)error {
#if HAS_GDCM
    if (!url.isFileURL) {
        if (error) {
            *error = [NSError errorWithDomain:DICOMSeriesLoaderErrorDomain
                                          code:DICOMSeriesLoaderErrorNoFiles
                                      userInfo:@{NSLocalizedDescriptionKey: @"URL fornecida não é um caminho local."}];
        }
        return nil;
    }

    std::string path = url.fileSystemRepresentation;

    gdcm::Directory directory;
    directory.Load(path.c_str(), true);
    const gdcm::Directory::FilenamesType &files = directory.GetFilenames();
    if (files.empty()) {
        if (error) {
            *error = [NSError errorWithDomain:DICOMSeriesLoaderErrorDomain
                                          code:DICOMSeriesLoaderErrorNoFiles
                                      userInfo:@{NSLocalizedDescriptionKey: @"Nenhum arquivo DICOM encontrado no diretório."}];
        }
        return nil;
    }

    gdcm::IPPSorter sorter;
    sorter.SetComputeZSpacing(true);
    if (!sorter.Sort(files)) {
        if (error) {
            *error = [NSError errorWithDomain:DICOMSeriesLoaderErrorDomain
                                          code:DICOMSeriesLoaderErrorNative
                                      userInfo:@{NSLocalizedDescriptionKey: @"Falha ao ordenar os arquivos DICOM pelo Image Position Patient."}];
        }
        return nil;
    }

    const std::vector<std::string> &sortedFiles = sorter.GetFilenames();
    if (sortedFiles.empty()) {
        if (error) {
            *error = [NSError errorWithDomain:DICOMSeriesLoaderErrorDomain
                                          code:DICOMSeriesLoaderErrorNoFiles
                                      userInfo:@{NSLocalizedDescriptionKey: @"Sorter GDCM não retornou arquivos ordenados."}];
        }
        return nil;
    }

    gdcm::ImageReader firstReader;
    firstReader.SetFileName(sortedFiles.front().c_str());
    if (!firstReader.Read()) {
        if (error) {
            *error = [NSError errorWithDomain:DICOMSeriesLoaderErrorDomain
                                          code:DICOMSeriesLoaderErrorNative
                                      userInfo:@{NSLocalizedDescriptionKey: @"Falha ao ler o primeiro arquivo da série."}];
        }
        return nil;
    }

    const gdcm::Image &firstImage = firstReader.GetImage();
    const unsigned int *dims = firstImage.GetDimensions();
    if (dims[0] == 0 || dims[1] == 0) {
        if (error) {
            *error = [NSError errorWithDomain:DICOMSeriesLoaderErrorDomain
                                          code:DICOMSeriesLoaderErrorUnsupportedFormat
                                      userInfo:@{NSLocalizedDescriptionKey: @"Dimensão inválida encontrada no primeiro arquivo."}];
        }
        return nil;
    }

    const gdcm::PixelFormat &pixelFormat = firstImage.GetPixelFormat();
    const unsigned int bitsAllocated = pixelFormat.GetBitsAllocated();
    const unsigned int samplesPerPixel = pixelFormat.GetSamplesPerPixel();
    if (bitsAllocated != 16 || samplesPerPixel != 1) {
        if (error) {
            *error = [NSError errorWithDomain:DICOMSeriesLoaderErrorDomain
                                          code:DICOMSeriesLoaderErrorUnsupportedFormat
                                      userInfo:@{NSLocalizedDescriptionKey: @"Somente imagens escalares de 16 bits são suportadas."}];
        }
        return nil;
    }

    const size_t sliceBytes = static_cast<size_t>(dims[0]) * static_cast<size_t>(dims[1]) * (bitsAllocated / 8);
    const size_t depth = sortedFiles.size();

    NSMutableData *voxels = [NSMutableData dataWithLength:sliceBytes * depth];
    if (!voxels) {
        if (error) {
            *error = [NSError errorWithDomain:DICOMSeriesLoaderErrorDomain
                                          code:DICOMSeriesLoaderErrorNative
                                      userInfo:@{NSLocalizedDescriptionKey: @"Falha ao alocar memória para o volume."}];
        }
        return nil;
    }

    char *destination = static_cast<char *>(voxels.mutableBytes);

    for (size_t idx = 0; idx < depth; ++idx) {
        gdcm::ImageReader reader;
        reader.SetFileName(sortedFiles[idx].c_str());
        if (!reader.Read()) {
            if (error) {
                *error = [NSError errorWithDomain:DICOMSeriesLoaderErrorDomain
                                              code:DICOMSeriesLoaderErrorNative
                                          userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Falha ao ler fatia DICOM em %zu", idx]}];
            }
            return nil;
        }
        const gdcm::Image &image = reader.GetImage();
        const unsigned int *sliceDims = image.GetDimensions();
        if (sliceDims[0] != dims[0] || sliceDims[1] != dims[1]) {
            if (error) {
                *error = [NSError errorWithDomain:DICOMSeriesLoaderErrorDomain
                                              code:DICOMSeriesLoaderErrorUnsupportedFormat
                                          userInfo:@{NSLocalizedDescriptionKey: @"As dimensões das fatias não são consistentes."}];
            }
            return nil;
        }
        if (!image.GetBuffer(destination + (idx * sliceBytes))) {
            if (error) {
                *error = [NSError errorWithDomain:DICOMSeriesLoaderErrorDomain
                                              code:DICOMSeriesLoaderErrorNative
                                          userInfo:@{NSLocalizedDescriptionKey: @"Falha ao copiar dados de imagem da fatia."}];
            }
            return nil;
        }
    }

    double spacing[3] = {1.0, 1.0, 1.0};
    if (const double *imgSpacing = firstImage.GetSpacing()) {
        spacing[0] = imgSpacing[0];
        spacing[1] = imgSpacing[1];
        spacing[2] = imgSpacing[2];
    }
    const double zSpacing = sorter.GetZSpacing();
    if (zSpacing > 0.0) {
        spacing[2] = zSpacing;
    }

    BOOL signedPixel = pixelFormat.GetPixelRepresentation() == 1;

    NSString *seriesDescription = url.lastPathComponent;
    const gdcm::DataSet &dataset = firstReader.GetFile().GetDataSet();
    gdcm::Tag seriesDescTag(0x0008, 0x103E);
    if (dataset.FindDataElement(seriesDescTag)) {
        const gdcm::DataElement &element = dataset.GetDataElement(seriesDescTag);
        const gdcm::ByteValue *value = element.GetByteValue();
        if (value && value->GetLength() > 0) {
            std::string description(value->GetPointer(), value->GetLength());
            if (!description.empty()) {
                seriesDescription = [[NSString alloc] initWithBytes:description.data()
                                                             length:description.size()
                                                           encoding:NSUTF8StringEncoding];
            }
        }
    }

    double rescaleSlope = 1.0;
    double rescaleIntercept = 0.0;
    {
        gdcm::Tag slopeTag(0x0028, 0x1053);
        if (dataset.FindDataElement(slopeTag)) {
            const gdcm::DataElement &element = dataset.GetDataElement(slopeTag);
            gdcm::Attribute<0x0028, 0x1053> attribute;
            attribute.SetFromDataElement(element);
            if (attribute.GetNumberOfValues() >= 1) {
                rescaleSlope = attribute.GetValue();
                if (rescaleSlope == 0.0) {
                    rescaleSlope = 1.0;
                }
            }
        }

        gdcm::Tag interceptTag(0x0028, 0x1052);
        if (dataset.FindDataElement(interceptTag)) {
            const gdcm::DataElement &element = dataset.GetDataElement(interceptTag);
            gdcm::Attribute<0x0028, 0x1052> attribute;
            attribute.SetFromDataElement(element);
            if (attribute.GetNumberOfValues() >= 1) {
                rescaleIntercept = attribute.GetValue();
            }
        }
    }

    return [[DICOMSeriesVolume alloc] initWithVoxels:voxels
                                               width:dims[0]
                                              height:dims[1]
                                               depth:depth
                                            spacingX:spacing[0]
                                            spacingY:spacing[1]
                                            spacingZ:spacing[2]
                                        rescaleSlope:rescaleSlope
                                    rescaleIntercept:rescaleIntercept
                                         bitsAllocated:bitsAllocated
                                           signedPixel:signedPixel
                                     seriesDescription:seriesDescription];
#else
    if (error) {
        *error = [NSError errorWithDomain:DICOMSeriesLoaderErrorDomain
                                      code:DICOMSeriesLoaderErrorUnavailable
                                  userInfo:@{NSLocalizedDescriptionKey: @"GDCM não está disponível no target atual."}];
    }
    return nil;
#endif
}

@end
