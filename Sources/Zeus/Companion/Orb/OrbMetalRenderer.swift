import Foundation
import Metal
import MetalKit
import QuartzCore
import simd
import ZeusCore

// Ported from github.com/mysticalsin/jarvis2.0
// Source path: frontend/src/orb.ts
// Source commit: 16e37bd801eb797798e02540665f8b3804b0fe14
// Copyright (c) 2026 Ethan Rogers
// License: personal non-commercial grant. Full text: LICENSES/jarvis2.0-LICENSE
//
// The simulation stays in ZeusCore. This view draws it with instanced point sprites and additive
// blending. Shader source is compiled at runtime so Package.swift does not gain a Metal build step.
// Linux has no Metal. Nothing in this file runs there, and a missing device does not claim a render.

enum OrbMetalLibrary {
    static let source = """
    #include <metal_stdlib>
    using namespace metal;

    struct Uniforms {
        float4x4 viewProjection;
        float4 color;
        float4 spin; // xyz rotation, w cloudZ. Kept 16-byte aligned with Swift.
        float4 size; // x is the point size.
    };

    struct VertexOut {
        float4 position [[position]];
        float pointSize [[point_size]];
        float4 color;
    };

    float3 rotateXYZ(float3 p, float x, float y, float z) {
        float cx = cos(x), sx = sin(x);
        float cy = cos(y), sy = sin(y);
        float cz = cos(z), sz = sin(z);
        float3 r;
        r.x = cy * cz * p.x + (-cy * sz) * p.y + sy * p.z;
        r.y = (cx * sz + cz * sx * sy) * p.x + (cx * cz - sx * sy * sz) * p.y + (-cy * sx) * p.z;
        r.z = (sx * sz - cx * cz * sy) * p.x + (cz * sx + cx * sy * sz) * p.y + (cx * cy) * p.z;
        return r;
    }

    vertex VertexOut orb_point_vertex(uint vid [[vertex_id]],
                                      constant float3 *positions [[buffer(0)]],
                                      constant Uniforms &u [[buffer(1)]]) {
        float3 p = rotateXYZ(positions[vid], u.spin.x, u.spin.y, u.spin.z);
        p.z += u.spin.w;
        VertexOut out;
        out.position = u.viewProjection * float4(p, 1);
        out.pointSize = max(u.size.x, 1);
        out.color = u.color;
        return out;
    }

    fragment float4 orb_point_fragment(VertexOut in [[stage_in]], float2 pc [[point_coord]]) {
        float d = distance(pc, float2(0.5));
        if (d > 0.5) discard_fragment();
        return in.color * (1 - smoothstep(0.15, 0.5, d));
    }

    vertex VertexOut orb_line_vertex(uint vid [[vertex_id]],
                                     constant float3 *positions [[buffer(0)]],
                                     constant Uniforms &u [[buffer(1)]]) {
        float3 p = rotateXYZ(positions[vid], u.spin.x, u.spin.y, u.spin.z);
        p.z += u.spin.w;
        VertexOut out;
        out.position = u.viewProjection * float4(p, 1);
        out.pointSize = 1;
        out.color = u.color;
        return out;
    }

    fragment float4 orb_line_fragment(VertexOut in [[stage_in]]) {
        return in.color;
    }
    """
}

struct OrbMetalUniforms {
    var viewProjection: float4x4
    var color: SIMD4<Float>
    /// xyz rotation, w is cloudZ. Matches the Metal struct field for field.
    var spin: SIMD4<Float>
    /// x is the point size in pixels.
    var size: SIMD4<Float>
}

final class OrbMetalRenderer: NSObject, MTKViewDelegate {
    let device: MTLDevice
    private let queue: MTLCommandQueue
    private let pointPipeline: MTLRenderPipelineState
    private let linePipeline: MTLRenderPipelineState
    private let positions: MTLBuffer
    private let linePositions: MTLBuffer
    private let electronPositions: MTLBuffer
    private var simulation: OrbSimulation
    private let bands: OrbPlaybackMeter
    private let lock = NSLock()
    private var lastTimestamp: CFTimeInterval = 0
    private var reduceMotion = false

    func setReduceMotion(_ reduced: Bool) {
        lock.lock()
        reduceMotion = reduced
        lock.unlock()
    }

