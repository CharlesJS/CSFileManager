import CSErrors
import CSFileInfo

#if canImport(Darwin)
import Darwin
#else
import Glibc
import CSFileManager_CShims
#endif

#if canImport(SystemPackage)
import SystemPackage
#else
import System
#endif

public struct CSFileManager: Sendable {
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
#if canImport(Darwin)
            case S_IFWHT:
                // Should not be reached in practice since this type is considered obsolete
                self = .whiteout
#endif
            default:
                // Should be unreachable unless new node types are added to the file system that we don't recognize here
                return nil
            }
        }
    }

    public struct ItemReplacementOptions: OptionSet, Sendable {
        public var rawValue: UInt32
        public init(rawValue: UInt32) { self.rawValue = rawValue }

        static let usingNewMetadataOnly = ItemReplacementOptions(rawValue: 1)
        static let withoutDeletingBackupItem = ItemReplacementOptions(rawValue: 2)
    }

    public static let shared = CSFileManager()

    @available(macOS 11.0, iOS 14.0, watchOS 7.0, tvOS 14.0, macCatalyst 14.0, *)
    public var rootDirectory: FilePath { "/" }
    public var rootDirectoryStringPath: String { "/" }

    @available(macOS 11.0, iOS 14.0, watchOS 7.0, tvOS 14.0, macCatalyst 14.0, *)
    public var homeDirectoryForCurrentUser: FilePath {
        try! User.current.homeDirectory!
    }

    public var homeDirectoryStringPathForCurrentUser: String {
        try! User.current.homeDirectoryStringPath!
    }

    @available(macOS 11.0, iOS 14.0, watchOS 7.0, tvOS 14.0, macCatalyst 14.0, *)
    public var temporaryDirectory: FilePath {
        guard let tmpDir = getenv("TMPDIR"), strlen(tmpDir) != 0 else {
            return "/tmp"
        }

        return FilePath(platformString: tmpDir)
    }

#if canImport(Darwin)
    public var temporaryDirectoryStringPath: String {
        guard let tmpDir = getenv("TMPDIR"), strlen(tmpDir) != 0 else {
            return "/tmp"
        }

        guard #available(macOS 12.0, iOS 15.0, watchOS 8.0, tvOS 15.0, macCatalyst 15.0, *), versionCheck(12) else {
            return String(cString: tmpDir)
        }

        return String(platformString: tmpDir)
    }
#endif

    private func generateUUID() -> String {
        withUnsafeTemporaryAllocation(of: CChar.self, capacity: 37) {
            let ptr = $0.baseAddress!

            var uuid = uuid_t(0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
            uuid_generate(&uuid)
            uuid_unparse(&uuid, ptr)

            return String(cString: ptr)
        }
    }

    private static let defaultTemplate = "XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX"

    @available(macOS 11.0, iOS 14.0, watchOS 7.0, tvOS 14.0, macCatalyst 14.0, *)
    public func createTemporaryFile(
        directory: FilePath? = nil,
        template t: String? = nil,
        suffix: String? = nil
    ) throws -> (FileDescriptor, FilePath) {
        let tempDir = directory ?? self.temporaryDirectory
        let template = t ?? Self.defaultTemplate

#if canImport(Darwin)
        guard #available(macOS 12.0, iOS 15.0, watchOS 8.0, tvOS 15.0, macCatalyst 15.0, *), versionCheck(12) else {
            let templatePath = String(decoding: tempDir) + "/" + template

            return try templatePath.withCString {
                try self.createTemporaryFile(templatePath: $0, suffix: suffix) { fd, path in
                    (FileDescriptor(rawValue: fd), FilePath(String(cString: path)))
                }
            }
        }
#endif

        let templatePath = tempDir.appending(template)

        return try templatePath.withPlatformString {
            try self.createTemporaryFile(templatePath: $0, suffix: suffix) { fd, path in
                (FileDescriptor(rawValue: fd), FilePath(platformString: path))
            }
        }
    }

#if canImport(Darwin)
    public func createTemporaryFileWithStringPath(
        directory: String? = nil,
        template: String? = nil,
        suffix: String? = nil
    ) throws -> (Int32, String) {
        guard #available(macOS 11.0, iOS 14.0, watchOS 7.0, tvOS 14.0, macCatalyst 14.0, *), versionCheck(11) else {
            var tempDir = directory ?? self.temporaryDirectoryStringPath

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

        let (desc, path) = try self.createTemporaryFile(
            directory: directory.map { FilePath($0) },
            template: template,
            suffix: suffix
        )

        guard #available(macOS 12.0, iOS 15.0, watchOS 8.0, tvOS 15.0, macCatalyst 15.0, *), versionCheck(12) else {
            return (desc.rawValue, String(decoding: path))
        }

        return (desc.rawValue, path.string)
    }
