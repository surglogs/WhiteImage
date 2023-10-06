//
//  SLFileManager.swift
//  Surglogs
//
//  Created by Marek Slaninka on 13.12.17.
//  Copyright © 2017 MOFA. All rights reserved.
//

import AVFoundation
import Foundation
import Photos
import UIKit

// public typealias DataReturn = (image: UIImage?, name: String, data: Data?)
// public typealias FilesData = (file: Data, name: String, image: UIImage?)


public class SLFileManager: NSObject, UIDocumentPickerDelegate, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
    
    weak var viewController: UIViewController?
    var image: UIImage?
    var callback: ((Result<DataReturn, FileError>) -> Void)?
    var didSelectFile: EmptyCompletion?
    var convertedImageToData: (() -> Void)?
    
    public enum FileError: Error {
        case largeFile
        case none
        
        public var errorMessage: String {
            switch self {
                case .largeFile:
                    return "File is too large. Max file size is 20MB."
                case .none:
                    return "File could not be loaded."
            }
        }
    }
    
    public struct DataReturn {
        public var image: UIImage?
        public var name: String
        public var data: Data
    }
        
    public required init(viewController: UIViewController) {
        self.viewController = viewController
    }
    
    @discardableResult
    public func loadImage(sender: Any?, didSelectFile: EmptyCompletion?,
                          didProcessFile: @escaping (Result<DataReturn, FileError>) -> Void) -> Self {
        callback = didProcessFile
        self.didSelectFile = didSelectFile
        showImagePicker(sender: sender)
        return self
    }
    
    
    @discardableResult
    public func getDataRepresentation(imageSizeInMB: Double, closure: @escaping ((Data?) -> Void)) -> Self {
        convertedImageToData = {
            DispatchQueue.global(qos: .userInteractive).async {
                let image = self.image?.convertLoadedImageToData(fileSizeInMb: imageSizeInMB)
                DispatchQueue.main.async {
                    closure(image)
                }
            }
        }
        return self
    }
    
    func getPicker() -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.delegate = self
        picker.navigationBar.isTranslucent = false
        picker.navigationBar.barTintColor = viewController?.navigationController?.navigationBar.barTintColor
        picker.navigationBar.tintColor = viewController?.navigationController?.navigationBar.tintColor
        picker.navigationBar.titleTextAttributes = [
            NSAttributedString.Key.foregroundColor: UIColor.white,
        ]
        return picker
    }
    
    func getSheetAlert(picker: UIImagePickerController, sender: Any?) -> UIAlertController {
        let alert = UIAlertController(title: "Choose source", message: "Choose prefferd source for your file", preferredStyle: .actionSheet)
        
        alert.addAction(openGalleryAction(picker: picker))
        
        alert.addAction(openCameraAction(picker: picker))
                
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: { _ in
            alert.dismiss(animated: true, completion: nil)
        }))
        
        if let popoverPresentationController = alert.popoverPresentationController {
            if let sourceView = sender as? UIViewController {
                popoverPresentationController.sourceView = sourceView.view
                popoverPresentationController.permittedArrowDirections = []
                popoverPresentationController.sourceRect = CGRect(x: sourceView.view.frame.midX, y: sourceView.view.frame.midY, width: 0, height: 0)
                
            } else {
                guard let sourceView = sender as? UIView else { return alert }
                popoverPresentationController.sourceView = sourceView
                popoverPresentationController.permittedArrowDirections = [UIPopoverArrowDirection.up, .down]
                popoverPresentationController.sourceRect = sourceView.bounds // CGRect(x: sourceView.bounds.minX, y: sourceView.bounds.minY, width: 0, height: 0)
            }
        }
        return alert
    }
    
    func openGalleryAction(picker: UIImagePickerController) -> UIAlertAction {
        UIAlertAction(title: "Gallery", style: .default) { _ in
            self.openGallery(picker: picker)
        }
    }
    
    
    func openGallery(picker: UIImagePickerController) {
        picker.sourceType = .photoLibrary
        picker.modalPresentationStyle = .overFullScreen
        checkPhotoLibraryPermission(returnBlock: { granted in
            self.handlePermissionRequest(granted: granted, picker: picker)
        })
    }
    
    func openCameraAction(picker: UIImagePickerController) -> UIAlertAction {
        UIAlertAction(title: "Camera", style: .default) { _ in
            if UIImagePickerController.isSourceTypeAvailable(.camera) {
                self.openCamera(picker: picker)
            } else {
                self.noCamera()
            }
        }
    }
    
    func openCamera(picker: UIImagePickerController) {
        picker.sourceType = .camera
        picker.cameraCaptureMode = .photo
        picker.modalPresentationStyle = .fullScreen
        checkCameraPermission(returnBlock: { granted in
            self.handlePermissionRequest(granted: granted, picker: picker)
        })
    }
    
    @discardableResult
    func showImagePicker(sender: Any?) -> SLFileManager {
        let picker = getPicker()
        let alert = getSheetAlert(picker: picker, sender: sender)
        presentPickerAlert(alert: alert)
        
        return self
    }
    
    
    func presentPickerAlert(alert: UIAlertController) {
        DispatchQueue.main.async {
            self.viewController?.present(alert, animated: true, completion: nil)
        }
    }
    
    func handlePermissionRequest(granted: Bool, picker: UIImagePickerController) {
        guard granted else { return }
        DispatchQueue.main.async {
            self.viewController?.present(picker, animated: true, completion: nil)
        }
    }
    
    public func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
        var fileName: String?
        var chimage: UIImage?
        
        if let image = info[UIImagePickerController.InfoKey.editedImage] as? UIImage {
            chimage = image
        } else if let image = info[UIImagePickerController.InfoKey.originalImage] as? UIImage {
            chimage = image
        }
        image = chimage
        
        if picker.sourceType == UIImagePickerController.SourceType.photoLibrary {
            fileName = getNameIfSourceIsPhotoLibrary(info: info)
        } else if picker.sourceType == UIImagePickerController.SourceType.camera {
            fileName = getNameIfSourceIsCamera(info: info)
        }
        prepareImage(with: fileName, image: chimage)
    }
    
    func prepareImage(with fileName: String?, image: UIImage?) {
        let completion: (DataReturn) -> Void = { [weak self] data in
            guard let self = self else { return }
            self.callback?(.success(data))
            self.convertedImageToData?()
        }
        
        let prepareImage: () -> Void = { [weak self] in
            guard let self = self else { return }
            guard let image = image else {
                DispatchQueue.main.async {
                    self.callback?(.failure(FileError.none))
                }
                return
            }
            DispatchQueue.global().async {
                guard let data = image.convertLoadedImageToData(fileSizeInMb: 0.5) else {
                    DispatchQueue.main.async {
                        self.callback?(.failure(FileError.largeFile))
                    }
                    return
                }
                
                let imageReturn = DataReturn(image: image, name: fileName ?? "image.jpg", data: data)
                DispatchQueue.main.async {
                    completion(imageReturn)
                }
            }
        }
        
        viewController?.dismiss(animated: true, completion: {
            self.didSelectFile?()
            prepareImage()
        })
    }
    
    func getNameIfSourceIsPhotoLibrary(info: [UIImagePickerController.InfoKey: Any]) -> String? {
        var fileName: String?
        
        if let url = info[UIImagePickerController.InfoKey.referenceURL] as? URL,
           let assets = PHAsset.fetchAssetWithALAssetURL(alURL: url),
           let fl = PHAssetResource.assetResources(for: assets).first?.originalFilename {
            if let fileNameWithoutExtension = NSURL(fileURLWithPath: fl).deletingPathExtension?.lastPathComponent {
                fileName = fileNameWithoutExtension + ".jpg"
            } else {
                fileName = fl + ".jpg"
            }
        }
        return fileName
    }
    
    func getNameIfSourceIsCamera(info: [UIImagePickerController.InfoKey: Any]) -> String? {
        var fileName: String?
        
        if let metadata = info[UIImagePickerController.InfoKey.mediaMetadata] as? [String: Any],
           let exif = metadata["{Exif}"] as? [String: Any],
           let dateStr = exif["DateTimeOriginal"] as? String {
            let df1 = DateFormatter()
            df1.locale = Locale(identifier: "en_US_POSIX")
            df1.dateFormat = "yyyy:MM:dd HH:mm:ss"
            if let date = df1.date(from: dateStr) {
                let df2 = DateFormatter()
                df2.locale = Locale(identifier: "en_US_POSIX")
                df2.dateFormat = "yyyy-dd-MM_HH-mm-ss"
                fileName = df2.string(from: date) + ".jpg"
            }
        }
        return fileName
    }
    
    func openCameraPicker() {
        let picker = getPicker()
        openCamera(picker: picker)
    }
    
    func openGalleryPicker() {
        let picker = getPicker()
        openGallery(picker: picker)
    }
    
    func checkPhotoLibraryPermission(returnBlock: @escaping (Bool) -> Void) {
        guard let vc = viewController else { return }
        var status = PHPhotoLibrary.authorizationStatus(for: PHAccessLevel.readWrite)
        switch status {
            case .authorized:
                returnBlock(true)
            case .denied, .restricted:
                UIAlertController.showInfoAlert("Permission request", message: "We need permission for accessing gallery. You can grant the requested permission in the device settings", cancelButtonText: "OK", presentingViewController: vc)
            case .notDetermined:
                getGalleryPermissions(returnBlock: returnBlock)
            case .limited:
                returnBlock(true)
            default:
                returnBlock(false)
        }
    }
    
    func checkCameraPermission(returnBlock: @escaping (Bool) -> Void) {
        guard let vc = viewController else { return }
        
        let status = AVCaptureDevice.authorizationStatus(for: AVMediaType.video)
        switch status {
            case .authorized:
                returnBlock(true)
            case .denied, .restricted:
                UIAlertController.showInfoAlert("Permission request", message: "We need permission for accessing camera. You can grant the requested permission in the device settings", cancelButtonText: "OK", presentingViewController: vc)
            case .notDetermined:
                getCameraPermissions(returnBlock: returnBlock)
            default:
                returnBlock(false)
        }
    }
    
    func getGalleryPermissions(returnBlock: @escaping (Bool) -> Void) {
        PHPhotoLibrary.requestAuthorization { status in
            switch status {
                case .authorized:
                    returnBlock(true)
                case .denied, .restricted:
                    break
                case .notDetermined:
                    returnBlock(false)
                default:
                    returnBlock(false)
            }
        }
    }
    
    func getCameraPermissions(returnBlock: @escaping (Bool) -> Void) {
        AVCaptureDevice.requestAccess(for: AVMediaType.video) { granted in
            if granted {
                returnBlock(true)
            } else {
                returnBlock(false)
            }
        }
    }
    
    func noCamera() {
        guard let vc = viewController else { return }
        
        UIAlertController.showInfoAlert("No Camera", message: "Sorry, this device has no camera", cancelButtonText: "OK", presentingViewController: vc)
    }
}

