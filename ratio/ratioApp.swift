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

    init() {
        FirebaseApp.configure()
        if let clientID = FirebaseApp.app()?.options.clientID {
            GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: clientID)
        }
        _session = State(initialValue: SessionStore())
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(session)
                .onOpenURL { GIDSignIn.sharedInstance.handle($0) }
        }
    }
}
