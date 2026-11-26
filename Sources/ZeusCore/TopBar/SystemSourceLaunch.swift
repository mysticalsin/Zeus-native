import Foundation

/// How the step-zero probe starts the system interpreter, and how a later census recognises that child.
///
/// The rules are pure. They read no clock, no file, and no process environment. The account record and the
/// fixed path are copied in by the caller. Preflight, the minimum release, and the resident helper stay out
/// of this file.
public enum SystemSourceLaunch {
    /// The vendor interpreter. A versioned copy is `/usr/bin/perl5.` and digits, checked by `isVendorInterpreter`.
    public static let interpreter = "/usr/bin/perl"

    /// The child starts here, so a relative module path cannot be read.
    public static let workingDirectory = "/"

    /// The one symbol the program binds. The facts-only entry exports this name. This file does not load it.
    public static let entrySymbol = "ZNPProbe"

    /// Boots the built-in loader, loads the library named by the first argument, and calls `entrySymbol`.
    /// The text has no quote, so the interpreter cannot interpolate, and it has no path of its own.
    public static let program: String = {
        let boot = "package DynaLoader;DynaLoader::boot_DynaLoader(q{DynaLoader});"
        let load = "my $opened=dl_load_file($ARGV[0],1);exit 1 unless $opened;"
        let symbol = entrySymbol
        let find = "my $found=dl_find_symbol($opened,q{" + symbol + "});exit 1 unless $found;"
        let call = "dl_install_xsub(q{DynaLoader::" + symbol + "},$found);DynaLoader::" + symbol + "();"
        return boot + load + find + call
    }()

    /// Values already read from the account record and from `confstr`. Nothing here is taken from the caller environment.
    public struct Account: Sendable, Equatable {
        public var home: String
        public var user: String
        public var temporaryDirectory: String
        public var logName: String
        public var shell: String
        public var fixedPath: String

        public init(home: String, user: String, temporaryDirectory: String, logName: String, shell: String, fixedPath: String) {
            self.home = home
            self.user = user
            self.temporaryDirectory = temporaryDirectory
            self.logName = logName
            self.shell = shell
            self.fixedPath = fixedPath
        }
    }

    /// The three attempts, in the order the probe tries them. The raw value is the report code.
    public enum Attempt: String, Sendable, Equatable, CaseIterable {
        case none
        case homeUserTmp
        case sessionSet
    }

    /// `-f`, `-e`, the program, `--`, then the library path. `--` is before the path so a path that looks like a switch stays a path.
    public static func arguments(libraryPath: String) -> [String] {
        ["-f", "-e", program, "--", libraryPath]
    }

    /// The names for one attempt, and no others. Each value is the matching account field.
    public static func environment(_ attempt: Attempt, account: Account) -> [String: String] {
        switch attempt {
        case .none:
            return [:]
        case .homeUserTmp:
            return [
                "HOME": account.home,
                "USER": account.user,
                "TMPDIR": account.temporaryDirectory,
            ]
        case .sessionSet:
            return [
                "HOME": account.home,
                "USER": account.user,
                "TMPDIR": account.temporaryDirectory,
                "LOGNAME": account.logName,
                "SHELL": account.shell,
                "PATH": account.fixedPath,
            ]
        }
    }

    /// True for the vendor interpreter, or for `/usr/bin/perl5.` followed by ASCII digits only.
    public static func isVendorInterpreter(path: String) -> Bool {
        if path == interpreter { return true }
        let versioned = interpreter + "5."
        guard path.hasPrefix(versioned) else { return false }
        let suffix = path.dropFirst(versioned.count)
        guard !suffix.isEmpty else { return false }
        return suffix.allSatisfy { $0 >= "0" && $0 <= "9" }
    }

    /// True only for a vendor image path, parent 1, the same user, and a last argument equal to this bundle's library.
    /// `executable` is the real image path. An empty library path is not a match.
    public static func isOrphan(
        executable: String,
        arguments: [String],
        parentPID: Int32,
        uid: UInt32,
        ownLibraryPath: String,
        ownUID: UInt32
    ) -> Bool {
        guard parentPID == 1, uid == ownUID else { return false }
        guard !ownLibraryPath.isEmpty, arguments.last == ownLibraryPath else { return false }
        return isVendorInterpreter(path: executable)
    }
}
