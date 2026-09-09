import SwiftUI

struct ContentView: View {
    @Environment(AppStore.self) private var store
    @State private var showAdd = false
    @State private var selection: Set<Ticket.ID> = []

    private let ticker = Timer.publish(every: 30, on: .main, in: .common).autoconnect()

    private var footerText: String {
        let count = store.tickets.count
        let tickets = "\(count) ticket\(count == 1 ? "" : "s")"
        return store.pendingMinutes > 0 ? "\(tickets) · \(WorkDuration.format(store.pendingMinutes)) pending today" : tickets
    }

    var body: some View {
        @Bindable var store = store
        VStack(spacing: 0) {
            DashboardView()
                .padding(20)
            Divider()
            TicketTable(selection: $selection, showAdd: $showAdd)
            Divider()
            HStack(spacing: 0) {
                Button { showAdd = true } label: {
                    Image(systemName: "plus")
                        .frame(width: 26, height: 22)
                }
                .help("Add ticket (⌘N)")
                Divider().frame(height: 16)
                Button { store.removeTickets(selection); selection = [] } label: {
                    Image(systemName: "minus")
                        .frame(width: 26, height: 22)
                }
                .disabled(selection.isEmpty)
                .help("Remove selected tickets (⌫)")
                Spacer()
                Text(footerText)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(.trailing, 12)
            }
            .buttonStyle(.borderless)
            .padding(.leading, 4)
            .frame(height: 28)
            .background(.bar)
            if let info = store.infoMessage {
                Divider()
                HStack {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                    Text(info)
                    Spacer()
                    Button("Dismiss") { store.infoMessage = nil }.buttonStyle(.link)
                }
                .font(.callout)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(.bar)
                .task(id: info) {
                    try? await Task.sleep(for: .seconds(6))
                    if store.infoMessage == info { store.infoMessage = nil }
                }
            }
        }
        .toolbar {
            ToolbarItem {
                Button { showAdd = true } label: { Label("Add ticket", systemImage: "plus") }
                    .keyboardShortcut("n", modifiers: .command)
                    .help("Add a ticket (⌘N)")
            }
            ToolbarItem {
                Button { Task { await store.syncMonthFromYouTrack() } } label: {
                    Label("Sync from YouTrack", systemImage: "arrow.triangle.2.circlepath")
                }
                .disabled(store.isSyncing)
                .help("Reload this month's logged hours from YouTrack")
            }
            ToolbarItem {
                Button { store.showReview = true } label: {
                    Label("Review & confirm", systemImage: "checkmark.circle")
                }
                .keyboardShortcut(.return, modifiers: [.command, .shift])
                .help("Review today's records and log them to YouTrack (⇧⌘↩)")
            }
        }
        .sheet(isPresented: $showAdd) { AddTicketSheet() }
        .sheet(isPresented: $store.showReview) { ReviewSheet() }
        .alert("Something went wrong", isPresented: Binding(
            get: { store.errorMessage != nil },
            set: { if !$0 { store.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(store.errorMessage ?? "")
        }
        .task { await store.start() }
        .onReceive(ticker) { _ in store.tick() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            store.tick()
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in
            store.tick()
            store.rescheduleNotifications()
        }
    }
}

// MARK: - Dashboard

struct DashboardView: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text(store.now, format: .dateTime.month(.wide).year())
                    .font(.title2.bold())
                Spacer()
                if let holiday = CzechCalendar.holidayName(on: store.now) {
                    Label(holiday, systemImage: "party.popper")
                        .foregroundStyle(.secondary)
                        .font(.callout)
                } else if CzechCalendar.isWeekend(store.now) {
                    Label("Weekend", systemImage: "cup.and.saucer")
                        .foregroundStyle(.secondary)
                        .font(.callout)
                }
                Text(store.now, format: .dateTime.weekday(.wide).day().month())
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 12) {
                StatTile(
                    title: "Tracked this month",
                    value: WorkDuration.format(store.trackedThisMonthMinutes),
                    detail: store.pendingMinutes > 0
                        ? "+ \(WorkDuration.format(store.pendingMinutes)) pending today"
                        : (store.lastSync == nil ? "From logged records" : "Synced with YouTrack"),
                    tint: .blue
                )
                StatTile(
                    title: "Working hours this month",
                    value: "\(store.workingHoursThisMonth)h",
                    detail: "\(store.workingDaysThisMonth) working days × \(CzechCalendar.hoursPerDay)h",
                    tint: .secondary
                )
                StatTile(
                    title: "Expected until today",
                    value: WorkDuration.formatHours(store.expectedMinutesUntilToday),
                    detail: "\(store.workingDaysUntilToday) of \(store.workingDaysThisMonth) working days",
                    tint: .secondary
                )
                StatTile(
                    title: store.balanceMinutes >= 0 ? "Ahead of plan" : "Behind plan",
                    value: WorkDuration.format(abs(store.balanceMinutes)),
                    detail: "tracked + pending − expected",
                    tint: store.balanceMinutes >= 0 ? .green : .orange
                )
            }

            ProgressView(
                value: Double(min(store.trackedThisMonthMinutes + store.pendingMinutes, store.workingHoursThisMonth * 60)),
                total: Double(max(1, store.workingHoursThisMonth * 60))
            )
            .tint(.blue)
        }
    }
}

