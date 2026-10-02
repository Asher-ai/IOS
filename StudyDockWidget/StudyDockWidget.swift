import WidgetKit
import SwiftUI

struct StudyDeadlineEntry: TimelineEntry {
    let date: Date
    let snapshot: DeadlineWidgetSnapshot?
    var problem: String? = nil
}

struct StudyDeadlineProvider: TimelineProvider {
    func placeholder(in context: Context) -> StudyDeadlineEntry { example }
    func getSnapshot(in context: Context, completion: @escaping (StudyDeadlineEntry) -> Void) {
        completion(context.isPreview ? example : read())
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<StudyDeadlineEntry>) -> Void) {
        let entry = read()
        // Include exact deadline boundaries so the overdue label changes without an app launch.
        let boundaries = (entry.snapshot?.items ?? []).map(\.dueAt).filter { $0 > entry.date && $0 < entry.date.addingTimeInterval(86_400) }
        let entries = [entry] + Set(boundaries).sorted().map { StudyDeadlineEntry(date: $0, snapshot: entry.snapshot, problem: entry.problem) }
        completion(Timeline(entries: entries, policy: .after(entry.date.addingTimeInterval(3_600))))
    }
    private func read() -> StudyDeadlineEntry {
        do { return StudyDeadlineEntry(date: Date(), snapshot: try WidgetSnapshotRepository().load()) }
        catch { return StudyDeadlineEntry(date: Date(), snapshot: nil, problem: "Open StudyDock to reconnect your planner.") }
    }
    private var example: StudyDeadlineEntry {
        let now = Date()
        return StudyDeadlineEntry(date: now, snapshot: DeadlineWidgetSnapshot(generatedAt: now, items: [
            DeadlineWidgetItem(id: UUID(), title: "Prototype review", subjectCode: "DESIGN", dueAt: now.addingTimeInterval(18 * 3_600), nextStep: "Test the first screen"),
            DeadlineWidgetItem(id: UUID(), title: "Literature review", subjectCode: "RESEARCH", dueAt: now.addingTimeInterval(64 * 3_600), nextStep: "Compare three papers")
        ]))
    }
}

struct StudyDeadlineWidgetView: View {
    let entry: StudyDeadlineEntry
    @Environment(\.widgetFamily) private var family
    private let teal = Color(red: 0.0, green: 0.43, blue: 0.43)
    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Label("STUDYDOCK", systemImage: "books.vertical.fill").font(.system(size: 10, weight: .bold)).tracking(1)
                Spacer(minLength: 0)
                if family == .systemMedium { Text("NEXT DEADLINES").font(.system(size: 9, weight: .semibold)) }
            }.foregroundStyle(teal)
            if let snapshot = entry.snapshot, !snapshot.items.isEmpty {
                if family == .systemSmall, let item = snapshot.items.first {
                    Text(item.subjectCode).font(.caption2).foregroundStyle(.secondary)
                    Text(item.title).font(.headline).lineLimit(2)
                    dueLabel(item)
                    Spacer(minLength: 0)
                    Text(item.nextStep).font(.caption2).foregroundStyle(.secondary).lineLimit(2)
                } else {
                    ForEach(Array(snapshot.items.prefix(2))) { item in
                        Link(destination: URL(string: "studydock://assessment/\(item.id.uuidString)")!) {
                            HStack(alignment: .top) {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text("\(item.subjectCode) · \(item.title)").font(.subheadline.weight(.semibold)).lineLimit(1)
                                    Text(item.nextStep).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                                }
                                Spacer(minLength: 6)
                                dueLabel(item)
                            }
                        }
                        if item.id != snapshot.items.prefix(2).last?.id { Divider() }
                    }
                    Spacer(minLength: 0)
                    Text("Updated \(snapshot.generatedAt.formatted(date: .omitted, time: .shortened))").font(.system(size: 9)).foregroundStyle(.secondary)
                }
            } else {
                Text(entry.problem == nil && entry.snapshot != nil ? "Room to focus." : "Your semester, in view.").font(.headline)
                Text(entry.problem ?? (entry.snapshot == nil ? "Open StudyDock and plan your first assessment." : "No outstanding assessments. Open your planner to add the next one.")).font(.caption).foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }
        }
        .containerBackground(.fill.tertiary, for: .widget)
        .widgetURL(URL(string: entry.snapshot?.items.first.map { "studydock://assessment/\($0.id.uuidString)" } ?? "studydock://deadlines"))
    }
    private func dueLabel(_ item: DeadlineWidgetItem) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            if item.dueAt <= entry.date { Text("OVERDUE").font(.system(size: 9, weight: .bold)).foregroundStyle(.orange) }
            Text(item.dueAt, format: .dateTime.month(.abbreviated).day()).font(.caption.weight(.semibold))
            Text(item.dueAt, style: .time).font(.caption2).foregroundStyle(.secondary)
        }
    }
}

@main
struct StudyDockWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: SharedGroup.widgetKind, provider: StudyDeadlineProvider()) { StudyDeadlineWidgetView(entry: $0) }
            .configurationDisplayName("Study deadlines")
            .description("See your next assessment and the step you can take now.")
            .supportedFamilies([.systemSmall, .systemMedium])
    }
}