    init(device: MTLDevice, bands: OrbPlaybackMeter, seed: UInt32 = 1) throws {
        self.device = device
        guard let queue = device.makeCommandQueue() else { throw OrbMetalError.noQueue }
        self.queue = queue
        let library = try device.makeLibrary(source: OrbMetalLibrary.source, options: nil)
        pointPipeline = try Self.pipeline(device: device, library: library, vertex: "orb_point_vertex", fragment: "orb_point_fragment", points: true)
        linePipeline = try Self.pipeline(device: device, library: library, vertex: "orb_line_vertex", fragment: "orb_line_fragment", points: false)
        guard let positions = device.makeBuffer(length: OrbSimulation.particleCount * 3 * MemoryLayout<Float>.stride, options: .storageModeShared),
              let linePositions = device.makeBuffer(length: OrbSimulation.maxLines * 2 * 3 * MemoryLayout<Float>.stride, options: .storageModeShared),
              let electronPositions = device.makeBuffer(length: OrbSimulation.maxLiveElectrons * 3 * MemoryLayout<Float>.stride, options: .storageModeShared)
        else { throw OrbMetalError.noBuffer }
        self.positions = positions
        self.linePositions = linePositions
        self.electronPositions = electronPositions
        simulation = OrbSimulation(seed: seed)
        self.bands = bands
        super.init()
    }

    func setVisualState(_ state: OrbVisualState) {
        lock.lock()
        simulation.setVisualState(state)
        lock.unlock()
    }

    func draw(in view: MTKView) {
        let now = CACurrentMediaTime()
        let delta = lastTimestamp == 0 ? 1.0 / 60.0 : now - lastTimestamp
        lastTimestamp = now
        lock.lock()
        simulation.renderFrame(delta: delta, audio: bands.playbackBands(), reduceMotion: reduceMotion)
        let snapshot = simulation
        lock.unlock()
        guard let drawable = view.currentDrawable, let pass = view.currentRenderPassDescriptor,
              let command = queue.makeCommandBuffer() else { return }
        pass.colorAttachments[0]?.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        pass.colorAttachments[0]?.loadAction = .clear
        encode(snapshot: snapshot, pass: pass, command: command, drawableSize: view.drawableSize)
        command.present(drawable)
        command.commit()
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    /// Draws one already-stepped simulation into `texture`. The caller owns the clock.
    func draw(snapshot: OrbSimulation, into texture: MTLTexture) throws {
        guard let command = queue.makeCommandBuffer() else { throw OrbMetalError.noCommand }
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0]?.texture = texture
        pass.colorAttachments[0]?.loadAction = .clear
        pass.colorAttachments[0]?.storeAction = .store
        // frontend/src/orb.ts:31, the page clear. The live mascot view clears transparent so it can sit
        // on the existing overlay; the offscreen proof keeps this opaque background.
        pass.colorAttachments[0]?.clearColor = MTLClearColor(red: 5.0 / 255, green: 5.0 / 255, blue: 8.0 / 255, alpha: 1)
        encode(snapshot: snapshot, pass: pass, command: command, drawableSize: CGSize(width: texture.width, height: texture.height))
        command.commit()
        command.waitUntilCompleted()
        if let error = command.error { throw error }
    }

    private func encode(snapshot: OrbSimulation, pass: MTLRenderPassDescriptor, command: MTLCommandBuffer, drawableSize: CGSize) {
        upload(snapshot)
        guard let encoder = command.makeRenderCommandEncoder(descriptor: pass) else { return }
        let aspect = Float(max(drawableSize.width, 1) / max(drawableSize.height, 1))
        let view = lookAt(eye: SIMD3(Float(snapshot.cameraX), Float(snapshot.cameraY), Float(snapshot.cameraZ)),
                          center: SIMD3(0, 0, Float(snapshot.lookAtZ)),
                          up: SIMD3(0, 1, 0))
        let projection = perspective(fovyRadians: 45 * .pi / 180, aspect: aspect, near: 1, far: 1000)
        var particleUniforms = uniforms(snapshot: snapshot, viewProjection: projection * view,
                                        pointSize: Float(snapshot.pointSize) * Float(drawableSize.height) / 28,
                                        color: SIMD4(Float(snapshot.color.r), Float(snapshot.color.g), Float(snapshot.color.b), Float(snapshot.displayedOpacity)))
        encoder.setRenderPipelineState(pointPipeline)
        encoder.setVertexBuffer(positions, offset: 0, index: 0)
        encoder.setVertexBytes(&particleUniforms, length: MemoryLayout<OrbMetalUniforms>.stride, index: 1)
        encoder.drawPrimitives(type: .point, vertexStart: 0, vertexCount: snapshot.particles.count)

        if snapshot.lineCount > 0 {
            var lineUniforms = uniforms(snapshot: snapshot, viewProjection: projection * view, pointSize: 1,
                                        color: SIMD4(Float(snapshot.color.r), Float(snapshot.color.g), Float(snapshot.color.b), Float(snapshot.lineOpacity)))
            encoder.setRenderPipelineState(linePipeline)
            encoder.setVertexBuffer(linePositions, offset: 0, index: 0)
            encoder.setVertexBytes(&lineUniforms, length: MemoryLayout<OrbMetalUniforms>.stride, index: 1)
            encoder.drawPrimitives(type: .line, vertexStart: 0, vertexCount: snapshot.lineCount * 2)
        }

        if !snapshot.electrons.isEmpty {
            var electronUniforms = uniforms(snapshot: snapshot, viewProjection: projection * view,
                                            pointSize: Float(drawableSize.height) / 18,
                                            color: SIMD4(1, 1, 1, 1))
            encoder.setRenderPipelineState(pointPipeline)
            encoder.setVertexBuffer(electronPositions, offset: 0, index: 0)
            encoder.setVertexBytes(&electronUniforms, length: MemoryLayout<OrbMetalUniforms>.stride, index: 1)
            encoder.drawPrimitives(type: .point, vertexStart: 0, vertexCount: snapshot.electrons.count)
        }
        encoder.endEncoding()
    }

