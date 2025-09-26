import CoreGraphics
import Metal
import UIKit
import simd
import ZIPFoundation

class VolumeTextureFactory {
    var part: VolumeCubeMaterial.BodyPart
    var resolution: float3
    var dimension: int3
    var scale: float3 {
        return float3(
            resolution.x * Float(dimension.x),
            resolution.y * Float(dimension.y),
            resolution.z * Float(dimension.z)
        )
    }
    
    init(_ part: VolumeCubeMaterial.BodyPart)
    {
        self.part = part
        
        if part == .head {
            resolution = float3(0.000449, 0.000449, 0.000501)
            dimension = int3(512, 512, 511)
            return
        }
        
        else if part == .chest{
            resolution = float3(0.000586, 0.000586, 0.002)
            dimension = int3(512, 512, 179)
            return
        }
        
        resolution = float3(1, 1, 1)
        dimension = int3(1, 1, 1)
    }
    
    func generate(device: MTLDevice) -> MTLTexture?
    {
        // example data type specification
        // type: Int16
        // size: dimension.x * dimension.y * dimension.z
        
        let descriptor = MTLTextureDescriptor()
        descriptor.textureType = .type3D
        descriptor.pixelFormat = .r16Sint
        descriptor.usage = .shaderRead
        
        if part == .none {
            descriptor.width = 1
            descriptor.height = 1
            descriptor.depth = 1
            
            // Unwrapping seguro para evitar crash
            guard let texture = device.makeTexture(descriptor: descriptor) else {
                print("🚨 ERRO: Falha ao criar a textura placeholder 1x1x1.")
                return nil
            }
            return texture
        } 
     
        let filename = part.rawValue
        guard let url = Bundle.main.url(forResource: filename, withExtension: "raw.zip") else {
            print("🚨 Recurso não encontrado: \(filename).raw.zip. Verifique se o git lfs pull foi executado.")
            return nil // Evita o crash
        }
        
        guard let archive = Archive(url: url, accessMode: .read) else {
            print("🚨 Não foi possível ler o arquivo zip: \(url.path). O arquivo pode ser um ponteiro do Git LFS.")
            return nil // Evita o crash
        }
        var data = Data()
        for entry in archive { // unzip data
            _ = try! archive.extract(entry) {
                data.append($0)
            }
        }
        
        descriptor.width = Int(dimension.x)
        descriptor.height = Int(dimension.y)
        descriptor.depth = Int(dimension.z)
        
        let bytesPerRow = MemoryLayout<Int16>.size * descriptor.width
        let bytesPerImage = bytesPerRow * descriptor.height
        
        guard let texture = device.makeTexture(descriptor: descriptor) else {
             print("🚨 ERRO: Falha ao criar a textura 3D para a parte: \(part.rawValue)")
             return nil
         }

        texture.replace(region: MTLRegionMake3D(0, 0, 0,
                                                descriptor.width,
                                                descriptor.height,
                                                descriptor.depth),
                        mipmapLevel: 0,
                        slice: 0,
                        withBytes: (data as NSData).bytes,
                        bytesPerRow: bytesPerRow,
                        bytesPerImage: bytesPerImage)
        
        return texture
    }
}
