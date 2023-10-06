import Foundation
import UIKit
// import ImageIO
// import Accelerate

public extension UIImage {
    
    func convertLoadedImageToData(fileSizeInMb: Double) -> Data? {
        guard let imageData = compressTo(fileSizeInMb) else {
            return nil
        }
        return imageData
        
    }
    
    private func compressTo(_ size: Double) -> Data? {
        var fImageData: Data?
        let fromSize: CGFloat = 3000
        let step: CGFloat = 500
        var i: CGFloat = fromSize
        debugPrint("Original image dimensions: \(self.size)")

        repeat {
            fImageData = compressTo(size, biggerSizeInPixels: i)
            guard fImageData == nil else {
                return fImageData
            }
            i -= step
            
        } while i > 0
        return fImageData
    }

    private func compressTo(_ expectedSizeInMb: Double, biggerSizeInPixels: CGFloat) -> Data? {
        let image = self
        let bigerSize: CGFloat = image.size.height > image.size.width ? image.size.height : image.size.width
        let scale = calculateScale(maxSize: biggerSizeInPixels, imageSize: bigerSize)
        guard let smallImage = resized(withPercentage: scale) else { return nil }
        debugPrint("Resized image dimensions: \(smallImage.size)")
        let sizeInBytes = Int(expectedSizeInMb * 1024 * 1024)
        var needCompress = true
        var imgData: Data?
        var compressingValue: CGFloat = 1.0
        while needCompress {
                if let data: Data = smallImage.jpegData(compressionQuality: compressingValue) {
                    debugPrint("Compressed image size: \(Double(data.count) / 1024 / 1024) MB")
                    if data.count < sizeInBytes {
                        needCompress = false
                        imgData = data
                    } else {
                        if compressingValue > 0.35 {
                            compressingValue -= 0.1
                            debugPrint("Decreasing compression to \(compressingValue)")
                        } else {
                            return nil
                        }
                    }
                }
        }
        if let data = imgData {
            return data
        }
        return nil
        
    }
        
    private func calculateScale(maxSize: CGFloat, imageSize: CGFloat) -> CGFloat {
        guard maxSize < imageSize else { return 1 }
        return maxSize / imageSize
    }
    
    func resized(withPercentage percentage: CGFloat) -> UIImage? {
        let canvasSize = CGSize(width: size.width * percentage, height: size.height * percentage)
        return scaleTo(canvasSize)
    }

    func scaleTo(_ newSize: CGSize) -> UIImage? {
        autoreleasepool { () -> UIImage? in
            let renderer = UIGraphicsImageRenderer(size: newSize)
            return renderer.image { _ in
                self.draw(in: CGRect(origin: .zero, size: newSize))
            }
        }
//            UIGraphicsBeginImageContextWithOptions(newSize, false, 1.0)
//            self.draw(in: CGRect(x: 0, y: 0, width: newSize.width, height: newSize.height))
//            let newImage: UIImage? = UIGraphicsGetImageFromCurrentImageContext()
//            UIGraphicsEndImageContext()
//            return newImage
//        }
    }
}
