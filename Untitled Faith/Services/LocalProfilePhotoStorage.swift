import CryptoKit
import UIKit

/// One thumbnail per account and backend, stored only on this device.
struct LocalProfilePhotoStorage {
    let directory: URL
    private var file: URL { directory.appendingPathComponent("photo.jpg") }

    init(namespace: String, root: URL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]) {
        let key = SHA256.hash(data: Data(namespace.utf8)).map { String(format: "%02x", $0) }.joined()
        directory = root.appendingPathComponent("ProfilePhotos", isDirectory: true).appendingPathComponent(key, isDirectory: true)
    }

    func load() throws -> UIImage? {
        guard FileManager.default.fileExists(atPath: file.path) else { return nil }
        guard let image = UIImage(data: try Data(contentsOf: file)) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        return image
    }

    func save(_ image: UIImage) throws {
        guard let data = image.jpegData(compressionQuality: 0.9) else {
            throw CocoaError(.fileWriteUnknown)
        }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
            attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication])
        var folder = directory
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try folder.setResourceValues(values)
        try data.write(to: file, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    func delete() throws {
        if FileManager.default.fileExists(atPath: directory.path) {
            try FileManager.default.removeItem(at: directory)
        }
    }
}
