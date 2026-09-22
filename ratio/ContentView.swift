//
//  ContentView.swift
//  ratio
//
//  Created by Mike on 22/09/2026.
//

import SwiftUI

struct ContentView: View {
    var body: some View {
        #if DEBUG
        // Phase 1 verification screen — see DesignSystemCatalogView's header comment.
        // Replaced once real screens exist from Phase 3 onward.
        DesignSystemCatalogView()
        #else
        VStack {
            Image(systemName: "globe")
                .imageScale(.large)
                .foregroundStyle(.tint)
            Text("Hello, world!")
        }
        .padding()
        #endif
    }
}

#Preview {
    ContentView()
}
