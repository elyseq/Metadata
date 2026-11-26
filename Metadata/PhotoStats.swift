//
//  PhotoStats.swift
//  Metadata
//
//  Created by Moyartu Manley on 11/20/26.
//

import Foundation
import _LocationEssentials
import ImageIO
import Photos
import UniformTypeIdentifiers

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

/** jasper: here's a bunch of stuff for calculating software/hardware lag. software first:*/

nonisolated struct IOSVersion: Hashable, Comparable, Sendable {
    let components: [Int]
    let suffix: String  // "(a)", "(c)" for security responses, otherwise ""

    init?(_ string: String) {
        let parts = string.trimmingCharacters(in: .whitespaces).split(separator: " ", maxSplits: 1)
        guard let numeric = parts.first else { return nil }
        let parsed = numeric.split(separator: ".").map { Int($0) }
        guard !parsed.isEmpty, !parsed.contains(nil) else { return nil }
        // Pad so "16.4" == "16.4.0"
        components = parsed.compactMap { $0 } + Array(repeating: 0, count: max(0, 3 - parsed.count))
        suffix = parts.count > 1 ? String(parts[1]) : ""
    }

    static func < (lhs: IOSVersion, rhs: IOSVersion) -> Bool {
        if lhs.components != rhs.components {
            return lhs.components.lexicographicallyPrecedes(rhs.components)
        }
        return lhs.suffix < rhs.suffix  // "" < "(a)" < "(c)"
    }
}

nonisolated struct IOSRelease: Sendable {
    let version: IOSVersion
    let day: Int  // days since 1970-01-01
    let availableToAllIPhones: Bool
}

nonisolated enum IOSReleaseHistory {
    static let releases: [IOSRelease] = {
        guard let url = Bundle.main.url(forResource: "ios_releases", withExtension: "csv"),
              let text = try? String(contentsOf: url, encoding: .utf8) else {
            assertionFailure("ios_releases.csv missing from bundle")
            return []
        }
        // columns: major,version,release_date,iphone_availability,notes
        return text.split(whereSeparator: \.isNewline).dropFirst().compactMap { line in
            let fields = line.split(separator: ",", maxSplits: 4, omittingEmptySubsequences: false)
            guard fields.count >= 4,
                  let version = IOSVersion(String(fields[1])),
                  let day = dayNumber(fields[2]) else { return nil }
            return IOSRelease(version: version, day: day, availableToAllIPhones: fields[3] == "all")
        }
    }()
}

/// Parses the date part of "2023:03:01 14:36:56" (EXIF) or "2023-03-01" (CSV) into days since 1970.
nonisolated func dayNumber<S: StringProtocol>(_ string: S) -> Int? {
    let parts = string.prefix(10)
        .split(whereSeparator: { $0 == ":" || $0 == "-" })
        .compactMap { Int($0) }
    guard parts.count == 3, parts[0] >= 2007, (1...12).contains(parts[1]), (1...31).contains(parts[2]) else {
        return nil  // also rejects EXIF's "0000:00:00 00:00:00"
    }
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    guard let date = calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2])) else {
        return nil
    }
    return Int(date.timeIntervalSince1970 / 86_400)
}

//// Number of days on average that the user lags on updating to the newest iOS version.
nonisolated func averageUpdateLag(exif: [EXIFData]) -> Int? {
    let releases = IOSReleaseHistory.releases
    let releasesByVersion = Dictionary(releases.map { ($0.version, $0) }, uniquingKeysWith: { first, _ in first })

    var lags: [Int] = []
    for photo in exif {
        guard photo.iphoneModel?.hasPrefix("iPhone") ?? true,  // skip Canon etc.; allow a missing model
              let versionString = photo.iosVersion,
              let version = IOSVersion(versionString),          // drops "Instagram", "Lightroom 9.0", ...
              let installed = releasesByVersion[version],       // only versions listed in the CSV
              let dateString = photo.date,
              let photoDay = dayNumber(dateString),
              photoDay >= installed.day                         // date earlier than the release means a wrong clock
        else { continue }

        // The first update the user could have installed but hadn't by the time of the photo
        let firstMissedUpdate = releases
            .filter { $0.availableToAllIPhones && $0.version > version && $0.day <= photoDay }
            .map(\.day)
            .min()

        lags.append(firstMissedUpdate.map { photoDay - $0 } ?? 0)
    }

    guard !lags.isEmpty else { return nil }
    return Int((Double(lags.reduce(0, +)) / Double(lags.count)).rounded())
}

/** then hardware: */
nonisolated struct IPhoneModel: Sendable {
    let name: String  // normalized, see normalizedModelName
    let day: Int      // US release, days since 1970-01-01
    let isBudget: Bool
}

