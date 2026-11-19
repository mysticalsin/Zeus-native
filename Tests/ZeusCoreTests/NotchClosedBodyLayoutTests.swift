import CoreGraphics
import Testing
import ZeusCore

@Suite struct NotchClosedBodyLayoutTests {
    @Test func hudCueExpandsClosedBodyWidth() {
        let narrow = NotchClosedBodyLayout.bodyWidth(
            notchWidth: 185, shoulder: 0, showWings: false, extraWidth: 0, hasNotch: true, slimPill: false)
        let wide = NotchClosedBodyLayout.bodyWidth(
            notchWidth: 185, shoulder: 0, showWings: true, extraWidth: 58, hasNotch: true, slimPill: false)
        #expect(narrow == 185)
        #expect(wide > narrow)
        #expect(wide - narrow > 100)
    }

    @Test func wingsSpringTargetsUnder120ms() {
        #expect(NotchClosedBodyLayout.wingsSpringResponse <= 0.12)
    }

    @Test func showWingsWhenHudLightsAppear() {
        #expect(NotchClosedBodyLayout.showWings(closedWingKindIsNone: true, hasLights: true, hasLiveActivity: false))
        #expect(!NotchClosedBodyLayout.showWings(closedWingKindIsNone: true, hasLights: false, hasLiveActivity: false))
    }

    /// Every extra width `ClosedWings.extraWidth(for:)` can return, plus the idle mascot's and no extra (-36 was the old idle value).
    private static let everyExtra: [CGFloat] = [-36, NotchClosedBodyLayout.idleMascotExtra, 0, 14, 30, 58, 60, 70, 110, 150, 180, 230, 300]
    private static let notchWidths: [CGFloat] = [160, 185, 200, 220, 250]

    @Test func theNotchGapIsExactlyTheNotchForEveryNotchAndExtra() {
        for notch in Self.notchWidths {
            for shoulder: CGFloat in [0, 8] {
                for extra in Self.everyExtra {
                    let g = NotchClosedBodyLayout.closedWingGeometry(notchWidth: notch, shoulder: shoulder, extra: extra)
                    #expect(g.notchGap == -notch / 2 ... notch / 2)
                }
            }
        }
    }

    @Test func wingsAreSymmetricAndNeverOverlapTheGap() {
        for notch in Self.notchWidths {
            for extra in Self.everyExtra {
                let g = NotchClosedBodyLayout.closedWingGeometry(notchWidth: notch, shoulder: 8, extra: extra)
                #expect(g.leftWing.lowerBound == -g.rightWing.upperBound)
                #expect(g.leftWing.upperBound == -g.rightWing.lowerBound)
                #expect(g.leftWing.upperBound <= g.notchGap.lowerBound)
                #expect(g.rightWing.lowerBound >= g.notchGap.upperBound)
                #expect(g.rightWing.upperBound - g.rightWing.lowerBound == NotchClosedBodyLayout.wingWidth - 14 + extra)
            }
        }
    }

    /// The frames `ClosedWingsRow` lays out, from the art and bars widths the view passes in. Art is 14 pt wider.
    @Test func theMusicWingFramesStayInsideTheSymmetricContentBox() {
        let box = NotchClosedBodyLayout.wingWidth - NotchClosedBodyLayout.contentInset
        for scale in [CGFloat(1), 2, 3] {
            let (art, bars) = NotchClosedBodyLayout.musicContent(scale: scale)
            #expect(art - bars == NotchClosedBodyLayout.contentInset * scale)
            let music = NotchClosedBodyLayout.rowLayout(
                notchWidth: 220, extra: 0, leftProposal: art, rightProposal: bars, clipsMusic: true)
            #expect(music.leftWidth == music.rightWidth)
            #expect(music.leftWidth == box)
            #expect(music.clipWidth == box)
            #expect(music.gapWidth == 220)
            #expect(music.outwardInset == 0)
        }
    }

    /// Art and bars wider than the box stay inside it. The wings stay matched, so the test cannot pass by clipping one side only.
    @Test func wideArtAndBarsStayInsideTheBoxWithoutSkewingTheWings() {
        let box = NotchClosedBodyLayout.wingWidth - NotchClosedBodyLayout.contentInset
        let wide = NotchClosedBodyLayout.rowLayout(
            notchWidth: 220, extra: 0, leftProposal: 80, rightProposal: 64, clipsMusic: true)
        #expect(wide.leftWidth == box)
        #expect(wide.rightWidth == box)
        #expect(wide.leftWidth == wide.rightWidth)
        let glow = NotchClosedBodyLayout.rowLayout(
            notchWidth: 220, extra: 0, leftProposal: 80, rightProposal: 18, clipsMusic: false)
        #expect(glow.leftWidth == glow.rightWidth)
        #expect(glow.outwardInset == NotchClosedBodyLayout.contentInset)
        #expect(glow.leftWidth == box + NotchClosedBodyLayout.contentInset)
        #expect(glow.leftWidth < 80)
    }