#endif

    @available(macOS 11.0, iOS 14.0, watchOS 7.0, tvOS 14.0, macCatalyst 14.0, *)
    public func createItemReplacementDirectory(for destination: FilePath? = nil, mode: mode_t = 0o755) throws -> FilePath {
        let directory = try self.getItemReplacementDirectory(for: destination)

        try self.createDirectory(at: directory, mode: mode, recursively: true)

        return directory
    }

#if canImport(Darwin)
    public func createItemReplacementDirectory(forPath destination: String? = nil, mode: mode_t = 0o755) throws -> String {
        let directory = try self.getItemReplacementDirectory(for: destination)

        try self.createDirectory(atPath: directory, mode: mode, recursively: true)

        return directory
    }
#endif

    private func generateItemReplacementDirectoryName() -> String {
        "CSFileManager_ItemReplacement_\(self.generateUUID())"
    }

    @available(macOS 11.0, iOS 14.0, watchOS 7.0, tvOS 14.0, macCatalyst 14.0, *)
    private func getItemReplacementDirectory(for destination: FilePath?) throws -> FilePath {
#if canImport(Darwin)
        guard #available(macOS 12.0, iOS 15.0, watchOS 8.0, tvOS 15.0, macCatalyst 15.0, *), versionCheck(12) else {
            return try FilePath(self.getItemReplacementDirectory(for: destination.map { String(describing: $0) }))
        }
#endif

        let tempPath = self.temporaryDirectory

        if let destination,
           let tempVolume = try FileInfo(at: tempPath, keys: .fileSystemID).fileSystemID,
           try self.getFileSystemID(for: destination) != tempVolume {
            return destination.removingLastComponent().appending(self.generateItemReplacementDirectoryName())
        }

        return tempPath.appending(self.generateItemReplacementDirectoryName())
    }

    private func getFileSystemID(for path: FilePath) throws -> FileInfo.FileSystemID? {
        do {
            return try FileInfo(at: path, keys: .fileSystemID).fileSystemID
        } catch {
            if error.isFileNotFoundError {
                return try self.getFileSystemID(for: path.removingLastComponent())
            } else {
                throw error
            }
        }
    }

#if canImport(Darwin)
    private func getItemReplacementDirectory(for destination: String?) throws -> String {
        guard #available(macOS 12.0, iOS 15.0, watchOS 8.0, tvOS 15.0, macCatalyst 15.0, *), versionCheck(12) else {
            let tempPath = self.temporaryDirectoryStringPath

            if let destination,
               let tempVolume = (try? FileInfo(atPath: tempPath, keys: .fileSystemID))?.fileSystemID,
               try self.getFileSystemID(forPath: destination) != tempVolume {
                let parent = destination.lastIndex(of: "/").map { destination[..<$0] } ?? tempPath[...]

                return "\(parent)/\(self.generateItemReplacementDirectoryName())"
            }

            return "\(tempPath)/\(self.generateItemReplacementDirectoryName())"
        }

        return try self.getItemReplacementDirectory(for: destination.map { FilePath($0) }).string
    }

    private func getFileSystemID(forPath path: String) throws -> FileInfo.FileSystemID? {
        do {
            return try FileInfo(atPath: path, keys: .fileSystemID).fileSystemID
        } catch {
            if error.isFileNotFoundError, let slashRange = path.lastIndex(of: "/") {
                return try self.getFileSystemID(forPath: String(path[..<slashRange]))
            } else {
                throw error
            }
        }
    }
#endif

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

#if canImport(Darwin)
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
#endif

    @available(macOS 11.0, iOS 14.0, watchOS 7.0, tvOS 14.0, macCatalyst 14.0, *)
    public func typeOfItem(at path: FilePath) throws -> FileType {
#if canImport(Darwin)
        guard #available(macOS 12.0, iOS 15.0, watchOS 8.0, tvOS 15.0, macCatalyst 15.0, *), versionCheck(12) else {
            return try path.withCString { try self.typeOfItem(path: String(decoding: path), cPath: $0) }
        }
