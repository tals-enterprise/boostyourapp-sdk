#if os(iOS)
import ImageIO
import UIKit

/// Icônes et captures des pubs : téléchargées, réduites à la taille d'affichage et gardées en cache (20 au plus).
final class IconLoader {
    /// 44 pt en @3x : icônes de la bannière
    static let bannerPixelSize: CGFloat = 132

    private let cache = NSCache<NSString, UIImage>()
    private let session: URLSession

    init() {
        cache.countLimit = 20
        session = URLSession(configuration: .default)
    }

    /// `completion` est appelé sur le thread principal (image nil en cas d'échec). `maxPixelSize` : plus grand côté
    /// de l'image gardée (interstitiel : icône et captures plus grandes).
    func load(_ urlString: String, maxPixelSize: CGFloat = IconLoader.bannerPixelSize, completion: @escaping (UIImage?) -> Void) {
        let key = "\(Int(maxPixelSize))|\(urlString)" as NSString
        if let cached = cache.object(forKey: key) {
            completion(cached)
            return
        }
        guard let url = URL(string: urlString) else {
            completion(nil)
            return
        }
        session.dataTask(with: url) { [weak self] data, _, _ in
            let image = data.flatMap { IconLoader.downsample($0, maxPixelSize: maxPixelSize) }
            DispatchQueue.main.async {
                if let image = image {
                    self?.cache.setObject(image, forKey: key)
                }
                completion(image)
            }
        }.resume()
    }

    private static func downsample(_ data: Data, maxPixelSize: CGFloat) -> UIImage? {
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions) else { return nil }
        let options = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
        ] as CFDictionary
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options) else { return nil }
        return UIImage(cgImage: image)
    }
}
#endif
