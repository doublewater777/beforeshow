import Metal
import RealityKit

/// Runs `shelfFarBlur` (ListeningPickShelfBlur.metal) over each rendered frame.
@available(iOS 26.0, *)
struct ShelfFarBlur: PostProcessEffect {
    let overscan: Float
    private var pipeline: (any MTLComputePipelineState)?

    init(overscan: Float) {
        self.overscan = overscan
    }

    mutating func prepare(for device: any MTLDevice) {
        guard let function = device.makeDefaultLibrary()?.makeFunction(name: "shelfFarBlur") else { return }
        pipeline = try? device.makeComputePipelineState(function: function)
    }

    mutating func postProcess(context: borrowing PostProcessEffectContext<any MTLCommandBuffer>) {
        let destination = context.targetColorTexture
        let linearFormat: MTLPixelFormat
        switch destination.pixelFormat {
        case .bgra8Unorm_srgb: linearFormat = .bgra8Unorm
        case .rgba8Unorm_srgb: linearFormat = .rgba8Unorm
        default: linearFormat = destination.pixelFormat
        }
        // Some GPUs cannot shader-write sRGB textures. A linear view shares the same storage.
        let needsEncoding = linearFormat != destination.pixelFormat
        guard let target = needsEncoding ? destination.makeTextureView(pixelFormat: linearFormat) : destination else { return }
        guard let pipeline, let encoder = context.commandBuffer.makeComputeCommandEncoder() else { return }
        var overscan = overscan
        var encodeSRGB: UInt32 = needsEncoding ? 1 : 0
        encoder.setComputePipelineState(pipeline)
        encoder.setTexture(context.sourceColorTexture, index: 0)
        encoder.setTexture(target, index: 1)
        encoder.setBytes(&overscan, length: MemoryLayout<Float>.size, index: 0)
        encoder.setBytes(&encodeSRGB, length: MemoryLayout<UInt32>.size, index: 1)
        let group = MTLSize(width: 16, height: 16, depth: 1)
        let grid = MTLSize(
            width: (context.targetColorTexture.width + group.width - 1) / group.width,
            height: (context.targetColorTexture.height + group.height - 1) / group.height,
            depth: 1
        )
        // Uniform groups also work on the simulator; the shader bounds-checks the final group.
        encoder.dispatchThreadgroups(grid, threadsPerThreadgroup: group)
        encoder.endEncoding()
    }
}
