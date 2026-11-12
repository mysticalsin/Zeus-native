import SwiftUI
import ZeusCore

/// Settings › Routines: saved prompts that run on a schedule through the model router.
struct RoutinesSettingsView: View {
    let runner = RoutineRunner.shared

    var body: some View {
        Form {
            if let problem = runner.problem {
                Section {
                    Label(problem, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .accessibilityLabel("Routines problem: \(problem)")
                }
            }
            Section {
                if runner.routines.isEmpty {
                    Text("No routines yet. A routine is a prompt Zeus runs for you, for example a weekday morning summary.")
                        .foregroundStyle(.secondary)
                }
                ForEach(runner.routines) { routine in
                    RoutineEditor(routine: routine, runner: runner)
                }
                Button("Add Routine") { _ = runner.add() }
            } header: {
                Text("Routines")
            } footer: {
                Text("Runs at the set time while the Mac is awake; if it was asleep, a missed routine runs once when it wakes. Results appear as a quiet card and stay in History.")
            }
            Section("History") {
                if runner.runs.isEmpty {
                    Text("Nothing has run yet.").foregroundStyle(.secondary)
                }
                ForEach(runner.runs.prefix(15)) { run in
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text(run.routineName).fontWeight(.semibold)
                            if let engine = run.engine.flatMap(RouterEngine.init(rawValue:)) {
                                Text(engine.title).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(run.date.formatted(date: .abbreviated, time: .shortened)).font(.caption).foregroundStyle(.secondary)
                        }
                        Text(run.output).lineLimit(3).foregroundStyle(run.failed ? .red : .secondary).textSelection(.enabled)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
        .formStyle(.grouped)
    }
}

private struct RoutineEditor: View {
    let routine: Routine
    let runner: RoutineRunner

    private func binding<T>(_ keyPath: WritableKeyPath<Routine, T>) -> Binding<T> {
        Binding(get: { routine[keyPath: keyPath] }, set: { value in
            var copy = routine
            copy[keyPath: keyPath] = value
            runner.update(copy)
        })
    }

    var body: some View {
        DisclosureGroup {
            TextField("Name", text: binding(\.name))
            TextField("Prompt", text: binding(\.prompt), prompt: Text("e.g. Summarize what changed in my repos since yesterday"), axis: .vertical)
                .lineLimit(2...5)
            Picker("Days", selection: binding(\.schedule.days)) {
                ForEach(RoutineSchedule.Days.allCases) { days in Text(days.title).tag(days) }
            }
            DatePicker("Time", selection: Binding(get: {
                Calendar.current.date(bySettingHour: routine.schedule.hour, minute: routine.schedule.minute, second: 0, of: Date()) ?? Date()
            }, set: { date in
                var copy = routine
                let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
                copy.schedule = RoutineSchedule(days: routine.schedule.days, hour: parts.hour ?? 9, minute: parts.minute ?? 0)
                runner.update(copy)
            }), displayedComponents: .hourAndMinute)
            Picker("Engine", selection: binding(\.engine)) {
                Text("Auto").tag(RouterChoice.auto)
                ForEach(RouterEngine.allCases) { engine in Text(engine.title).tag(RouterChoice.engine(engine)) }
            }
            HStack {
                Button(runner.running.contains(routine.id) ? "Running…" : "Run Now") { runner.run(routine, manual: true) }
                    .disabled(runner.running.contains(routine.id) || routine.prompt.trimmingCharacters(in: .whitespaces).isEmpty)
                Spacer()
                Button("Delete", role: .destructive) { runner.delete(routine.id) }
            }
        } label: {
            Toggle(isOn: binding(\.enabled)) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(routine.name)
                    Text(routine.schedule.summary).font(.caption).foregroundStyle(.secondary)
                }
            }
            .accessibilityLabel("\(routine.name), \(routine.schedule.summary), \(routine.enabled ? "on" : "off")")
        }
    }
}
