import CSErrors
import CSFileInfo
import System

#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

public struct CSFileManager {
    public enum FileType {
        case regular
        case directory
        case symbolicLink
        case fifo
        case characterSpecial
        case blockSpecial
        case socket
        case whiteout

        init?(permissionsMode: mode_t) {
            switch permissionsMode & S_IFMT {
            case S_IFREG:
                self = .regular
            case S_IFDIR:
                self = .directory
            case S_IFLNK:
                self = .symbolicLink
            case S_IFIFO:
                self = .fifo
            case S_IFCHR:
                self = .characterSpecial
            case S_IFBLK:
                self = .blockSpecial
            case S_IFSOCK:
                self = .socket
            case S_IFWHT:
                // Should not be reached in practice since this type is considered obsolete
                self = .whiteout
            default:
                // Should be unreachable unless new node types are added to the file system that we don't recognize here
                return nil
            }
        }
    }

    public struct ItemReplacementOptions: OptionSet {
        public var rawValue: UInt32
        public init(rawValue: UInt32) { self.rawValue = rawValue }

        static let usingNewMetadataOnly = ItemReplacementOptions(rawValue: 1)
        static let withoutDeletingBackupItem = ItemReplacementOptions(rawValue: 2)
    }

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

    private static let defaultTemplate = "XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX"

    @available(macOS 11.0, iOS 14.0, watchOS 7.0, tvOS 14.0, macCatalyst 14.0, *)
    public func createTemporaryFile(template t: String? = nil, suffix: String? = nil) throws -> (FileDescriptor, FilePath) {
        let template = t ?? Self.defaultTemplate

        guard #available(macOS 12.0, iOS 15.0, watchOS 8.0, tvOS 15.0, macCatalyst 15.0, *), versionCheck(12) else {
            let templatePath = String(decoding: self.temporaryDirectory) + "/" + template

            return try templatePath.withCString {
                try self.createTemporaryFile(templatePath: $0, suffix: suffix) { fd, path in
                    (FileDescriptor(rawValue: fd), FilePath(String(cString: path)))
                }
            }
        }

        let templatePath = self.temporaryDirectory.appending(template)

