import Metal
import simd
import ZIPFoundation

final class VolumeTextureFactory {
    private(set) var dataset: VolumeDataset

    init(dataset: VolumeDataset) {
        self.dataset = dataset
    }

    convenience init(part: VolumeCubeMaterial.BodyPart) {
        self.init(dataset: VolumeTextureFactory.dataset(for: part))
    }

    var resolution: float3 { dataset.spacing }
    var dimension: int3 { dataset.dimensions }
    var scale: float3 { dataset.scale }

    func update(dataset: VolumeDataset) {
        self.dataset = dataset
    }

    func generate(device: MTLDevice) -> MTLTexture? {
        let descriptor = MTLTextureDescriptor()
        descriptor.textureType = .type3D
        descriptor.pixelFormat = dataset.pixelFormat.metalPixelFormat
        descriptor.usage = .shaderRead
        descriptor.width = Int(dataset.dimensions.x)
        descriptor.height = Int(dataset.dimensions.y)
        descriptor.depth = Int(dataset.dimensions.z)

        guard let texture = device.makeTexture(descriptor: descriptor) else {
            print("🚨 ERRO: Falha ao criar a textura 3D (\(descriptor.width)x\(descriptor.height)x\(descriptor.depth)).")
            return nil
        }

        let bytesPerRow = dataset.pixelFormat.bytesPerVoxel * descriptor.width
        let bytesPerImage = bytesPerRow * descriptor.height

        #if DEBUG
        print("[VolumeTextureFactory] Uploading texture format=\(descriptor.pixelFormat) dim=\(descriptor.width)x\(descriptor.height)x\(descriptor.depth) bytesPerImage=\(bytesPerImage))")
        #endif

        dataset.data.withUnsafeBytes { buffer in
            guard let baseAddress = buffer.baseAddress else { return }
            texture.replace(region: MTLRegionMake3D(0, 0, 0,
                                                    descriptor.width,
                                                    descriptor.height,
                                                    descriptor.depth),
                            mipmapLevel: 0,
                            slice: 0,
                            withBytes: baseAddress,
                            bytesPerRow: bytesPerRow,
                            bytesPerImage: bytesPerImage)
        }

        return texture
    }
}

private extension VolumeTextureFactory {
    static func dataset(for part: VolumeCubeMaterial.BodyPart) -> VolumeDataset {
        switch part {
        case .head:
            return loadZippedResource(named: "head",
                                      dimensions: int3(512, 512, 511),
                                      spacing: float3(0.000449, 0.000449, 0.000501),
                                      pixelFormat: .int16Signed,
                                      intensity: (-1024)...3071)
        case .chest:
            return loadZippedResource(named: "chest",
                                      dimensions: int3(512, 512, 179),
                                      spacing: float3(0.000586, 0.000586, 0.002),
                                      pixelFormat: .int16Signed,
                                      intensity: (-1024)...3071)
        case .none, .dicom:
            return placeholderDataset()
        }
    }

    static func placeholderDataset() -> VolumeDataset {
        let data = Data(count: VolumePixelFormat.int16Signed.bytesPerVoxel)
        return VolumeDataset(data: data,
                             dimensions: int3(1, 1, 1),
                             spacing: float3(1, 1, 1),
                             pixelFormat: .int16Signed,
                             intensityRange: (-1024)...3071)
    }

    static func loadZippedResource(named name: String,
                                   dimensions: int3,
                                   spacing: float3,
                                   pixelFormat: VolumePixelFormat,
                                   intensity: ClosedRange<Int32>) -> VolumeDataset {
        guard let url = Bundle.main.url(forResource: name, withExtension: "raw.zip") else {
            print("🚨 Recurso não encontrado: \(name).raw.zip. Certifique-se de executar git lfs pull.")
            return placeholderDataset()
        }

        guard let archive = Archive(url: url, accessMode: .read) else {
            print("🚨 Não foi possível ler o arquivo zip: \(url.path).")
            return placeholderDataset()
        }

        var data = Data(capacity: Int(dimensions.x) * Int(dimensions.y) * Int(dimensions.z) * pixelFormat.bytesPerVoxel)
        do {
            for entry in archive {
                _ = try archive.extract(entry) { buffer in
                    data.append(buffer)
                }
            }
        } catch {
            print("🚨 Falha ao extrair \(name).raw.zip: \(error)")
            return placeholderDataset()
        }

        if data.isEmpty {
            print("🚨 Arquivo \(name).raw.zip extraído porém vazio.")
            return placeholderDataset()
        }

        return VolumeDataset(data: data,
                             dimensions: dimensions,
                             spacing: spacing,
                             pixelFormat: pixelFormat,
                             intensityRange: intensity)
    }
}
