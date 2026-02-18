import AppKit
import Metal
import MetalKit

/// Metal-based renderer pro zobrazení JPEG framů z remote desktopu.
class FrameRenderer: NSObject, MTKViewDelegate {
    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private let textureLoader: MTKTextureLoader
    private var pipelineState: MTLRenderPipelineState?
    private var currentTexture: MTLTexture?
    private let lock = NSLock()

    private var persistentTexture: MTLTexture?

    private let textureOptions: [MTKTextureLoader.Option: Any] = [
        .textureUsage: NSNumber(value: MTLTextureUsage.shaderRead.rawValue),
        .SRGB: NSNumber(value: false)
    ]

    init?(mtkView: MTKView) {
        guard let device = MTLCreateSystemDefaultDevice() else { return nil }
        self.device = device

        guard let queue = device.makeCommandQueue() else { return nil }
        self.commandQueue = queue
        self.textureLoader = MTKTextureLoader(device: device)

        super.init()

        setupPipeline(mtkView: mtkView)

        mtkView.device = device
        mtkView.delegate = self
        mtkView.isPaused = false
        mtkView.enableSetNeedsDisplay = false
        mtkView.preferredFramesPerSecond = 60
    }

    // MARK: - Setup

    private func setupPipeline(mtkView: MTKView) {
        let shaderSource = """
        #include <metal_stdlib>
        using namespace metal;

        struct VOut {
            float4 position [[position]];
            float2 uv;
        };

        vertex VOut vsMain(uint vid [[vertex_id]]) {
            float2 pos[] = {
                float2(-1, -1), float2(1, -1), float2(-1, 1),
                float2(1, -1), float2(1, 1), float2(-1, 1)
            };
            float2 uv[] = {
                float2(0, 1), float2(1, 1), float2(0, 0),
                float2(1, 1), float2(1, 0), float2(0, 0)
            };

            VOut o;
            o.position = float4(pos[vid], 0, 1);
            o.uv = uv[vid];
            return o;
        }

        fragment float4 fsMain(VOut in [[stage_in]],
                               texture2d<float> tex [[texture(0)]]) {
            constexpr sampler smp(mag_filter::linear, min_filter::linear);
            return tex.sample(smp, in.uv);
        }
        """

        guard let library = try? device.makeLibrary(source: shaderSource, options: nil),
              let vertexFunc = library.makeFunction(name: "vsMain"),
              let fragmentFunc = library.makeFunction(name: "fsMain") else {
            return
        }

        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = vertexFunc
        descriptor.fragmentFunction = fragmentFunc
        descriptor.colorAttachments[0].pixelFormat = mtkView.colorPixelFormat

        pipelineState = try? device.makeRenderPipelineState(descriptor: descriptor)
    }

    // MARK: - Frame Display

    private var frameCount = 0
    private var failCount = 0

    func displayFrame(_ jpegData: Data) {
        frameCount += 1

        guard let texture = try? textureLoader.newTexture(data: jpegData, options: textureOptions) else {
            failCount += 1
            if failCount <= 5 {
                print(">>> [RENDER] MTKTextureLoader FAILED for frame #\(frameCount), data size: \(jpegData.count), first 4: \(Array(jpegData.prefix(4)))")
            }
            return
        }

        if frameCount <= 3 {
            print(">>> [RENDER] Texture OK: \(texture.width)x\(texture.height), frame #\(frameCount)")
        }

        // Full frame – aktualizovat persistent texturu
        updatePersistentTexture(from: texture)

        lock.lock()
        currentTexture = persistentTexture ?? texture
        lock.unlock()
    }

    /// Zobrazí regionální updaty – blituje JPEG regiony na persistent texturu
    func displayRegions(_ regions: [RegionUpdate]) {
        guard let cmdBuffer = commandQueue.makeCommandBuffer(),
              let blitEncoder = cmdBuffer.makeBlitCommandEncoder() else { return }

        var needsNewPersistent = false

        for region in regions {
            guard let regionTexture = try? textureLoader.newTexture(data: region.jpegData, options: textureOptions) else {
                continue
            }

            // Vytvořit persistent texturu pokud neexistuje
            if persistentTexture == nil {
                needsNewPersistent = true
                break
            }

            let srcSize = MTLSize(width: min(Int(region.width), regionTexture.width),
                                  height: min(Int(region.height), regionTexture.height),
                                  depth: 1)
            let dstOrigin = MTLOrigin(x: Int(region.x), y: Int(region.y), z: 0)

            // Bezpečnostní kontrola hranic
            guard dstOrigin.x + srcSize.width <= persistentTexture!.width,
                  dstOrigin.y + srcSize.height <= persistentTexture!.height else {
                continue
            }

            blitEncoder.copy(from: regionTexture, sourceSlice: 0, sourceLevel: 0,
                           sourceOrigin: MTLOrigin(x: 0, y: 0, z: 0), sourceSize: srcSize,
                           to: persistentTexture!, destinationSlice: 0, destinationLevel: 0,
                           destinationOrigin: dstOrigin)
        }

        blitEncoder.endEncoding()
        cmdBuffer.commit()

        if needsNewPersistent {
            // Nemáme persistent texturu – čekáme na první full frame
            return
        }

        lock.lock()
        currentTexture = persistentTexture
        lock.unlock()
    }

    private func updatePersistentTexture(from source: MTLTexture) {
        // Vytvořit novou persistent texturu pokud má jiné rozměry
        if persistentTexture == nil ||
           persistentTexture!.width != source.width ||
           persistentTexture!.height != source.height {

            let desc = MTLTextureDescriptor.texture2DDescriptor(
                pixelFormat: source.pixelFormat,
                width: source.width,
                height: source.height,
                mipmapped: false)
            desc.usage = [.shaderRead, .shaderWrite]
            persistentTexture = device.makeTexture(descriptor: desc)
        }

        guard let persistent = persistentTexture,
              let cmdBuffer = commandQueue.makeCommandBuffer(),
              let blitEncoder = cmdBuffer.makeBlitCommandEncoder() else { return }

        let size = MTLSize(width: source.width, height: source.height, depth: 1)
        blitEncoder.copy(from: source, sourceSlice: 0, sourceLevel: 0,
                       sourceOrigin: MTLOrigin(x: 0, y: 0, z: 0), sourceSize: size,
                       to: persistent, destinationSlice: 0, destinationLevel: 0,
                       destinationOrigin: MTLOrigin(x: 0, y: 0, z: 0))
        blitEncoder.endEncoding()
        cmdBuffer.commit()
    }

    // MARK: - MTKViewDelegate

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    func draw(in view: MTKView) {
        lock.lock()
        let texture = currentTexture
        lock.unlock()

        guard let texture = texture,
              let pipeline = pipelineState,
              let drawable = view.currentDrawable,
              let descriptor = view.currentRenderPassDescriptor,
              let commandBuffer = commandQueue.makeCommandBuffer(),
              let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: descriptor) else { return }

        encoder.setRenderPipelineState(pipeline)
        encoder.setFragmentTexture(texture, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6)
        encoder.endEncoding()

        commandBuffer.present(drawable)
        commandBuffer.commit()
    }
}
