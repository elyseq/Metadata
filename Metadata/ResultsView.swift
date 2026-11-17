//
//  ResultsView.swift
//  Metadata
//
//  Created by Jasper Knabe on 11/14/26.
//

import SwiftUI
import MapKit
import CoreLocation

@Observable
@MainActor
final class Inferences: LoadableModel {
    var records: [PhotoRecord] = []
    var items: [MKMapItem] = []
    var itemsDict: [MKMapItem:Int] = [:]
    
    override func load() async throws {
        records = await loadRecords()
        (items, itemsDict) = await homeInference(records: records)
    }
}


struct ResultsView: View {
    @State private var isShowingFullMap = false
    @State private var position: MapCameraPosition = .automatic
    
    @State private var inferences = Inferences()
    
    var body: some View {
        List {
            ResultSection(header: "Map"){
                MapView(items: inferences.items, position: $position)
                    .frame(height: 300)
                    .clipShape(.rect(cornerRadius: 15))
                    .contentShape(.rect(cornerRadius: 15))
                    .onTapGesture {
                        isShowingFullMap = true
                    }
                
                ForEach($inferences.items, id: \.name) {$item in
                    HStack(){
                        Text("\(inferences.itemsDict[item]!)")
                        VStack(alignment: .leading) {
                            Text(item.name ?? "Name")
                            Text(item.addressRepresentations?.cityWithContext ?? "City")
                                .font(.caption)
                        }}
                    .onTapGesture {
                        position = .item(item)
                    }
                }
            }
            ResultSection(header: "Header"){
                Text("Content")
            }
        }
        .listStyle(SidebarListStyle())
        .navigationDestination(isPresented: $isShowingFullMap) {
            MapView(items: inferences.items, position: $position)
        }
        .task{ await inferences.loadIfNeeded()}
    }
}

private struct MapView: View {
    let items: [MKMapItem]
    @Binding var position: MapCameraPosition
    var interactionModes: MapInteractionModes = [.pan, .zoom]
    var body: some View {
        Map(position: $position, interactionModes: interactionModes) {
            ForEach(items, id: \.self){ item in
                Marker("\(item.name ?? "Unknown")", coordinate: item.location.coordinate)
            }
        }
        .onMapCameraChange { context in
            
            position = .camera(context.camera)
        }
    }
    
}

private struct ResultSection<Content: View>: View {
    let header: String
    @State private var isExpanded: Bool = true
    
    @ViewBuilder var content: () -> Content
    
    var body: some View { Section<Text, Content, EmptyView>(
        isExpanded: $isExpanded,
        content: content,
        header: {
            Text(header)
        }
    )}
}

#Preview {
    ResultsView()
}
