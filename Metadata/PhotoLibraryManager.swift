//
//  PhotoLibraryManager.swift
//  Metadata
//
//  Created by Elyse Q on 11/8/26.
//

//var isAuthorized: Bool {
//    get async {
//        let status = AVCaptureDevice.authorizationStatus(for: .video)
//        
//        // Determine if the user previously authorized camera access.
//        var isAuthorized = status == .authorized
//        
//        // If the system hasn't determined the user's authorization status,
//        // explicitly prompt them for approval.
//        if status == .notDetermined {
//            isAuthorized = await AVCaptureDevice.requestAccess(for: .video)
//        }
//        
//        return isAuthorized
//    }
//}
//
//func setUpCaptureSession() async {
//    guard await isAuthorized else { return }
//    // Set up the capture session.
//}


import Foundation
import Photos
import CoreLocation
import MapKit

extension CLLocationCoordinate2D: @retroactive Equatable {}
extension CLLocationCoordinate2D: @retroactive Hashable {
    public static func == (lhs: CLLocationCoordinate2D, rhs: CLLocationCoordinate2D) -> Bool {
        return lhs.latitude == rhs.latitude && lhs.longitude == rhs.longitude
    }
    
    public func hash(into hasher: inout Hasher) {
            hasher.combine(latitude)
            hasher.combine(longitude)
        }
}


func requestAccess() async -> PHAuthorizationStatus {
    let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)

    if status == .notDetermined {
        return await PHPhotoLibrary.requestAuthorization(for: .readWrite)
    }

    return status
}

func hasFullAccess() async -> Bool {
    let status = await requestAccess()
    return status == .authorized
}



struct PhotoRecord {
    let id: String
    let created: Date?
    let modified: Date?
    let location: CLLocation?
    let width: Int
    let height: Int
    let isScreenshot: Bool
    let isLivePhoto: Bool
    let isFavorite: Bool
    let isHidden: Bool
    let burstID: String?
    let source: PHAssetSourceType
    let originalFilename: String?
    let uti: String?
}

extension PhotoRecord {
    init(asset: PHAsset) {
        let resource = PHAssetResource.assetResources(for: asset).first
        self.init(
            id: asset.localIdentifier,
            created: asset.creationDate,
            modified: asset.modificationDate,
            location: asset.location,
            width: asset.pixelWidth,
            height: asset.pixelHeight,
            isScreenshot: asset.mediaSubtypes.contains(.photoScreenshot),
            isLivePhoto: asset.mediaSubtypes.contains(.photoLive),
            isFavorite: asset.isFavorite,
            isHidden: asset.isHidden,
            burstID: asset.burstIdentifier,
            source: asset.sourceType,
            originalFilename: resource?.originalFilename,   // e.g. "IMG_4821.HEIC"
            uti: resource?.uniformTypeIdentifier            // e.g. "public.heic"
        )
    }
}

nonisolated struct EXIFData {
    let date: String?
    let iosVersion: String?
    let iphoneModel: String?
    let make: String?
    let lensModel: String?
    let exposureProgram: String?
}


nonisolated func getEXIFMetadata(for asset: PHAsset) async -> EXIFData? {
    let opts = PHImageRequestOptions()
    opts.version = .original              // unedited original, keeps the original EXIF
    opts.isNetworkAccessAllowed = false   // don't download from iCloud
    opts.deliveryMode = .fastFormat

    let data: Data? = await withCheckedContinuation { cont in
        PHImageManager.default().requestImageDataAndOrientation(for: asset, options: opts) { data, _, _, _ in
            cont.resume(returning: data)
        }
    }
    guard let data,
          let src = CGImageSourceCreateWithData(data as CFData, nil),
          let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [String: Any]
    else { return nil }

    let tiff = props[kCGImagePropertyTIFFDictionary as String] as? [String: Any]
    let exif = props[kCGImagePropertyExifDictionary as String] as? [String: Any]

    return EXIFData(
        date: exif?[kCGImagePropertyExifDateTimeOriginal as String] as? String,
        iosVersion: tiff?[kCGImagePropertyTIFFSoftware as String] as? String,
        iphoneModel: tiff?[kCGImagePropertyTIFFModel as String] as? String,
        make: tiff?[kCGImagePropertyTIFFMake as String] as? String,
        lensModel: tiff?[kCGImagePropertyExifLensModel as String] as? String,
        exposureProgram: exif?[kCGImagePropertyExifExposureProgram as String] as? String
    )
}

