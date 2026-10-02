# StudyDock

An independent Assessment 3 iOS application for university students coordinating assessment deadlines while balancing study, commuting and work. This is a new codebase; the earlier LabTrack project is not reused.

## Design before implementation

Capture an assignment reference from another app, confirm its subject and deadline, record one next study step, and see the next deadline on the Home Screen. Official assignment pages remain the source of truth. StudyDock records submission status; it does not upload coursework.

The primary stakeholder is a university coursework student taking several subjects and checking assessment information on an iPhone between other commitments. UTS documents this time-management problem and recommends recording assessment deadlines in a portable diary: [Managing your time](https://www.uts.edu.au/for-students/current-students/support/counselling-service-and-self-help/self-help-resources/managing-your-time).

## Architecture

SwiftUI Views → StudyPlannerViewModel → domain Use Cases → StudyRepository protocol → CoreDataStudyRepository → Core Data.

`StudySubjectRecord` has many `AssessmentRecord` objects, with an inverse relationship; a subject is required by the domain and repository. The predicate `submittedAt == nil AND dueAt <= cutoff` returns unfinished work, including overdue assessments. Unit tests inject mock repositories and never open Core Data.

## System extensions

- **Share Extension:** captures one URL or text reference in an atomic per-reference file in the App Group. Confirm the subject, deadline and next step in the main app. A capture UUID makes import retries idempotent.
- **WidgetKit:** small and medium Home Screen families read an atomic summary from the App Group. Every relevant save and foreground refresh republishes the snapshot and calls `WidgetCenter.shared.reloadTimelines`. Timeline entries also cover deadline boundaries. Widgets link to the corresponding assessment.

Core Data is the authoritative local database. Its private app-container store avoids simultaneous database writes from extensions. App Group JSON files are transfer records and read projections, not the primary database. There is no CloudKit, account, network sync or deletion-survival guarantee.

## Setup

1. Open `StudyDock.xcodeproj` in Xcode 16 or newer (iOS 17+ deployment target).
2. Select the **StudyDock** scheme and an iPhone simulator; run with Command-R.
3. For a physical device, select your Apple development team for the app and both extensions. Use unique bundle identifiers if necessary.
4. All three targets must use the same App Group. Default: **`group.au.edu.studydock.shared`**. Register it in your team, or change `STUDYDOCK_APP_GROUP` in `Config/Shared.xcconfig` and all three targets' Signing & Capabilities as needed. Entitlements and Info.plists use that build setting.
5. Open the app once. Add a subject and assessment, or use **Guide → Load example semester** in an empty planner.
6. Add the small/medium **StudyDock → Study deadlines** Home Screen widgets.
7. In Safari, share an assignment page, choose **StudyDock** (under More if needed), and tap **Save reference**. Open **Shared inbox** to complete the plan.
8. Run Command-U for the mock-based unit suite. UI integration tests use the separate **StudyDockIntegration** scheme on a disposable simulator. Run the example-semester scenario on an empty planner.

## Sources and attribution

Code was newly authored with OpenAI Codex assistance for this project; no LabTrack code, another student's code, external packages or copied sample implementation is included. AI assistance covers requirements analysis, implementation, tests and the report draft. The student must review and understand the implementation and personalise the reflection honestly.

API references (Apple documentation, accessed 2 October 2026):
- [Core Data](https://developer.apple.com/documentation/coredata)
- [Configuring App Groups](https://developer.apple.com/documentation/xcode/configuring-app-groups)
- [Keeping a widget up to date](https://developer.apple.com/documentation/widgetkit/keeping-a-widget-up-to-date)
- [Share extension lifecycle](https://developer.apple.com/library/archive/documentation/General/Conceptual/ExtensibilityPG/Share.html)

## Version control

The local repository uses `main` for verified changes and feature branches for major work. Conventional Commits document actual development. Repository: https://github.com/Asher-ai/IOS. See the separately delivered `SUBMISSION_GUIDE.txt` for the final checks and demo flow. The identified student report is delivered locally; it is not part of this public source repository.

## Verified behaviour

On 2 October 2026 with Xcode 27.0 and an iPhone 17 Pro simulator running iOS 26.5:

- App, Widget Extension and Share Extension compiled successfully.
- All 26 mock-based unit tests passed.
- UI workflow passed: create subject and assessment, terminate/relaunch, verify persistence, record submission.
- Example-semester UI test passed with both overdue and upcoming work.
- Safari capture/import UI test passed, including removal from the inbox only after persistence.
- Release build for generic physical iOS hardware passed without signing; no physical device was used.
- App Group snapshot inspection confirmed four actual assessment records, rather than placeholder widget data.

See `VERIFICATION.txt` for extension demonstration evidence and remaining physical-device checks. The deployment target is iOS 17, but runtime verification was on iOS 26.5; older supported versions were not tested.

## Screen map and business rules

Nine functional screens: Deadlines, Subjects, Add subject, Subject detail, Plan assessment, Assessment detail, Update study plan, Shared inbox, and Planner guide.

| Use case | Business rule |
| --- | --- |
| RegisterStudySubjectUseCase | A nonempty subject code and name; codes are case-insensitively unique |
| PlanAssessmentUseCase | Existing subject, named assessment, concrete next step and confirmed deadline |
| ReviewStudyWorkloadUseCase | A 1-31 day horizon; overdue unfinished work is retained |
| ReviseAssessmentPlanUseCase | Submitted work is immutable; the deadline is reconfirmed |
| RecordAssessmentSubmissionUseCase | An existing assessment can be submitted only once |
| CaptureAssessmentReferenceUseCase | Nonempty URL/text; web links only; bounded capture size |

All six use cases define domain-specific typed failures and have unit-test coverage. Example data is opt-in and clearly identified as fictional.
