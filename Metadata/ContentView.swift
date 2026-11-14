//
//  ContentView.swift
//  Metadata
//
//  Created by Elyse Q on 11/8/26.
//

import SwiftUI
import Photos

struct ContentView: View {

    @State private var hasPhotoAccess = false

    var body: some View {
        VStack {
            Text("Metadata")
                .font(.largeTitle)

            Button("Allow Photo Library Access") {
                Task {
                    let status = await requestAccess()
                    hasPhotoAccess = status == .authorized
                }
            }

            if hasPhotoAccess {
                ResultsView()
            }
        }
    }
}



//#Preview {
//    ContentView()
//        .modelContainer(for: Item.self, inMemory: true)
//}
