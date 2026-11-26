import Testing
@testable import ZeusCore

@Suite("System source launch")
struct SystemSourceLaunchTests {
    private let account = SystemSourceLaunch.Account(
        home: "home-from-account",
        user: "user-from-account",
        temporaryDirectory: "tmp-from-account",
        logName: "log-from-account",
        shell: "shell-from-account",
        fixedPath: "path-from-account"
    )

    private let callerValues = [
        "from-the-caller",
        "/Users/someone",
        "/bin/zsh",
        "CALLER_HOME",
        "CALLER_PATH",
    ]

    @Test func argumentsPlaceThePathAfterTheEndOfSwitches() {
        let path = "own-library"
        let arguments = SystemSourceLaunch.arguments(libraryPath: path)
        #expect(arguments == ["-f", "-e", SystemSourceLaunch.program, "--", path])
        #expect(arguments[3] == "--")
        #expect(arguments.last == path)
    }

    @Test func aPathThatLooksLikeASwitchStaysAfterTheMarker() {
        let arguments = SystemSourceLaunch.arguments(libraryPath: "-x")
        #expect(arguments.dropLast().map { $0 } == ["-f", "-e", SystemSourceLaunch.program, "--"])
        #expect(arguments.last == "-x")
    }

    @Test func theProgramTextHasNoPathAndNoInterpolationPoint() {
        let program = SystemSourceLaunch.program
        #expect(program.contains("/") == false)
        #expect(program.contains("\"") == false)
        #expect(program.contains("\\") == false)
        #expect(program.contains("`") == false)
        #expect(program.contains("qq") == false)
        #expect(program.contains("ENV") == false)
        #expect(program.contains("getenv") == false)
        #expect(program.contains("boot_DynaLoader"))
        #expect(program.contains("dl_load_file"))
        #expect(program.contains("dl_find_symbol"))
        #expect(program.contains("dl_install_xsub"))
        #expect(program.contains("$ARGV[0]"))
        #expect(program.contains("q{\(SystemSourceLaunch.entrySymbol)}"))
        #expect(program.contains("DynaLoader::\(SystemSourceLaunch.entrySymbol)()"))
        #expect(SystemSourceLaunch.workingDirectory == "/")
    }

    @Test func eachEnvironmentHoldsOnlyItsOwnNames() {
        let empty = SystemSourceLaunch.environment(.none, account: account)
        let home = SystemSourceLaunch.environment(.homeUserTmp, account: account)
        let session = SystemSourceLaunch.environment(.sessionSet, account: account)

        #expect(empty.isEmpty)
        #expect(home.keys.sorted() == ["HOME", "TMPDIR", "USER"])
        #expect(session.keys.sorted() == ["HOME", "LOGNAME", "PATH", "SHELL", "TMPDIR", "USER"])
        #expect(home["HOME"] == account.home)
        #expect(home["USER"] == account.user)
        #expect(home["TMPDIR"] == account.temporaryDirectory)
        #expect(home["PATH"] == nil)
        #expect(home["LOGNAME"] == nil)
        #expect(home["SHELL"] == nil)
        #expect(session["HOME"] == account.home)
        #expect(session["USER"] == account.user)
        #expect(session["TMPDIR"] == account.temporaryDirectory)
        #expect(session["LOGNAME"] == account.logName)
        #expect(session["SHELL"] == account.shell)
        #expect(session["PATH"] == account.fixedPath)
        #expect(SystemSourceLaunch.Attempt.allCases.map(\.rawValue) == ["none", "homeUserTmp", "sessionSet"])

        let values = Array(empty.values) + Array(home.values) + Array(session.values)
        for caller in callerValues {
            #expect(values.contains(caller) == false)
        }
    }

    @Test func anEmptyAccountStillDoesNotAddCallerNames() {
        let blank = SystemSourceLaunch.Account(
            home: "", user: "", temporaryDirectory: "", logName: "", shell: "", fixedPath: ""
        )
        let session = SystemSourceLaunch.environment(.sessionSet, account: blank)
        #expect(session.keys.sorted() == ["HOME", "LOGNAME", "PATH", "SHELL", "TMPDIR", "USER"])
        #expect(session.values.allSatisfy { $0.isEmpty })
        #expect(SystemSourceLaunch.environment(.none, account: blank).isEmpty)
    }