#endif

        return try path.withPlatformString { try self.typeOfItem(path: path.string, cPath: $0) }
    }

    @available(macOS 11.0, iOS 14.0, watchOS 7.0, tvOS 14.0, macCatalyst 14.0, *)
    public func typeOfItem(fileDescriptor: FileDescriptor) throws -> FileType {
        try self.typeOfItem(fileDescriptor: fileDescriptor.rawValue)
    }

#if canImport(Darwin)
    public func typeOfItem(atPath path: String) throws -> FileType {
        guard #available(macOS 11.0, iOS 14.0, watchOS 7.0, tvOS 14.0, macCatalyst 14.0, *), versionCheck(11) else {
            return try path.withCString { try self.typeOfItem(path: path, cPath: $0) }
        }

        return try self.typeOfItem(at: FilePath(path))
    }
#endif

    public func typeOfItem(fileDescriptor: Int32) throws -> FileType {
        let info = try callPOSIXFunction(expect: .zero) { fstat(fileDescriptor, $0) }

        guard let type = FileType(permissionsMode: info.st_mode) else {
            // Should be unreachable unless new node types are added to the file system that we don't recognize here
#if canImport(Darwin)
            throw errno(EFTYPE)
#else
            throw errno(EINVAL)
#endif
        }

        return type
    }

    private func typeOfItem(path: String, cPath: UnsafePointer<CChar>) throws -> FileType {
        let info = try callPOSIXFunction(expect: .zero, path: path) { lstat(cPath, $0) }

        guard let type = FileType(permissionsMode: info.st_mode) else {
            // Should be unreachable unless new node types are added to the file system that we don't recognize here
#if canImport(Darwin)
            throw errno(EFTYPE, path: path)
#else
            throw errno(EINVAL, path: path)
#endif
        }

        return type
    }

    @available(macOS 11.0, iOS 14.0, watchOS 7.0, tvOS 14.0, macCatalyst 14.0, *)
    public func contentsOfDirectory(at path: FilePath, recursively: Bool = false) throws -> some Sequence<FilePath> {
#if canImport(Darwin)
        guard #available(macOS 12.0, iOS 15.0, watchOS 8.0, tvOS 15.0, macCatalyst 15.0, *), versionCheck(12) else {
            let pathString = String(decoding: path)

            return POSIXDirectoryEnumerator(path: pathString, recursive: recursively).lazy.map {
                FilePath("\(pathString)/\($0)")
            }
        }
#endif

        return POSIXDirectoryEnumerator(path: path.string, recursive: recursively).lazy.map { path.appending($0) }
    }

#if canImport(Darwin)
    public func contentsOfDirectory(atPath path: String, recursively: Bool = false) throws -> some Sequence<String> {
        POSIXDirectoryEnumerator(path: path, recursive: recursively)
    }
#endif

    @available(macOS 11.0, iOS 14.0, watchOS 7.0, tvOS 14.0, macCatalyst 14.0, *)
    public func createDirectory(at path: FilePath, mode: mode_t = 0o755, recursively: Bool = false) throws {
        do {
#if canImport(Darwin)
            guard #available(macOS 12.0, iOS 15.0, watchOS 8.0, tvOS 15.0, macCatalyst 15.0, *), versionCheck(12) else {
                try path.withCString { cPath in
                    _ = try callPOSIXFunction(expect: .zero, path: path) { mkdir(cPath, mode) }
                }

                return
            }
#endif

            try path.withPlatformString { cPath in
                _ = try callPOSIXFunction(expect: .zero, path: path) { mkdir(cPath, mode) }
            }
        } catch {
            if recursively, error.isFileNotFoundError {
#if canImport(Darwin)
                let parent = if #available(macOS 12.0, iOS 15.0, watchOS 8.0, tvOS 15.0, macCatalyst 15.0, *),
                    versionCheck(12) {
                    path.removingLastComponent()
                } else {
                    try FilePath(self.parentPath(forPath: String(decoding: path)))
                }
#else
                let parent = path.removingLastComponent()
#endif

                try self.createDirectory(at: parent, mode: mode, recursively: true)
                try self.createDirectory(at: path, mode: mode, recursively: false)
                return
            }

            throw error
        }
    }

