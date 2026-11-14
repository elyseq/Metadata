//
//  ContentView.swift
//  Metadata
//
//  Created by Elyse Q on 11/8/26.
//

import SwiftUI
import SwiftData
import Photos

struct ContentView: View {

    @State private var hasPhotoAccess = false

    var body: some View {
        NavigationView {
            VStack {
                SettingsView(hasPhotoAccess: $hasPhotoAccess)
                NavigationLink(destination: ResultsView()) {
                    Text("Next")
                }.disabled(!hasPhotoAccess)
            }
        }
    }
}



#Preview {
    ContentView()
        .modelContainer(for: Item.self, inMemory: true)
}
