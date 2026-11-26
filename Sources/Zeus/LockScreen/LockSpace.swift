import Foundation
#if os(macOS)
import Darwin
#endif

/// The only file that names the window-server space functions.
///
/// A `LockSpaceHosting` host lets a caller use a fake. `LiveLockSpace` keeps a table only when
/// every one of the seven names resolves. The removal candidate is looked up from the same table
/// and never called. Nothing here runs on a background thread.
public protocol LockSpaceHosting: AnyObject {
    func missingSymbols() -> [String]
    func makeSpace() -> Bool
    func attach(windowNumber: Int) -> Bool
    func show() -> Bool
    func hide() -> Bool
    func destroy() -> Bool
}

public enum LockSpaceCatalog {
    /// The seven names, in the order the table is built. One missing name drops the whole table.
    public static let symbolNames: [String] = [
        "SLSMainConnectionID",
        "SLSSpaceCreate",
        "SLSSpaceSetAbsoluteLevel",
        "SLSShowSpaces",
        "SLSHideSpaces",
        "SLSSpaceAddWindowsAndRemoveFromSpaces",
        "SLSSpaceDestroy",
    ]

    public static let removalCandidate = "SLSRemoveWindowsFromSpaces"

    /// Absolute system path. Never a bare framework name.
    public static let frameworkPath = "/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight"

    /// Create takes this flag and no options.
    public static let createFlag = 1
    /// The space level above the lock screen.
    public static let level = 400
    /// The move call's selector.
    public static let moveSelector = 7
}

public final class LiveLockSpace: LockSpaceHosting {
    private var table: LockSpaceTable?
    private var missing: [String]
    private var removalFound: Bool
    private var space: UInt64?
    private var connection: Int32?
    /// How many space functions this host has actually called. A lookup does not count.
    public private(set) var invocations = 0

    /// Builds a host from an injected lookup. The pointers are kept only when all seven resolve,
    /// and this path never opens the framework.
    public static func hosting(lookup: (String) -> UnsafeMutableRawPointer?) -> LiveLockSpace {
        var found: [String: UnsafeMutableRawPointer] = [:]
        var missing: [String] = []
        for name in LockSpaceCatalog.symbolNames {
            if let pointer = lookup(name) {
                found[name] = pointer
            } else {
                missing.append(name)
            }
        }
        let removalFound = lookup(LockSpaceCatalog.removalCandidate) != nil
        let table = missing.isEmpty ? LockSpaceTable(found) : nil
        let reported = table == nil && missing.isEmpty ? LockSpaceCatalog.symbolNames : missing
        return LiveLockSpace(table: table, missing: reported, removalFound: removalFound)
    }

    /// A host that has not opened the framework and has not kept a pointer.
    public static func unloaded() -> LiveLockSpace {
        LiveLockSpace(table: nil, missing: LockSpaceCatalog.symbolNames, removalFound: false)
    }

    private init(table: LockSpaceTable?, missing: [String], removalFound: Bool) {
        self.table = table
        self.missing = missing
        self.removalFound = removalFound
    }

    public func missingSymbols() -> [String] { missing }

    /// True when the removal name resolved. The pointer from that lookup is not kept.
    public func removalCandidateResolved() -> Bool { removalFound }

    public var symbolsLoaded: Bool {
        guard let table else { return false }
        return table.retainedCount == LockSpaceCatalog.symbolNames.count
    }

    /// Opens the framework by its absolute path with `RTLD_NOW`, and only when asked.
    /// A second ask does not open it again once the table is complete.
    public func loadSymbols() -> Bool {
        if symbolsLoaded { return true }
        #if os(macOS)
        guard let handle = dlopen(LockSpaceCatalog.frameworkPath, RTLD_NOW) else { return false }
        let loaded = LiveLockSpace.hosting { name in dlsym(handle, name) }
        guard let table = loaded.table, loaded.symbolsLoaded else { return false }
        self.table = table
        missing = loaded.missing
        removalFound = loaded.removalFound
        return symbolsLoaded
        #else
        return false
        #endif
    }

    public func makeSpace() -> Bool {
        guard let table, symbolsLoaded, space == nil else { return false }
        #if os(macOS)
        invocations += 1
        let connection = table.mainConnection()
        let created = table.create(connection, Int32(LockSpaceCatalog.createFlag), nil)
        guard created != 0 else { return false }
        invocations += 1
        table.setLevel(connection, created, Int32(LockSpaceCatalog.level))
        self.connection = connection
        self.space = created
        return true
        #else
        return false
        #endif
    }