#if canImport(Darwin)
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

    private func parentPath(forPath path: String) throws -> String {
        let bytes = try [UInt8](unsafeUninitializedCapacity: Int(MAXPATHLEN) + 1) { buffer, count in
            count = strlen(try callPOSIXFunction(path: path) {
                dirname_r(path, buffer.baseAddress)
            })
        }

        return String(decoding: bytes, as: UTF8.self)
    }
#endif

    @available(macOS 11.0, iOS 14.0, watchOS 7.0, tvOS 14.0, macCatalyst 14.0, *)
    public func targetOfSymbolicLink(at path: FilePath) throws -> FilePath {
#if canImport(Darwin)
        guard #available(macOS 12.0, iOS 15.0, watchOS 8.0, tvOS 15.0, macCatalyst 15.0, *), versionCheck(12) else {
            let target = try path.withCString { cPath in
                try String(unsafeUninitializedCapacity: Int(PATH_MAX) + 1) {
                    try $0.withMemoryRebound(to: CChar.self) {
                        try self.getSymlinkTarget(path: String(describing: path), cPath: cPath, buffer: $0)
                    }
                }
            }

            return FilePath(target)
        }
#endif

        return try path.withPlatformString { cPath in
            try withUnsafeTemporaryAllocation(of: CChar.self, capacity: Int(PATH_MAX) + 1) { buffer in
                let len = try self.getSymlinkTarget(
                    path: path.string,
                    cPath: cPath,
                    buffer: UnsafeMutableBufferPointer(rebasing: buffer.dropLast())
                )

                buffer[len] = 0

                return FilePath(platformString: buffer.baseAddress!)
            }
        }
    }

    @available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, macCatalyst 16.0, *)
    public func targetOfSymbolicLink(at file: FileDescriptor) throws -> FilePath {
#if canImport(Darwin)
        try withUnsafeTemporaryAllocation(of: CChar.self, capacity: Int(PATH_MAX) + 1) { buffer in
            let len = try callPOSIXFunction(expect: .nonNegative) {
                freadlink(file.rawValue, buffer.baseAddress, buffer.count - 1)
            }
            buffer[len] = 0

            return FilePath(platformString: buffer.baseAddress!)
        }
#else
        try self.targetOfSymbolicLink(at: FilePath("/proc/self/fd/\(file.rawValue)"))
#endif
    }

    private func getSymlinkTarget(
        path: String,
        cPath: UnsafePointer<CChar>,
        buffer: UnsafeMutableBufferPointer<CChar>
    ) throws -> Int {
        guard let baseAddress = buffer.baseAddress else { return 0 }

        return try callPOSIXFunction(expect: .nonNegative, path: path) {
            readlink(cPath, baseAddress, buffer.count)
        }
    }

    @available(macOS 11.0, iOS 14.0, watchOS 7.0, tvOS 14.0, macCatalyst 14.0, *)
    public func createSymbolicLink(at path: FilePath, withTarget targetPath: FilePath) throws {
#if canImport(Darwin)
        guard #available(macOS 12.0, iOS 15.0, watchOS 8.0, tvOS 15.0, macCatalyst 15.0, *), versionCheck(12) else {
            try path.withCString { cPath in
                try targetPath.withCString { targetCPath in
                    try self.createSymbolicLink(path: String(describing: path), cPath: cPath, targetCPath: targetCPath)
                }
            }

            return
        }
#endif

        try path.withPlatformString { cPath in
            try targetPath.withPlatformString { targetCPath in
                try self.createSymbolicLink(path: path.string, cPath: cPath, targetCPath: targetCPath)
            }
        }
    }

#if canImport(Darwin)
    public func createSymbolicLink(atPath path: String, withTargetPath targetPath: String) throws {
        guard #available(macOS 12.0, iOS 15.0, watchOS 8.0, tvOS 15.0, macCatalyst 15.0, *), versionCheck(12) else {
            try path.withCString { cPath in
                try targetPath.withCString { targetCPath in
                    try self.createSymbolicLink(path: path, cPath: cPath, targetCPath: targetCPath)
                }
            }

            return
        }

        try path.withPlatformString { cPath in
            try targetPath.withPlatformString { targetCPath in
                try self.createSymbolicLink(path: path, cPath: cPath, targetCPath: targetCPath)
            }
        }
    }