        return try templatePath.withPlatformString {
            try self.createTemporaryFile(templatePath: $0, suffix: suffix) { fd, path in
                (FileDescriptor(rawValue: fd), FilePath(platformString: path))
            }
        }
    }

    public func createTemporaryFileWithStringPath(template: String? = nil, suffix: String? = nil) throws -> (Int32, String) {
        guard #available(macOS 11.0, iOS 14.0, watchOS 7.0, tvOS 14.0, macCatalyst 14.0, *), versionCheck(11) else {
            var tempDir = self.temporaryDirectoryStringPath

            if tempDir.last != "/" {
                tempDir.append("/")
            }

            let templatePath = "\(tempDir)\(template ?? Self.defaultTemplate)"

            return try templatePath.withCString {
                try self.createTemporaryFile(templatePath: $0, suffix: suffix) { fd, path in
                    (fd, String(cString: path))
                }
            }
        }

        let (desc, path) = try self.createTemporaryFile(template: template, suffix: suffix)

        guard #available(macOS 12.0, iOS 15.0, watchOS 8.0, tvOS 15.0, macCatalyst 15.0, *), versionCheck(12) else {
            return (desc.rawValue, String(decoding: path))
        }

        return (desc.rawValue, path.string)
    }

    private func createTemporaryFile<T>(
        templatePath: UnsafePointer<CChar>,
        suffix: UnsafePointer<CChar>?,
        handler: (Int32, UnsafePointer<CChar>) -> T
    ) throws -> T {
        let old_mask = umask(0o077)
        defer { umask(old_mask) }

        let pathLen = strlen(templatePath)
        let suffixLen = suffix.map { strlen($0) } ?? 0
        let path = UnsafeMutablePointer<CChar>.allocate(capacity: pathLen + suffixLen + 1)
        defer { path.deallocate() }

        path.initialize(from: templatePath, count: pathLen + 1)

        let fd: Int32
        if let suffix {
            (path + pathLen).initialize(from: suffix, count: suffixLen + 1)

            fd = mkstemps(path, Int32(suffixLen))
        } else {
            fd = mkstemp(path)
        }

        guard fd >= 0 else {
            throw errno()
        }

        return handler(fd, path)
    }

    @available(macOS 11.0, iOS 14.0, watchOS 7.0, tvOS 14.0, macCatalyst 14.0, *)
    public func itemIsReachable(at path: FilePath) throws -> Bool {
        do {
            _ = try self.typeOfItem(at: path)
            return true
        } catch {
            if error.isFileNotFoundError {
                return false
            }

            throw error
        }
    }

    public func itemIsReachable(atPath path: String) throws -> Bool {
        do {
            _ = try self.typeOfItem(atPath: path)
            return true
        } catch {
            if error.isFileNotFoundError {
                return false
            }

            throw error
        }
    }

    @available(macOS 11.0, iOS 14.0, watchOS 7.0, tvOS 14.0, macCatalyst 14.0, *)
    public func typeOfItem(at path: FilePath) throws -> FileType {
        guard #available(macOS 12.0, iOS 15.0, watchOS 8.0, tvOS 15.0, macCatalyst 15.0, *), versionCheck(12) else {
            return try path.withCString { try self.typeOfItem(path: String(decoding: path), cPath: $0) }
        }

        return try path.withPlatformString { try self.typeOfItem(path: path.string, cPath: $0) }
    }

    @available(macOS 11.0, iOS 14.0, watchOS 7.0, tvOS 14.0, macCatalyst 14.0, *)
    public func typeOfItem(fileDescriptor: FileDescriptor) throws -> FileType {
        try self.typeOfItem(fileDescriptor: fileDescriptor.rawValue)
    }

    public func typeOfItem(atPath path: String) throws -> FileType {
        guard #available(macOS 11.0, iOS 14.0, watchOS 7.0, tvOS 14.0, macCatalyst 14.0, *), versionCheck(11) else {
            return try path.withCString { try self.typeOfItem(path: path, cPath: $0) }
        }

        return try self.typeOfItem(at: FilePath(path))
    }

    public func typeOfItem(fileDescriptor: Int32) throws -> FileType {
        let info = try callPOSIXFunction(expect: .zero) { fstat(fileDescriptor, $0) }

        guard let type = FileType(permissionsMode: info.st_mode) else {
            // Should be unreachable unless new node types are added to the file system that we don't recognize here
            throw errno(EFTYPE)
        }

        return type
    }

    private func typeOfItem(path: String, cPath: UnsafePointer<Int8>) throws -> FileType {
        let info = try callPOSIXFunction(expect: .zero, path: path) { lstat(cPath, $0) }

        guard let type = FileType(permissionsMode: info.st_mode) else {
            // Should be unreachable unless new node types are added to the file system that we don't recognize here
            throw errno(EFTYPE, path: path)
        }

        return type
    }

    @available(macOS 11.0, iOS 14.0, watchOS 7.0, tvOS 14.0, macCatalyst 14.0, *)
    public func contentsOfDirectory(at path: FilePath, recursively: Bool = false) throws -> some Sequence<FilePath> {
        guard #available(macOS 12.0, iOS 15.0, watchOS 8.0, tvOS 15.0, macCatalyst 15.0, *), versionCheck(12) else {
            let pathString = String(decoding: path)

            return POSIXDirectoryEnumerator(path: pathString, recursive: recursively).lazy.map {
                FilePath("\(pathString)/\($0)")
            }
        }

        return POSIXDirectoryEnumerator(path: path.string, recursive: recursively).lazy.map { path.appending($0) }
    }

    public func contentsOfDirectory(atPath path: String, recursively: Bool = false) throws -> some Sequence<String> {
        POSIXDirectoryEnumerator(path: path, recursive: recursively)
    }

    @available(macOS 11.0, iOS 14.0, watchOS 7.0, tvOS 14.0, macCatalyst 14.0, *)
    public func createDirectory(at path: FilePath, mode: mode_t = 0o755, recursively: Bool = false) throws {
        do {
            guard #available(macOS 12.0, iOS 15.0, watchOS 8.0, tvOS 15.0, macCatalyst 15.0, *), versionCheck(12) else {
                try path.withCString { cPath in
                    _ = try callPOSIXFunction(expect: .zero, path: path) { mkdir(cPath, mode) }
                }

                return
            }

            try path.withPlatformString { cPath in
                _ = try callPOSIXFunction(expect: .zero, path: path) { mkdir(cPath, mode) }
            }
        } catch {
            if recursively, error.isFileNotFoundError {
                let parent = if #available(macOS 12.0, iOS 15.0, watchOS 8.0, tvOS 15.0, macCatalyst 15.0, *), 
                    versionCheck(12) {
                    path.removingLastComponent()
                } else {
                    try FilePath(self.parentPath(forPath: String(decoding: path)))
                }

                try self.createDirectory(at: parent, mode: mode, recursively: true)
                try self.createDirectory(at: path, mode: mode, recursively: false)
                return
            }

            throw error
        }
    }

    public func createDirectory(atPath path: String, mode: mode_t = 0o755, recursively: Bool = false) throws {
        guard #available(macOS 11.0, iOS 14.0, watchOS 7.0, tvOS 14.0, macCatalyst 14.0, *), versionCheck(11) else {
            do {
                _ = try callPOSIXFunction(expect: .zero, path: path) { mkdir(path, mode) }
            } catch {
                if recursively, error.isFileNotFoundError {
                    let parent = try self.parentPath(forPath: path)

                    try self.createDirectory(atPath: parent, mode: mode, recursively: true)
                    try self.createDirectory(atPath: path, mode: mode, recursively: false)
                    return
                }

                throw error
            }

            return
        }

        try self.createDirectory(at: FilePath(path), mode: mode, recursively: recursively)
    }

    @available(macOS, obsoleted: 12.0)
    @available(iOS, obsoleted: 15.0)
    @available(watchOS, obsoleted: 8.0)
    @available(tvOS, obsoleted: 15.0)
    @available(macCatalyst, obsoleted: 15.0)
    @available(visionOS, unavailable)
    private func parentPath(forPath path: String) throws -> String {
        let bytes = try [UInt8](unsafeUninitializedCapacity: Int(MAXPATHLEN) + 1) { buffer, count in
            count = strlen(try callPOSIXFunction(path: path) { dirname_r(path, buffer.baseAddress) })
        }

        return String(decoding: bytes, as: UTF8.self)
    }

    @available(macOS 11.0, iOS 14.0, watchOS 7.0, tvOS 14.0, macCatalyst 14.0, *)
    public func removeItem(at path: FilePath, recursively: Bool = false) throws {
        let isDirectory = try self.typeOfItem(at: path) == .directory

        if isDirectory && recursively {
            for eachChild in try self.contentsOfDirectory(at: path, recursively: false) {
                try self.removeItem(at: eachChild, recursively: true)
            }
        }

        guard #available(macOS 12.0, iOS 15.0, watchOS 8.0, tvOS 15.0, macCatalyst 15.0, *), versionCheck(12) else {
            try self.removeItem(path: String(decoding: path), isDirectory: isDirectory)
            return
        }

        try self.removeItem(path: path.string, isDirectory: isDirectory)
    }

    public func removeItem(atPath path: String, recursively: Bool = false) throws {
        guard #available(macOS 11.0, iOS 14.0, watchOS 7.0, tvOS 14.0, macCatalyst 14.0, *), versionCheck(11) else {
            let isDirectory = try self.typeOfItem(atPath: path) == .directory

            if isDirectory && recursively {
                for eachChild in try self.contentsOfDirectory(atPath: path, recursively: false) {
                    try self.removeItem(atPath: "\(path)/\(eachChild)", recursively: true)
                }
            }

            try self.removeItem(path: path, isDirectory: isDirectory)

            return
        }

        try self.removeItem(at: FilePath(path), recursively: recursively)
    }

    private func removeItem(path: String, isDirectory: Bool) throws {
        try callPOSIXFunction(expect: .zero, path: path) { isDirectory ? rmdir(path) : unlink(path) }
    }

    @available(macOS 11.0, iOS 14.0, watchOS 7.0, tvOS 14.0, macCatalyst 14.0, *)
    public func replaceItem(
        at originalPath: FilePath,
        withItemAt newPath: FilePath,
        options: ItemReplacementOptions = []
    ) throws {
        let originalInfo = try FileInfo(path: originalPath, keys: [.volumeUUID, .volumeCapabilities])
        let newInfo = try FileInfo(path: originalPath, keys: [.volumeUUID, .volumeCapabilities])

        guard #available(macOS 12.0, iOS 15.0, watchOS 8.0, tvOS 15.0, macCatalyst 15.0, *), versionCheck(12) else {
            try originalPath.withCString { orig in
                try newPath.withCString { new in
                    try self.replaceItem(
                        path: String(describing: originalPath),
                        originalCPath: orig,
                        originalInfo: originalInfo,
                        newCPath: new,
                        newInfo: newInfo,
                        options: options
                    )
                }
            }

            return
        }

        try originalPath.withPlatformString { orig in
            try newPath.withPlatformString { new in
                try self.replaceItem(
                    path: originalPath.string,
                    originalCPath: orig,
                    originalInfo: originalInfo,
                    newCPath: new,
                    newInfo: newInfo,
                    options: options
                )
            }
        }
    }

    public func replaceItem(
        atPath originalPath: String,
        withItemAtPath newPath: String,
        options: ItemReplacementOptions = []
    ) throws {
        let originalInfo = try FileInfo(path: originalPath, keys: [.volumeUUID, .volumeCapabilities])
        let newInfo = try FileInfo(path: originalPath, keys: [.volumeUUID, .volumeCapabilities])

        guard #available(macOS 11.0, iOS 14.0, watchOS 7.0, tvOS 14.0, macCatalyst 14.0, *), versionCheck(11) else {
            try originalPath.withCString { orig in
                try newPath.withCString { new in
                    try self.replaceItem(
                        path: originalPath,
                        originalCPath: orig,
                        originalInfo: originalInfo,
                        newCPath: new,
                        newInfo: newInfo,
                        options: options
                    )
                }
            }

            return
        }

        try self.replaceItem(at: FilePath(originalPath), withItemAt: FilePath(newPath), options: options)
   }

    private func replaceItem(
        path: String,
        originalCPath: UnsafePointer<CChar>,
        originalInfo: FileInfo,
        newCPath: UnsafePointer<CChar>,
        newInfo: FileInfo,
        options: ItemReplacementOptions
    ) throws {
        try self._replaceItem(
            path: path,
            originalCPath: originalCPath,
            originalInfo: originalInfo,
            newCPath: newCPath,
            newInfo: newInfo,
            options: options
        )

        if !options.contains(.withoutDeletingBackupItem) {
            try callPOSIXFunction(expect: .zero) { unlink(newCPath) }
        }
    }

    private func _replaceItem(
        path: String,
        originalCPath: UnsafePointer<CChar>,
        originalInfo: FileInfo,
        newCPath: UnsafePointer<CChar>,
        newInfo: FileInfo,
        options: ItemReplacementOptions
    ) throws {
        if var originalUUID = originalInfo.volumeUUID,
           var newUUID = newInfo.volumeUUID,
           uuid_compare(&originalUUID, &newUUID) == 0,
           let capabilities = originalInfo.volumeNativeCapabilities {
            if capabilities.interfaces.contains(.renameSwap) {
                try self.renameSwap(path: path, originalCPath: originalCPath, newCPath: newCPath, options: options)
                return
            }

            if capabilities.interfaces.contains(.exchangedata) {
                try self.exchangeFiles(path: path, originalCPath: originalCPath, newCPath: newCPath, options: options)
                return
            }
        }

        try self.manualReplaceItem(path: path, originalCPath: originalCPath, newCPath: newCPath, options: options)
    }

    private func renameSwap(
        path: String,
        originalCPath: UnsafePointer<CChar>,
        newCPath: UnsafePointer<CChar>,
        options: ItemReplacementOptions
    ) throws {
        if !options.contains(.usingNewMetadataOnly) {
            try self.copyMetadata(path: path, from: originalCPath, to: newCPath, swap: false, preserveFrom: true)
        }

        _ = try callPOSIXFunction(expect: .zero, path: path) {
            renamex_np(newCPath, originalCPath, UInt32(bitPattern: RENAME_SWAP))
        }
    }

    private func exchangeFiles(
        path: String,
        originalCPath: UnsafePointer<CChar>,
        newCPath: UnsafePointer<CChar>,
        options: ItemReplacementOptions
    ) throws {
        _ = try callPOSIXFunction(expect: .zero, path: path) {
            exchangedata(newCPath, originalCPath, 0)
        }

        if options.contains(.usingNewMetadataOnly) {
            let preserveBackup = options.contains(.withoutDeletingBackupItem)

            let origFd = try callPOSIXFunction(expect: .nonNegative) { open(originalCPath, O_RDWR) }
            defer { close(origFd) }

            let newFd = try callPOSIXFunction(expect: .nonNegative) { open(newCPath, O_RDWR) }
            defer { close(newFd) }

            let (tempFd, tempPath) = preserveBackup ? try self.createTemporaryFileWithStringPath() : (-1, "")
            defer {
                if tempFd >= 0 {
                    close(tempFd)
                    try? self.removeItem(atPath: tempPath)
                }
            }

            if preserveBackup {
                try callPOSIXFunction(expect: .zero, path: path) {
                    fcopyfile(origFd, tempFd, nil, copyfile_flags_t(COPYFILE_XATTR))
                }
            }

            try callPOSIXFunction(expect: .zero, path: path) {
                fcopyfile(newFd, origFd, nil, copyfile_flags_t(COPYFILE_XATTR))
            }

            if preserveBackup {
                try callPOSIXFunction(expect: .zero, path: path) {
                    fcopyfile(tempFd, newFd, nil, copyfile_flags_t(COPYFILE_XATTR))
                }
            }
        } else {
            let preserveFrom = options.contains(.withoutDeletingBackupItem)
            try self.copyMetadata(path: path, from: newCPath, to: originalCPath, swap: true, preserveFrom: preserveFrom)
        }
    }

    private func manualReplaceItem(
        path: String,
        originalCPath: UnsafePointer<CChar>,
        newCPath: UnsafePointer<CChar>,
        options: ItemReplacementOptions
    ) throws {
        if !options.contains(.usingNewMetadataOnly) {
            try self.copyMetadata(path: path, from: originalCPath, to: newCPath, swap: false, preserveFrom: true)
        }

        let len = strlen(newCPath)
        let uuidLen = MemoryLayout<uuid_string_t>.size
        let tempPath = UnsafeMutablePointer<CChar>.allocate(capacity: len + 6 + uuidLen + 1)
        defer { tempPath.deallocate() }

        let uuid = UnsafeMutablePointer<UInt8>.allocate(capacity: MemoryLayout<uuid_t>.stride)
        defer { uuid.deallocate() }
        uuid_generate(uuid)

        let uuidString = UnsafeMutablePointer<UInt8>.allocate(capacity: uuidLen)
        defer { uuidString.deallocate() }
        uuid_unparse(uuid, uuidString)

        strncpy(tempPath, newCPath, len)
        strncpy(tempPath + len, ".swap.", 6)
        strncpy(tempPath + len + 6, uuidString, uuidLen)
        tempPath[len + 6 + uuidLen] = 0

        try callPOSIXFunction(expect: .zero, path: String(cString: tempPath)) { rename(originalCPath, tempPath) }
        try callPOSIXFunction(expect: .zero, path: path) { rename(newCPath, originalCPath) }
        try callPOSIXFunction(expect: .zero, path: path) { rename(tempPath, newCPath) }
    }

    private func copyMetadata(
        path: String,
        from: UnsafePointer<CChar>,
        to: UnsafePointer<CChar>,
        swap: Bool,
        preserveFrom: Bool
    ) throws {
        let get: (UnsafePointer<CChar>) throws -> [ExtendedAttribute]
        let set: (Set<ExtendedAttribute>, UnsafePointer<CChar>) throws -> Void
        let remove: ([String], UnsafePointer<CChar>) throws -> Void

        if #available(macOS 12.0, iOS 15.0, watchOS 8.0, tvOS 15.0, macCatalyst 15.0, *), versionCheck(12) {
            get = { try ExtendedAttribute.list(at: FilePath(platformString: $0), options: .noTraverseLink) }
            set = { try ExtendedAttribute.write($0, to: FilePath(platformString: $1), options: .noTraverseLink) }
            remove = { try ExtendedAttribute.remove(keys: $0, at: FilePath(platformString: $1), options: .noTraverseLink) }
        } else if #available(macOS 11.0, iOS 14.0, watchOS 7.0, tvOS 14.0, macCatalyst 14.0, *), versionCheck(11) {
            get = { try ExtendedAttribute.list(at: FilePath(String(cString: $0)), options: .noTraverseLink) }
            set = { try ExtendedAttribute.write($0, to: FilePath(String(cString: $1)), options: .noTraverseLink) }
            remove = { try ExtendedAttribute.remove(keys: $0, at: FilePath(String(cString: $1)), options: .noTraverseLink) }
        } else {
            get = { try ExtendedAttribute.list(atPath: String(cString: $0), options: .noTraverseLink) }
            set = { try ExtendedAttribute.write($0, toPath: String(cString: $1), options: .noTraverseLink) }
            remove = { try ExtendedAttribute.remove(keys: $0, atPath: String(cString: $1), options: .noTraverseLink) }
        }

        let srcAttrs = try Set(get(from))
        let dstAttrs = try Set(get(to))

        let newDstAttrs: Set<ExtendedAttribute>
        let newSrcAttrs: Set<ExtendedAttribute>?
        if swap {
            newDstAttrs = srcAttrs
            newSrcAttrs = dstAttrs
        } else {
            newDstAttrs = srcAttrs.union(dstAttrs)
            newSrcAttrs = nil
        }

        try set(newDstAttrs, to)

        if let newSrcAttrs, preserveFrom {
            if !newSrcAttrs.isEmpty {
                try set(newSrcAttrs, from)
            }

            let attrsToRemove = srcAttrs.subtracting(newSrcAttrs)
            if !attrsToRemove.isEmpty {
                try remove(attrsToRemove.map(\.key), from)
            }
        }
    }
}
