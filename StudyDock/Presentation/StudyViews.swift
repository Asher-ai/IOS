import SwiftUI

private let dockTeal = Color(red: 0.0, green: 0.43, blue: 0.43)
private let dockNavy = Color(red: 0.07, green: 0.15, blue: 0.24)

struct StudyDockRootView: View {
    @ObservedObject var model: StudyPlannerViewModel
    @Environment(\.scenePhase) private var scenePhase
    var body: some View {
        TabView(selection: $model.selectedTab) {
            NavigationStack { DeadlinesView(model: model) }
                .tabItem { Label("Deadlines", systemImage: "calendar") }.tag(0)
            NavigationStack { SubjectsView(model: model) }
                .tabItem { Label("Subjects", systemImage: "books.vertical") }.tag(1)
            NavigationStack { SharedInboxView(model: model) }
                .tabItem { Label("Shared inbox", systemImage: "tray.and.arrow.down") }.badge(model.inbox.count).tag(2)
            NavigationStack { PlannerGuideView(model: model) }
                .tabItem { Label("Guide", systemImage: "info.circle") }.tag(3)
        }
        .onChange(of: scenePhase) { _, phase in if phase == .active { model.refresh() } }
        .onOpenURL { model.open($0) }
        .alert("Check your study planner", isPresented: Binding(get: { model.message != nil }, set: { if !$0 { model.message = nil } })) {
            Button("OK", role: .cancel) { model.message = nil }
        } message: { Text(model.message ?? "") }
        .sheet(isPresented: Binding(get: { model.routedAssessmentID != nil }, set: { if !$0 { model.routedAssessmentID = nil } })) {
            if let id = model.routedAssessmentID {
                NavigationStack { AssessmentDetailView(model: model, assessmentID: id).toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { model.routedAssessmentID = nil } } } }
            }
        }
    }
}

struct DeadlinesView: View {
    @ObservedObject var model: StudyPlannerViewModel
    @State private var showPlan = false
    @State private var filter = "Next 7 days"
    private var plans: [AssessmentPlan] {
        if filter == "Submitted" { return model.assessments.filter(\.isSubmitted) }
        if filter == "All open" { return model.assessments.filter { !$0.isSubmitted } }
        return model.upcoming
    }
    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 14) {
                    Label("MAKE ROOM TO FOCUS", systemImage: "sparkle").font(.caption.weight(.bold)).tracking(1.5)
                    Text("One clear next step.").font(.system(.title, design: .rounded, weight: .bold))
                    Text("Keep deadlines visible. Turn each assessment into something you can start.").font(.subheadline).opacity(0.85)
                    HStack(spacing: 26) {
                        metric("\(model.upcoming.count)", "due within 7 days")
                        metric("\(model.assessments.filter { $0.isOverdue(at: Date()) }.count)", "overdue")
                    }
                }.foregroundStyle(.white).padding(20).frame(maxWidth: .infinity, alignment: .leading)
                    .background(dockNavy, in: RoundedRectangle(cornerRadius: 22))
            }.listRowBackground(Color.clear).listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 8, trailing: 0))

            if let notice = model.integrationNotice {
                Section { Label(notice, systemImage: "exclamationmark.triangle").font(.footnote).foregroundStyle(.orange) }
            }
            Section {
                Picker("Assessment list", selection: $filter) {
                    ForEach(["Next 7 days", "All open", "Submitted"], id: \.self) { Text($0) }
                }.pickerStyle(.segmented)
            }.listRowBackground(Color.clear).listRowInsets(EdgeInsets())
            Section(filter == "Next 7 days" ? "Upcoming & overdue" : filter) {
                if plans.isEmpty {
                    ContentUnavailableView {
                        Label(model.subjects.isEmpty ? "Start your semester" : "A little breathing room", systemImage: "leaf")
                    } description: {
                        Text(model.subjects.isEmpty ? "Add a subject, then plan its first assessment. You can also explore an example semester in Guide." : "No assessments in this view. Plan a deadline or check All open.")
                    } actions: {
                        if model.subjects.isEmpty { Button("Add your first subject") { model.selectedTab = 1 } }
                        else { Button("Plan an assessment") { showPlan = true } }
                    }
                }
                ForEach(plans) { plan in
                    NavigationLink { AssessmentDetailView(model: model, assessmentID: plan.id) } label: {
                        AssessmentRow(plan: plan, subjectCode: model.subject(for: plan)?.code ?? "Subject")
                    }
                }
            }
        }
        .navigationTitle("StudyDock")
        .toolbar { ToolbarItem(placement: .primaryAction) { Button("Plan assessment", systemImage: "plus") { showPlan = true }.accessibilityIdentifier("planAssessment") } }
        .refreshable { model.refresh() }
        .sheet(isPresented: $showPlan) { NavigationStack { PlanAssessmentView(model: model) } }
    }
    private func metric(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) { Text(value).font(.title.bold()); Text(label).font(.caption) }
    }
}

