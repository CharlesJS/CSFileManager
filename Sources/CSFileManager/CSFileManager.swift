import CSErrors
import System

#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

public struct CSFileManager {
    public static let shared = CSFileManager()

    @available(macOS 11.0, iOS 14.0, watchOS 7.0, tvOS 14.0, macCatalyst 14.0, *)
    public var temporaryDirectory: FilePath {
        FilePath(self.temporaryDirectoryStringPath)
    }

    public var temporaryDirectoryStringPath: String {
        getenv("TMPDIR").flatMap {
            guard #available(macOS 12.0, iOS 15.0, watchOS 8.0, tvOS 15.0, macCatalyst 15.0, *), versionCheck(12) else {
                return String(cString: $0)
            }

            return String(platformString: $0)
        } ?? "/tmp"
    }

    @available(macOS 11.0, iOS 14.0, watchOS 7.0, tvOS 14.0, macCatalyst 14.0, *)
    public func createTemporaryFile(template: String? = nil) throws -> (FileDescriptor, FilePath) {
        guard #available(macOS 12.0, iOS 15.0, watchOS 8.0, tvOS 15.0, macCatalyst 15.0, *), versionCheck(12) else {
            let (fd, path) = try self.createTemporaryFileWithStringPath(template: template)

            return (FileDescriptor(rawValue: fd), FilePath(path))
        }

        let templatePath = self.temporaryDirectory.appending(template ?? "XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX")

        return try templatePath.withPlatformString {
            try self.createTemporaryFile(templatePath: $0) { fd, path in
                (FileDescriptor(rawValue: fd), FilePath(platformString: path))
            }
        }
    }

    public func createTemporaryFileWithStringPath(template: String? = nil) throws -> (Int32, String) {
        let templatePath = "\(self.temporaryDirectoryStringPath)/\(template ?? "XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX")"

        guard #available(macOS 12.0, iOS 15.0, watchOS 8.0, tvOS 15.0, macCatalyst 15.0, *), versionCheck(12) else {
            return try templatePath.withCString {
                try self.createTemporaryFile(templatePath: $0) { fd, path in
                    (fd, String(cString: path))
                }
            }
        }

        return try templatePath.withPlatformString {
            try self.createTemporaryFile(templatePath: $0) { fd, path in
                (fd, String(platformString: path))
            }
        }
    }

    private func createTemporaryFile<T>(
        templatePath: UnsafePointer<CChar>,
        handler: (Int32, UnsafePointer<CChar>) -> T
    ) throws -> T {
        let old_mask = umask(0o077)
        defer { umask(old_mask) }

        let pathLen = strlen(templatePath)
        let path = UnsafeMutablePointer<CChar>.allocate(capacity: pathLen + 1)
        defer { path.deallocate() }

        path.initialize(from: templatePath, count: pathLen + 1)

        let fd = mkstemp(path)
        guard fd >= 0 else {
            throw errno()
        }

        return handler(fd, path)
    }
}