    private func upload(_ snapshot: OrbSimulation) {
        let particlePointer = positions.contents().bindMemory(to: Float.self, capacity: snapshot.particles.count * 3)
        for (index, particle) in snapshot.particles.enumerated() {
            particlePointer[index * 3] = Float(particle.x)
            particlePointer[index * 3 + 1] = Float(particle.y)
            particlePointer[index * 3 + 2] = Float(particle.z)
        }
        let linePointer = linePositions.contents().bindMemory(to: Float.self, capacity: max(snapshot.lineCount, 1) * 6)
        for (index, line) in snapshot.lines.enumerated() {
            linePointer[index * 6] = Float(line.x1)
            linePointer[index * 6 + 1] = Float(line.y1)
            linePointer[index * 6 + 2] = Float(line.z1)
            linePointer[index * 6 + 3] = Float(line.x2)
            linePointer[index * 6 + 4] = Float(line.y2)
            linePointer[index * 6 + 5] = Float(line.z2)
        }
        let electronPointer = electronPositions.contents().bindMemory(to: Float.self, capacity: OrbSimulation.maxLiveElectrons * 3)
        for (index, electron) in snapshot.electrons.enumerated() {
            let travel = electron.travel
            electronPointer[index * 3] = Float(electron.sx + (electron.ex - electron.sx) * travel)
            electronPointer[index * 3 + 1] = Float(electron.sy + (electron.ey - electron.sy) * travel)
            electronPointer[index * 3 + 2] = Float(electron.sz + (electron.ez - electron.sz) * travel)
        }
    }

    private func uniforms(snapshot: OrbSimulation, viewProjection: float4x4, pointSize: Float, color: SIMD4<Float>) -> OrbMetalUniforms {
        OrbMetalUniforms(
            viewProjection: viewProjection,
            color: color,
            spin: SIMD4(Float(snapshot.spinX), Float(snapshot.spinY), Float(snapshot.spinZ), Float(snapshot.cloudZ)),
            size: SIMD4(pointSize, 0, 0, 0))
    }

    private static func pipeline(device: MTLDevice, library: MTLLibrary, vertex: String, fragment: String, points: Bool) throws -> MTLRenderPipelineState {
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = library.makeFunction(name: vertex)
        descriptor.fragmentFunction = library.makeFunction(name: fragment)
        guard let attachment = descriptor.colorAttachments[0] else { throw OrbMetalError.noCommand }
        attachment.pixelFormat = .bgra8Unorm
        // frontend/src/orb.ts:57 and :72, additive blending, depth write off.
        attachment.isBlendingEnabled = true
        attachment.rgbBlendOperation = .add
        attachment.alphaBlendOperation = .add
        attachment.sourceRGBBlendFactor = .one
        attachment.destinationRGBBlendFactor = .one
        attachment.sourceAlphaBlendFactor = .one
        attachment.destinationAlphaBlendFactor = .one
        if points { descriptor.inputPrimitiveTopology = .point }
        return try device.makeRenderPipelineState(descriptor: descriptor)
    }
}

enum OrbMetalError: Error {
    case noQueue
    case noBuffer
    case noCommand
}

private func perspective(fovyRadians: Float, aspect: Float, near: Float, far: Float) -> float4x4 {
    let yScale = 1 / tan(fovyRadians * 0.5)
    let xScale = yScale / aspect
    let zRange = far / (near - far)
    return float4x4(columns: (
        SIMD4<Float>(xScale, 0, 0, 0),
        SIMD4<Float>(0, yScale, 0, 0),
        SIMD4<Float>(0, 0, zRange, -1),
        SIMD4<Float>(0, 0, zRange * near, 0)))
}

private func lookAt(eye: SIMD3<Float>, center: SIMD3<Float>, up: SIMD3<Float>) -> float4x4 {
    let forward = simd_normalize(center - eye)
    let side = simd_normalize(simd_cross(forward, up))
    let lifted = simd_cross(side, forward)
    return float4x4(columns: (
        SIMD4<Float>(side.x, lifted.x, -forward.x, 0),
        SIMD4<Float>(side.y, lifted.y, -forward.y, 0),
        SIMD4<Float>(side.z, lifted.z, -forward.z, 0),
        SIMD4<Float>(-simd_dot(side, eye), -simd_dot(lifted, eye), simd_dot(forward, eye), 1)))
}
