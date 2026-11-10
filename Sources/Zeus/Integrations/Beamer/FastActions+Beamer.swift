import ZeusCore

extension FastActions {
    /// Voice commands for Beamer. Pause, resume, start and open say why when Beamer can't do them;
    /// "switch to my X" only acts when X is a machine Beamer knows (or the iPad, which it can't pair).
    func resolveBeamer(_ command: BeamerCommand, intent: FastIntent) -> Resolution {
        let beamer = BeamerModel.shared
        let status = beamer.status
        let summary: String
        let ack: String
        switch command {
        case .start: summary = "Start Beamer"; ack = "Starting Beamer."
        case .showWindow: summary = "Open Beamer"; ack = "Opening Beamer."
        case .pause: summary = "Pause Beamer"; ack = "Pausing Beamer."
        case .resume: summary = "Resume Beamer"; ack = "Resuming Beamer."
        case .returnHome: summary = "Input back to this Mac"; ack = "Bringing it back."
        case .switchTo(let spoken):
            if BeamerMatching.isIPad(spoken), !status.machines.contains(where: { BeamerMatching.isIPad($0.name) }) {
                return .plan(Plan(intent: intent, summary: "iPad", ack: "Beamer doesn't pair iPads. Use Universal Control for the iPad.") { started in
                    started(); return nil
                })
            }
            // Not a machine Beamer has: not ours.
            guard status.availability != .notInstalled,
                  status.machines.isEmpty || BeamerMatching.machine(named: spoken, in: status.machines.map(\.name)) != nil else { return .pass }
            summary = "Switch to \(spoken)"; ack = "Switching to \(spoken)."
        }
        return .plan(Plan(intent: intent, summary: summary, ack: ack) { started in
            started()
            let outcome = await beamer.perform(command)
            return outcome.ok ? nil : outcome.message
        })
    }
}