#endif

    private func createSymbolicLink(
        path: String,
        cPath: UnsafePointer<CChar>,
        targetCPath: UnsafePointer<CChar>
    ) throws {
        try callPOSIXFunction(expect: .zero, path: path) { symlink(cPath, targetCPath) }
    }

    @available(macOS 11.0, iOS 14.0, watchOS 7.0, tvOS 14.0, macCatalyst 14.0, *)
    public func copyItem(at srcPath: FilePath, to dstPath: FilePath) throws {
#if canImport(Darwin)
        guard #available(macOS 12.0, iOS 15.0, watchOS 8.0, tvOS 15.0, macCatalyst 15.0, *), versionCheck(12) else {
            try srcPath.withCString { cSrc in
                try dstPath.withCString { cDst in
                    try self.copyItem(atCPath: cSrc, toCPath: cDst, errPath: String(describing: dstPath))
                }
            }

            return
        }

        try srcPath.withPlatformString { cSrc in
            try dstPath.withPlatformString { cDst in
                try self.copyItem(atCPath: cSrc, toCPath: cDst, errPath: dstPath.string)
            }
        }
#else
        let srcFile = try FileDescriptor.open(srcPath, .readOnly)
        var dstFile: FileDescriptor? = nil

        defer {
            try? srcFile.close()
            try? dstFile?.close()
        }

        let srcStat = try callPOSIXFunction(expect: .zero, path: srcPath) { fstat(srcFile.rawValue, $0) }

        switch try self.typeOfItem(fileDescriptor: srcFile) {
        case .regular:
            dstFile = try FileDescriptor.open(
                dstPath, .writeOnly,
                options: [.create, .exclusiveCreate],
                permissions: .init(rawValue: srcStat.st_mode)
            )

            let bytesCopied = copy_file_range(srcFile.rawValue, nil, dstFile!.rawValue, nil, srcStat.st_size, 0)
            if bytesCopied < 0 {
                if [EXDEV, EOPNOTSUPP].contains(errno) {
                    let bufsize = 1024 * 1024
                    var bytesLeft = srcStat.st_size

                    while bytesLeft > 0 {
                        let bytesSent = sendfile(dstFile!.rawValue, srcFile.rawValue, nil, min(bytesLeft, bufsize))

                        if bytesSent < 0 {
                            throw errno(path: dstPath)
                        }

                        bytesLeft -= bytesSent
                    }
                } else {
                    throw errno(path: dstPath)
                }
            }
        case .directory:
            try callPOSIXFunction(expect: .zero, path: dstPath) {
                dstPath.withPlatformString { mkdir($0, srcStat.st_mode) }
            }

            for srcItem in try self.contentsOfDirectory(at: srcPath) {
                let dstItem = dstPath.appending(srcItem.lastComponent!)

                try self.copyItem(at: srcItem, to: dstItem)
            }

            dstFile = try FileDescriptor.open(dstPath, .readOnly, options: .directory)
        case .symbolicLink:
            try self.createSymbolicLink(at: dstPath, withTarget: self.targetOfSymbolicLink(at: srcPath))

            dstFile = try FileDescriptor.open(dstPath, .writeOnly)
        case .fifo, .characterSpecial, .blockSpecial, .socket, .whiteout:
            throw errno(EINVAL, path: srcPath)
        }

        do {
            for eachXattr in try ExtendedAttribute.list(at: srcFile, options: .noTraverseLink) {
                try eachXattr.write(to: dstFile!, options: .noTraverseLink)
            }
        } catch Errno.notSupported {}

        try self.copyMetadata(from: srcFile, to: dstFile!, srcStat: srcStat, srcPath: srcPath, dstPath: dstPath)
#endif
    }

#if !canImport(Darwin)
    private func copyMetadata(
        from src: FileDescriptor,
        to dst: FileDescriptor,
        srcStat: stat,
        srcPath: FilePath,
        dstPath: FilePath
    ) throws {
        try callPOSIXFunction(expect: .zero, path: dstPath, isWrite: true) {
            let res = fchown(dst.rawValue, srcStat.st_uid, srcStat.st_gid)

            if res != 0 && errno == EPERM {
                return 0 as Int32
            }

            return res
        }

        if fchmod(dst.rawValue, srcStat.st_mode & 0o7777) != 0 && ![EPERM, EACCES].contains(errno) {
            throw errno(path: dstPath, isWrite: true)
        }
        var ds = stat()
        fstat(dst.rawValue, &ds)

        try withUnsafeTemporaryAllocation(of: timespec.self, capacity: 2) {
            $0[0] = srcStat.st_atim
            $0[1] = srcStat.st_mtim

            if futimens(dst.rawValue, $0.baseAddress) != 0 && ![EPERM, EACCES].contains(errno) {
                throw errno(path: dstPath, isWrite: true)
            }
        }
    }
