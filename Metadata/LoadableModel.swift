//
//  LoadableModel.swift
//  Metadata
//
//  Created by Rocky Slaymaker on 11/16/26.
//

import SwiftUI

@Observable
@MainActor
class LoadableModel {
    var isLoading = false
    var hasLoaded = false
    var error: Error? = nil

    func load() async throws {}

    func loadIfNeeded() async {
            guard !hasLoaded, !isLoading else { return }
            isLoading = true
            error = nil
            defer { isLoading = false }

            do {
                try await load()
                hasLoaded = true
                onLoad?()
            } catch {
                self.error = error
            }
        }

        func refresh() async {
            hasLoaded = false
            await loadIfNeeded()
        }
    
    var onLoad: (() -> Void)?
}
