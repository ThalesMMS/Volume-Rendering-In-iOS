import simd

public typealias float2 = SIMD2<Float>
public typealias float3 = SIMD3<Float>
public typealias float4 = SIMD4<Float>
public typealias int3 = SIMD3<Int32>

protocol sizeable {}
extension sizeable {
    static var size: Int {
        return MemoryLayout<Self>.size
    }

    static var stride: Int {
        return MemoryLayout<Self>.stride
    }

    static func size(_ count: Int)->Int {
        return MemoryLayout<Self>.size * count
    }

    static func stride(_ count: Int)->Int {
        return MemoryLayout<Self>.stride * count
    }
}

extension Int32: sizeable {}
extension Float: sizeable {}
extension float2: sizeable {}
extension float3: sizeable {}
extension float4: sizeable {}

extension SIMD4 where Scalar == Float {
    var xyz: SIMD3<Float> { SIMD3(x, y, z) }
}
