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
    var photoCount = 0
    var perDay: PhotosPerDay?
    var sleep: SleepSchedule?
    var exif: [EXIFData] = []
    var updateLag: Int = 0
    var hardwareLag: Int = 0
    
    override func load() async throws {
        records = loadRecords()
        photoCount = totalPhotos(records: records)
        perDay = avgPhotosPerDay(records: records)
        sleep = sleepSchedule(records: records)
        (items, itemsDict) = await homeInference(records: records)
        exif = await getEXIFPhotosSelection(howMany: 200)
//        for e in exif {
//            print((e.iosVersion ?? "not found") + " " + (e.iphoneModel ?? "not found") + " " + (e.date ?? "not found"))
//        }
        updateLag = averageUpdateLag(exif: exif) ?? 0
        hardwareLag = averageHardwareLag(exif: exif) ?? 0
        
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
            ResultSection(header: "Stats"){
                LabeledContent("Total Photos", value: inferences.photoCount.formatted())
                if let perDay = inferences.perDay {
                    LabeledContent("Photos per day (overall)",
                                   value: perDay.overall.formatted(.number.precision(.fractionLength(1))))
                    LabeledContent("Photos per day (on days in which a photo was taken)",
                                   value: perDay.onActiveDays.formatted(.number.precision(.fractionLength(1))))
                }
                LabeledContent("Average days waited to install software updates (i.e. how vulnerable you are)", value: inferences.updateLag.formatted())
                LabeledContent("Average days waited to buy a new iPhone", value: inferences.hardwareLag.formatted())
                if let sleep = inferences.sleep {
                    LabeledContent("Likely bedtime", value: sleep.bedtime.formatted(date: .omitted, time: .shortened))
                    LabeledContent("Likely wake-up time", value: sleep.wakeup.formatted(date: .omitted, time: .shortened))
                    Text("Based on \(sleep.nights) nights of photo timestamps").font(.caption)
                }
                
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
