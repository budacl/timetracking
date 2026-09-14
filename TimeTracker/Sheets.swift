import SwiftUI

// MARK: - Add ticket

struct AddTicketSheet: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var issueText = ""
    @State private var title = ""

    private var isValid: Bool { IssueIdParser.extract(from: issueText) != nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Add ticket").font(.headline)
            TextField("Ticket ID or URL, e.g. MOB-1234", text: $issueText)
                .textFieldStyle(.roundedBorder)
                .onSubmit(add)
            TextField("Title (optional – loaded from YouTrack when empty)", text: $title)
                .textFieldStyle(.roundedBorder)
                .onSubmit(add)
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Add") { add() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!isValid)
            }
        }
        .padding(20)
        .frame(width: 440)
    }

    private func add() {
        guard isValid else { return }
        let issue = issueText
        let name = title
        dismiss()
        Task { await store.addTicket(issueId: issue, title: name) }
    }
}

// MARK: - Review & confirm

struct ReviewSheet: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    private var pending: [Ticket] { store.tickets.filter { $0.minutes > 0 } }

    private var isToday: Bool { CzechCalendar.calendar.isDateInToday(store.reviewDate) }

    private var dateHint: String? {
        if store.isOnVacation(store.reviewDate) { return "You are on vacation on this day" }
        if let holiday = CzechCalendar.holidayName(on: store.reviewDate) { return "Holiday: \(holiday)" }
        if CzechCalendar.isWeekend(store.reviewDate) { return "Weekend" }
        return nil
    }

    var body: some View {
        @Bindable var store = store
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Image(systemName: "clock.badge.checkmark")
                    .font(.system(size: 28))
                    .foregroundStyle(.blue)
                VStack(alignment: .leading, spacing: 2) {
                    Text(isToday ? "Review today's time tracking" : "Review time tracking").font(.headline)
                    Text(store.reviewDate, format: .dateTime.weekday(.wide).day().month(.wide).year())
                        .foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    HStack(spacing: 8) {
                        Text("Log to date").foregroundStyle(.secondary)
                        DatePicker("Log to date", selection: $store.reviewDate, in: ...Date(), displayedComponents: .date)
                            .labelsHidden()
                            .datePickerStyle(.field)
                        if !isToday {
                            Button("Today") { store.reviewDate = Date() }
                                .controlSize(.small)
                        }
                    }
                    if let dateHint {
                        Label(dateHint, systemImage: "exclamationmark.triangle")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
            }

            if pending.isEmpty {
                ContentUnavailableView(
                    "Nothing to log",
                    systemImage: "tray",
                    description: Text("No time has been added to any ticket today.")
                )
                .frame(height: 160)
            } else {
                List {
                    ForEach(pending) { ticket in
                        ReviewRow(ticket: ticket)
                    }
                }
                .frame(minHeight: 140, maxHeight: 320)
                .scrollContentBackground(.hidden)
                .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 8))

                HStack {
                    Text("Total").bold()
                    Spacer()
                    Text(WorkDuration.format(store.pendingMinutes))
                        .bold()
                        .monospacedDigit()
                }
                .padding(.horizontal, 8)
            }

            Text("Confirming creates one work item per ticket in YouTrack (type “\(store.workTypeName)”, dated \(isToday ? "today" : store.reviewDate.formatted(.dateTime.day().month(.abbreviated)))) and resets the time in the list to 0. Tickets stay in the list.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if let error = store.submitError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if store.token.isEmpty {
                Label("Set your YouTrack token in Settings (⌘,) before confirming.", systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            HStack {
                if store.isSubmitting {
                    ProgressView().controlSize(.small)
                    Text("Logging to YouTrack…").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Later") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Confirm & log to YouTrack") { Task { await store.confirmAndLog() } }
                    .keyboardShortcut(.defaultAction)
                    .disabled(pending.isEmpty || store.isSubmitting || store.token.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 640)
        .onAppear { store.reviewDate = Date() }
        .onDisappear { store.submitError = nil }
    }
}

private struct ReviewRow: View {
    @Environment(AppStore.self) private var store
    let ticket: Ticket

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(ticket.issueId).font(.body.monospaced())
                Text(ticket.title.isEmpty ? "—" : ticket.title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            TextField("Note (optional)", text: Binding(
                get: { ticket.note },
                set: { store.setNote(ticket.id, $0) }
            ))
            .textFieldStyle(.roundedBorder)
            .frame(width: 200)
            DurationField(minutes: ticket.minutes) { store.setMinutes(ticket.id, $0) }
                .frame(width: 90)
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Vacations

struct VacationSheet: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var start = CzechCalendar.calendar.startOfDay(for: Date())
    @State private var end = CzechCalendar.calendar.startOfDay(for: Date())
    @State private var note = ""

    private var previewDays: Int {
        store.workingDays(in: Vacation(start: min(start, end), end: max(start, end)))
    }

    private var sortedVacations: [Vacation] {
        store.vacations.sorted { $0.start > $1.start }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Image(systemName: "beach.umbrella")
                    .font(.system(size: 28))
                    .foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Vacation & days off").font(.headline)
                    Text("These days are not working days: they lower the month's expected hours and no review reminder is shown.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            GroupBox("Add period") {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 12) {
                        DatePicker("From", selection: $start, displayedComponents: .date)
                            .datePickerStyle(.field)
                        DatePicker("To", selection: $end, in: start..., displayedComponents: .date)
                            .datePickerStyle(.field)
                        TextField("Note (optional)", text: $note)
                            .textFieldStyle(.roundedBorder)
                            .frame(minWidth: 140)
                    }
                    HStack {
                        Text(previewDays == 1 ? "1 working day" : "\(previewDays) working days")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Add") {
                            store.addVacation(from: start, to: end, note: note)
                            note = ""
                        }
                        .keyboardShortcut(.defaultAction)
                        .disabled(previewDays == 0)
                    }
                }
                .padding(4)
            }
            .onChange(of: start) { _, new in if end < new { end = new } }

            if sortedVacations.isEmpty {
                ContentUnavailableView(
                    "No vacations recorded",
                    systemImage: "sun.max",
                    description: Text("Add a period above when you plan to be away.")
                )
                .frame(height: 150)
            } else {
                List {
                    ForEach(sortedVacations) { vacation in
                        VacationRow(vacation: vacation, workingDays: store.workingDays(in: vacation)) {
                            store.removeVacation(vacation.id)
                        }
                    }
                }
                .frame(minHeight: 150, maxHeight: 300)
                .scrollContentBackground(.hidden)
                .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 8))
            }

            HStack {
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
        }
        .padding(20)
        .frame(width: 620)
    }
}