#endif

#if canImport(Darwin)
    public func copyItem(atPath src: String, toPath dst: String) throws {
        guard #available(macOS 11.0, iOS 14.0, watchOS 7.0, tvOS 14.0, macCatalyst 14.0, *), versionCheck(11) else {
            try src.withCString { cSrc in
                try dst.withCString { cDst in
                    try self.copyItem(atCPath: cSrc, toCPath: cDst, errPath: String(describing: dst))
                }
            }

            return
        }

        return try self.copyItem(at: FilePath(src), to: FilePath(dst))
    }

    private func copyItem(atCPath src: UnsafePointer<CChar>, toCPath dst: UnsafePointer<CChar>, errPath: String) throws {
        try callPOSIXFunction(expect: .zero, path: errPath) {
            let flags = copyfile_flags_t(COPYFILE_ALL | COPYFILE_CLONE | COPYFILE_RECURSIVE)
            return copyfile(src, dst, nil, flags)
        }
    }
#endif

    @available(macOS 11.0, iOS 14.0, watchOS 7.0, tvOS 14.0, macCatalyst 14.0, *)
    public func moveItem(at src: FilePath, to dst: FilePath) throws {
#if canImport(Darwin)
        guard #available(macOS 12.0, iOS 15.0, watchOS 8.0, tvOS 15.0, macCatalyst 15.0, *), versionCheck(12) else {
            try src.withCString { cSrc in
                try dst.withCString { cDst in
                    try self.moveItem(atPath: cSrc, toPath: cDst, errPath: String(describing: dst))
                }
            }

            return
        }

        try src.withPlatformString { cSrc in
            try dst.withPlatformString { cDst in
                try self.moveItem(atPath: cSrc, toPath: cDst, errPath: dst.string)
            }
        }
#else
        let ret = src.withPlatformString { cSrc in
            dst.withPlatformString { cDst in
                rename(cSrc, cDst)
            }
        }

        if ret != 0 {
            if errno == EXDEV {
                try self.copyItem(at: src, to: dst)
                try self.removeItem(at: src, recursively: true)
            } else {
                throw errno(path: dst)
            }
        }
#endif
    }

#if canImport(Darwin)
    public func moveItem(atPath src: String, toPath dst: String) throws {
        guard #available(macOS 11.0, iOS 14.0, watchOS 7.0, tvOS 14.0, macCatalyst 14.0, *), versionCheck(11) else {
            try src.withCString { cSrc in
                try dst.withCString { cDst in
                    try self.moveItem(atPath: cSrc, toPath: cDst, errPath: dst)
                }
            }

            return
        }

        try self.moveItem(at: FilePath(src), to: FilePath(dst))
    }

    private func moveItem(atPath src: UnsafePointer<CChar>, toPath dst: UnsafePointer<CChar>, errPath: String) throws {
        if rename(src, dst) != 0 {
            if errno == EXDEV {
                try self.copyItem(atCPath: src, toCPath: dst, errPath: errPath)
                try self.removeItem(cPath: src, recursively: true)
            } else {
                throw errno(path: errPath)
            }
        }
    }
#endif

    @available(macOS 11.0, iOS 14.0, watchOS 7.0, tvOS 14.0, macCatalyst 14.0, *)
    public func removeItem(at path: FilePath, recursively: Bool = false) throws {
        let isDirectory = try self.typeOfItem(at: path) == .directory

        if isDirectory && recursively {
            for eachChild in try self.contentsOfDirectory(at: path, recursively: false) {
                try self.removeItem(at: eachChild, recursively: true)
            }
        }

#if canImport(Darwin)
        guard #available(macOS 12.0, iOS 15.0, watchOS 8.0, tvOS 15.0, macCatalyst 15.0, *), versionCheck(12) else {
            try path.withCString { cPath in
                try self.removeItem(path: String(decoding: path), cPath: cPath, isDirectory: isDirectory)
            }
            return
        }
#endif

        try path.withPlatformString { cPath in
            try self.removeItem(path: path.string, cPath: cPath, isDirectory: isDirectory)
        }
    }

