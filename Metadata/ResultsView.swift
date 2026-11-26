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
    var updateLag: Int?
    var hardwareLag: Int?
    var photographer: PhotographerInference?
    
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
        updateLag = averageUpdateLag(exif: exif)
        hardwareLag = averageHardwareLag(exif: exif)
        photographer = inferPhotographer(exif: exif, rawCount: rawPhotoCounts(records: records))
        
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
            ResultSection(header: "Photo habits"){
                LabeledContent("Total Photos", value: inferences.photoCount.formatted())
                if let perDay = inferences.perDay {
                    LabeledContent("Photos per day (overall)",
                                   value: perDay.overall.formatted(.number.precision(.fractionLength(1))))
                    LabeledContent("Photos per day (on days in which a photo was taken)",
                                   value: perDay.onActiveDays.formatted(.number.precision(.fractionLength(1))))
                }
            }
            
            ResultSection(header: "Photography"){
                if let photographer = inferences.photographer {
                    LabeledContent("Are you a photographer?", value: photographer.verdict.summary)
                    if let camera = photographer.topCameraModels.first {
                        LabeledContent("Most used camera", value: camera.name)
                    }
                    Text("Based on \(photographer.exifSampleSize) photos with camera data, plus \(photographer.rawCount) RAW files").font(.caption)
                }
                
            }
            
            ResultSection(header: "Sleep inferences"){
                if let sleep = inferences.sleep {
                    LabeledContent("You likely go to bed after this time", value: sleep.bedtime.formatted(date: .omitted, time: .shortened))
                    LabeledContent("You likely wake up before this time", value: sleep.wakeup.formatted(date: .omitted, time: .shortened))
                    Text("Based on \(sleep.nights) nights of photo timestamps").font(.caption)
                }
            }
            
            ResultSection(header: "Your phone"){
                if let hardwareLag = inferences.hardwareLag {
                    LabeledContent("Typical wait before purchasing a new iPhone", value: formatDuration(days: hardwareLag))
                }
                if let updateLag = inferences.updateLag{
                    LabeledContent("How long you wait to update iOS", value: formatDuration (days: updateLag))
                    Text("i.e how vulnerable you are").font(.caption)
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

func formatDuration(days: Int) -> String {
    guard days > 365 else {
        return days == 1 ? "1 day" : "\(days) days"
    }
    let years = ((Double(days)) / 365 * 10).rounded() / 10
    let text = years.formatted(.number.precision(.fractionLength(0...1)))
    return years == 1 ? "\(text) year" : "\(text) years"
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