private struct VacationRow: View {
    let vacation: Vacation
    let workingDays: Int
    let onDelete: () -> Void

    private var isCurrent: Bool { vacation.contains(Date()) }
    private var isPast: Bool { CzechCalendar.calendar.startOfDay(for: vacation.end) < CzechCalendar.calendar.startOfDay(for: Date()) }

    private var rangeText: String {
        let cal = CzechCalendar.calendar
        if cal.isDate(vacation.start, inSameDayAs: vacation.end) {
            return vacation.start.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).year())
        }
        let sameYear = cal.component(.year, from: vacation.start) == cal.component(.year, from: vacation.end)
        let startText = sameYear
            ? vacation.start.formatted(.dateTime.day().month(.abbreviated))
            : vacation.start.formatted(.dateTime.day().month(.abbreviated).year())
        let endText = vacation.end.formatted(.dateTime.day().month(.abbreviated).year())
        return "\(startText) – \(endText)"
    }

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(rangeText)
                    if isCurrent {
                        Text("now")
                            .font(.caption2.bold())
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1)
                            .background(.orange.opacity(0.2), in: Capsule())
                            .foregroundStyle(.orange)
                    }
                }
                if !vacation.note.isEmpty {
                    Text(vacation.note).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            .foregroundStyle(isPast ? .secondary : .primary)
            Spacer()
            Text(workingDays == 1 ? "1 working day" : "\(workingDays) working days")
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
            Button(role: .destructive, action: onDelete) {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .help("Remove this period")
        }
        .padding(.vertical, 2)
    }
}