#if canImport(Darwin)
    public func removeItem(atPath path: String, recursively: Bool = false) throws {
        guard #available(macOS 11.0, iOS 14.0, watchOS 7.0, tvOS 14.0, macCatalyst 14.0, *), versionCheck(11) else {
            let isDirectory = try self.typeOfItem(atPath: path) == .directory

            if isDirectory && recursively {
                for eachChild in try self.contentsOfDirectory(atPath: path, recursively: false) {
                    try self.removeItem(atPath: "\(path)/\(eachChild)", recursively: true)
                }
            }

            try path.withCString { cPath in
                try self.removeItem(path: path, cPath: cPath, isDirectory: isDirectory)
            }

            return
        }

        try self.removeItem(at: FilePath(path), recursively: recursively)
    }
#endif

    private func removeItem(cPath: UnsafePointer<CChar>, recursively: Bool) throws {
#if canImport(Darwin)
        guard #available(macOS 11.0, iOS 14.0, watchOS 7.0, tvOS 14.0, macCatalyst 14.0, *), versionCheck(11) else {
            try self.removeItem(atPath: String(cString: cPath), recursively: recursively)
            return
        }

        guard #available(macOS 12.0, iOS 15.0, watchOS 8.0, tvOS 15.0, macCatalyst 15.0, *), versionCheck(12) else {
            try self.removeItem(at: FilePath(String(cString: cPath)), recursively: recursively)
            return
        }
#endif

        try self.removeItem(at: FilePath(platformString: cPath), recursively: recursively)
    }

    private func removeItem(path: String, cPath: UnsafePointer<CChar>, isDirectory: Bool) throws {
        try callPOSIXFunction(expect: .zero, path: path) { isDirectory ? rmdir(path) : unlink(path) }
    }

    @available(macOS 11.0, iOS 14.0, watchOS 7.0, tvOS 14.0, macCatalyst 14.0, *)
    public func replaceItem(
        at originalPath: FilePath,
        withItemAt newPath: FilePath,
        options: ItemReplacementOptions = []
    ) throws {
#if canImport(Darwin)
        let originalInfo = try FileInfo(at: originalPath, keys: [.fileSystemID, .volumeCapabilities, .volumeMountPoint])
        let newInfo = try FileInfo(at: newPath, keys: [.fileSystemID, .volumeCapabilities, .volumeMountPoint])

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
#else
        if let originalFSID = try FileInfo(at: originalPath, keys: .fileSystemID).fileSystemID,
           let newFSID = try FileInfo(at: newPath, keys: .fileSystemID).fileSystemID,
           originalFSID == newFSID {
            try self.linuxExchange(originalPath: originalPath, newPath: newPath, options: options)
        } else {
            try self.crossVolumeExchange(originalPath: originalPath, newPath: newPath, options: options)
        }
#endif
    }

#if canImport(Darwin)
    public func replaceItem(
        atPath originalPath: String,
        withItemAtPath newPath: String,
        options: ItemReplacementOptions = []
    ) throws {
        let originalInfo = try FileInfo(atPath: originalPath, keys: [.fileSystemID, .volumeCapabilities])
        let newInfo = try FileInfo(atPath: newPath, keys: [.fileSystemID, .volumeCapabilities])

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
        if let originalFSID = originalInfo.fileSystemID,
           let newFSID = newInfo.fileSystemID,
           originalFSID == newFSID,
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
            try self.copyExtendedAttributes(path: path, from: originalCPath, to: newCPath, swap: false, preserveFrom: true)
        }

        _ = try callPOSIXFunction(expect: .zero, path: path) {
            renamex_np(newCPath, originalCPath, UInt32(bitPattern: RENAME_SWAP))
        }

        if !options.contains(.withoutDeletingBackupItem) {
            try self.removeItem(cPath: newCPath, recursively: true)
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
            try self.copyExtendedAttributes(
                path: path,
                from: newCPath,
                to: originalCPath,
                swap: true,
                preserveFrom: options.contains(.withoutDeletingBackupItem)
            )
        }

        if !options.contains(.withoutDeletingBackupItem) {
            try self.removeItem(cPath: newCPath, recursively: true)
        }
    }

    private func manualReplaceItem(
        path: String,
        originalCPath: UnsafePointer<CChar>,
        newCPath: UnsafePointer<CChar>,
        options: ItemReplacementOptions
    ) throws {
        if !options.contains(.usingNewMetadataOnly) {
            try self.copyExtendedAttributes(path: path, from: originalCPath, to: newCPath, swap: false, preserveFrom: true)
        }

        let len = strlen(newCPath)
        let uuidLen = MemoryLayout<uuid_string_t>.size
        try withUnsafeTemporaryAllocation(of: CChar.self, capacity: len + 6 + uuidLen + 1) {
            let tempPath = $0.baseAddress!

            try withUnsafeTemporaryAllocation(of: UInt8.self, capacity: MemoryLayout<uuid_t>.stride) {
                let uuid = $0.baseAddress!
                uuid_generate(uuid)

                try withUnsafeTemporaryAllocation(of: UInt8.self, capacity: uuidLen) {
                    let uuidString = $0.baseAddress!

                    uuid_unparse(uuid, uuidString)

                    strncpy(tempPath, newCPath, len)
                    strncpy(tempPath + len, ".swap.", 6)
                    strncpy(tempPath + len + 6, uuidString, uuidLen)
                    tempPath[len + 6 + uuidLen] = 0

                    try self.moveItem(atPath: originalCPath, toPath: tempPath, errPath: String(cString: tempPath))
                    try self.moveItem(atPath: newCPath, toPath: originalCPath, errPath: String(cString: originalCPath))

                    if options.contains(.withoutDeletingBackupItem) {
                        try self.moveItem(atPath: tempPath, toPath: newCPath, errPath: String(cString: newCPath))
                    } else {
                        try self.removeItem(cPath: tempPath, recursively: true)
                    }
                }
            }
        }
    }
