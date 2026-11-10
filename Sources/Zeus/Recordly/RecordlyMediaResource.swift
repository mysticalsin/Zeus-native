import AVFoundation
import AVKit
import Foundation
import Observation
import SwiftUI
import UniformTypeIdentifiers
import ZeusCore

/// Feeds AVFoundation from a pinned `RecordlyValidatedMedia` descriptor through a custom-scheme URL. Every byte
/// handed to the player comes from `readBounded` on that descriptor; no pathname is opened, and there is no
/// fallback URL. It never closes the handle: the Controller owns it, and a closed handle fails requests.
final class RecordlyMediaResourceLoader: NSObject, AVAssetResourceLoaderDelegate, @unchecked Sendable {
    static let scheme = "zeus-recordly-media"
    static let maxOutstandingRequests = 8
    static let chunksPerPass = 16

    let url: URL
    /// Loader state below is confined to this serial queue, which is also the delegate queue.
    let queue = DispatchQueue(label: "zeus.recordly.media-loader")
    private let media: RecordlyValidatedMedia
    private let purpose: RecordlyValidatedMedia.ReadPurpose
    private let contentType: String
    private var outstanding: [ObjectIdentifier: AVAssetResourceLoadingRequest] = [:]
    private var invalidated = false

    init?(media: RecordlyValidatedMedia, purpose: RecordlyValidatedMedia.ReadPurpose = .preview) {
        guard (purpose == .export || media.byteCount <= RecordlyValidatedMedia.maxPreviewBytes),
              let url = URL(string: "\(Self.scheme)://\(UUID().uuidString)/media.\(Self.fileExtension(of: media.path))")
        else { return nil }
        self.media = media
        self.purpose = purpose
        self.url = url
        self.contentType = Self.fileExtension(of: media.path) == "mov"
            ? UTType.quickTimeMovie.identifier
            : UTType.mpeg4Movie.identifier
        super.init()
    }

    /// Display-only: the decoded path string is read for its extension and never opened.
    private static func fileExtension(of path: String) -> String {
        switch (path as NSString).pathExtension.lowercased() {
        case "mov": "mov"
        case "m4v": "m4v"
        default: "mp4"
        }
    }

    func makeAsset() -> AVURLAsset {
        let asset = AVURLAsset(url: url)
        asset.resourceLoader.setDelegate(self, queue: queue)
        return asset
    }

    /// Finishes every outstanding request as cancelled and refuses new ones. Safe to call more than once.
    func invalidate() {
        queue.async { [self] in
            invalidated = true
            let pending = Array(outstanding.values)
            outstanding.removeAll()
            for request in pending { request.finishLoading(with: Self.cancelledError) }
        }
    }

    private static var cancelledError: NSError { NSError(domain: NSURLErrorDomain, code: NSURLErrorCancelled) }

    // MARK: AVAssetResourceLoaderDelegate (called on `queue`)

    func resourceLoader(
        _ resourceLoader: AVAssetResourceLoader,
        shouldWaitForLoadingOfRequestedResource loadingRequest: AVAssetResourceLoadingRequest
    ) -> Bool {
        guard loadingRequest.request.url == url else { return false }
        guard !invalidated else {
            loadingRequest.finishLoading(with: Self.cancelledError)
            return true
        }
        guard outstanding.count < Self.maxOutstandingRequests else {
            loadingRequest.finishLoading(with: NSError(domain: NSURLErrorDomain, code: NSURLErrorResourceUnavailable))
            return true
        }
        if let info = loadingRequest.contentInformationRequest {
            info.contentType = contentType
            info.contentLength = media.byteCount
            info.isByteRangeAccessSupported = true
        }
        outstanding[ObjectIdentifier(loadingRequest)] = loadingRequest
        pump(loadingRequest)
        return true
    }

    func resourceLoader(_ resourceLoader: AVAssetResourceLoader, didCancel loadingRequest: AVAssetResourceLoadingRequest) {
        outstanding.removeValue(forKey: ObjectIdentifier(loadingRequest))
    }

    // MARK: Bounded serving