struct AssessmentRow: View {
    let plan: AssessmentPlan
    let subjectCode: String
    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text(subjectCode).font(.caption.weight(.bold)).foregroundStyle(dockTeal)
                Spacer()
                if plan.isSubmitted { Label("Submitted", systemImage: "checkmark.circle.fill").foregroundStyle(dockTeal).font(.caption) }
                else if plan.isOverdue(at: Date()) { Label("Overdue", systemImage: "exclamationmark.circle").foregroundStyle(.orange).font(.caption.weight(.semibold)) }
            }
            Text(plan.title).font(.headline)
            Text(plan.dueAt.formatted(date: .abbreviated, time: .shortened)).font(.subheadline).foregroundStyle(.secondary)
            if !plan.isSubmitted { Label(plan.nextStep, systemImage: "arrow.turn.down.right").font(.caption).foregroundStyle(.secondary).lineLimit(2) }
        }.padding(.vertical, 7)
    }
}

struct SubjectsView: View {
    @ObservedObject var model: StudyPlannerViewModel
    @State private var adding = false
    var body: some View {
        List {
            Section { Text("A home for each subject and the work that belongs to it.").foregroundStyle(.secondary) }
            if model.subjects.isEmpty { ContentUnavailableView("No subjects yet", systemImage: "books.vertical", description: Text("Add the subject code and name from your subject outline.")) }
            ForEach(model.subjects) { subject in
                NavigationLink { SubjectDetailView(model: model, subject: subject) } label: {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(subject.code).font(.caption.bold()).foregroundStyle(dockTeal)
                        Text(subject.name).font(.headline)
                        Text("\(model.assessments.filter { $0.subjectID == subject.id && !$0.isSubmitted }.count) assessments to submit").font(.caption).foregroundStyle(.secondary)
                    }.padding(.vertical, 5)
                }
            }
        }.navigationTitle("Subjects")
            .toolbar { Button("Add subject", systemImage: "plus") { adding = true }.accessibilityIdentifier("addSubject") }
            .sheet(isPresented: $adding) { NavigationStack { AddSubjectView(model: model) } }
    }
}

struct AddSubjectView: View {
    @ObservedObject var model: StudyPlannerViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var code = ""
    @State private var name = ""
    var body: some View {
        Form {
            Section("From your subject outline") {
                TextField("Subject code", text: $code).textInputAutocapitalization(.characters).accessibilityIdentifier("subjectCode")
                TextField("Subject name", text: $name).accessibilityIdentifier("subjectName")
            }
            Section { Text("Each assessment belongs to one subject. Subject codes must be unique in your planner.").font(.footnote).foregroundStyle(.secondary) }
        }.navigationTitle("Add subject").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save") { if model.registerSubject(code: code, name: name) { dismiss() } }.accessibilityIdentifier("saveSubject") }
            }
    }
}

struct SubjectDetailView: View {
    @ObservedObject var model: StudyPlannerViewModel
    let subject: StudySubject
    @State private var planning = false
    var body: some View {
        List {
            Section { Text(subject.name).font(.title3.bold()) }
            Section("Assessment plan") {
                let plans = model.assessments.filter { $0.subjectID == subject.id }
                if plans.isEmpty { Text("No assessments planned. Add the first deadline from your subject outline.").foregroundStyle(.secondary) }
                ForEach(plans) { plan in
                    NavigationLink { AssessmentDetailView(model: model, assessmentID: plan.id) } label: { AssessmentRow(plan: plan, subjectCode: subject.code) }
                }
            }
            Button("Plan an assessment") { planning = true }
        }.navigationTitle(subject.code)
            .sheet(isPresented: $planning) { NavigationStack { PlanAssessmentView(model: model, initialSubjectID: subject.id) } }
    }
}