func loadRecords() -> [PhotoRecord] {
    let options = PHFetchOptions()
    options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: true)]
    options.includeHiddenAssets = true   // hidden photos are excluded by default

    let result = PHAsset.fetchAssets(with: .image, options: options)
    var records: [PhotoRecord] = []
    records.reserveCapacity(result.count)
    result.enumerateObjects { asset, _, _ in
        records.append(PhotoRecord(asset: asset))
    }
    return records
}

func randomIndexSet(count: Int, in range: Range<Int>) -> IndexSet {
//    var set = IndexSet()
//    while set.count < count {
//        set.insert(Int.random(in: range))
//    }
    
    return IndexSet((0..<count-1).map { i in
        range.lowerBound + i * (range.upperBound-range.lowerBound) / (count - 1)
    })
}

func getEXIFPhotosSelection(howMany: Int) async -> [EXIFData] {
    let options = PHFetchOptions()
    options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: true)]
    options.includeHiddenAssets = true
    let assets = PHAsset.fetchAssets(with: .image, options: options)
    
    let indices = randomIndexSet(count: howMany, in: 0..<assets.count)
    var photos: [EXIFData] = []
    
    for asset in assets.objects(at: indices) {
        if let exif = await getEXIFMetadata(for: asset) {
            photos.append(exif)
        }
    }
    return photos
}


func sampleInferences(records: [PhotoRecord]) -> Bool {
    let screenshots = records.filter(\.isScreenshot).count
    
    // Photos per year
    let byYear = Dictionary(grouping: records) {
        Calendar.current.component(.year, from: $0.created ?? .distantPast)
    }.mapValues(\.count)
    
    return true
}

func likelyHome(records: [PhotoRecord]) -> String {
    let geotagged = records.filter { $0.location != nil }
    let nightPhotos = geotagged.filter {
        guard let d = $0.created else { return false }
        let h = Calendar.current.component(.hour, from: d)
        return h >= 22 || h < 6
    }
    // Round coordinates to ~100 m cells, then find the busiest cell
    let cells = Dictionary(grouping: nightPhotos) { r -> String in
        let c = r.location!.coordinate
        return String(format: "%.3f,%.3f", c.latitude, c.longitude)
    }
    let likelyHome = cells.max { $0.value.count < $1.value.count }
    let output = likelyHome?.key ?? "whoops"
    return output
}

func homeInference(records: [PhotoRecord]) async -> ([MKMapItem], [MKMapItem:Int]) {
    let geotagged = records.filter { $0.location != nil }
    
    // Likely "home": cluster geotagged photos taken between 10pm and 6am
    let nightPhotos = geotagged.filter {
        guard let d = $0.created else { return false }
        let h = Calendar.current.component(.hour, from: d)
        return h >= 22 || h < 6
    }
    // Round coordinates to ~100 m cells, then find the busiest cell
    let cells = Dictionary(grouping: nightPhotos) { r -> CLLocationCoordinate2D in
        let c: CLLocationCoordinate2D = r.location!.coordinate
        return CLLocationCoordinate2D(latitude: round(c.latitude / 0.001) * 0.001, longitude: round(c.longitude / 0.001) * 0.001)
    }
    let likelyHomes = cells.sorted { $0.value.count > $1.value.count }.prefix(3).map({($0.key, $0.value.count)})
    
    var tempItems = [MKMapItem:Int]()
    for (home, num) in likelyHomes {
        if let request = MKReverseGeocodingRequest(location: CLLocation(latitude: home.latitude, longitude: home.longitude)) {
            let mapitems = try? await request.mapItems
            if let mapitem = mapitems?.first {
                tempItems[mapitem] = num
            }
        }
    }
    let itemArray = tempItems.sorted{ $0.value > $1.value}.map(\.key)
    return (itemArray, tempItems)
}