nonisolated enum IPhoneModelHistory {
    static let models: [IPhoneModel] = {
        guard let url = Bundle.main.url(forResource: "iphone_models", withExtension: "csv"),
              let text = try? String(contentsOf: url, encoding: .utf8) else {
            assertionFailure("iphone_models.csv missing from bundle")
            return []
        }
        // columns: model,us_release_date,shipped_with_ios,last_supported_ios,last_ios_release_date,still_supported
        return text.split(whereSeparator: \.isNewline).dropFirst().compactMap { line in
            let fields = line.split(separator: ",", maxSplits: 2, omittingEmptySubsequences: false)
            guard fields.count >= 2, let day = dayNumber(fields[1]) else { return nil }
            let name = normalizedModelName(String(fields[0]))
            return IPhoneModel(name: name, day: day, isBudget: isBudgetModel(name))
        }
    }()
}

/// Maps both the CSV names and EXIF Model strings to one form, e.g.
/// "iPhone SE (2nd gen)" and "iPhone SE (2nd generation)" -> "iphone se (2nd gen)",
/// "iPhone (1st gen)" and "iPhone" -> "iphone", "iPhone 4s" and "iPhone 4S" -> "iphone 4s".
nonisolated func normalizedModelName(_ name: String) -> String {
    var normalized = name.lowercased()
    for (target, replacement) in [("generation", "gen"), ("(1st gen)", ""), ("(gsm)", ""), ("(cdma)", "")] {
        normalized = normalized.replacingOccurrences(of: target, with: replacement)
    }
    return normalized.split(separator: " ").joined(separator: " ")
}

/// SE and "e" models (16e, 17e) — a newer budget phone isn't an upgrade for a flagship owner.
nonisolated func isBudgetModel(_ normalizedName: String) -> Bool {
    normalizedName.hasPrefix("iphone se")
        || (normalizedName.last == "e" && normalizedName.dropLast().last?.isNumber == true)
}

/// Models in one lineup ship up to ~6 weeks apart (iPhone X after 8, XR after XS, 14 Plus after 14 Pro),
/// so only a model released at least this long after yours counts as newer.
private nonisolated let minimumDaysBetweenLineups = 60

nonisolated func averageHardwareLag(exif: [EXIFData]) -> Int? {
    let models = IPhoneModelHistory.models
    // EXIF can't tell the GSM and CDMA iPhone 4 apart; keep the first (earlier) one
    let modelsByName = Dictionary(models.map { ($0.name, $0) }, uniquingKeysWith: { first, _ in first })

    var lags: [Int] = []
    for photo in exif {
        guard let modelString = photo.iphoneModel,
              let owned = modelsByName[normalizedModelName(modelString)],  // drops Canon etc.
              let dateString = photo.date,
              let photoDay = dayNumber(dateString),
              photoDay >= owned.day                                         // before launch means a wrong clock
        else { continue }

        // The first newer phone they could have bought but hadn't by the time of the photo
        let firstNewerModel = models
            .filter { !$0.isBudget && $0.day >= owned.day + minimumDaysBetweenLineups && $0.day <= photoDay }
            .map(\.day)
            .min()

//        lags.append(firstNewerModel.map { photoDay - $0 } ?? 0) //phone lag option
        lags.append(photoDay - owned.day)       //phone age option
    }

    guard !lags.isEmpty else { return nil }
    return Int((Double(lags.reduce(0, +)) / Double(lags.count)).rounded())
}

/** Photographer inference*/
nonisolated enum PhotographerHeuristics {
    // if there are less than this num of photos then theres not enough data to determine
    static let minExifSample = 30
    static let minRawSample = 10
    
    //percentage of photos that would have to come from a dedicated camera to determine
    static let someDedicatedShare = 0.05
    static let mostlyDedicatedShare = 0.40
    
    static let rawCountThreshold = 10
    static let manualModeShare = 0.10
    static let proSoftwareShare = 0.02
    
    // score needed for verdict
    static let hobbyistScore = 2
    static let photographerScore = 5
    
    // models for dedicated cameras
    static let cameraMakes: [String] = [
        "canon", "nikon", "sony", "fujifilm", "panasonic", "olympus", "om digital", "leica", "pentax", "ricoh", "hasselblad", "sigma", "phase one"
    ]
    
    // prefixes that indicate photo was taken by phone
    static let phoneModelPrefixes: [String] = [
        "iphone", "ipad", "xperia", "nexus", "oneplus", "samsung", "pixel", "sm-", "xq-"]
    
    static let proSoftware: [String] = ["lightroom", "photoshop", "capture one", "darktable", "luminar"]
}

