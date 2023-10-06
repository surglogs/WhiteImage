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

import ImageHelper

public protocol SLFileManagerProtocol: UIImagePickerControllerDelegate, UINavigationControllerDelegate {
    init(viewController: UIViewController)
    @discardableResult func loadImage(sender: Any?, didSelectFile: EmptyCompletion?, didProcessFile: @escaping (Result<SLFileManager.DataReturn, SLFileManager.FileError>) -> Void) -> Self
    @discardableResult func loadFile(sender: Any?, didSelectFile: EmptyCompletion?, didProcessFile: @escaping (Result<SLFileManager.DataReturn, SLFileManager.FileError>) -> Void) -> Self
}

public class SLFileManager: NSObject, SLFileManagerProtocol, UIDocumentPickerDelegate {
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
    
    let defaultFileTypes: [String] = [
        // IMAGE:
        "public.image",
        // DOCUMENT:
        "com.adobe.pdf",
        "com.microsoft.word.doc",
        "public.text",
        "org.openxmlformats.wordprocessingml.document",
        "com.microsoft.excel.xls",
        "org.openxmlformats.spreadsheetml.sheet",
    ]
    
    let imageFileTypes: [String] = [
        "public.image",
    ]
    
    var fileTypes: [String] = []
    
    public required init(viewController: UIViewController) {
        self.viewController = viewController
    }
    
    @discardableResult
    public func loadImage(sender: Any?, didSelectFile: EmptyCompletion?, didProcessFile: @escaping (Result<DataReturn, FileError>) -> Void) -> Self {
        callback = didProcessFile
        self.didSelectFile = didSelectFile
        fileTypes = imageFileTypes
        showImagePicker(sender: sender)
        return self
    }
    
    @discardableResult
    public func loadFile(sender: Any?, didSelectFile: EmptyCompletion?, didProcessFile: @escaping (Result<DataReturn, FileError>) -> Void) -> Self {
        self.didSelectFile = didSelectFile
        callback = didProcessFile
        fileTypes = defaultFileTypes
        showImagePicker(sender: sender)
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
        
        alert.addAction(openFileBrowserAction())
        
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
    
    func openFileBrowserAction() -> UIAlertAction {
        UIAlertAction(title: "Document browser", style: .default) { _ in
            self.getFile()
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
    
    func reportCorruptedImageToSentry(originalImage: UIImage, fileName: String?) {
        let sentryMaxAttachmentSize = 19 * 1024 * 1024
        var attachment: Attachment?
        if #available(iOS 17.0, *),
           let data = originalImage.heicData(),
           data.count < sentryMaxAttachmentSize {
            attachment = Attachment(data: data, filename: fileName ?? "image.heic", contentType: "heic")
        } else if let data = originalImage.jpegData(compressionQuality: 1),
                  data.count < sentryMaxAttachmentSize {
            attachment = Attachment(data: data, filename: fileName ?? "image.jpeg", contentType: "jpeg")
        }
        
        var event = CorruptedFileSentryEvent()
        
        Monitoring.logEvent(errorEvent: event) { scope in
            if let attachment {
                scope.addAttachment(attachment)
                scope.setFingerprint(["image-compression-error"])
            }
        }
    }
    
    func getFile() {
        let controller = UIDocumentPickerViewController(
            documentTypes: fileTypes, // choose your desired documents the user is allowed to select
            in: .import // choose your desired UIDocumentPickerMode
        )
        controller.navigationController?.navigationBar.barTintColor = .surBlue
        controller.allowsMultipleSelection = false
        controller.shouldShowFileExtensions = true
        
        controller.delegate = self
        controller.allowsMultipleSelection = false
        
        UINavigationBar.appearance(whenContainedInInstancesOf: [UIDocumentBrowserViewController.self]).tintColor = UIColor.surGrayMain
        // e.g. present UIDocumentPickerViewController via your current UIViewController
        viewController?.present(
            controller,
            animated: true,
            completion: nil
        )
    }
    
    public func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        if controller.documentPickerMode == .import {
            //            self.didSelectFile?()
            guard let firstUrl = urls.first,
                  let dataReturn = getFileData(for: firstUrl)
            else {
                callback?(.failure(FileError.none))
                return
            }
            let fileSize = Double(dataReturn.data.count / 1_048_576)
            guard fileSize < 20 else {
                callback?(.failure(FileError.largeFile))
                return
            }
            callback?(.success(dataReturn))
        }
    }
    
    public func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentAt url: URL) {
        if controller.documentPickerMode == .import {
            //            self.didSelectFile?()
            guard let dataReturn = getFileData(for: url) else {
                callback?(.failure(FileError.none))
                return
            }
            let fileSize = Double(dataReturn.data.count / 1_048_576)
            guard fileSize < 20 else {
                callback?(.failure(FileError.largeFile))
                return
            }
            callback?(.success(dataReturn))
        }
    }
    
    func getFileData(for url: URL) -> DataReturn? {
        let fileManager = FileManager.default
        print(fileManager.fileExists(atPath: url.path))
        let data = try? Data(contentsOf: url)
        
        guard let doc = data else {
            //  Utility.showAlert(message: Strings.ERROR.text, title: Strings.DOCUMENT_FORMAT_NOT_SUPPORTED.text, controller: self)
            return nil
        }
        let image = UIImage(data: doc)
        
        return DataReturn(image: image, name: url.lastPathComponent, data: doc)
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
                guard let data = image.compressTo(fileSizeInMb: 0.5, with: self.getResizer()) else {
                    DispatchQueue.main.async {
                        self.callback?(.failure(FileError.largeFile))
                    }
                    return
                }
                guard let convertedImage = UIImage(data: data),
                      convertedImage.checkIfHasMoreThanOneColor() else {
                    DispatchQueue.main.async {
                        self.reportCorruptedImageToSentry(originalImage: image, fileName: fileName)
                        self.callback?(.failure(FileError.none))
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
    
    func getResizer() -> ImageResizer {
        if Experience.isFeatureEnabled(feature: Features.ciResizer) {
            return CoreImageResizer()
        } else if Experience.isFeatureEnabled(feature: Features.cgResizer) {
            return CoreGraphicsResizer()
        } else {
            return UIKitResizer()
        }
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

public extension SLFileManager {
    @MainActor func handleFileError(_ error: SLFileManager.FileError, loadingAlert: UIAlertController?) {
        guard let vc = self.viewController else {return}
        let properties = AlertViewProperties(title: "File error", message: error.errorMessage)
        guard let loadingAlert else {
            UIAlertController.showInfoAlert(properties, on: vc)
            return
        }
        loadingAlert.dismiss(animated: true, completion: {
            UIAlertController.showInfoAlert(properties, on: vc)
        })
    }
}

struct CorruptedFileSentryEvent: MonitoringWarningEvent {
    var message: String
    var type: String
    var extra: [String : Any] = [:]
    var tags: [String : String]? = nil
    
    init() {
        self.message = "File comprimation failed"
        self.type = "File comprimation failed"
    }
}
