//
//  ResultsView.swift
//  Metadata
//
//  Created by Jasper Knabe on 11/14/26.
//

import SwiftUI

struct ResultsView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading) {
                ForEach(0..<100) {
                    Text("It fucking worked \($0)")
                }
                Spacer()
            }
            .frame(
                  minWidth: 0,
                  maxWidth: .infinity,
                  minHeight: 0,
                  maxHeight: .infinity,
                  alignment: .topLeading
            ).padding()
        }
    }
}

#Preview {
    ResultsView()
}