struct PlanAssessmentView: View {
    @ObservedObject var model: StudyPlannerViewModel
    var initialSubjectID: UUID?
    var reference: SharedAssessmentReference?
    @Environment(\.dismiss) private var dismiss
    @State private var subjectID: UUID?
    @State private var title = ""
    @State private var dueAt = Date().addingTimeInterval(86_400)
    @State private var nextStep = ""
    @State private var notes = ""
    @State private var sourceURL = ""
    @State private var confirmed = false
    @State private var addingSubject = false
    var body: some View {
        Form {
            if reference != nil {
                Section { Label("A shared link is a reference, not a verified deadline. Check the source before planning it.", systemImage: "checkmark.shield").font(.subheadline) }
            }
            Section("Assessment") {
                Picker("Subject", selection: $subjectID) {
                    Text("Choose a subject").tag(nil as UUID?)
                    ForEach(model.subjects) { Text("\($0.code) · \($0.name)").tag(Optional($0.id)) }
                }
                Button("Add a subject") { addingSubject = true }
                TextField("Assessment title", text: $title).accessibilityIdentifier("assessmentTitle")
            }
            Section {
                DatePicker("Due date & time", selection: $dueAt)
                Text("Time zone: \(TimeZone.current.identifier)").font(.caption).foregroundStyle(.secondary)
                Toggle("I checked the official deadline", isOn: $confirmed).accessibilityIdentifier("confirmDeadline")
            } header: { Text("Confirmed deadline") } footer: { Text("Enter the equivalent time in the time zone shown. Past deadlines are allowed so overdue work stays visible.") }
            Section("Make it actionable") {
                TextField("Next step, e.g. read the marking criteria", text: $nextStep, axis: .vertical).accessibilityIdentifier("nextStep")
                TextField("Study notes (optional)", text: $notes, axis: .vertical).lineLimit(3...7)
            }
            Section("Assignment source") {
                TextField("https://… (optional)", text: $sourceURL).keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                if SharedLinkValidation.isWebURL(sourceURL), let url = URL(string: sourceURL) { Link("Check the assignment page", destination: url) }
            }
        }.navigationTitle(reference == nil ? "Plan assessment" : "Review shared reference").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save") {
                    let draft = AssessmentDraft(subjectID: subjectID ?? UUID(), title: title, dueAt: dueAt,
                        timeZoneID: TimeZone.current.identifier, nextStep: nextStep, notes: notes, sourceURL: sourceURL,
                        deadlineConfirmed: confirmed, capturedReferenceID: reference?.id)
                    if model.plan(draft) { dismiss() }
                }.accessibilityIdentifier("saveAssessment") }
            }
            .onAppear {
                if subjectID == nil { subjectID = initialSubjectID ?? model.subjects.first?.id }
                if title.isEmpty, let reference { title = reference.title; notes = reference.text; sourceURL = reference.sourceURL ?? "" }
            }
            .onChange(of: dueAt) { _, _ in confirmed = false }
            .sheet(isPresented: $addingSubject, onDismiss: { if subjectID == nil { subjectID = model.subjects.first?.id } }) { NavigationStack { AddSubjectView(model: model) } }
    }
}

struct AssessmentDetailView: View {
    @ObservedObject var model: StudyPlannerViewModel
    let assessmentID: UUID
    @State private var editing = false
    @State private var confirmingSubmission = false
    var body: some View {
        Group {
            if let plan = model.assessments.first(where: { $0.id == assessmentID }) {
                List {
                    Section {
                        Text(model.subject(for: plan)?.code ?? "Subject").font(.caption.bold()).foregroundStyle(dockTeal)
                        Text(plan.title).font(.title2.bold())
                        Label(plan.isSubmitted ? "Submitted" : plan.isOverdue(at: Date()) ? "Overdue · check your options" : "Ready to work on", systemImage: plan.isSubmitted ? "checkmark.circle.fill" : "clock").foregroundStyle(plan.isOverdue(at: Date()) ? .orange : dockTeal)
                    }
                    Section("Deadline") {
                        Text(plan.dueAt.formatted(date: .complete, time: .shortened))
                        Text("Displayed in \(TimeZone.current.identifier). Confirmed in \(plan.timeZoneID).").font(.caption).foregroundStyle(.secondary)
                    }
                    Section("Your next step") { Text(plan.nextStep) }
                    if !plan.notes.isEmpty { Section("Study notes") { Text(plan.notes) } }
                    if let url = plan.sourceURL { Section("Source of truth") { Link("Open official assignment page", destination: url) } }
                    if let submitted = plan.submittedAt { Section("Submission record") { Text(submitted.formatted(date: .abbreviated, time: .shortened)) } }
                    else {
                        Section {
                            Button("Update study plan") { editing = true }
                            Button("Mark as submitted", systemImage: "checkmark.circle") { confirmingSubmission = true }.accessibilityIdentifier("markSubmitted")
                        } footer: { Text("This records your status in StudyDock. Submit your actual work through your university's submission system first.") }
                    }
                }.sheet(isPresented: $editing) { NavigationStack { ReviseAssessmentView(model: model, plan: plan) } }
            } else { ContentUnavailableView("Assessment unavailable", systemImage: "doc.questionmark", description: Text("Return to your deadline list and select an assessment.")) }
        }.navigationTitle("Assessment").navigationBarTitleDisplayMode(.inline)
            .confirmationDialog("Have you submitted the actual assessment to your university?", isPresented: $confirmingSubmission, titleVisibility: .visible) {
                Button("Yes, record submission") { model.recordSubmission(id: assessmentID) }
                Button("Not yet", role: .cancel) {}
            }
    }
}

