import Testing
@testable import Zeus

@Suite("Step zero listening mode device")
struct ListeningModeDeviceTests {
    private let device = ListeningModeDevice.self

    @Test func twoSelectorsUseGlobalScopeAndFourBytes() {
        #expect(device.Selector.allCases == [.mode, .mask])
        #expect(device.modeSelector == fourcc("lstm"))
        #expect(device.maskSelector == fourcc("lsms"))
        #expect(device.modeSelector != device.maskSelector)
        #expect(device.scopeGlobal == fourcc("glob"))
        #expect(device.elementMain == 0)
        #expect(device.byteCount == 4)
        let mode = device.address(for: .mode)
        let mask = device.address(for: .mask)
        #expect(mode.selector == device.modeSelector)
        #expect(mask.selector == device.maskSelector)
        #expect(mode.scope == device.scopeGlobal)
        #expect(mask.scope == device.scopeGlobal)
        #expect(mode.element == 0)
        #expect(mask.element == 0)
        #expect(mode != mask)
    }

    @Test func aReadKeepsBothValuesAndAsksInOrder() {
        let tally = Tally()
        let read = device.read(readGate(
            tally,
            modeBytes: answer(status: 0, bytes: [2, 0, 0, 0]),
            maskBytes: answer(status: 0, bytes: [7, 0, 0, 1])
        ))
        #expect(read == .values(mode: 2, mask: 0x0100_0007))
        #expect(tally.kinds == ["has", "size", "read", "has", "size", "read"])
        #expect(tally.selectors == [
            device.modeSelector, device.modeSelector, device.modeSelector,
            device.maskSelector, device.maskSelector, device.maskSelector,
        ])
        #expect(tally.scopes.allSatisfy { $0 == device.scopeGlobal })
        #expect(tally.elements.allSatisfy { $0 == device.elementMain })
        #expect(tally.writes == 0)
    }

    @Test func aMissingPropertyOrBadSizeAsksForNothingFurther() {
        let missing = Tally()
        let missed = device.read(readGate(missing, hasMode: false, modeBytes: answer(status: 0, bytes: [9, 0, 0, 0])))
        #expect(missed == .unbound(.missingMode))
        #expect(missing.kinds == ["has"])
        #expect(missing.selectors == [device.modeSelector])

        let short = Tally()
        let three = device.read(readGate(short, modeSize: device.SizeAnswer(status: 0, bytes: 3)))
        #expect(three == .unbound(.modeSize))
        #expect(short.kinds == ["has", "size"])

        let long = Tally()
        let five = device.read(readGate(long, modeSize: device.SizeAnswer(status: 0, bytes: 5)))
        #expect(five == .unbound(.modeSize))
        #expect(long.kinds == ["has", "size"])

        let zero = Tally()
        let empty = device.read(readGate(zero, modeSize: device.SizeAnswer(status: 0, bytes: 0)))
        #expect(empty == .unbound(.modeSize))

        let negative = Tally()
        let below = device.read(readGate(negative, modeSize: device.SizeAnswer(status: 0, bytes: -1)))
        #expect(below == .unbound(.modeSize))
        #expect(negative.kinds == ["has", "size"])

        let exact = Tally()
        let kept = device.read(readGate(exact, modeSize: device.SizeAnswer(status: 0, bytes: device.byteCount)))
        #expect(kept == .values(mode: 1, mask: 2))
        #expect(exact.kinds == ["has", "size", "read", "has", "size", "read"])
    }

    @Test func aFailedStatusDoesNotReadTheBytes() {
        for status in [Int32(1), Int32(-1), Int32.max, Int32.min] {
            let tally = Tally()
            let read = device.read(readGate(
                tally,
                modeSize: device.SizeAnswer(status: status, bytes: device.byteCount),
                modeBytes: answer(status: 0, bytes: [4, 0, 0, 0])
            ))
            #expect(read == .unbound(.modeSizeStatus))
            #expect(tally.kinds == ["has", "size"])
        }

        let tally = Tally()
        let read = device.read(readGate(
            tally,
            modeBytes: answer(status: 1, bytes: [4, 0, 0, 0])
        ))
        #expect(read == .unbound(.modeReadStatus))
        #expect(tally.kinds == ["has", "size", "read"])
        #expect(tally.selectors.allSatisfy { $0 == device.modeSelector })
    }

    @Test func bytesOutsideFourAreDropped() {
        #expect(device.integer(from: []) == nil)
        #expect(device.integer(from: [1, 0, 0]) == nil)
        #expect(device.integer(from: [1, 0, 0, 0, 0]) == nil)
        #expect(device.integer(from: Array(repeating: 9, count: 64)) == nil)
        #expect(device.integer(from: [0, 0, 0, 0]) == 0)
        #expect(device.integer(from: [1, 0, 0, 0]) == 1)
        #expect(device.integer(from: [0xFF, 0xFF, 0xFF, 0xFF]) == UInt32.max)
        #expect(device.bytes(of: 0) == [0, 0, 0, 0])
        #expect(device.bytes(of: 1) == [1, 0, 0, 0])
        #expect(device.bytes(of: UInt32.max) == [0xFF, 0xFF, 0xFF, 0xFF])
        #expect(device.bytes(of: 0x0100_0007).count == device.byteCount)
        #expect(device.integer(from: device.bytes(of: 0x0100_0007)) == 0x0100_0007)

        let over = Tally()
        let wide = device.read(readGate(over, modeBytes: answer(status: 0, bytes: [1, 0, 0, 0, 9])))
        #expect(wide == .unbound(.modeBytes))
        #expect(over.kinds == ["has", "size", "read"])

        let exact = Tally()
        let kept = device.read(readGate(exact, modeBytes: answer(status: 0, bytes: device.bytes(of: 40))))
        #expect(kept == .values(mode: 40, mask: 2))
        #expect(exact.kinds.contains("read"))
    }

    @Test func aMaskFailureDropsTheModeValue() {
        let missing = Tally()
        let missed = device.read(readGate(missing, modeBytes: answer(status: 0, bytes: device.bytes(of: 2)), hasMask: false))
        #expect(missed == .unbound(.missingMask))
        #expect(missing.kinds == ["has", "size", "read", "has"])

        let sized = Tally()
        let badSize = device.read(readGate(
            sized,
            modeBytes: answer(status: 0, bytes: device.bytes(of: 2)),
            maskSize: device.SizeAnswer(status: 0, bytes: 8)
        ))
        #expect(badSize == .unbound(.maskSize))
        #expect(sized.kinds == ["has", "size", "read", "has", "size"])

        let status = Tally()
        let badStatus = device.read(readGate(
            status,
            modeBytes: answer(status: 0, bytes: device.bytes(of: 2)),
            maskBytes: answer(status: 5, bytes: device.bytes(of: 3))
        ))
        #expect(badStatus == .unbound(.maskReadStatus))
        #expect(status.kinds == ["has", "size", "read", "has", "size", "read"])

        let counted = Tally()
        let badCount = device.read(readGate(
            counted,
            modeBytes: answer(status: 0, bytes: device.bytes(of: 2)),
            maskBytes: answer(status: 0, bytes: [3])
        ))
        #expect(badCount == .unbound(.maskBytes))
        if case .values = badCount {
            Issue.record("a failed mask kept the mode")
        }
    }

    @Test func aCheckedWriteSendsFourBytesOnce() {
        let tally = Tally()
        let wrote = device.write(3, gate: writeGate(tally, status: 0))
        #expect(wrote == .wrote(true))
        #expect(tally.kinds == ["default", "transport", "has", "size", "settable", "write"])
        #expect(tally.written == [device.bytes(of: 3)])
        #expect(tally.selectors == [device.modeSelector, device.modeSelector, device.modeSelector, device.modeSelector])
        #expect(tally.selectors.allSatisfy { $0 != device.maskSelector })
        #expect(tally.scopes.allSatisfy { $0 == device.scopeGlobal })
        #expect(tally.elements.allSatisfy { $0 == 0 })
        #expect(tally.writes == 1)

        let high = Tally()
        let full = device.write(UInt32.max, gate: writeGate(high, status: 0))
        #expect(full == .wrote(true))
        #expect(high.written == [[0xFF, 0xFF, 0xFF, 0xFF]])
        #expect(high.writes == 1)

        let zero = Tally()
        let cleared = device.write(0, gate: writeGate(zero, status: 0))
        #expect(cleared == .wrote(true))
        #expect(zero.written == [[0, 0, 0, 0]])
    }

    @Test func aFailedCheckDoesNotWrite() {
        let notDefault = Tally()
        #expect(device.write(2, gate: writeGate(notDefault, isDefault: false)) == .notWritten(.notDefault))
        #expect(notDefault.kinds == ["default"])
        #expect(notDefault.writes == 0)

        let wired = Tally()
        #expect(device.write(2, gate: writeGate(wired, bluetooth: false)) == .notWritten(.notBluetooth))
        #expect(wired.kinds == ["default", "transport"])
        #expect(wired.writes == 0)

        let missing = Tally()
        #expect(device.write(2, gate: writeGate(missing, has: false)) == .notWritten(.missing))
        #expect(missing.kinds == ["default", "transport", "has"])
        #expect(missing.writes == 0)

        let badStatus = Tally()
        #expect(device.write(
            2,
            gate: writeGate(badStatus, size: device.SizeAnswer(status: 1, bytes: device.byteCount))
        ) == .notWritten(.sizeStatus))
        #expect(badStatus.kinds == ["default", "transport", "has", "size"])

        let badSize = Tally()
        #expect(device.write(
            2,
            gate: writeGate(badSize, size: device.SizeAnswer(status: 0, bytes: 8))
        ) == .notWritten(.size))
        #expect(badSize.kinds == ["default", "transport", "has", "size"])

        let flagStatus = Tally()
        #expect(device.write(
            2,
            gate: writeGate(flagStatus, settable: device.FlagAnswer(status: 1, settable: true))
        ) == .notWritten(.settableStatus))
        #expect(flagStatus.kinds == ["default", "transport", "has", "size", "settable"])
        #expect(flagStatus.writes == 0)

        let fixed = Tally()
        #expect(device.write(
            2,
            gate: writeGate(fixed, settable: device.FlagAnswer(status: 0, settable: false))
        ) == .notWritten(.notSettable))
        #expect(fixed.writes == 0)
        #expect(fixed.written.isEmpty)
    }

    @Test func aRejectedWriteIsNotSentAgain() {
        let tally = Tally()
        let first = device.write(4, gate: writeGate(tally, status: 7))
        #expect(first == .wrote(false))
        #expect(tally.writes == 1)
        #expect(tally.written == [device.bytes(of: 4)])

        let second = device.write(4, gate: writeGate(tally, status: 0))
        #expect(second == .wrote(true))
        #expect(tally.writes == 2)
        #expect(tally.written.count == 2)
    }

    @Test func aSecondCallStartsEmpty() {
        let tally = Tally()
        let first = device.read(readGate(
            tally,
            modeBytes: answer(status: 0, bytes: device.bytes(of: 1)),
            maskBytes: answer(status: 0, bytes: device.bytes(of: 2))
        ))
        let second = device.read(readGate(
            tally,
            modeBytes: answer(status: 0, bytes: device.bytes(of: 9)),
            maskBytes: answer(status: 0, bytes: device.bytes(of: 8))
        ))
        #expect(first == .values(mode: 1, mask: 2))
        #expect(second == .values(mode: 9, mask: 8))
        #expect(first != second)
        #expect(tally.writes == 0)

        let again = device.write(6, gate: writeGate(tally, status: 0))
        #expect(again == .wrote(true))
        #expect(tally.written == [device.bytes(of: 6)])
    }

    private func answer(status: Int32, bytes: [UInt8]) -> ListeningModeDevice.BytesAnswer {
        ListeningModeDevice.BytesAnswer(status: status, bytes: bytes)
    }

    private func readGate(
        _ tally: Tally,
        hasMode: Bool = true,
        modeSize: ListeningModeDevice.SizeAnswer = .init(status: 0, bytes: 4),
        modeBytes: ListeningModeDevice.BytesAnswer = .init(status: 0, bytes: [1, 0, 0, 0]),
        hasMask: Bool = true,
        maskSize: ListeningModeDevice.SizeAnswer = .init(status: 0, bytes: 4),
        maskBytes: ListeningModeDevice.BytesAnswer = .init(status: 0, bytes: [2, 0, 0, 0])
    ) -> ListeningModeDevice.ReadGate {
        ListeningModeDevice.ReadGate(
            hasProperty: { address in
                tally.note("has", address)
                if address.selector == device.modeSelector { return hasMode }
                return hasMask
            },
            dataSize: { address in
                tally.note("size", address)
                return address.selector == device.modeSelector ? modeSize : maskSize
            },
            readBytes: { address in
                tally.note("read", address)
                return address.selector == device.modeSelector ? modeBytes : maskBytes
            }
        )
    }

    private func writeGate(
        _ tally: Tally,
        isDefault: Bool = true,
        bluetooth: Bool = true,
        has: Bool = true,
        size: ListeningModeDevice.SizeAnswer = .init(status: 0, bytes: 4),
        settable: ListeningModeDevice.FlagAnswer = .init(status: 0, settable: true),
        status: Int32 = 0
    ) -> ListeningModeDevice.WriteGate {
        ListeningModeDevice.WriteGate(
            isDefault: {
                tally.kinds.append("default")
                return isDefault
            },
            transportBluetooth: {
                tally.kinds.append("transport")
                return bluetooth
            },
            hasProperty: { address in
                tally.note("has", address)
                return has
            },
            dataSize: { address in
                tally.note("size", address)
                return size
            },
            isSettable: { address in
                tally.note("settable", address)
                return settable
            },
            writeBytes: { address, bytes in
                tally.note("write", address)
                tally.writes += 1
                tally.written.append(bytes)
                return status
            }
        )
    }

    private func fourcc(_ word: String) -> UInt32 {
        var value: UInt32 = 0
        for byte in word.utf8 {
            value = (value << 8) | UInt32(byte)
        }
        return value
    }
}

private final class Tally: @unchecked Sendable {
    var kinds: [String] = []
    var selectors: [UInt32] = []
    var scopes: [UInt32] = []
    var elements: [UInt32] = []
    var written: [[UInt8]] = []
    var writes = 0

    func note(_ kind: String, _ address: ListeningModeDevice.Address) {
        kinds.append(kind)
        selectors.append(address.selector)
        scopes.append(address.scope)
        elements.append(address.element)
    }
}