    /// A Mac with no hardware notch keeps the 40 pt gap. An external display keeps its own notch width, still mirrored.
    @Test func aBarWithoutANotchAndAnExternalDisplayKeepMirroredWings() {
        let box = NotchClosedBodyLayout.wingWidth - NotchClosedBodyLayout.contentInset
        let plain = NotchClosedBodyLayout.rowLayout(
            notchWidth: NotchClosedBodyLayout.noNotchGap, extra: 0, leftProposal: 80, rightProposal: 30, clipsMusic: false)
        #expect(plain.gapWidth == 40)
        #expect(plain.leftWidth == plain.rightWidth)
        let external = NotchClosedBodyLayout.rowLayout(
            notchWidth: 300, extra: 0, leftProposal: 90, rightProposal: 20, clipsMusic: true)
        #expect(external.gapWidth == 300)
        #expect(external.leftWidth == box)
        #expect(external.rightWidth == box)
    }

    @Test func theWingsFillTheContentBoxInsideTheBodyPadding() {
        for notch in Self.notchWidths {
            for extra in Self.everyExtra {
                let g = NotchClosedBodyLayout.closedWingGeometry(notchWidth: notch, shoulder: 8, extra: extra)
                #expect(g.rightWing.upperBound == g.bodyWidth / 2 - 8 - 14)
                #expect(g.leftWing.lowerBound == -g.bodyWidth / 2 + 8 + 14)
            }
        }
    }

    @Test func bodyWidthGrowsBothWingsByTheExtra() {
        for notch in Self.notchWidths {
            for extra in Self.everyExtra {
                let expected = notch + 2 * 8 + 2 * (NotchClosedBodyLayout.wingWidth + extra)
                let g = NotchClosedBodyLayout.closedWingGeometry(notchWidth: notch, shoulder: 8, extra: extra)
                #expect(g.bodyWidth == expected)
                #expect(NotchClosedBodyLayout.bodyWidth(
                    notchWidth: notch, shoulder: 8, showWings: true, extraWidth: extra, hasNotch: true, slimPill: false) == expected)
            }
        }
    }

    @Test func aBarWithoutANotchKeepsAFortyPointGap() {
        for extra in Self.everyExtra {
            let width = NotchClosedBodyLayout.bodyWidth(
                notchWidth: 0, shoulder: 0, showWings: true, extraWidth: extra, hasNotch: false, slimPill: true)
            #expect(width == 40 + 2 * (NotchClosedBodyLayout.wingWidth + extra))
            let g = NotchClosedBodyLayout.closedWingGeometry(notchWidth: 40, shoulder: 0, extra: extra)
            #expect(g.bodyWidth == width)
            #expect(g.notchGap == -20 ... 20)
        }
    }

    @Test func theRestingMascotFitsItsWing() {
        for notch in Self.notchWidths {
            let g = NotchClosedBodyLayout.closedWingGeometry(
                notchWidth: notch, shoulder: 8, extra: NotchClosedBodyLayout.idleMascotExtra)
            #expect(g.wingContentWidth >= NotchClosedBodyLayout.miniMascotSize)
        }
    }

    @Test func theOldRightOnlyGrowthIsGone() {
        let g = NotchClosedBodyLayout.closedWingGeometry(notchWidth: 220, shoulder: 8, extra: 150)
        let expected: CGFloat = 220 + 16 + 2 * (62 + 150)
        #expect(g.bodyWidth == expected)
        #expect(g.rightWing.lowerBound == 110)
    }

    // MARK: Island background

    @Test func theClosedBodyHangsSixPointsBelowTheHardwareNotch() {
        #expect(NotchClosedBodyLayout.belowNotch == 6)
    }

    @Test func blackIsTheDefaultBackgroundAndAnythingUnknownIsBlack() {
        #expect(NotchBackground.settingID == "notch.background")
        #expect(NotchBackground.allCases.map(\.rawValue) == ["Black", "Transparent"])
        #expect(NotchBackground.resolve("Black") == .black)
        #expect(NotchBackground.resolve("Transparent") == .transparent)
        for stray in ["", "black", "transparent ", "Clear", "nope"] { #expect(NotchBackground.resolve(stray) == .black) }
    }

    @Test func blackDrawsFillOutlineAndGlowInEveryPresentation() {
        for closed in [true, false] {
            #expect(NotchBackground.black.layers(closed: closed) == NotchBodyLayers(fill: true, outline: true, glow: true))
        }
    }

    @Test func transparentDrawsNoFillOutlineOrGlowWhileClosedAndKeepsThemOpen() {
        #expect(NotchBackground.transparent.layers(closed: true) == NotchBodyLayers(fill: false, outline: false, glow: false))
        #expect(NotchBackground.transparent.layers(closed: false) == NotchBodyLayers(fill: true, outline: true, glow: true))
    }
}
