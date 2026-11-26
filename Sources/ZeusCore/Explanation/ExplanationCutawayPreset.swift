import Foundation

/// App-owned cutaway preset for the housing of a teaching model.
///
/// Phase 4 asks the app, not the model, to set that housing to glass at
/// opacity 0.25 and to render it from both sides. A model-supplied shader
/// is refused. This type does not draw, does not load a material library,
/// and does not fetch anything.
public enum ExplanationCutawayPreset {
    public enum Material: String, Equatable, Sendable, CaseIterable {
        case glass
    }

    /// The housing the app applies. It carries no shader source and no shader name.
    public struct Housing: Equatable, Sendable {
        public let material: Material
        public let opacity: Double
        public let doubleSided: Bool

        public init(material: Material, opacity: Double, doubleSided: Bool) {
            self.material = material
            self.opacity = opacity
            self.doubleSided = doubleSided
        }
    }

    /// Closed material. The raw value matches the glass material name already
    /// used on explanation objects. The model does not choose it.
    public static let material = Material.glass
    /// One quarter. Distinct from the model cutaway's 0.15 fade.
    public static let opacity = 0.25
    public static let doubleSided = true
    /// The preset never admits a shader, a shader name, or shader source.
    public static let admitsModelShader = false
    public static let housing = Housing(material: material, opacity: opacity, doubleSided: doubleSided)

    public enum Refusal: Equatable, Sendable {
        case shader
    }

    public enum Outcome: Equatable, Sendable {
        case housing(Housing)
        case refused(Refusal)
    }

    /// What a model may try to send. `shader` is the only field that can
    /// change the outcome. The other fields are discarded.
    public struct Proposal: Equatable, Sendable {
        public var material: String?
        public var opacity: Double?
        public var doubleSided: Bool?
        public var shader: String?

        public init(material: String? = nil, opacity: Double? = nil,
                    doubleSided: Bool? = nil, shader: String? = nil) {
            self.material = material
            self.opacity = opacity
            self.doubleSided = doubleSided
            self.shader = shader
        }
    }

    /// Resolves a model proposal to the app housing.
    ///
    /// A shader is refused before any other field is read, so a proposal that
    /// already names glass at 0.25 still does not pass a shader through.
    /// Nil and a string made only of space, tab, newline, carriage return, or
    /// U+00A0 are not a shader. A zero-width space and every other scalar are.
    /// The blank set is written out so a platform character set cannot treat a
    /// format mark as blank. With no shader, the housing is the preset. The
    /// model's material, opacity, and sidedness are not copied, including
    /// non-finite numbers.
    public static func resolve(_ proposal: Proposal = .init()) -> Outcome {
        if shaderSupplied(proposal.shader) { return .refused(.shader) }
        return .housing(housing)
    }

    /// Space, tab, line feed, carriage return, and non-breaking space.
    private static let blankScalars: Set<Unicode.Scalar> = [" ", "\t", "\n", "\r", "\u{00A0}"]

    /// True when the model sent shader text. Nil and a blank string are absent.
    /// Any other scalar, including a name or a zero-width space, is a shader.
    private static func shaderSupplied(_ shader: String?) -> Bool {
        guard let shader else { return false }
        return shader.unicodeScalars.contains { !blankScalars.contains($0) }
    }
}
