import AppKit
import ApplicationServices
import ZeusCore

/// Read-only proofs from the command line; nothing is clicked, typed or sent.
/// `Zeus --drive-dryrun '<plan json>'`, `Zeus --drive-snapshot`, `Zeus --annotate-dryrun`, `Zeus --agent-dryrun "<words>"`.
enum MacControlSelfTest {
    @MainActor
    static func runIfRequested() {
        let args = CommandLine.arguments
        func value(after flag: String) -> String? {
            guard let i = args.firstIndex(of: flag), args.indices.contains(i + 1) else { return nil }
            return args[i + 1]
        }
        if let json = value(after: "--drive-dryrun") {
            guard case .action(let action)? = ZeusTagParser.parse("[ACTION:\(json)]").tags.first, action.kind == ZeusAction.Kind.macDrive,
                  let plan = DrivePlan.parse(action.payload) else { print("{\"ok\":false,\"error\":\"bad plan\"}"); exit(1) }
            let autonomy = DriveController.autonomy
            var found: [String] = []
            for step in plan.steps {
                if case .click(let t, _) = step, let label = t.label {
                    found.append("\(label)=\(AXFinder.element(titled: label) != nil)")
                }
            }
            print("ok=true risk=\(plan.risk) autonomy=\(autonomy.rawValue) needsApproval=\(plan.needsApproval(autonomy)) axTrusted=\(AXIsProcessTrusted()) axFound=[\(found.joined(separator: ","))] frontmost=\(NSWorkspace.shared.frontmostApplication?.localizedName ?? "?")")
            print(plan.card)
            exit(0)
        }
        if args.contains("--drive-snapshot") {
            guard let snapshot = AXSnapshotter.shared.capture() else {
                print("ok=false axTrusted=\(AXIsProcessTrusted())"); exit(1)
            }
            print("ok=true elements=\(snapshot.elements.count) truncated=\(snapshot.truncated)")
            print(snapshot.render(limit: 60))
            exit(0)
        }
        if let words = value(after: "--screen-awareness-dryrun") {
            let ax = AXSnapshotter.shared.capture(budget: 0.15).map { $0.render(limit: 30) }
            let plan = ScreenAwareness.plan(transcript: words, axSummary: ax, tab: nil)
            print("ok=true question=\"\(words)\" axTokens=\(plan.axTokenEstimate) preferPixels=\(plan.preferPixels) needsCapture=\(plan.needsCapture) screenRecording=\(CGPreflightScreenCaptureAccess())")
            print(plan.promptPrefix)
            exit(0)
        }
        if args.contains("--annotate-dryrun") {
            let frame = NSScreen.screens.first?.frame ?? CGRect(x: 0, y: 0, width: 1512, height: 982)
            let center = CGPoint(x: frame.midX, y: frame.midY)
            let points = (0...40).map { i -> CGPoint in
                let a = Double(i) / 40 * 2 * .pi
                return CGPoint(x: center.x + 60 * cos(a), y: center.y + 40 * sin(a))
            }
            let stroke = AnnotationStroke(points: points)
            let region = stroke.region(in: frame)
            let px = AnnotationStroke.pixelRect(region, displayFrame: frame, pixelWidth: 1280,
                                                pixelHeight: Int(1280 * frame.height / frame.width))
            print("shape=\(stroke.shape.rawValue) screenRecording=\(CGPreflightScreenCaptureAccess()) enabled=\(AnnotationController.shared.enabled)")
            print(stroke.prompt(question: nil, pixels: px, screen: 1))
            exit(0)
        }
        if let words = value(after: "--agent-dryrun") {
            let store = AgentStore()
            let agents = store.profiles()
            guard let route = AgentRouter.route(words, agents: agents) else {
                print("agents=\(agents.map(\.name)) route=none"); exit(0)
            }
            let memory = store.memory(for: route.agent)
            print("agents=\(agents.map(\.name)) route=\(route.agent.name) request=\"\(route.request)\" remember=\(route.remember ?? "-") notes=\(memory.notes.count)")
            print(AgentRouter.preamble(route.agent, memory: memory))
            exit(0)
        }
    }
}
