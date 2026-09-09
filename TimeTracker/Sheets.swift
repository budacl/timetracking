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
