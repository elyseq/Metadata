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

class PhotoLibraryManager {

    static func requestAccess() async -> PHAuthorizationStatus {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)

        if status == .notDetermined {
            return await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        }

        return status
    }

    static func hasFullAccess() async -> Bool {
        let status = await requestAccess()
        return status == .authorized
    }
    
    static func getAllOfEm() async -> PHFetchResult<PHAsset>? {
        
        if (await !hasFullAccess()) {return nil}
        let everything = PHAsset.fetchAssets(with: .image, options: nil) // this is gets all images
        
        return everything
    }
}
