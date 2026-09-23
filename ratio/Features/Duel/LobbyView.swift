import FirebaseFirestore
import SwiftUI

/// screens/40-friend-lobby.png — share a 6-character code, wait for a friend, chat
/// (filtered before sending), and the host starts the match (PRD: "Friend lobby").
struct LobbyView: View {
    let code: String

    @Environment(\.dismiss) private var dismiss
    @Environment(StudentStore.self) private var student
    @State private var lobby: Lobby?
    @State private var messages: [Message] = []
    /// Messages the filter stopped, shown only to their sender.
    @State private var notSent: [Message] = []
    @State private var draft = ""
    @State private var sending = false
    @State private var starting = false
    @State private var error: String?
    @State private var listeners: [ListenerRegistration] = []
    @State private var playing: String?

    private var isHost: Bool { lobby?.host == student.uid }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    Button { leave() } label: { Image(systemName: "chevron.left").font(.title3).frame(width: 44, height: 44, alignment: .leading) }
                        .accessibilityLabel("Leave the lobby")
                    Spacer()
                    Text("Friend lobby · \(lobby.flatMap { Module(rawValue: $0.moduleId)?.title } ?? "")").ratioFont(.monoLabel).foregroundStyle(Color.ratioInk2)
                }
                Text("Share this \(Text("code.").italic().foregroundStyle(Color.ratioOxblood))").ratioFont(.display)
                codeKeys
                Text("No 0, O, 1 or I · Easy to read aloud").ratioFont(.monoLabel).foregroundStyle(Color.ratioInk2).frame(maxWidth: .infinity)
                HStack(spacing: 12) {
                    RatioButton("Copy", style: .tertiary) { UIPasteboard.general.string = code }
                    ShareLink(item: URL(string: "ratio://lobby/\(code)")!, message: Text("Duel me on Ratio: code \(code)")) {
                        Text("Share link")
                            .ratioFont(.h3)
                            .foregroundStyle(Color.ratioOnInk)
                            .frame(maxWidth: .infinity, minHeight: 56)
                            .background(Color.ratioInk, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    }
                }
                if let lobby { expiry(lobby) }
                players
                chat
                if isHost {
                    RatioButton(starting ? "Starting…" : "Start match", isEnabled: lobby?.guest != nil && !starting) { start() }
                    Text(lobby?.guest == nil ? "Start unlocks when a friend joins" : "The match starts with a 5-second countdown")
                        .ratioFont(.monoLabel).foregroundStyle(Color.ratioInk2).frame(maxWidth: .infinity)
                } else {
                    Text("Waiting for \(lobby.map { $0.names[$0.host] ?? "the host" } ?? "the host") to start")
                        .ratioFont(.monoLabel).foregroundStyle(Color.ratioInk2).frame(maxWidth: .infinity)
                }
            }
            .padding(24)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Color.ratioParchment.ignoresSafeArea())
        .foregroundStyle(Color.ratioInk)
        .onAppear(perform: listen)
        .onDisappear { listeners.forEach { $0.remove() } }
        .fullScreenCover(item: Binding(get: { playing.map(MatchRef.init) }, set: { playing = $0?.id })) { match in
            LiveMatchView(matchId: match.id)
        }
        .onChange(of: playing) { _, matchId in
            if matchId == nil, lobby?.matchId != nil { dismiss() } // Back from the match: the lobby is spent.
        }
        .alert("Something went wrong", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(error ?? "")
        }
    }

    // MARK: Code and players

    private var codeKeys: some View {
        HStack(spacing: 8) {
            ForEach(Array(code.enumerated()), id: \.offset) { index, character in
                Text(String(character))
                    .font(.custom("IBMPlexMono-Regular", size: 30, relativeTo: .title))
                    .frame(maxWidth: .infinity, minHeight: 64)
                    .background(Color.ratioPaper, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay { RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.ratioRule) }
                    .overlay(alignment: .bottom) { Capsule().fill(Color.ratioInk).frame(height: 2).padding(.horizontal, 4) }
                    .padding(.leading, index == 3 ? 12 : 0)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Code \(code.map(String.init).joined(separator: " "))")
    }

    private func expiry(_ lobby: Lobby) -> some View {
        SwiftUI.TimelineView(.periodic(from: .now, by: 1)) { context in
            let left = max(0, Int(lobby.expiresAt.timeIntervalSince(context.date)))
            Label(left > 0 ? "Expires in \(left / 60):\(String(format: "%02d", left % 60))" : "Expired", systemImage: "clock")
                .ratioFont(.monoLabel)
                .foregroundStyle(Color.ratioInk2)
                .frame(maxWidth: .infinity)
        }
    }

    private var players: some View {
        VStack(spacing: 0) {
            if let lobby {
                playerRow(uid: lobby.host, isHost: true)
                Divider().overlay(Color.ratioRule).padding(.vertical, 12)
                if let guest = lobby.guest {
                    playerRow(uid: guest, isHost: false)
                } else {
                    HStack(spacing: 14) {
                        Circle().strokeBorder(Color.ratioInk2, style: StrokeStyle(lineWidth: 1, dash: [3, 3])).frame(width: 52, height: 52)
                        Text("Waiting for a friend…").ratioFont(.h3).italic().foregroundStyle(Color.ratioInk2)
                        Spacer()
                    }
                }
            } else {
                ProgressView()
            }
        }
        .padding(20)
        .background(Color.ratioPaper, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(Color.ratioRule) }
    }

    private func playerRow(uid: String, isHost: Bool) -> some View {
        let name = lobby?.names[uid] ?? "Student"
        return HStack(spacing: 14) {
            ProfilePhoto(uid: uid, initial: String(name.prefix(1)), version: uid == student.uid ? student.profile.avatarVersion : nil, size: 52)
            VStack(alignment: .leading, spacing: 2) {
                Text(uid == student.uid ? "You" : name).ratioFont(.h3)
                if uid == student.uid { Text(name).ratioFont(.small).foregroundStyle(Color.ratioInk2) }
            }
            Spacer()
            if isHost { RatioTag("Host") }
        }
    }

    // MARK: Chat

    private var chat: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Chat").ratioFont(.monoLabel).foregroundStyle(Color.ratioInk2)
            ForEach((messages + notSent).sorted { ($0.at ?? .distantFuture) < ($1.at ?? .distantFuture) }) { message in
                bubble(message)
            }
            HStack(spacing: 10) {
                TextField("Say something…", text: $draft, axis: .vertical)
                    .ratioFont(.body)
                    .lineLimit(1...3)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(Color.ratioSunk, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .submitLabel(.send)
                    .onSubmit(send)
                Button(action: send) {
                    Text("Send").ratioFont(.h3).foregroundStyle(Color.ratioOnInk).padding(.horizontal, 20).frame(minHeight: 48)
                        .background(Color.ratioInk, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(sending || draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            Text("Messages are checked before they're sent. Report or block from any message.")
                .ratioFont(.monoLabel)
                .foregroundStyle(Color.ratioInk2)
        }
        .padding(20)
        .background(Color.ratioPaper, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(Color.ratioRule) }
    }

    private func bubble(_ message: Message) -> some View {
        let mine = message.uid == student.uid
        return VStack(alignment: mine ? .trailing : .leading, spacing: 6) {
            Text(mine ? "You" : message.name).ratioFont(.monoLabel).foregroundStyle(Color.ratioInk2)
            HStack(spacing: 10) {
                if mine { Spacer(minLength: 40) }
                Group {
                    if message.blocked {
                        Text("Message not sent: \(message.text)")
                            .italic()
                            .foregroundStyle(Color.ratioInk2)
                            .padding(14)
                            .overlay { RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Color.ratioInk2, style: StrokeStyle(lineWidth: 1, dash: [4, 4])) }
                    } else {
                        Text(message.text)
                            .foregroundStyle(mine ? Color.ratioOnInk : Color.ratioInk)
                            .padding(14)
                            .background(mine ? Color.ratioInk : Color.ratioSunk, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    }
                }
                .ratioFont(.body)
                if !mine && !message.blocked {
                    Menu {
                        Button("Report message", systemImage: "flag") { report(message) }
                        Button("Block \(message.name)", systemImage: "hand.raised", role: .destructive) { block(message) }
                    } label: {
                        Image(systemName: "ellipsis").frame(width: 44, height: 44)
                    }
                    .foregroundStyle(Color.ratioInk2)
                    .accessibilityLabel("More for this message")
                }
                if !mine { Spacer(minLength: 40) }
            }
        }
        .frame(maxWidth: .infinity, alignment: mine ? .trailing : .leading)
    }

    // MARK: Actions

    private func listen() {
        guard listeners.isEmpty else { return }
        let ref = Firestore.firestore().collection("lobbies").document(code)
        listeners = [
            ref.addSnapshotListener { snapshot, _ in
                guard let snapshot, let lobby = try? snapshot.data(as: Lobby.self) else { return }
                self.lobby = lobby
                if let matchId = lobby.matchId, playing == nil { playing = matchId }
                if lobby.status == "closed", !isHost { dismiss() }
            },
            ref.collection("messages").order(by: "at").addSnapshotListener { snapshot, _ in
                guard let snapshot else { return }
                messages = snapshot.documents.compactMap { document in
                    (try? document.data(as: Message.self)).map { var m = $0; m.id = document.documentID; return m }
                }
            },
        ]
    }

    private func send() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !sending else { return }
        sending = true
        Task {
            defer { sending = false }
            do {
                let result = try await DuelService.sendMessage(code: code, text: text)
                draft = ""
                if !result.sent {
                    let why = result.reason == "contact" ? "personal details removed" : "that isn't allowed here"
                    notSent.append(Message(id: UUID().uuidString, uid: student.uid, name: "You", text: why, at: .now, blocked: true))
                }
            } catch {
                self.error = "Your message didn't send. Check your connection."
            }
        }
    }

    private func report(_ message: Message) {
        Task {
            do { try await DuelService.report(code: code, messageId: message.id) } catch { self.error = "The report didn't go through. Try again." }
        }
    }

    private func block(_ message: Message) {
        Task {
            do {
                try await DuelService.block(uid: message.uid)
                leave()
            } catch {
                self.error = "Couldn't block this student. Try again."
            }
        }
    }

    private func start() {
        starting = true
        Task {
            defer { starting = false }
            do {
                if let matchId = try await DuelService.startLobby(code: code) { playing = matchId }
            } catch {
                self.error = (error as NSError).localizedDescription
            }
        }
    }

    private func leave() {
        Task { await DuelService.leaveLobby(code: code) }
        dismiss()
    }

    // MARK: Documents

    nonisolated struct Lobby: Decodable {
        var host: String
        var guest: String?
        var names: [String: String]
        var moduleId: String
        var limitMs: Int
        var status: String
        var matchId: String?
        var expiresAt: Date
    }

    nonisolated struct Message: Decodable, Identifiable {
        var id = ""
        var uid: String
        var name: String
        var text: String
        var at: Date?
        /// Set locally for a message the filter stopped.
        var blocked = false

        private enum CodingKeys: String, CodingKey { case uid, name, text, at }

        init(id: String, uid: String, name: String, text: String, at: Date?, blocked: Bool) {
            self.id = id
            self.uid = uid
            self.name = name
            self.text = text
            self.at = at
            self.blocked = blocked
        }
    }

    private struct MatchRef: Identifiable { let id: String }
}

/// Make a lobby or join one with a code (or from a shared link).
struct LobbyEntryView: View {
    let module: Module
    let seconds: Int
    var initialCode: String?
    let open: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var code = ""
    @State private var working = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Host").ratioFont(.monoLabel).foregroundStyle(Color.ratioInk2)
                    Text("Make a lobby for \(module.title), \(seconds) s a question, and share the code.").ratioFont(.body)
                    RatioButton("Make a lobby", isEnabled: !working) { create() }
                }
                Divider().overlay(Color.ratioRule)
                VStack(alignment: .leading, spacing: 10) {
                    Text("Join").ratioFont(.monoLabel).foregroundStyle(Color.ratioInk2)
                    TextField("K7MP4X", text: $code)
                        .font(.custom("IBMPlexMono-Regular", size: 28, relativeTo: .title))
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .padding(14)
                        .background(Color.ratioSunk, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .onChange(of: code) { _, value in
                            let clean = String(value.uppercased().filter { $0.isLetter || $0.isNumber }.prefix(6))
                            if clean != value { code = clean }
                        }
                    RatioButton("Join", style: .secondary, isEnabled: code.count == 6 && !working) { join(code) }
                }
                if let error { Text(error).ratioFont(.small).foregroundStyle(Color.ratioOxblood) }
                Spacer()
            }
            .padding(24)
            .background(Color.ratioParchment.ignoresSafeArea())
            .foregroundStyle(Color.ratioInk)
            .navigationTitle("Friend lobby")
            .toolbarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
        .task {
            if let initialCode {
                code = initialCode
                join(initialCode)
            }
        }
    }

    private func create() {
        working = true
        error = nil
        Task {
            defer { working = false }
            do { open(try await DuelService.createLobby(module: module, seconds: seconds)) } catch { self.error = (error as NSError).localizedDescription }
        }
    }

    private func join(_ code: String) {
        working = true
        error = nil
        Task {
            defer { working = false }
            do { open(try await DuelService.joinLobby(code: code)) } catch { self.error = (error as NSError).localizedDescription }
        }
    }
}
