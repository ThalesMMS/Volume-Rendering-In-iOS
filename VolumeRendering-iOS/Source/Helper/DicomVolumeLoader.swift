import Foundation
import ZIPFoundation

enum DicomVolumeLoaderError: Error {
    case securityScopeUnavailable
    case unsupportedBitDepth
    case missingResult
    case bridgeError(NSError)
}

struct DicomImportResult {
    let dataset: VolumeDataset
    let sourceURL: URL
    let seriesDescription: String
}

final class DicomVolumeLoader {

    private let loader = DICOMSeriesLoader()

    private struct PreparedDirectory {
        let url: URL
        let cleanupRoot: URL?
    }

    func loadVolume(from url: URL) throws -> DicomImportResult {
        let prepared = try prepareDirectory(from: url)
        let directoryURL = prepared.url

        let volume: DICOMSeriesVolume
        do {
            volume = try loader.loadSeries(at: directoryURL)
        } catch let error as NSError {
            throw DicomVolumeLoaderError.bridgeError(error)
        }

        if volume.bitsAllocated != 16 {
            throw DicomVolumeLoaderError.unsupportedBitDepth
        }

        let dimensions = int3(Int32(volume.width), Int32(volume.height), Int32(volume.depth))
        // DICOM spacing is in millimeters; SceneKit expects meters.
        let spacing = float3(Float(volume.spacingX) * 0.001,
                             Float(volume.spacingY) * 0.001,
                             Float(volume.spacingZ) * 0.001)
        let conversion = convertToHU(volume: volume)

        let dataset = VolumeDataset(data: conversion.data,
                                     dimensions: dimensions,
                                     spacing: spacing,
                                     pixelFormat: .int16Signed,
                                     intensityRange: conversion.range)

        if let cleanupRoot = prepared.cleanupRoot {
            try? FileManager.default.removeItem(at: cleanupRoot)
        }

        return DicomImportResult(dataset: dataset,
                                 sourceURL: url,
                                 seriesDescription: volume.seriesDescription)
    }

    private func prepareDirectory(from url: URL) throws -> PreparedDirectory {
        if url.hasDirectoryPath {
            return PreparedDirectory(url: url, cleanupRoot: nil)
        }

        if url.pathExtension.lowercased() == "zip" {
            return try unzip(url: url)
        }

        // Assume individual file inside a directory; use parent directory.
        return PreparedDirectory(url: url.deletingLastPathComponent(), cleanupRoot: nil)
    }

    private func unzip(url: URL) throws -> PreparedDirectory {
        let temporaryDirectory = URL(fileURLWithPath: NSTemporaryDirectory(),
                                     isDirectory: true).appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)

        guard let archive = Archive(url: url, accessMode: .read) else {
            throw DicomVolumeLoaderError.missingResult
        }

        for entry in archive {
            let destinationURL = temporaryDirectory.appendingPathComponent(entry.path)
            let destinationDir = destinationURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: destinationDir, withIntermediateDirectories: true)
            try archive.extract(entry, to: destinationURL)
        }

        // If the archive expands to a single directory, dive into it for cleanliness.
        let contents = try FileManager.default.contentsOfDirectory(at: temporaryDirectory,
                                                                   includingPropertiesForKeys: [.isDirectoryKey],
                                                                   options: [.skipsHiddenFiles])
        if contents.count == 1, (try contents.first?.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
            return PreparedDirectory(url: contents[0], cleanupRoot: temporaryDirectory)
        }

        return PreparedDirectory(url: temporaryDirectory, cleanupRoot: temporaryDirectory)
    }
}

private extension DicomVolumeLoader {
    struct ConversionResult {
        let data: Data
        let range: ClosedRange<Int32>
    }

    func convertToHU(volume: DICOMSeriesVolume) -> ConversionResult {
        let voxelCount = Int(volume.width) * Int(volume.height) * Int(volume.depth)
        var converted = Data(count: voxelCount * MemoryLayout<Int16>.size)

        var minHU = Int32.max
        var maxHU = Int32.min

        let clampMin: Int32 = -1024
        let clampMax: Int32 = 3071

        let slope = volume.rescaleSlope == 0 ? 1.0 : volume.rescaleSlope
        let intercept = volume.rescaleIntercept

        let sourceData = volume.voxels as Data

        converted.withUnsafeMutableBytes { destBuffer in
            guard let destPtr = destBuffer.bindMemory(to: Int16.self).baseAddress else { return }

            sourceData.withUnsafeBytes { rawBuffer in
                if volume.isSignedPixel {
                    let source = rawBuffer.bindMemory(to: Int16.self)
                    for index in 0..<voxelCount {
                        let rawValue = Int32(source[index])
                        let huDouble = Double(rawValue) * slope + intercept
                        let huRounded = Int32(lround(huDouble))
                        minHU = min(minHU, huRounded)
                        maxHU = max(maxHU, huRounded)
                        let huClamped = max(clampMin, min(clampMax, huRounded))
                        let clamped = max(Int32(Int16.min), min(Int32(Int16.max), huClamped))
                        destPtr[index] = Int16(clamped)
                    }
                } else {
                    let source = rawBuffer.bindMemory(to: UInt16.self)
                    for index in 0..<voxelCount {
                        let rawValue = Int32(source[index])
                        let huDouble = Double(rawValue) * slope + intercept
                        let huRounded = Int32(lround(huDouble))
                        minHU = min(minHU, huRounded)
                        maxHU = max(maxHU, huRounded)
                        let huClamped = max(clampMin, min(clampMax, huRounded))
                        let clamped = max(Int32(Int16.min), min(Int32(Int16.max), huClamped))
                        destPtr[index] = Int16(clamped)
                    }
                }
            }
        }

        if minHU > maxHU {
            minHU = clampMin
            maxHU = clampMax
        } else {
            minHU = max(minHU, clampMin)
            maxHU = min(maxHU, clampMax)
        }

        #if DEBUG
        let sampleCount = min(8, voxelCount)
        let preview = converted.withUnsafeBytes { buffer -> [Int16] in
            let ptr = buffer.bindMemory(to: Int16.self)
            return Array(ptr[0..<sampleCount])
        }
        print("[DICOM] Converted volume -> minHU: \(minHU) maxHU: \(maxHU) slope: \(slope) intercept: \(intercept) sample=\(preview)")
        #endif

        return ConversionResult(data: converted,
                                 range: minHU...maxHU)
    }
}
