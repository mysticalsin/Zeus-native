import Foundation
import Testing
@testable import ZeusCore

/// Phase 4 cutaway preset (docs/POINTING-ASSISTANT-PLAN.md).
/// The app, not the model, sets the housing to glass at opacity 0.25 and
/// renders it from both sides. A model-supplied shader is refused.
@Suite("Explanation cutaway preset")
struct ExplanationCutawayPresetTests {
    private typealias Preset = ExplanationCutawayPreset

    /// The contract, written out. Tests compare against this value, not against
    /// `Preset.housing`, so a stub that is wrong in both places cannot pass.
    private var expected: Preset.Housing {
        Preset.Housing(material: .glass, opacity: 0.25, doubleSided: true)
    }

    private func resolve(
        material: String? = nil,
        opacity: Double? = nil,
        doubleSided: Bool? = nil,
        shader: String? = nil
    ) -> Preset.Outcome {
        Preset.resolve(Preset.Proposal(
            material: material, opacity: opacity, doubleSided: doubleSided, shader: shader))
    }

    @Test func thePresetIsGlassAtAQuarterAndDoubleSided() {
        #expect(Preset.material == .glass)
        #expect(Preset.material.rawValue == "glass")
        #expect(Preset.Material.allCases == [.glass])
        #expect(Preset.opacity == 0.25)
        #expect(Preset.opacity != 0.15)
        #expect(Preset.opacity.isFinite)
        #expect(Preset.opacity > 0 && Preset.opacity < 1)
        #expect(Preset.doubleSided == true)
        #expect(Preset.admitsModelShader == false)
        #expect(Preset.housing == expected)
        #expect(Preset.housing.material == .glass)
        #expect(Preset.housing.opacity == 0.25)
        #expect(Preset.housing.doubleSided == true)
    }

    @Test func anAbsentShaderResolvesToTheAppHousing() {
        let absent = [
            resolve(),
            Preset.resolve(),
            Preset.resolve(.init()),
            resolve(shader: nil),
            resolve(shader: ""),
            resolve(shader: " "),
            resolve(shader: "\n"),
            resolve(shader: "\t"),
            resolve(shader: "\n\t "),
            resolve(shader: "\r\n"),
            resolve(shader: "\u{00A0}"),
            resolve(shader: " \u{00A0}\n"),
        ]
        for outcome in absent {
            #expect(outcome == .housing(expected))
        }
        #expect(resolve() == resolve())
    }

    @Test func aModelShaderIsRefusedAndNotRetained() {
        let programs = [
            "shader",
            "glass",
            "pbr",
            "SCNProgram",
            "metal",
            "{",
            "void main() {}",
            "none",
            "null",
            "false",
            "0",
            "GLASS",
            "x",
            "\\",
            " glass ",
            "a\nb",
            "\u{0000}",
            "\u{200B}",
            "シェーダ",
            String(repeating: "a", count: 100_000),
            String(repeating: " ", count: 20) + "x",
        ]
        for program in programs {
            #expect(resolve(shader: program) == .refused(.shader))
        }
        let first = resolve(shader: "vertex")
        let second = resolve(shader: String(repeating: "fragment", count: 40))
        #expect(first == second)
        #expect(first == .refused(.shader))
        #expect(resolve(material: "glass", opacity: 0.25, doubleSided: true, shader: "x") == .refused(.shader))
    }

    @Test func modelLookIsDiscardedWhenNoShaderIsSupplied() {
        let materials = ["metal", "matte", "emissive", "Glass", "GLASS", "glass ", "plastic", "", " ", "glass"]
        let opacities: [Double?] = [nil, 0, 1, 0.15, 0.2500001, .nan, .infinity, -.infinity, -1, 2]
        let sides: [Bool?] = [nil, false, true]
        for material in materials {
            for opacity in opacities {
                for side in sides {
                    #expect(resolve(material: material, opacity: opacity, doubleSided: side) == .housing(expected))
                }
            }
        }
        if case .housing(let value) = resolve(material: "metal", opacity: 0.15, doubleSided: false) {
            #expect(value.opacity.isFinite)
            #expect(value.opacity == 0.25)
            #expect(value.doubleSided == true)
            #expect(value.material == .glass)
        } else {
            Issue.record("an absent shader produced no housing")
        }
    }

    @Test func aShaderRefusalWinsOverEveryOtherField() {
        let hostile: [Double] = [.nan, .infinity, -.infinity, 0.15, 0.25, 1]
        for opacity in hostile {
            #expect(resolve(material: "metal", opacity: opacity, doubleSided: false, shader: "x") == .refused(.shader))
            #expect(resolve(material: "glass", opacity: opacity, doubleSided: true, shader: " \nshader") == .refused(.shader))
        }
        #expect(resolve(opacity: .nan, shader: " \t") == .housing(expected))
        #expect(resolve(material: "metal", opacity: .infinity, doubleSided: false, shader: "\n") == .housing(expected))
    }
}