    @Test func vendorInterpreterMatchesThePlainPathAndADigitSuffixOnly() {
        let plain = SystemSourceLaunch.interpreter
        #expect(SystemSourceLaunch.isVendorInterpreter(path: plain))
        #expect(SystemSourceLaunch.isVendorInterpreter(path: plain + "5.30"))
        #expect(SystemSourceLaunch.isVendorInterpreter(path: plain + "5.34"))
        #expect(SystemSourceLaunch.isVendorInterpreter(path: plain + "5.034"))
        #expect(SystemSourceLaunch.isVendorInterpreter(path: plain + "5.") == false)
        #expect(SystemSourceLaunch.isVendorInterpreter(path: plain + "5") == false)
        #expect(SystemSourceLaunch.isVendorInterpreter(path: plain + "5.30x") == false)
        #expect(SystemSourceLaunch.isVendorInterpreter(path: plain + "5.30.1") == false)
        #expect(SystemSourceLaunch.isVendorInterpreter(path: plain + "5.30 ") == false)
        #expect(SystemSourceLaunch.isVendorInterpreter(path: "/bin/zsh") == false)
        #expect(SystemSourceLaunch.isVendorInterpreter(path: "") == false)
        #expect(SystemSourceLaunch.isVendorInterpreter(path: plain + "2") == false)
    }

    @Test func orphanMatchesOnlyTheVendorImageParentOneAndTheSameUser() {
        let library = "own-library"
        let arguments = SystemSourceLaunch.arguments(libraryPath: library)
        let image = SystemSourceLaunch.interpreter + "5.30"
        #expect(isOrphan(executable: image, arguments: arguments, parentPID: 1, uid: 501, library: library, ownUID: 501))
        #expect(isOrphan(executable: SystemSourceLaunch.interpreter, arguments: arguments, parentPID: 1, uid: 501, library: library, ownUID: 501))
        #expect(isOrphan(executable: image, arguments: [library], parentPID: 1, uid: 501, library: library, ownUID: 501))
        #expect(isOrphan(executable: image, arguments: arguments, parentPID: 1, uid: 501, library: "other-library", ownUID: 501) == false)
        #expect(isOrphan(executable: image, arguments: arguments, parentPID: 200, uid: 501, library: library, ownUID: 501) == false)
        #expect(isOrphan(executable: image, arguments: arguments, parentPID: 0, uid: 501, library: library, ownUID: 501) == false)
        #expect(isOrphan(executable: image, arguments: arguments, parentPID: 1, uid: 501, library: library, ownUID: 502) == false)
        #expect(isOrphan(executable: "/bin/zsh", arguments: arguments, parentPID: 1, uid: 501, library: library, ownUID: 501) == false)
        #expect(isOrphan(executable: SystemSourceLaunch.interpreter + "5.30x", arguments: arguments, parentPID: 1, uid: 501, library: library, ownUID: 501) == false)
        #expect(isOrphan(executable: "perl", arguments: arguments, parentPID: 1, uid: 501, library: library, ownUID: 501) == false)
        #expect(isOrphan(executable: image, arguments: [], parentPID: 1, uid: 501, library: library, ownUID: 501) == false)
        #expect(isOrphan(executable: image, arguments: [library, "extra"], parentPID: 1, uid: 501, library: library, ownUID: 501) == false)
        #expect(isOrphan(executable: image, arguments: [""], parentPID: 1, uid: 1, library: "", ownUID: 1) == false)
    }

    private func isOrphan(
        executable: String,
        arguments: [String],
        parentPID: Int32,
        uid: UInt32,
        library: String,
        ownUID: UInt32
    ) -> Bool {
        SystemSourceLaunch.isOrphan(
            executable: executable,
            arguments: arguments,
            parentPID: parentPID,
            uid: uid,
            ownLibraryPath: library,
            ownUID: ownUID
        )
    }
}
