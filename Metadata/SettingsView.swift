//
//  SettingsView.swift
//  Metadata
//
//  Created by Rocky Slaymaker on 11/14/26.
//

import SwiftUI
import Photos

struct SettingsView: View {
    
    @Binding var hasPhotoAccess: Bool
    
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
        }
    }
}

struct SettingsViewPreview: PreviewProvider {
  @State static var hasPhotoAccess = true
  static var previews: some View {
      SettingsView(hasPhotoAccess: $hasPhotoAccess)
  }
}
