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

func getAllOfEm() async -> PHFetchResult<PHAsset>? {
    
    if (await !hasFullAccess()) {return nil}
    let everything = PHAsset.fetchAssets(with: .image, options: nil) // this is gets all images
    
    return everything
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

func loadRecords() async -> [PhotoRecord] {
    guard await hasFullAccess() else { return [] }

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


func sampleInferences(records: [PhotoRecord]) async -> Bool {
    let geotagged = records.filter { $0.location != nil }
    let screenshots = records.filter(\.isScreenshot).count
    
    // Photos per year
    let byYear = Dictionary(grouping: records) {
        Calendar.current.component(.year, from: $0.created ?? .distantPast)
    }.mapValues(\.count)
    
    // Likely "home": cluster geotagged photos taken between 10pm and 6am
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
    
    return true
}
