//
//  ratioApp.swift
//  ratio
//
//  Created by Mike on 22/09/2026.
//

import FirebaseCore
import GoogleSignIn
import SwiftUI

@main
struct ratioApp: App {
    @State private var session: SessionStore
    @State private var content = ContentStore()
    @State private var links = DeepLinks()

    init() {
        FirebaseApp.configure()
        UniversityDirectory.configure()
        if let clientID = FirebaseApp.app()?.options.clientID {
            GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: clientID)
        }
        _session = State(initialValue: SessionStore())
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(session)
                .environment(content)
                .environment(links)
                .onOpenURL { url in
                    if !GIDSignIn.sharedInstance.handle(url) { links.pending = url }
                }
        }
    }
}

/// A ratio:// link waiting for the signed-in app to handle it (a friend-lobby invite
/// can open the app from cold, before sign-in has finished).
@Observable
final class DeepLinks {
    var pending: URL?
}
