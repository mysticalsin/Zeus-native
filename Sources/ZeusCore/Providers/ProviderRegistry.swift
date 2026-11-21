import Foundation

public struct ProviderEntry: Sendable {
    public var descriptor: ProviderDescriptor
    public var make: @Sendable () -> any TTSProvider
    public init(descriptor: ProviderDescriptor, make: @escaping @Sendable () -> any TTSProvider) {
        self.descriptor = descriptor
        self.make = make
    }
}

/// Adding a provider is one adapter file plus one entry here.
public enum ProviderRegistry {
    public static let entries: [ProviderEntry] = [
        ProviderEntry(descriptor: ElevenLabsTTSAdapter.descriptor, make: { ElevenLabsTTSAdapter() }),
        ProviderEntry(descriptor: GoogleCloudTTSAdapter.descriptor, make: { GoogleCloudTTSAdapter() }),
    ]

    public static func make(_ id: String) -> (any TTSProvider)? {
        entries.first { $0.descriptor.id == id }?.make()
    }

    public static func descriptor(_ id: String) -> ProviderDescriptor? {
        entries.first { $0.descriptor.id == id }?.descriptor
    }
}