struct ReviseAssessmentView: View {
    @ObservedObject var model: StudyPlannerViewModel
    let plan: AssessmentPlan
    @Environment(\.dismiss) private var dismiss
    @State private var dueAt: Date
    @State private var nextStep: String
    @State private var notes: String
    @State private var confirmed = false
    init(model: StudyPlannerViewModel, plan: AssessmentPlan) {
        self.model = model; self.plan = plan
        _dueAt = State(initialValue: plan.dueAt); _nextStep = State(initialValue: plan.nextStep); _notes = State(initialValue: plan.notes)
    }
    var body: some View {
        Form {
            Section("Deadline in \(TimeZone.current.identifier)") {
                DatePicker("Confirmed deadline", selection: $dueAt)
                Toggle("I checked the current deadline", isOn: $confirmed)
            }
            Section("Study plan") {
                TextField("Your next step", text: $nextStep, axis: .vertical)
                TextField("Study notes", text: $notes, axis: .vertical).lineLimit(3...8)
            }
        }.navigationTitle("Update study plan").navigationBarTitleDisplayMode(.inline)
            .onChange(of: dueAt) { _, _ in confirmed = false }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save") { if model.revise(id: plan.id, dueAt: dueAt, nextStep: nextStep, notes: notes, confirmed: confirmed) { dismiss() } } }
            }
    }
}

struct SharedInboxView: View {
    @ObservedObject var model: StudyPlannerViewModel
    @State private var selected: SharedAssessmentReference?
    @State private var discarding: SharedAssessmentReference?
    var body: some View {
        List {
            Section { Text("Share a web link or assessment text to StudyDock from Safari or another app. Confirm the subject and deadline here.").foregroundStyle(.secondary) }
            if let notice = model.integrationNotice { Text(notice).font(.footnote).foregroundStyle(.orange) }
            if model.inbox.isEmpty { ContentUnavailableView("Nothing waiting to be planned", systemImage: "tray", description: Text("In another app, tap Share, choose StudyDock, then Save reference. Your capture will appear here.")) }
            ForEach(model.inbox) { reference in
                Button { selected = reference } label: {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(reference.title).font(.headline).foregroundStyle(.primary)
                        Text(reference.sourceURL ?? reference.text).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                        Label("Review & confirm deadline", systemImage: "arrow.right.circle").font(.caption).foregroundStyle(dockTeal)
                    }.padding(.vertical, 7)
                }.swipeActions { Button("Discard", role: .destructive) { discarding = reference } }
            }
        }.navigationTitle("Shared inbox").refreshable { model.refresh() }
            .sheet(item: $selected) { reference in NavigationStack { PlanAssessmentView(model: model, reference: reference) } }
            .confirmationDialog("Discard this shared reference?", isPresented: Binding(get: { discarding != nil }, set: { if !$0 { discarding = nil } }), titleVisibility: .visible) {
                Button("Discard reference", role: .destructive) { if let discarding { model.discardReference(id: discarding.id) }; discarding = nil }
            }
    }
}

struct PlannerGuideView: View {
    @ObservedObject var model: StudyPlannerViewModel
    var body: some View {
        List {
            Section("Capture → confirm → act") {
                Label("Add the subjects you are taking this semester.", systemImage: "1.circle")
                Label("Share an assignment link to StudyDock, then review it in Shared inbox.", systemImage: "2.circle")
                Label("Confirm its deadline and write one next step.", systemImage: "3.circle")
                Label("Add a StudyDock widget to keep your next deadline visible.", systemImage: "4.circle")
            }
            Section("Home Screen widget") {
                Text("Touch and hold the Home Screen, choose Edit → Add Widget, search for StudyDock, then choose the small or medium widget. Open StudyDock once after installation.")
                Text("Widgets show saved deadlines and refresh when your planner changes. iOS decides the exact refresh time; open the app for the latest record.").font(.footnote).foregroundStyle(.secondary)
            }
            Section("Private, offline planning") {
                Text("Subjects and assessments stay in Core Data on this device. Shared references and a small widget summary are stored in StudyDock's App Group.")
                Text("No account, analytics, automatic Canvas import or cloud sync. Deleting the app can remove your planner. StudyDock does not submit university work or verify deadline changes.").font(.footnote).foregroundStyle(.secondary)
            }
            Section("Explore the workflow") {
                Button("Load example semester") { model.loadExampleSemester(); model.selectedTab = 0 }.disabled(!model.subjects.isEmpty).accessibilityIdentifier("loadExamples")
                Text("Available in an empty planner. The examples are clearly marked and use dates relative to today.").font(.footnote).foregroundStyle(.secondary)
            }
            Section("About") { Text("StudyDock · Assessment 3\nAn independent iOS platform integration project.").font(.footnote) }
        }.navigationTitle("Planner guide")
    }
}