public typealias EmptyCompletion = () -> Void

extension PHAsset {
    class func fetchAssetWithALAssetURL(alURL: URL) -> PHAsset? {
        var phAsset: PHAsset?
        
        let optionsForFetch = PHFetchOptions()
        optionsForFetch.includeHiddenAssets = true
        
        let fetchResult = PHAsset.fetchAssets(withALAssetURLs: [alURL], options: optionsForFetch)
        guard fetchResult.count == 0 else {
            return fetchResult[0]
        }
        
        let str = alURL.absoluteString
        guard let startOfString = str.firstIndex(of: "=") else { return nil }
        
        var localIDFragment = str[startOfString...]
        
        guard let first = localIDFragment.first else { return nil }
        
        let endOfString = str.index(localIDFragment.firstIndex(of: first)!, offsetBy: 36)
        localIDFragment = localIDFragment[..<endOfString]
        
        let fetchResultForPhotostream = PHAssetCollection.fetchAssetCollections(with: PHAssetCollectionType.album, subtype: PHAssetCollectionSubtype.albumMyPhotoStream, options: nil)
        if fetchResultForPhotostream.count > 0 {
            let photostream = fetchResultForPhotostream[0] as PHAssetCollection
            let fetchResultForPhotostreamAssets = PHAsset.fetchAssets(in: photostream, options: optionsForFetch)
            var stop = false
            guard fetchResultForPhotostreamAssets.count > 1 else {
                return phAsset
            }
            for i in 0 ... fetchResultForPhotostreamAssets.count - 1 {
                guard stop != true else { break }
                let phAssetBeingCompared = fetchResultForPhotostreamAssets[i] as PHAsset
                
                if phAssetBeingCompared.localIdentifier.range(of: localIDFragment) != nil {
                    phAsset = phAssetBeingCompared
                    stop = true
                }
            }
            return phAsset
        }
        
        return nil
    }
}
