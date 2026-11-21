//
//  PhotoStats.swift
//  Metadata
//
//  Created by Moyartu Manley on 11/20/26.
//

import Foundation
import _LocationEssentials

/**moyartu: i added some functions to help work on some of the inferences; sectioning my stuff off just in case it breaks stuff*/
// keyword nonisolated ensures it doesnt run on a main thread; which can slow things down if user has large lib
nonisolated func totalPhotos(records: [PhotoRecord]) -> Int {
    return records.count
}

// avg photos per day
nonisolated struct PhotosPerDay {
    let overall: Double
    let onActiveDays: Double
}

nonisolated func avgPhotosPerDay(records: [PhotoRecord], calendar: Calendar = .current) -> PhotosPerDay? {
    let dates = records.compactMap(\.created)
    guard let firstTaken = dates.min(), let lastTaken = dates.max() else { return nil }
    let timespan = calendar.dateComponents([.day],
                                           from: calendar.startOfDay(for: firstTaken),
                                           to: calendar.startOfDay(for: lastTaken)).day! + 1
    let activeDays = Set(dates.map {calendar.startOfDay(for: $0)}).count
    return PhotosPerDay(overall: Double(dates.count)/Double(timespan),
                        onActiveDays: Double(dates.count)/Double(activeDays))
}

/**Sleep stuff*/
// heuristics for sleep inference; can be adjusted
nonisolated enum SleepHeuristics {
    // photos taken before this hour count toward the previous evening's night
    // ex. 10pm-7am, photos taken before 7am count toward yesterday night w this logic
    static let nightRolloverHours = 7
    
    // ignore gaps smaller than this amount
    static let minGap: TimeInterval = 4 * 3600
    
    // minimum amount of nights of data before the results can be somewhat trusted
    static let minNights = 7
}

nonisolated func nightOf( date: Date, calendar: Calendar = .current) -> Date {
    // a night is associated with the evening it started; so 1am on a tuesday is considered under the same night as monday
    let shift = TimeInterval(SleepHeuristics.nightRolloverHours * 3600)
    return calendar.startOfDay(for: date.addingTimeInterval(-shift))
}


// likely sleeping locs
nonisolated struct SleepingLocation {
    var center: CLLocation
    var nights: Set<Date>
    var photoCount: Int
}

nonisolated func sleepingLocations(records: [PhotoRecord],
                                   radius: CLLocationDistance = 150,
                                   calendar: Calendar = .current) -> [SleepingLocation] {
    var locations: [SleepingLocation] = []
    for record in records {
        guard let date = record.created, let location = record.location else { continue }
        let hour = calendar.component(.hour, from: date)
        guard hour >= 22 || hour < 6 else { continue }
        let night = calendar.startOfDay(for: nightOf(date: date, calendar: calendar))
        if let idx = locations.firstIndex(where: {$0.center.distance(from: location) <= radius}){
            locations[idx].nights.insert(night)
            locations[idx].photoCount += 1
        } else {
            locations.append(SleepingLocation(center: location, nights: [night], photoCount: 1))
        }
    }
    return locations.sorted{$0.nights.count > $1.nights.count}
}

// sleep schedule inferences
nonisolated struct SleepSchedule {
    // time of day
    let bedtime: Date
    let wakeup: Date
    
    // how many nights the estimate is based on
    let nights: Int
}

nonisolated func sleepSchedule(records: [PhotoRecord],
                               calendar: Calendar = .current) -> SleepSchedule?{
    let dates = records.compactMap(\.created).sorted()
    var bestPerNight: [Date: (start: Date, end: Date)] = [:]
    
    // for each night keep longest gap between two consecutive photos
    // photo before the gap = last time awake; photo after = first time awake
    for (photoA, photoB) in zip(dates, dates.dropFirst()){
        let gap = photoB.timeIntervalSince(photoA)
        guard gap >= SleepHeuristics.minGap else { continue }
        
        // only use gaps from evening to early morning
        let hourA = calendar.component(.hour, from: photoA)
        let hourB = calendar.component(.hour, from: photoB)
        guard (hourA >= 20 || hourA < 5), (3..<13).contains(hourB) else { continue }
        
        // keep only the longest gap
        let night = nightOf(date: photoA, calendar: calendar)
        if let current = bestPerNight[night], current.end.timeIntervalSince(current.start) >= gap { continue }
        bestPerNight[night] = (photoA, photoB)
    }
    
    // ensure there are enough nights to create a median
    guard bestPerNight.count >= SleepHeuristics.minNights else {return nil}
    
    // convert to minutes since noon to prevent time wrapping
    func sinceNoon(date: Date) -> Int{
        let calendar = calendar.dateComponents([.hour, .minute], from: date)
        return ((calendar.hour! * 60 + calendar.minute!) - 720 + 1440) % 1440
    }
    
    func median(_ xs: [Int]) -> Int {xs.sorted()[xs.count/2]}
    func clock (min: Int) -> Date {
        let mins = (min + 720) % 1440
        return calendar.date(bySettingHour: mins/60, minute: mins % 60, second: 0, of: Date())!
    }
    let bed = median(bestPerNight.values.map { sinceNoon(date: $0.start) })
    let wake = median(bestPerNight.values.map { sinceNoon(date: $0.end) })
    return SleepSchedule(bedtime: clock(min: bed),
                         wakeup: clock(min: wake),
                         nights: bestPerNight.count)
    
}
/**moyartu: end of my additions*/