struct StatTile: View {
    let title: String
    let value: String
    let detail: String
    var tint: Color = .primary

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Text(value)
                .font(.system(size: 26, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(tint == .secondary ? .primary : tint)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
    }
}

// MARK: - Ticket table

struct TicketTable: View {
    @Environment(AppStore.self) private var store
    @Binding var selection: Set<Ticket.ID>
    @Binding var showAdd: Bool

    var body: some View {
        Table(store.tickets, selection: $selection) {
            TableColumn("Ticket") { ticket in
                HStack(spacing: 8) {
                    Text(ticket.issueId)
                        .font(.body.monospaced())
                        .foregroundStyle(.secondary)
                    Text(ticket.title.isEmpty ? "—" : ticket.title)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                .help(ticket.display)
            }
            TableColumn("Time") { ticket in
                HStack(spacing: 4) {
                    DurationField(minutes: ticket.minutes) { store.setMinutes(ticket.id, $0) }
                    Menu {
                        Button("+ 15m") { store.addMinutes(ticket.id, 15) }
                        Button("+ 30m") { store.addMinutes(ticket.id, 30) }
                        Button("+ 1h") { store.addMinutes(ticket.id, 60) }
                        Button("+ 2h") { store.addMinutes(ticket.id, 120) }
                        Divider()
                        Button("− 15m") { store.addMinutes(ticket.id, -15) }
                        Button("Reset to 0") { store.setMinutes(ticket.id, 0) }
                    } label: {
                        Image(systemName: "plus.circle")
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .fixedSize()
                    .help("Add time")
                }
            }
            .width(min: 150, ideal: 170, max: 220)
        }
        .contextMenu(forSelectionType: Ticket.ID.self) { ids in
            if ids.count == 1, let ticket = store.tickets.first(where: { ids.contains($0.id) }) {
                Button("Open in YouTrack") { store.openInYouTrack(ticket) }
                Button("Refresh title") { Task { await store.refreshTitle(for: ticket.id) } }
                Divider()
            }
            Button("Remove", role: .destructive) { store.removeTickets(ids) }
        } primaryAction: { ids in
            if let ticket = store.tickets.first(where: { ids.contains($0.id) }) {
                store.openInYouTrack(ticket)
            }
        }
        .onDeleteCommand { store.removeTickets(selection) }
        .overlay {
            if store.tickets.isEmpty {
                ContentUnavailableView {
                    Label("No tickets yet", systemImage: "ticket")
                } description: {
                    Text("Add the tickets you are working on, then type the time you spent into the Time column (e.g. 1h 30m).")
                } actions: {
                    Button { showAdd = true } label: {
                        Label("Add ticket", systemImage: "plus")
                    }
                    .keyboardShortcut(.defaultAction)
                }
            }
        }
    }
}

/// Editable "1h 30m" text field that commits on Enter or focus loss.
struct DurationField: View {
    let minutes: Int
    let onCommit: (Int) -> Void

    @State private var text = ""
    @State private var invalid = false
    @FocusState private var focused: Bool

    var body: some View {
        TextField("0m", text: $text)
            .textFieldStyle(.roundedBorder)
            .multilineTextAlignment(.trailing)
            .monospacedDigit()
            .focused($focused)
            .foregroundStyle(invalid ? .red : .primary)
            .onAppear { text = WorkDuration.format(minutes) }
            .onChange(of: minutes) { _, new in
                if !focused { text = WorkDuration.format(new) }
            }
            .onChange(of: focused) { _, isFocused in
                if !isFocused { commit() }
            }
            .onSubmit { commit() }
            .help("Type a duration such as 1h 30m, 45m, 1:30 or 90 (minutes)")
    }

    private func commit() {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty {
            invalid = false
            onCommit(0)
            text = WorkDuration.format(0)
            return
        }
        if let parsed = WorkDuration.parse(trimmed) {
            invalid = false
            onCommit(parsed)
            text = WorkDuration.format(parsed)
        } else {
            invalid = true
            text = WorkDuration.format(minutes)
            invalid = false
        }
    }
}
