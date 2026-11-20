import Foundation
import Testing
import ZeusCore

@Suite("Accessory settings")
struct AccessorySettingsTests {
    @Test func accessorySlotCarriesTheClosedSettingsAndTheTopBarPlacement() {
        let slot = AccessorySectionSlot.descriptor
        #expect(slot.id == "glass.accessory")
        #expect(slot.title == "Accessory")
        #expect(slot.filled == true)
        #expect(slot.order == 6)
        #expect(slot.keys == [
            "accessory.earbudsOverlay",
            "accessory.overlayStyle",
            "accessory.speakerNames",
        ])
        #expect(slot.placement == .topbarTab(6))
        #expect(GlassSectionManifest.slotProblems([slot]).isEmpty)
    }

    @Test func everyAccessoryItemIsOffAndFailsClosed() {
        let preferences = AccessoryPreferences.failClosed
        #expect(preferences.earbudsOverlay == false)
        #expect(preferences.overlayStyle == .off)
        #expect(preferences.speakerNames == false)
        #expect(AccessoryPreferences.restored(overlay: nil, style: nil, speakers: nil) == preferences)
        #expect(AccessoryPreferences.restored(overlay: "true", style: "compact", speakers: "true") == AccessoryPreferences(
            earbudsOverlay: true, overlayStyle: .compact, speakerNames: true
        ))
    }

    @Test func corruptStoredValuesFailClosed() {
        let junk = ["yes", "TRUE", "1", "on", "", " ", "falsey"]
        for overlay in junk {
            for speakers in junk {
                let restored = AccessoryPreferences.restored(overlay: overlay, style: "nope", speakers: speakers)
                #expect(restored == .failClosed)
            }
        }
        #expect(AccessoryPreferences.restored(overlay: "false", style: nil, speakers: "false") == .failClosed)
        #expect(AccessoryPreferences.restored(overlay: "true", style: "COMPACT", speakers: "false").overlayStyle == .off)
        #expect(AccessoryOverlayStyle.resolved(nil) == .off)
        #expect(AccessoryOverlayStyle.resolved("") == .off)
        #expect(AccessoryOverlayStyle.resolved("split ") == .off)
        for style in AccessoryOverlayStyle.allCases {
            #expect(AccessoryOverlayStyle.resolved(style.rawValue) == style)
        }
    }

    @Test func anImportCannotTurnAccessorySettingsOn() {
        let styles = AccessoryOverlayStyle.allCases
        let flags = [false, true]
        for earbuds in flags {
            for style in styles {
                for speakers in flags {
                    let imported = AccessoryPreferences(earbudsOverlay: earbuds, overlayStyle: style, speakerNames: speakers)
                    #expect(AccessoryPreferences.failClosed.applyingImport(imported) == .failClosed)
                }
            }
        }
        let open = AccessoryPreferences(earbudsOverlay: true, overlayStyle: .compact, speakerNames: true)
        #expect(open.applyingImport(.failClosed) == .failClosed)
        let kept = AccessoryPreferences(earbudsOverlay: true, overlayStyle: .split, speakerNames: false)
        #expect(open.applyingImport(kept) == kept)
        let styleStaysOff = AccessoryPreferences(earbudsOverlay: false, overlayStyle: .off, speakerNames: false)
        #expect(styleStaysOff.applyingImport(AccessoryPreferences(
            earbudsOverlay: false, overlayStyle: .split, speakerNames: false
        )) == styleStaysOff)
    }

    @Test func accessoryKeysAreRegisteredForExportImportSearchAndReset() throws {
        let root = accessoryRepositoryRoot()
        let catalog = try String(contentsOf: root.appendingPathComponent("Sources/Zeus/App/SettingsCatalog.swift"), encoding: .utf8)
        let store = try String(contentsOf: root.appendingPathComponent("Sources/Zeus/App/SettingsStore.swift"), encoding: .utf8)
        let expected = [
            (AccessoryPreferenceKey.earbudsOverlay, "defaultValue: \"false\""),
            (AccessoryPreferenceKey.overlayStyle, "defaultValue: \"off\""),
            (AccessoryPreferenceKey.speakerNames, "defaultValue: \"false\""),
        ]
        for (id, marker) in expected {
            let line = catalog.split(separator: "\n", omittingEmptySubsequences: false).first { $0.contains("id: \"\(id)\"") }
            #expect(line?.contains(marker) == true)
            #expect(line?.contains("section: .topBar") == true)
            #expect(store.contains("\"\(id)\""))
        }
    }

    @Test func layoutUsesTheGlassRowPaddingAndCardSpacing() {
        #expect(GlassSettingsMetrics.controlRow == 52)
        #expect(GlassSettingsMetrics.helperLine == 16)
        #expect(GlassSettingsMetrics.panelPadding == 32)
        #expect(GlassSettingsMetrics.cardSpacing == 28)
    }

    @Test func everyControlHasAHelperAndAVoiceOverLabel() {
        for copy in [AccessoryCopy.earbuds, AccessoryCopy.style, AccessoryCopy.speakers] {
            #expect(!copy.title.isEmpty)
            #expect(copy.helper.hasSuffix("."))
            #expect(!copy.accessibilityLabel.isEmpty)
            #expect(!copy.accessibilityHint.isEmpty)
            #expect(!copy.helper.contains("—"))
            #expect(!copy.accessibilityLabel.contains("—"))
        }
        for style in AccessoryOverlayStyle.allCases {
            #expect(!AccessoryCopy.styleChoice(style).isEmpty)
        }
        #expect(AccessoryCopy.enableConfirmation.hasSuffix("."))
        #expect(AccessoryCopy.confirm == "Look")
        #expect(AccessoryCopy.cancel == "Not now")
        #expect(AccessoryCopy.previewOff.hasSuffix("."))
    }

    @Test func copyDoesNotNameOtherProducts() {
        let blobs = [
            AccessoryCopy.earbuds.title, AccessoryCopy.earbuds.helper, AccessoryCopy.earbuds.accessibilityLabel,
            AccessoryCopy.style.title, AccessoryCopy.style.helper, AccessoryCopy.speakers.title, AccessoryCopy.speakers.helper,
            AccessoryCopy.enableConfirmation, AccessoryCopy.previewOff,
        ] + AccessoryOverlayStyle.allCases.map(AccessoryCopy.styleChoice)
        let banned = ["AirPlay", "AirPods", "Bluetooth", "Bonjour", "Superwhisper"]
        for blob in blobs {
            for word in banned {
                #expect(!blob.contains(word))
            }
        }
    }

    @Test func previewIsHiddenUntilOverlayAndStyleAreOn() {
        let hidden = AccessoryPreviewTile.make(preferences: .failClosed, live: AccessoryConnectInput.preview, reduceMotion: false)
        #expect(hidden.visible == false)
        #expect(hidden.emptyMessage == AccessoryCopy.previewOff)
        #expect(hidden.duration == MotionTokens.crossfadeDuration)

        var styleOnly = AccessoryPreferences.failClosed
        styleOnly.overlayStyle = .split
        #expect(AccessoryPreviewTile.make(preferences: styleOnly, live: nil, reduceMotion: false).visible == false)

        var overlayOnly = AccessoryPreferences.failClosed
        overlayOnly.earbudsOverlay = true
        #expect(AccessoryPreviewTile.make(preferences: overlayOnly, live: nil, reduceMotion: false).visible == false)

        var open = AccessoryPreferences.failClosed
        open.earbudsOverlay = true
        open.overlayStyle = .compact
        let sample = AccessoryPreviewTile.make(preferences: open, live: nil, reduceMotion: true)
        #expect(sample.visible == true)
        #expect(sample.duration == 0)
        #expect(sample.lines.contains("Unknown") == false)
        #expect(!sample.accessibilityLabel.isEmpty)
        #expect(sample.showsListeningMode == false)

        let unknown = AccessoryConnectInput(
            id: "live",
            name: "Hall buds",
            connected: true,
            charge: AccessoryChargeReading(left: 0, right: 0, caseCharge: 0, known: false),
            listeningMode: nil
        )
        let live = AccessoryPreviewTile.make(preferences: open, live: unknown, reduceMotion: false)
        #expect(live.visible == true)
        #expect(live.lines.joined(separator: " ").contains("Unknown"))
        #expect(!live.lines.joined(separator: " ").contains("0%"))
        #expect(live.duration == MotionTokens.crossfadeDuration)
    }

    @Test func thePageUsesTheMetricsAndNamesNoOtherProduct() throws {
        let root = accessoryRepositoryRoot()
        let page = root.appendingPathComponent("Sources/Zeus/Settings/GlassShell/Sections/AccessorySettingsSection.swift")
        let source = try String(contentsOf: page, encoding: .utf8)
        #expect(source.contains("GlassSettingsMetrics.controlRow"))
        #expect(source.contains("GlassSettingsMetrics.helperLine"))
        #expect(source.contains("GlassSettingsMetrics.panelPadding"))
        #expect(source.contains("GlassSettingsMetrics.cardSpacing"))
        #expect(source.contains("AccessoryConnectInput"))
        #expect(source.contains("accessibilityLabel"))
        #expect(source.contains("accessibilityHint"))
        #expect(source.contains("focusable"))
        #expect(!source.contains("NSWindow"))
        #expect(!source.contains(".sheet"))
        for word in ["AirPlay", "AirPods", "Bluetooth", "Bonjour", "Superwhisper"] {
            #expect(!source.contains(word))
        }
    }

    @Test func accessorySourcesDoNotNameOtherProducts() throws {
        let root = accessoryRepositoryRoot()
        let files = [
            "Sources/ZeusCore/Settings/Sections/AccessorySectionSlot.swift",
            "Sources/Zeus/Settings/GlassShell/Sections/AccessorySettingsSection.swift",
        ]
        let folders = [
            "Sources/ZeusCore/Settings/Sections/Accessory",
            "Sources/Zeus/Settings/GlassShell/Sections/Accessory",
        ]
        var paths = files.map { root.appendingPathComponent($0) }
        for folder in folders {
            let directory = root.appendingPathComponent(folder)
            let nested = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
            #expect(!nested.isEmpty)
            paths.append(contentsOf: nested.filter { $0.pathExtension == "swift" })
        }
        let banned = ["AirPlay", "AirPods", "Bluetooth", "Bonjour", "Superwhisper"]
        for path in paths {
            let source = try String(contentsOf: path, encoding: .utf8)
            for word in banned {
                #expect(!source.contains(word), "\(path.lastPathComponent) names \(word)")
            }
        }
    }
}

func accessoryRepositoryRoot() -> URL {
    URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
}
