import FirebaseAuth
import FirebaseFirestore
import SwiftUI

/// "Spotted an error? Report it" (PRD: "Report an error in any lesson or question…
/// also available in-line on every item"). Writes `reports/{id}` for triage within 72
/// hours; students can create reports but never read them back.
struct ReportErrorSheet: View {
    let itemId: String
    let lessonId: String?

    enum Reason: String, CaseIterable, Identifiable {
        case wrongAnswer = "wrong-answer"
        case lawWrong = "law-wrong"
        case unclear
        case other

        var id: String { rawValue }

        var title: String {
            switch self {
            case .wrongAnswer: "The marked answer is wrong"
            case .lawWrong: "The law is stated wrongly or out of date"
            case .unclear: "A typo or unclear wording"
            case .other: "Something else"
            }
        }
    }

    @Environment(\.dismiss) private var dismiss
    @State private var reason: Reason?
    @State private var note = ""
    @State private var sent = false

    private static let maxNote = 500

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if sent {
                        Text("Thank you.").ratioFont(.h1)
                        Text("A reviewer will look at this within 72 hours. If it's wrong, it's fixed for everyone.")
                            .ratioFont(.body)
                        RatioButton("Done", style: .secondary) { dismiss() }
                    } else {
                        Text("What's wrong?").ratioFont(.h2)
                        VStack(spacing: 10) {
                            ForEach(Reason.allCases) { option in
                                RatioOptionRow(text: option.title, state: reason == option ? .selected : .default) { reason = option }
                            }
                        }
                        RatioTextField("Details (optional)", placeholder: "What should it say?", text: $note, axis: .vertical)
                            .onChange(of: note) { _, new in
                                if new.count > Self.maxNote { note = String(new.prefix(Self.maxNote)) }
                            }
                        RatioButton("Send report", isEnabled: reason != nil) { send() }
                    }
                }
                .padding(24)
            }
            .background(Color.ratioParchment.ignoresSafeArea())
            .foregroundStyle(Color.ratioInk)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
        .presentationDetents([.large])
    }

    /// Queued locally and sent when online, so reporting never waits on the network.
    private func send() {
        guard let reason, let uid = Auth.auth().currentUser?.uid else { return }
        var report: [String: Any] = [
            "uid": uid,
            "itemId": itemId,
            "reason": reason.rawValue,
            "status": "open",
            "createdAt": FieldValue.serverTimestamp(),
            "appVersion": Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "",
        ]
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { report["note"] = trimmed }
        if let lessonId { report["lessonId"] = lessonId }
        Firestore.firestore().collection("reports").addDocument(data: report)
        withAnimation { sent = true }
    }
}