    public func attach(windowNumber: Int) -> Bool {
        guard windowNumber > 0 else { return false }
        guard let table, symbolsLoaded, let space, let connection else { return false }
        #if os(macOS)
        guard let windows = LockSpaceArray.one(Int64(windowNumber)) else { return false }
        invocations += 1
        table.move(connection, windows.pointer, space, Int32(LockSpaceCatalog.moveSelector))
        return true
        #else
        return false
        #endif
    }

    public func show() -> Bool {
        guard let table, symbolsLoaded, let space, let connection else { return false }
        #if os(macOS)
        guard let spaces = LockSpaceArray.one(Int64(bitPattern: space)) else { return false }
        invocations += 1
        table.show(connection, spaces.pointer)
        return true
        #else
        return false
        #endif
    }

    public func hide() -> Bool {
        guard let table, symbolsLoaded, let space, let connection else { return false }
        #if os(macOS)
        guard let spaces = LockSpaceArray.one(Int64(bitPattern: space)) else { return false }
        invocations += 1
        table.hide(connection, spaces.pointer)
        return true
        #else
        return false
        #endif
    }

    public func destroy() -> Bool {
        guard let table, symbolsLoaded, let space, let connection else { return false }
        #if os(macOS)
        invocations += 1
        table.destroy(connection, space)
        self.space = nil
        self.connection = nil
        return true
        #else
        return false
        #endif
    }
}

/// Seven function pointers. The value exists only when every name resolved, so a missing name
/// leaves no pointer behind.
private struct LockSpaceTable: Sendable {
    let mainConnection: @convention(c) () -> Int32
    let create: @convention(c) (Int32, Int32, UnsafeRawPointer?) -> UInt64
    let setLevel: @convention(c) (Int32, UInt64, Int32) -> Void
    let show: @convention(c) (Int32, UnsafeRawPointer?) -> Void
    let hide: @convention(c) (Int32, UnsafeRawPointer?) -> Void
    let move: @convention(c) (Int32, UnsafeRawPointer?, UInt64, Int32) -> Void
    let destroy: @convention(c) (Int32, UInt64) -> Void

    init?(_ found: [String: UnsafeMutableRawPointer]) {
        let names = LockSpaceCatalog.symbolNames
        guard names.count == 7,
              let main = found[names[0]],
              let create = found[names[1]],
              let level = found[names[2]],
              let show = found[names[3]],
              let hide = found[names[4]],
              let move = found[names[5]],
              let destroy = found[names[6]]
        else { return nil }
        mainConnection = unsafeBitCast(main, to: (@convention(c) () -> Int32).self)
        self.create = unsafeBitCast(create, to: (@convention(c) (Int32, Int32, UnsafeRawPointer?) -> UInt64).self)
        setLevel = unsafeBitCast(level, to: (@convention(c) (Int32, UInt64, Int32) -> Void).self)
        self.show = unsafeBitCast(show, to: (@convention(c) (Int32, UnsafeRawPointer?) -> Void).self)
        self.hide = unsafeBitCast(hide, to: (@convention(c) (Int32, UnsafeRawPointer?) -> Void).self)
        self.move = unsafeBitCast(move, to: (@convention(c) (Int32, UnsafeRawPointer?, UInt64, Int32) -> Void).self)
        self.destroy = unsafeBitCast(destroy, to: (@convention(c) (Int32, UInt64) -> Void).self)
    }

    /// Reads each pointer so the table stays live. It does not call any of them.
    var retainedCount: Int {
        _ = mainConnection
        _ = create
        _ = setLevel
        _ = show
        _ = hide
        _ = move
        _ = destroy
        return 7
    }
}

#if os(macOS)
private struct LockSpaceArray {
    let array: CFArray
    var pointer: UnsafeRawPointer { Unmanaged.passUnretained(array).toOpaque() }

    /// One signed 64-bit number in an array the space calls can take. The space id itself stays
    /// a `UInt64` in the host; this is only the array element. The caller keeps this value until
    /// the call returns, so the array is still alive.
    static func one(_ value: Int64) -> LockSpaceArray? {
        var bits = value
        guard let number = CFNumberCreate(kCFAllocatorDefault, .sInt64Type, &bits) else { return nil }
        return LockSpaceArray(array: [number] as CFArray)
    }
}
#endif