    private func complete(_ request: AVAssetResourceLoadingRequest, error: Error?) {
        outstanding.removeValue(forKey: ObjectIdentifier(request))
        if let error { request.finishLoading(with: error) } else { request.finishLoading() }
    }

    /// Serves at most `chunksPerPass` chunks, then yields the queue so cancels and other requests interleave.
    private func pump(_ request: AVAssetResourceLoadingRequest) {
        guard outstanding[ObjectIdentifier(request)] === request else { return }
        guard let data = request.dataRequest else { return complete(request, error: nil) }
        let size = media.byteCount
        let offset = data.requestedOffset
        guard offset >= 0, offset <= size, data.requestedLength >= 0 else {
            return complete(request, error: RecordlyCheckpointStore.StoreError.readOutOfRange)
        }
        let end: Int64
        if data.requestsAllDataToEndOfResource {
            end = size
        } else {
            let (sum, overflow) = offset.addingReportingOverflow(Int64(data.requestedLength))
            end = overflow ? size : min(sum, size)
        }
        do {
            for _ in 0..<Self.chunksPerPass {
                let current = data.currentOffset
                if current >= end { return complete(request, error: nil) }
                let want = Int(min(Int64(RecordlyValidatedMedia.maxReadChunk), end - current))
                let bytes = try media.readBounded(offset: current, length: want, expectedSize: size, purpose: purpose)
                if bytes.isEmpty { throw RecordlyCheckpointStore.StoreError.mediaChanged }
                data.respond(with: bytes)
            }
        } catch {
            return complete(request, error: error)
        }
        queue.async { [weak self] in self?.pump(request) }
    }
}

/// Owns one preview player. Starting twice replaces the first; stopping drops the player and the loader but
/// leaves the Controller's handle open.
@MainActor
@Observable
final class RecordlyMediaPreviewModel {
    static let shared = RecordlyMediaPreviewModel()
    private(set) var player: AVPlayer?
    private(set) var failure: String?
    @ObservationIgnored private var loader: RecordlyMediaResourceLoader?
    @ObservationIgnored private var statusObservation: NSKeyValueObservation?

    func start(media: RecordlyValidatedMedia) {
        stop()
        guard let loader = RecordlyMediaResourceLoader(media: media) else {
            failure = "Preview unavailable: the recording is larger than the 512 MiB preview limit."
            return
        }
        self.loader = loader
        let item = AVPlayerItem(asset: loader.makeAsset())
        statusObservation = item.observe(\.status, options: [.new]) { [weak self] item, _ in
            let status = item.status
            let message = item.error?.localizedDescription
            Task { @MainActor in
                guard let self, self.player?.currentItem === item else { return }
                if status == .failed { self.failure = "Preview unavailable: \(message ?? "the player could not read this recording.")" }
            }
        }
        player = AVPlayer(playerItem: item)
    }

    func stop() {
        player?.pause()
        player?.replaceCurrentItem(with: nil)
        player = nil
        statusObservation = nil
        loader?.invalidate()
        loader = nil
        failure = nil
    }
}

/// Bounded playback of the pinned recording. This is a preview only: it is not a timeline editor or an export.
struct RecordlyMediaPreview: View {
    let media: RecordlyValidatedMedia?
    let unavailableReason: String?
    // This toolchain has no SwiftUI @State macro; one shared preview model (start replaces).
    private let model = RecordlyMediaPreviewModel.shared

    var body: some View {
        Group {
            if media == nil {
                note(unavailableReason ?? "No trusted recording is available to preview.")
            } else if let failure = model.failure {
                note(failure)
            } else if let player = model.player {
                VideoPlayer(player: player).frame(minHeight: 90, maxHeight: 140)
            } else {
                ProgressView().controlSize(.small)
            }
        }
        .task(id: media.map(ObjectIdentifier.init)) {
            if let media { model.start(media: media) } else { model.stop() }
        }
        .onDisappear { model.stop() }
    }

    private func note(_ text: String) -> some View {
        Text(text).font(TopBarStyle.label(10)).foregroundStyle(Theme.cloudSecondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}