#else
    private func linuxExchange(originalPath: FilePath, newPath: FilePath, options: ItemReplacementOptions) throws {
        let ret = try originalPath.withPlatformString { originalCPath in
            try newPath.withPlatformString { newCPath in
                if !options.contains(.usingNewMetadataOnly) {
                    try self.copyExtendedAttributes(
                        path: originalPath.string,
                        from: originalCPath,
                        to: newCPath,
                        swap: false,
                        preserveFrom: true
                    )
                }

                return renameat2(AT_FDCWD, newCPath, AT_FDCWD, originalCPath, UInt32(bitPattern: RENAME_EXCHANGE))
            }
        }

        if ret == 0 {
            if !options.contains(.withoutDeletingBackupItem) {
                try self.removeItem(at: newPath, recursively: true)
            }
        } else if [EINVAL, EXDEV].contains(errno) {
            let tempName = "\(newPath.lastComponent ?? "").swap.\(self.generateUUID())"
            let tempPath = newPath.removingLastComponent().appending(tempName)

            try self.moveItem(at: originalPath, to: tempPath)
            try self.moveItem(at: newPath, to: originalPath)

            if options.contains(.withoutDeletingBackupItem) {
                try self.moveItem(at: tempPath, to: newPath)
            } else {
                try self.removeItem(at: tempPath, recursively: true)
            }
        } else {
            throw errno(path: originalPath)
        }
    }

    private func crossVolumeExchange(originalPath: FilePath, newPath: FilePath, options: ItemReplacementOptions) throws {
        let tempDir = try self.createItemReplacementDirectory(for: originalPath)
        defer { try? self.removeItem(at: tempDir) }

        let stagingPath = tempDir.appending(self.generateUUID())

        try self.copyItem(at: newPath, to: stagingPath)

        if !options.contains(.usingNewMetadataOnly) {
            do {
                try originalPath.withPlatformString { originalCPath in
                    try stagingPath.withPlatformString { stagingCPath in
                        try self.copyExtendedAttributes(
                            path: originalPath.string,
                            from: originalCPath,
                            to: stagingCPath,
                            swap: false,
                            preserveFrom: true
                        )
                    }
                }
            } catch Errno.notSupported {}
        }

        let tempPath = originalPath.removingLastComponent().appending(".swap.\(self.generateUUID())")

        try self.moveItem(at: originalPath, to: tempPath)
        try self.moveItem(at: stagingPath, to: originalPath)

        if options.contains(.withoutDeletingBackupItem) {
            let newTempPath = newPath.removingLastComponent().appending(".swap.\(self.generateUUID())")

            try self.moveItem(at: tempPath, to: newTempPath)
            try self.removeItem(at: newPath)
            try self.moveItem(at: newTempPath, to: newPath)
        } else {
            try self.removeItem(at: newPath)
        }
    }
#endif

    private func copyExtendedAttributes(
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