nonisolated extension EXIFData {
    var hasCameraData: Bool {
        make != nil || iphoneModel != nil
    }
}

nonisolated struct CameraCount: Hashable{
    let name: String
    let count: Int
}

nonisolated struct PhotographerInference {
    nonisolated enum Verdict {
        case notEnoughData, probablyNot, hobbyist, likelyPhotographer
        var summary: String {
            switch self {
                case .notEnoughData: return "Not enough data to make a decision"
            case .probablyNot: return "Probably not a photographer"
            case .hobbyist: return "Hobbyist photographer"
            case .likelyPhotographer: return "Likely a photographer"
            }
        }
    }
    
    let verdict: Verdict
    // photos w camera data
    let exifSampleSize: Int
    let dedicatedCameraShare: Double
    // count raw files across lib
    let rawCount: Int
    let manualModeCount: Double
    let topCameraModels: [CameraCount]
}

nonisolated func rawPhotoCounts(records: [PhotoRecord]) -> Int {
    records.filter { record in
        // using uti to check for raw photo data
        guard let uti = record.uti, let type = UTType(uti) else { return false }
        return type.conforms(to: .rawImage)
    }.count
}

//scoring
nonisolated func isDedicatedCamera(_ photo: EXIFData) -> Bool{
    guard let make = photo.make?.lowercased() else { return false }
    let model = photo.iphoneModel?.lowercased() ?? ""
    if PhotographerHeuristics.phoneModelPrefixes.contains(where: {model.hasPrefix($0)}) {
        return false
    }
    return PhotographerHeuristics.cameraMakes.contains {make.contains($0)}
}

nonisolated func usedManualControls(_ photo: EXIFData) -> Bool {
    guard let program = photo.exposureProgram else { return false }
    return ["1", "3", "4"].contains(program)
}

nonisolated func usedProSoftware (_ photo: EXIFData) -> Bool {
    // ios version would be the tiff software str if shot on an iphone vs. lightroom if it was exported from an editor
    guard let software = photo.iosVersion?.lowercased() else { return false }
    return PhotographerHeuristics.proSoftware.contains {software.contains($0)}
}

nonisolated func cameraName(_ photo: EXIFData) -> String {
    let make = photo.make?.trimmingCharacters(in: .whitespaces)
    let model = photo.iphoneModel?.trimmingCharacters(in: .whitespaces)
    switch (make, model){
    case let (make?, model?):
        return model.lowercased().hasPrefix(make.lowercased()) ? make : "\(make) \(model)"
    case let (make?, nil):
        return make
    case let (nil, model?):
        return model
    case (nil, nil):
        return "Unknown"
    }
}

nonisolated func inferPhotographer(exif: [EXIFData], rawCount: Int) -> PhotographerInference {
    // only look at photos w camera data since pics from msgs and web wouldnt rly say anything abt if user is a photographer
    let withCamera = exif.filter(\.hasCameraData)
    let n = withCamera.count
    
    func share (_ test: (EXIFData) -> Bool) -> Double {
        n == 0 ? 0 : Double(withCamera.filter(test).count) / Double(n)
    }
    let dedicated = share(isDedicatedCamera)
    let manual = share(usedManualControls)
    let proSoftware = share(usedProSoftware)
    
    let topCameras = Dictionary(grouping: withCamera.compactMap(cameraName), by: {$0})
        .map {CameraCount(name: $0.key, count: $0.value.count)}
        .sorted { ($0.count, $1.name) > ($1.count, $0.name)} // most used cameras first
        .prefix(3)
        .map {$0}
    
    let verdict: PhotographerInference.Verdict
    if n < PhotographerHeuristics.minExifSample && rawCount < PhotographerHeuristics.minRawSample {
        verdict = .notEnoughData
    } else {
        var score = 0
        if dedicated >= PhotographerHeuristics.mostlyDedicatedShare {
            score += 3
        }
        else if dedicated >= PhotographerHeuristics.someDedicatedShare {
            score += 2
        }
        if rawCount >= PhotographerHeuristics.rawCountThreshold {
            score += 2
        }
        if manual >= PhotographerHeuristics.mostlyDedicatedShare {
            score += 1
        }
        if proSoftware >= PhotographerHeuristics.mostlyDedicatedShare {
            score += 1
        }
        
        if score >= PhotographerHeuristics.photographerScore {verdict = .likelyPhotographer}
        else if score >= PhotographerHeuristics.hobbyistScore {verdict = .hobbyist}
        else {verdict = .probablyNot}
}
    return PhotographerInference(verdict: verdict, exifSampleSize: n, dedicatedCameraShare: dedicated, rawCount: rawCount, manualModeCount: manual, topCameraModels: topCameras)
    
}

