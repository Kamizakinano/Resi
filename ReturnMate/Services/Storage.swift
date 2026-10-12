import Foundation
import Security
import UIKit

/// Salvataggio locale cifrato (Data Protection: il file è leggibile solo con il dispositivo sbloccato).
enum Persistence {
    static var directory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("ReturnMate", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true,
                                                 attributes: [.protectionKey: FileProtectionType.complete])
        return dir
    }

    static var dataURL: URL { directory.appendingPathComponent("data.json") }

    static func encoder() -> JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.sortedKeys]
        return e
    }

    static func decoder() -> JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }

    static func load() -> AppData? {
        guard let data = try? Data(contentsOf: dataURL) else { return nil }
        return try? decoder().decode(AppData.self, from: data)
    }

    static func save(_ appData: AppData) throws {
        let data = try encoder().encode(appData)
        try data.write(to: dataURL, options: [.atomic, .completeFileProtection])
    }

    static func wipe() {
        try? FileManager.default.removeItem(at: directory)
    }
}

enum AttachmentStore {
    static var directory: URL {
        let dir = Persistence.directory.appendingPathComponent("Attachments", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true,
                                                 attributes: [.protectionKey: FileProtectionType.complete])
        return dir
    }

    static func url(for attachment: Attachment) -> URL {
        directory.appendingPathComponent(attachment.fileName)
    }

    /// Salva un'immagine ridimensionata (max 2000 px) in JPEG.
    static func saveImage(_ image: UIImage, kind: AttachmentKind) throws -> Attachment {
        let resized = image.resized(maxDimension: 2000)
        guard let data = resized.jpegData(compressionQuality: 0.8) else {
            throw CocoaError(.fileWriteUnknown)
        }
        return try saveData(data, ext: "jpg", kind: kind)
    }

    static func saveData(_ data: Data, ext: String, kind: AttachmentKind) throws -> Attachment {
        let id = UUID()
        let att = Attachment(id: id, kind: kind, fileName: "\(id.uuidString).\(ext.lowercased())")
        try data.write(to: url(for: att), options: [.atomic, .completeFileProtection])
        return att
    }

    static func loadImage(_ attachment: Attachment) -> UIImage? {
        guard attachment.isImage, let data = try? Data(contentsOf: url(for: attachment)) else { return nil }
        return UIImage(data: data)
    }

    static func delete(_ attachment: Attachment) {
        try? FileManager.default.removeItem(at: url(for: attachment))
    }
}

enum Keychain {
    private static let service = "com.returnmate.app"

    static func set(_ value: String?, for key: String) {
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
        SecItemDelete(base as CFDictionary)
        guard let value, !value.isEmpty, let data = value.data(using: .utf8) else { return }
        var add = base
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        SecItemAdd(add as CFDictionary, nil)
    }

    static func get(_ key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func deleteAll() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
        ]
        SecItemDelete(query as CFDictionary)
    }
}

extension UIImage {
    func resized(maxDimension: CGFloat) -> UIImage {
        let maxSide = max(size.width, size.height)
        guard maxSide > maxDimension else { return self }
        let scale = maxDimension / maxSide
        let newSize = CGSize(width: (size.width * scale).rounded(), height: (size.height * scale).rounded())
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: newSize, format: format).image { _ in
            draw(in: CGRect(origin: .zero, size: newSize))
        }
    }
}
