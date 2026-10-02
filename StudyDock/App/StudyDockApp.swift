import SwiftUI

@main
struct StudyDockApp: App {
    var body: some Scene {
        WindowGroup { StudyDockBootstrapView() }
    }
}

struct StudyDockBootstrapView: View {
    @State private var model: StudyPlannerViewModel?
    @State private var startupError: String?
    var body: some View {
        Group {
            if let model { StudyDockRootView(model: model) }
            else if let startupError {
                ContentUnavailableView {
                    Label("Your planner needs attention", systemImage: "externaldrive.badge.exclamationmark")
                } description: { Text(startupError) } actions: { Button("Try opening again", action: openPlanner) }
            } else { ProgressView("Opening your study planner…") }
        }
        .tint(Color(red: 0.0, green: 0.43, blue: 0.43))
        .task { if model == nil { openPlanner() } }
    }
    private func openPlanner() {
        do { model = StudyPlannerViewModel(repository: try CoreDataStudyRepository()); startupError = nil }
        catch { startupError = error.localizedDescription }
    }
}
