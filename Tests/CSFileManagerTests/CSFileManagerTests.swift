import CSErrors
import CSFileInfo
@testable import CSFileManager
import DiskImageHelper
import Foundation
import SyncPolyfill
import Testing

#if canImport(System)
import System
#else
import SystemPackage
#endif

let withFixtures = MountTrait(size: 1024 * 1024, fileSystems: DiskImageHelper.FileSystem.allCases.filter(\.isWritable))

@Suite(.serialized, withFixtures)
struct CSFileManagerTests {
    typealias DiskImage = MountTrait<GenericDiskImageInfo>.DiskImage

#if canImport(Darwin)
    static let hostSupportsResourceFork = true
#else
    static let hostSupportsResourceFork = false
#endif

#if canImport(Darwin)
    @Test
    func testAll() throws {
        for version in [10, 11, 12, 13] {
            try emulateOSVersion(version) {
                self.testRootDirectory()
                self.testHomeDirectory()
                self.testTemporaryDirectory()
                self.testTemporaryDirectoryFallback()
                try self.testCreateTemporaryFile()
                try self.testCreateTemporaryFileWithDirectory()
                try self.testCreateTemporaryFileWithTemplate()
                try self.testCreateTemporaryFileWithTemplateAndSuffix()
                try self.testCreateTemporaryFileWithTemplateAndFallback()
                try self.testCreateTemporaryFileWithTemplateAndNoSlashOnTMPDIR()
                try self.testCreateTemporaryFileFailure()
                try self.testCreateItemReplacementDirectoryOnBootVolume()
                for eachDiskImage in withFixtures.images {
                    try self.testCreateItemReplacementDirectoryOnOtherVolume(diskImage: eachDiskImage)
                }
                try self.testReachablePaths()
                try self.testUnreachablePaths()
                try self.testReachabilityCheckError()
                try self.testGetTypeOfItem()
                try self.testContentsOfDirectory()
                try self.testCreateDirectory()
#if canImport(Darwin)
                try self.testCreateDirectoryWithStringPaths()
#endif
#if Foundation
                try self.testCreateDirectoryWithURLs()
#endif
                try self.testCopyItems()
                try self.testMoveItems(image1: nil, image2: nil)
                try self.testRemoveRegularFile()
                try self.testRemoveEmptyDirectory()
                try self.testRemoveDirectoryWithContents()
                try self.testReplaceItems(image1: nil, image2: nil)
            }
        }
    }
#endif

    private func expectNoSuchFile(_ url: URL) {
        let error = #expect(throws: CocoaError.self) { try url.checkResourceIsReachable() }
        #expect(error?.code == .fileReadNoSuchFile)
    }

    private func expectNoSuchFile(_ path: FilePath) {
        self.expectNoSuchFile(URL(filePath: path.string))
    }

    private func expectNoSuchFile(_ path: String) {
        self.expectNoSuchFile(URL(filePath: path))
    }

    @Test
    func testRootDirectory() {
        #expect(CSFileManager.shared.rootDirectory == "/")
#if canImport(Darwin)
        #expect(CSFileManager.shared.rootDirectoryStringPath == "/")
#endif
#if Foundation
        #expect(CSFileManager.shared.rootDirectoryURL == URL(filePath: "/"))
#endif
    }

    @Test
    func testHomeDirectory() {
        #expect(CSFileManager.shared.homeDirectoryForCurrentUser == FilePath(NSHomeDirectory()))
#if canImport(Darwin)
        #expect(CSFileManager.shared.homeDirectoryStringPathForCurrentUser == NSHomeDirectory())
#endif
#if Foundation
        #expect(
            CSFileManager.shared.homeDirectoryURLForCurrentUser ==
            URL(filePath: NSHomeDirectory(), directoryHint: .isDirectory)
        )
#endif
    }

    @Test
    func testTemporaryDirectory() {
        #expect(CSFileManager.shared.temporaryDirectory == FilePath(FileManager.default.temporaryDirectory.path))
#if canImport(Darwin)
        #expect(CSFileManager.shared.temporaryDirectoryStringPath == FileManager.default.temporaryDirectory.path + "/")
#endif
#if Foundation
        #expect(CSFileManager.shared.temporaryDirectoryURL == FileManager.default.temporaryDirectory)
#endif
    }

    @Test
    func testTemporaryDirectoryFallback() {
        let oldTmpDir = getenv("TMPDIR").map { String(cString: $0) }
        defer { setenv("TMPDIR", oldTmpDir ?? "", 1) }
        unsetenv("TMPDIR")

        #expect(CSFileManager.shared.temporaryDirectory == FilePath("/tmp"))
#if canImport(Darwin)
        #expect(CSFileManager.shared.temporaryDirectoryStringPath == "/tmp")
#endif
#if Foundation
        #expect(CSFileManager.shared.temporaryDirectoryURL == URL(filePath: "/tmp/"))
#endif

        setenv("TMPDIR", "", 1)
        #expect(CSFileManager.shared.temporaryDirectory == FilePath("/tmp"))
#if canImport(Darwin)
        #expect(CSFileManager.shared.temporaryDirectoryStringPath == "/tmp")
#endif
#if Foundation
        #expect(CSFileManager.shared.temporaryDirectoryURL == URL(filePath: "/tmp/"))
#endif
    }

    @Test
    func testCreateTemporaryFile() throws {
        let (desc, path) = try CSFileManager.shared.createTemporaryFile()
        defer {
            try? desc.close()
            try? CSFileManager.shared.removeItem(at: path)
        }

        #expect(path.starts(with: CSFileManager.shared.temporaryDirectory))
        #expect(path.lastComponent?.string.count == 32)
        try desc.writeAll("Foo Bar".data(using: .ascii)!)

        #expect(try String(data: Data(contentsOf: URL(filePath: path.string)), encoding: .ascii) == "Foo Bar")

#if canImport(Darwin)
        let (fdInt, pathString) = try CSFileManager.shared.createTemporaryFileWithStringPath()
        defer {
            close(fdInt)
            try? CSFileManager.shared.removeItem(atPath: pathString)
        }

        #expect(pathString.starts(with: CSFileManager.shared.temporaryDirectoryStringPath))
        #expect(URL(filePath: pathString).lastPathComponent.count == 32)
        #expect(write(fdInt, "Foo Bar Baz", 11) == 11)
        #expect(try String(data: Data(contentsOf: URL(filePath: pathString)), encoding: .ascii) == "Foo Bar Baz")
#endif

#if Foundation
        let (handle, url) = try CSFileManager.shared.createTemporaryFileURL()
        defer {
            try? handle.close()
            try? CSFileManager.shared.removeItem(at: url)
        }

        #expect(url.path.starts(with: CSFileManager.shared.temporaryDirectory.string))
        #expect(url.lastPathComponent.count == 32)
        try handle.write(contentsOf: "Foo Bar Baz".data(using: .ascii)!)
        #expect(try String(data: Data(contentsOf: url), encoding: .ascii) == "Foo Bar Baz")
#endif
    }

    @Test
    func testCreateTemporaryFileWithDirectory() throws {
        let directory = FilePath("/tmp/\(UUID().uuidString)")
        try CSFileManager.shared.createDirectory(at: directory)
        defer { try? CSFileManager.shared.removeItem(at: directory) }

        let (desc, path) = try CSFileManager.shared.createTemporaryFile(directory: directory)
        defer { try? desc.close() }

        #expect(path.starts(with: directory))
        #expect(path.lastComponent?.string.count == 32)
        try desc.writeAll("Foo Bar".data(using: .ascii)!)

        #expect(try String(data: Data(contentsOf: URL(filePath: path.string)), encoding: .ascii) == "Foo Bar")

#if canImport(Darwin)
        let (fdInt, pathString) = try CSFileManager.shared.createTemporaryFileWithStringPath(directory: directory.string)
        defer { close(fdInt) }

        #expect(pathString.starts(with: directory.string))
        #expect(URL(filePath: pathString).lastPathComponent.count == 32)
        #expect(write(fdInt, "Foo Bar Baz", 11) == 11)
        #expect(try String(data: Data(contentsOf: URL(filePath: pathString)), encoding: .ascii) == "Foo Bar Baz")
#endif

#if Foundation
        let (handle, url) = try CSFileManager.shared.createTemporaryFileURL(directory: URL(filePath: directory))
        defer { try? handle.close() }

        #expect(url.path.starts(with: directory.string))
        #expect(url.lastPathComponent.count == 32)
        try handle.write(contentsOf: "Foo Bar Baz".data(using: .ascii)!)
        #expect(try String(data: Data(contentsOf: url), encoding: .ascii) == "Foo Bar Baz")
#endif
    }

    @Test
    func testCreateTemporaryFileWithTemplate() throws {
        let (desc, path) = try CSFileManager.shared.createTemporaryFile(template: "fooXXXXXX")
        defer {
            try? desc.close()
            try? CSFileManager.shared.removeItem(at: path)
        }

        #expect(path.starts(with: CSFileManager.shared.temporaryDirectory))
        #expect(path.lastComponent?.string.count == 9)
        #expect(path.lastComponent?.string.prefix(3) == "foo")
        #expect(path.lastComponent?.string.suffix(6) != "XXXXXX")
        #expect(path.extension == nil)
        try desc.writeAll("Foo Bar".data(using: .ascii)!)

        #expect(try String(data: Data(contentsOf: URL(filePath: path.string)), encoding: .ascii) == "Foo Bar")

#if canImport(Darwin)
        let (fdInt, pathString) = try CSFileManager.shared.createTemporaryFileWithStringPath(template: "quxXXX")
        defer {
            close(fdInt)
            try? CSFileManager.shared.removeItem(atPath: pathString)
        }

        #expect(pathString.starts(with: CSFileManager.shared.temporaryDirectoryStringPath))
        #expect(URL(filePath: pathString).lastPathComponent.count == 6)
        #expect(URL(filePath: pathString).lastPathComponent.prefix(3) == "qux")
        #expect(URL(filePath: pathString).lastPathComponent.suffix(3) != "XXX")
        #expect(URL(filePath: pathString).pathExtension == "")
        #expect(write(fdInt, "Foo Bar Baz", 11) == 11)
        #expect(try String(data: Data(contentsOf: URL(filePath: pathString)), encoding: .ascii) == "Foo Bar Baz")
#endif

#if Foundation
        let (handle, url) = try CSFileManager.shared.createTemporaryFileURL(template: "fooXXXXXX")
        defer {
            try? handle.close()
            try? CSFileManager.shared.removeItem(at: url)
        }

        #expect(url.path.starts(with: CSFileManager.shared.temporaryDirectory.string))
        #expect(url.lastPathComponent.count == 9)
        #expect(url.lastPathComponent.prefix(3) == "foo")
        #expect(url.lastPathComponent.suffix(6) != "XXXXXX")
        #expect(url.pathExtension == "")
        try handle.write(contentsOf: "Foo Bar Baz".data(using: .ascii)!)
        #expect(try String(data: Data(contentsOf: url), encoding: .ascii) == "Foo Bar Baz")
#endif
    }

    @Test
    func testCreateTemporaryFileWithTemplateAndSuffix() throws {
        let (desc, path) = try CSFileManager.shared.createTemporaryFile(template: "fooXXXXXX", suffix: "bar.baz")
        defer {
            try? desc.close()
            try? CSFileManager.shared.removeItem(at: path)
        }

        #expect(path.starts(with: CSFileManager.shared.temporaryDirectory))
        #expect(path.lastComponent?.string.count == 16)
        #expect(path.lastComponent?.string.prefix(3) == "foo")
        #expect(path.lastComponent?.string.prefix(8).suffix(6) != "XXXXXX")
        #expect(path.lastComponent?.string.suffix(7) == "bar.baz")
        #expect(path.extension == "baz")
        try desc.writeAll("Foo Bar".data(using: .ascii)!)

        #expect(try String(data: Data(contentsOf: URL(filePath: path.string)), encoding: .ascii) == "Foo Bar")

#if canImport(Darwin)
        let (fdInt, pathString) = try CSFileManager.shared.createTemporaryFileWithStringPath(
            template: "quxXXX",
            suffix: "quux.foo"
        )
        defer {
            close(fdInt)
            try? CSFileManager.shared.removeItem(atPath: pathString)
        }

        #expect(pathString.starts(with: CSFileManager.shared.temporaryDirectoryStringPath))
        #expect(URL(filePath: pathString).lastPathComponent.count == 14)
        #expect(URL(filePath: pathString).lastPathComponent.prefix(3) == "qux")
        #expect(URL(filePath: pathString).lastPathComponent.prefix(6).suffix(3) != "XXX")
        #expect(URL(filePath: pathString).lastPathComponent.suffix(8) == "quux.foo")
        #expect(URL(filePath: pathString).pathExtension == "foo")
        #expect(write(fdInt, "Foo Bar Baz", 11) == 11)
        #expect(try String(data: Data(contentsOf: URL(filePath: pathString)), encoding: .ascii) == "Foo Bar Baz")
#endif

#if Foundation
        let (handle, url) = try CSFileManager.shared.createTemporaryFileURL(template: "fooXXXXXX", suffix: "bar.baz")
        defer {
            try? handle.close()
            try? CSFileManager.shared.removeItem(at: url)
        }

        #expect(url.path.starts(with: CSFileManager.shared.temporaryDirectory.string))
        #expect(url.lastPathComponent.count == 16)
        #expect(url.lastPathComponent.prefix(3) == "foo")
        #expect(url.lastPathComponent.prefix(8).suffix(6) != "XXXXXX")
        #expect(url.lastPathComponent.suffix(7) == "bar.baz")
        #expect(url.pathExtension == "baz")
        try handle.write(contentsOf: "Foo Bar Baz".data(using: .ascii)!)
        #expect(try String(data: Data(contentsOf: url), encoding: .ascii) == "Foo Bar Baz")
#endif
    }

    @Test
    func testCreateTemporaryFileWithTemplateAndFallback() throws {
        let oldTmpDir = String(cString: getenv("TMPDIR"))
        defer { setenv("TMPDIR", oldTmpDir, 1) }
        unsetenv("TMPDIR")

        let (desc, path) = try CSFileManager.shared.createTemporaryFile(template: "fooXXXXXX", suffix: "bar.baz")
        defer {
            try? desc.close()
            try? CSFileManager.shared.removeItem(at: path)
        }

        #expect(path.starts(with: "/tmp/"))
        #expect(path.lastComponent?.string.count == 16)
        #expect(path.lastComponent?.string.prefix(3) == "foo")
        #expect(path.lastComponent?.string.prefix(8).suffix(6) != "XXXXXX")
        #expect(path.lastComponent?.string.suffix(7) == "bar.baz")
        #expect(path.extension == "baz")
        try desc.writeAll("Foo Bar".data(using: .ascii)!)

        #expect(try String(data: Data(contentsOf: URL(filePath: path.string)), encoding: .ascii) == "Foo Bar")

#if canImport(Darwin)
        let (fdInt, pathString) = try CSFileManager.shared.createTemporaryFileWithStringPath(
            template: "quxXXX",
            suffix: "quux.foo"
        )
        defer {
            close(fdInt)
            try? CSFileManager.shared.removeItem(atPath: pathString)
        }

        #expect(pathString.starts(with: "/tmp/"))
        #expect(URL(filePath: pathString).lastPathComponent.count == 14)
        #expect(URL(filePath: pathString).lastPathComponent.prefix(3) == "qux")
        #expect(URL(filePath: pathString).lastPathComponent.prefix(6).suffix(3) != "XXX")
        #expect(URL(filePath: pathString).lastPathComponent.suffix(8) == "quux.foo")
        #expect(URL(filePath: pathString).pathExtension == "foo")
        #expect(write(fdInt, "Foo Bar Baz", 11) == 11)
        #expect(try String(data: Data(contentsOf: URL(filePath: pathString)), encoding: .ascii) == "Foo Bar Baz")
#endif

#if Foundation
        let (handle, url) = try CSFileManager.shared.createTemporaryFileURL(template: "fooXXXXXX", suffix: "bar.baz")
        defer {
            try? handle.close()
            try? CSFileManager.shared.removeItem(at: url)
        }

        #expect(url.path.starts(with: "/tmp/"))
        #expect(url.lastPathComponent.count == 16)
        #expect(url.lastPathComponent.prefix(3) == "foo")
        #expect(url.lastPathComponent.prefix(8).suffix(6) != "XXXXXX")
        #expect(url.lastPathComponent.suffix(7) == "bar.baz")
        #expect(url.pathExtension == "baz")
        try handle.write(contentsOf: "Foo Bar Baz".data(using: .ascii)!)
        #expect(try String(data: Data(contentsOf: url), encoding: .ascii) == "Foo Bar Baz")
#endif
    }

    @Test
    func testCreateTemporaryFileWithTemplateAndNoSlashOnTMPDIR() throws {
        let oldTmpDir = String(cString: getenv("TMPDIR"))
        defer { setenv("TMPDIR", oldTmpDir, 1) }
        setenv("TMPDIR", "/tmp", 1)

        let (desc, path) = try CSFileManager.shared.createTemporaryFile(template: "fooXXXXXX", suffix: "bar.baz")
        defer {
            try? desc.close()
            try? CSFileManager.shared.removeItem(at: path)
        }

        #expect(path.starts(with: "/tmp/"))
        #expect(path.lastComponent?.string.count == 16)
        #expect(path.lastComponent?.string.prefix(3) == "foo")
        #expect(path.lastComponent?.string.prefix(8).suffix(6) != "XXXXXX")
        #expect(path.lastComponent?.string.suffix(7) == "bar.baz")
        #expect(path.extension == "baz")
        try desc.writeAll("Foo Bar".data(using: .ascii)!)

        #expect(try String(data: Data(contentsOf: URL(filePath: path.string)), encoding: .ascii) == "Foo Bar")

#if canImport(Darwin)
        let (fdInt, pathString) = try CSFileManager.shared.createTemporaryFileWithStringPath(
            template: "quxXXX",
            suffix: "quux.foo"
        )
        defer {
            close(fdInt)
            try? CSFileManager.shared.removeItem(atPath: pathString)
        }

        #expect(pathString.starts(with: "/tmp/"))
        #expect(URL(filePath: pathString).lastPathComponent.count == 14)
        #expect(URL(filePath: pathString).lastPathComponent.prefix(3) == "qux")
        #expect(URL(filePath: pathString).lastPathComponent.prefix(6).suffix(3) != "XXX")
        #expect(URL(filePath: pathString).lastPathComponent.suffix(8) == "quux.foo")
        #expect(URL(filePath: pathString).pathExtension == "foo")
        #expect(write(fdInt, "Foo Bar Baz", 11) == 11)
        #expect(try String(data: Data(contentsOf: URL(filePath: pathString)), encoding: .ascii) == "Foo Bar Baz")
#endif

#if Foundation
        let (handle, url) = try CSFileManager.shared.createTemporaryFileURL(template: "fooXXXXX", suffix: "bar.baz")
        defer {
            try? handle.close()
            try? CSFileManager.shared.removeItem(at: url)
        }

        #expect(url.path.starts(with: "/tmp/"))
        #expect(url.lastPathComponent.count == 15)
        #expect(url.lastPathComponent.prefix(3) == "foo")
        #expect(url.lastPathComponent.suffix(7) == "bar.baz")
        #expect(url.pathExtension == "baz")
        try handle.write(contentsOf: "Foo Bar Baz".data(using: .ascii)!)
        #expect(try String(data: Data(contentsOf: url), encoding: .ascii) == "Foo Bar Baz")
#endif
    }

    @Test
    func testCreateTemporaryFileFailure() throws {
        #expect(
            #expect(throws: (any Swift.Error).self) {
                try CSFileManager.shared.createTemporaryFile(template: "nonexist/dir/XXXXXX")
            }?.isFileNotFoundError == true
        )

#if canImport(Darwin)
        #expect(
            #expect(throws: (any Swift.Error).self) {
                try CSFileManager.shared.createTemporaryFileWithStringPath(template: "nonexist/dir/XXXX")
            }?.isFileNotFoundError == true
        )
#endif
    }

    @Test
    func testCreateItemReplacementDirectoryOnBootVolume() throws {
        func testFilePath(target: FilePath?, mode: mode_t, closure: (FilePath) throws -> Void) throws {
            let path = try CSFileManager.shared.createItemReplacementDirectory(for: target, mode: mode)
            defer { try? CSFileManager.shared.removeItem(at: path) }

            try closure(path)
        }

        print("line: \(#line)")
        try testFilePath(target: nil, mode: 0o755) { path throws in
            #expect(path.starts(with: CSFileManager.shared.temporaryDirectory))
            #expect(try FileInfo(at: path, keys: .permissionsMode).permissionsMode == 0o755)
        }
        print("line: \(#line)")

        try testFilePath(target: FilePath(NSHomeDirectory()), mode: 0o600) { path throws in
            #expect(path.starts(with: CSFileManager.shared.temporaryDirectory))
            #expect(try FileInfo(at: path, keys: .permissionsMode).permissionsMode == 0o600)
        }
        print("line: \(#line)")

#if canImport(Darwin)
        func testString(target: String?, mode: mode_t, closure: (String) throws -> Void) throws {
            let path = try CSFileManager.shared.createItemReplacementDirectory(forPath: target, mode: mode)
            defer { try? CSFileManager.shared.removeItem(atPath: path) }

            try closure(path)
        }

        try testString(target: nil, mode: 0o755) { path throws in
            #expect(path.starts(with: CSFileManager.shared.temporaryDirectoryStringPath))
            #expect(try FileInfo(atPath: path, keys: .permissionsMode).permissionsMode == 0o755)
        }

        try testString(target: NSHomeDirectory(), mode: 0o600) { path throws in
            #expect(path.starts(with: CSFileManager.shared.temporaryDirectoryStringPath))
            #expect(try FileInfo(atPath: path, keys: .permissionsMode).permissionsMode == 0o600)
        }
#endif

#if Foundation
        func testURL(target: URL?, mode: mode_t, closure: (URL) throws -> Void) throws {
            let path = try CSFileManager.shared.createItemReplacementDirectory(for: target, mode: mode)
            defer { try? CSFileManager.shared.removeItem(at: path) }

            try closure(path)
        }

        try testURL(target: nil, mode: 0o755) { url throws in
            #expect(url.path.starts(with: CSFileManager.shared.temporaryDirectory.string))
            #expect(try FileInfo(at: url, keys: .permissionsMode).permissionsMode == 0o755)
        }

        try testURL(target: FileManager.default.homeDirectoryForCurrentUser, mode: 0o600) { url throws in
            #expect(url.path.starts(with: CSFileManager.shared.temporaryDirectory.string))
            #expect(try FileInfo(at: url, keys: .permissionsMode).permissionsMode == 0o600)
        }
#endif
    }

    @Test(arguments: withFixtures.images)
    func testCreateItemReplacementDirectoryOnOtherVolume(diskImage: DiskImage) throws {
        let imageMount = FilePath(diskImage.mountPoint.path)
        let imageParentDir = imageMount.appending(UUID().uuidString)

        try CSFileManager.shared.createDirectory(at: imageParentDir, recursively: true)
        defer { try? CSFileManager.shared.removeItem(at: imageParentDir) }

        let imageTargetFile = imageParentDir.appending(UUID().uuidString)
        try Data().write(to: URL(filePath: imageTargetFile.string))

        func testFilePath(target: FilePath?, mode: mode_t, closure: (FilePath) throws -> Void) throws {
            let path = try CSFileManager.shared.createItemReplacementDirectory(for: target, mode: mode)
            defer { try? CSFileManager.shared.removeItem(at: path) }

            try closure(path)
        }

#if canImport(Darwin)
        func testString(target: String?, mode: mode_t, closure: (String) throws -> Void) throws {
            let path = try CSFileManager.shared.createItemReplacementDirectory(forPath: target, mode: mode)
            defer { try? CSFileManager.shared.removeItem(atPath: path) }

            try closure(path)
        }
#endif

            try testFilePath(target: imageTargetFile, mode: 0o700) { path throws in
                #expect(path.starts(with: imageParentDir))
                #expect(try FileInfo(at: path, keys: .permissionsMode).permissionsMode == 0o700)
            }

#if canImport(Darwin)
            try testString(target: imageTargetFile.string, mode: 0o700) { path throws in
                #expect(path.starts(with: imageParentDir.string))
                #expect(try FileInfo(atPath: path, keys: .permissionsMode).permissionsMode == 0o700)
            }
#endif

#if Foundation
        func testURL(target: URL?, mode: mode_t, closure: (URL) throws -> Void) throws {
            let path = try CSFileManager.shared.createItemReplacementDirectory(for: target, mode: mode)
            defer { try? CSFileManager.shared.removeItem(at: path) }

            try closure(path)
        }

        try testURL(target: nil, mode: 0o755) { url throws in
            #expect(url.path.starts(with: CSFileManager.shared.temporaryDirectory.string))
            #expect(try FileInfo(at: url, keys: .permissionsMode).permissionsMode == 0o755)
        }

        try testURL(target: FileManager.default.homeDirectoryForCurrentUser, mode: 0o600) { url throws in
            #expect(url.path.starts(with: CSFileManager.shared.temporaryDirectory.string))
            #expect(try FileInfo(at: url, keys: .permissionsMode).permissionsMode == 0o600)
        }

        try testURL(target: URL(filePath: imageTargetFile.string), mode: 0o700) { url throws in
            #expect(url.path.starts(with: imageParentDir.string))
            #expect(try FileInfo(at: url, keys: .permissionsMode).permissionsMode == 0o700)
        }
#endif
    }

    @Test
    func testReachablePaths() throws {
        #expect(try CSFileManager.shared.itemIsReachable(at: "/bin/ls"))
        #expect(try CSFileManager.shared.itemIsReachable(at: "/usr/bin"))

#if canImport(Darwin)
        #expect(try CSFileManager.shared.itemIsReachable(atPath: "/bin/ls"))
        #expect(try CSFileManager.shared.itemIsReachable(atPath: "/usr/bin"))
#endif

#if Foundation
        #expect(try CSFileManager.shared.itemIsReachable(at: URL(filePath: "/bin/ls")))
        #expect(try CSFileManager.shared.itemIsReachable(at: URL(filePath: "/usr/bin")))
#endif
    }

    @Test
    func testUnreachablePaths() throws {
        let bogusPath = "/bin/does_not_exist.\(UUID().uuidString)"

        #expect(try !CSFileManager.shared.itemIsReachable(at: FilePath(bogusPath)))
#if canImport(Darwin)
        #expect(try !CSFileManager.shared.itemIsReachable(atPath: bogusPath))
#endif
#if Foundation
        #expect(try !CSFileManager.shared.itemIsReachable(at: URL(filePath: bogusPath)))
#endif
    }

    @Test
    func testReachabilityCheckError() throws {
        let noPermissionsDir = CSFileManager.shared.temporaryDirectory.appending(UUID().uuidString)
        let unreachableFile = noPermissionsDir.appending("unreachable.file")

        try CSFileManager.shared.createDirectory(at: noPermissionsDir)
        defer { 
            chmod(noPermissionsDir.string, 0o755)
            try? CSFileManager.shared.removeItem(at: noPermissionsDir, recursively: true)
        }

        try Data().write(to: URL(filePath: unreachableFile.string))

        #expect(try CSFileManager.shared.itemIsReachable(at: unreachableFile))
#if canImport(Darwin)
        #expect(try CSFileManager.shared.itemIsReachable(atPath: unreachableFile.string))
#endif

        try callPOSIXFunction(expect: .zero) { chmod(noPermissionsDir.string, 0o400) }

        let wasRoot = geteuid() == 0
        if wasRoot {
            print("set to daemon succeeds: \(seteuid(1))")
        }
        defer {
            if wasRoot {
                print("set back succeeds: \(seteuid(0))")
            }
        }

        #expect(
            #expect(throws: (any Swift.Error).self) {
                try CSFileManager.shared.itemIsReachable(at: unreachableFile)
            }?.isPermissionError == true
        )
        
#if canImport(Darwin)
        #expect(
            #expect(throws: (any Swift.Error).self) {
                try CSFileManager.shared.itemIsReachable(atPath: unreachableFile.string)
            }?.isPermissionError == true
        )
#endif

#if Foundation
        #expect(
            #expect(throws: (any Swift.Error).self) {
                try CSFileManager.shared.itemIsReachable(at: URL(filePath: unreachableFile.string))
            }?.isPermissionError == true
        )
#endif
    }

    @Test
    func testGetTypeOfItem() throws {
        func checkType(path: FilePath, expectedType: CSFileManager.FileType, canOpen: Bool = true) throws {
            try #expect(CSFileManager.shared.typeOfItem(at: path) == expectedType)
#if canImport(Darwin)
            try #expect(CSFileManager.shared.typeOfItem(atPath: path.string) == expectedType)
#endif
#if Foundation
            try #expect(CSFileManager.shared.typeOfItem(at: URL(filePath: path.string)) == expectedType)
#endif

            if canOpen {
#if canImport(Darwin)
                let desc = try FileDescriptor.open(path, .readOnly, options: .symlink)
#else
                let desc = try FileDescriptor.open(path, .readOnly, options: .noFollow)
#endif
                defer { try? desc.close() }
                
                try #expect(CSFileManager.shared.typeOfItem(fileDescriptor: desc) == expectedType)
                try #expect(CSFileManager.shared.typeOfItem(fileDescriptor: desc.rawValue) == expectedType)
            }
        }

        try checkType(path: "/bin/ls", expectedType: .regular)
        try checkType(path: "/bin", expectedType: .directory)
        try checkType(path: "/etc", expectedType: .symbolicLink)
        try checkType(path: "/dev/null", expectedType: .characterSpecial)
        try checkType(path: "/dev/disk0", expectedType: .blockSpecial, canOpen: false)

        let fifoPath = CSFileManager.shared.temporaryDirectory.appending("myfifo")
        mkfifo(fifoPath.string, 0o755)
        defer { try? CSFileManager.shared.removeItem(at: fifoPath) }
        try checkType(path: fifoPath, expectedType: .fifo, canOpen: false)

#if canImport(Darwin)
        let socket = socket(PF_LOCAL, SOCK_STREAM, 0)
#else
        let socket = socket(PF_LOCAL, Int32(bitPattern: SOCK_STREAM.rawValue), 0)
#endif
        defer { close(socket) }
        try #expect(CSFileManager.shared.typeOfItem(fileDescriptor: FileDescriptor(rawValue: socket)) == .socket)
        try #expect(CSFileManager.shared.typeOfItem(fileDescriptor: socket) == .socket)

        #expect(
            #expect(throws: (any Swift.Error).self) {
                try CSFileManager.shared.typeOfItem(at: "/this/should/not/exist")
            }?.isFileNotFoundError == true
        )

#if canImport(Darwin)
        #expect(
            #expect(throws: (any Swift.Error).self) {
                try CSFileManager.shared.typeOfItem(atPath: "/this/should/not/exist")
            }?.isFileNotFoundError == true
        )
#endif

#if Foundation
        #expect(
            #expect(throws: (any Swift.Error).self) {
                try CSFileManager.shared.typeOfItem(at: URL(filePath: "/this/should/not/exist"))
            }?.isFileNotFoundError == true
        )
#endif
    }
    
    @Test
    func testContentsOfDirectory() throws {
        let manager = CSFileManager.shared

        let root = manager.temporaryDirectory.appending(UUID().uuidString)
        let childName1 = UUID().uuidString
        let childName2 = UUID().uuidString
        let child1 = root.appending(childName1)
        let child2 = root.appending(childName2)
        let grandchildName1 = UUID().uuidString
        let grandchildName2 = UUID().uuidString
        let grandchildName3 = UUID().uuidString
        let grandchild1 = child1.appending(grandchildName1)
        let grandchild2 = child1.appending(grandchildName2)
        let grandchild3 = child2.appending(grandchildName3)

        for eachPath in [grandchild1, grandchild2, grandchild3] {
            try manager.createDirectory(at: eachPath, recursively: true)
        }

        #expect(try Set(manager.contentsOfDirectory(at: root)) == [child1, child2])
        #expect(try Set(manager.contentsOfDirectory(at: child1)) == [grandchild1, grandchild2])
        #expect(try Set(manager.contentsOfDirectory(at: child2)) == [grandchild3])
        #expect(
            try Set(manager.contentsOfDirectory(at: root, recursively: true)) == [child1, child2, grandchild1, grandchild2, grandchild3]
        )
        
#if canImport(Darwin)
        #expect(try Set(manager.contentsOfDirectory(atPath: root.string)) == [childName1, childName2])
        #expect(try Set(manager.contentsOfDirectory(atPath: child1.string)) == [grandchildName1, grandchildName2])
        #expect(try Set(manager.contentsOfDirectory(atPath: child2.string)) == [grandchildName3])
        #expect(
            try Set(manager.contentsOfDirectory(atPath: root.string, recursively: true)) == [
                childName1, "\(childName1)/\(grandchildName1)", "\(childName1)/\(grandchildName2)",
                childName2, "\(childName2)/\(grandchildName3)"
            ]
        )
#endif

#if Foundation
        #expect(
            try Set(manager.contentsOfDirectory(at: URL(filePath: root.string))) == [
                URL(filePath: child1.string, directoryHint: .isDirectory),
                URL(filePath: child2.string, directoryHint: .isDirectory)
            ]
        )
        #expect(
            try Set(manager.contentsOfDirectory(at: URL(filePath: child1.string))) == [
                URL(filePath: grandchild1.string, directoryHint: .isDirectory),
                URL(filePath: grandchild2.string, directoryHint: .isDirectory)
            ]
        )
        #expect(
            try Set(manager.contentsOfDirectory(at: URL(filePath: child2.string))) == [URL(filePath: grandchild3, directoryHint: .isDirectory)]
        )
        #expect(
            try Set(manager.contentsOfDirectory(at: URL(filePath: root.string), recursively: true)) == [
                URL(filePath: child1.string, directoryHint: .isDirectory),
                URL(filePath: child1.string).appending(path: grandchildName1, directoryHint: .isDirectory),
                URL(filePath: child1.string).appending(path: grandchildName2, directoryHint: .isDirectory),
                URL(filePath: child2.string, directoryHint: .isDirectory),
                URL(filePath: child2.string).appending(path: grandchildName3, directoryHint: .isDirectory)
            ]
        )
#endif
    }

    @Test
    func testEnumerateNonexistentPath() throws {
        let nonexistentPath = FilePath("/does/not/exist/\(UUID().uuidString)")

        #expect(try Set(CSFileManager.shared.contentsOfDirectory(at: nonexistentPath)) == [])
#if canImport(Darwin)
        #expect(try Set(CSFileManager.shared.contentsOfDirectory(atPath: nonexistentPath.string)) == [])
#endif
#if Foundation
        #expect(try Set(CSFileManager.shared.contentsOfDirectory(at: URL(filePath: nonexistentPath.string))) == [])
#endif
    }

    @Test
    func testCreateDirectory() throws {
        let testDir = CSFileManager.shared.temporaryDirectory.appending(UUID().uuidString)
        defer { try? CSFileManager.shared.removeItem(at: testDir, recursively: true) }

        self.expectNoSuchFile(testDir)
        try CSFileManager.shared.createDirectory(at: testDir, mode: 0o755, recursively: false)
        #expect(try URL(filePath: testDir.string).checkResourceIsReachable())
        #expect(try FileManager.default.attributesOfItem(atPath: testDir.string)[.posixPermissions] as? mode_t == 0o755)

        let midDir = testDir.appending(UUID().uuidString)
        let deepDir = midDir.appending(UUID().uuidString)
        #expect(
            #expect(throws: (any Swift.Error).self) {
                try CSFileManager.shared.createDirectory(at: deepDir, recursively: false)
            }?.isFileNotFoundError == true
        )
        self.expectNoSuchFile(midDir)
        self.expectNoSuchFile(deepDir)
        try CSFileManager.shared.createDirectory(at: deepDir, mode: 0o700, recursively: true)
        #expect(try URL(filePath: deepDir.string).checkResourceIsReachable())
        #expect(try FileManager.default.attributesOfItem(atPath: midDir.string)[.posixPermissions] as? mode_t == 0o700)
        #expect(try FileManager.default.attributesOfItem(atPath: deepDir.string)[.posixPermissions] as? mode_t == 0o700)
    }

#if canImport(Darwin)
    @Test
    func testCreateDirectoryWithStringPaths() throws {
        let testDir = CSFileManager.shared.temporaryDirectory.appending(UUID().uuidString).string
        defer { try? CSFileManager.shared.removeItem(atPath: testDir, recursively: true) }

        self.expectNoSuchFile(testDir)
        try CSFileManager.shared.createDirectory(atPath: testDir, mode: 0o755, recursively: false)
        #expect(try URL(filePath: testDir).checkResourceIsReachable())
        #expect(try FileManager.default.attributesOfItem(atPath: testDir)[.posixPermissions] as? mode_t == 0o755)

        let midDir = FilePath(testDir).appending(UUID().uuidString).string
        let deepDir = FilePath(midDir).appending(UUID().uuidString).string
        #expect(
            #expect(throws: (any Swift.Error).self) {
                try CSFileManager.shared.createDirectory(atPath: deepDir, recursively: false)
            }?.isFileNotFoundError == true
        )
        self.expectNoSuchFile(midDir)
        self.expectNoSuchFile(deepDir)
        try CSFileManager.shared.createDirectory(atPath: deepDir, mode: 0o700, recursively: true)
        #expect(try URL(filePath: deepDir).checkResourceIsReachable())
        #expect(try FileManager.default.attributesOfItem(atPath: midDir)[.posixPermissions] as? mode_t == 0o700)
        #expect(try FileManager.default.attributesOfItem(atPath: deepDir)[.posixPermissions] as? mode_t == 0o700)
    }
#endif

#if Foundation
    @Test
    func testCreateDirectoryWithURLs() throws {
        let testDir = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: testDir) }

        self.expectNoSuchFile(testDir)
        try CSFileManager.shared.createDirectory(at: testDir, mode: 0o755, recursively: false)
        #expect(try testDir.checkResourceIsReachable())
        #expect(try FileManager.default.attributesOfItem(atPath: testDir.path)[.posixPermissions] as? mode_t == 0o755)

        let midDir = testDir.appending(path: UUID().uuidString)
        let deepDir = midDir.appending(path: UUID().uuidString)
        #expect(
            #expect(throws: (any Swift.Error).self) {
                try CSFileManager.shared.createDirectory(at: deepDir, recursively: false)
            }?.isFileNotFoundError == true
        )
        self.expectNoSuchFile(midDir)
        self.expectNoSuchFile(deepDir)
        try CSFileManager.shared.createDirectory(at: deepDir, mode: 0o700, recursively: true)
        #expect(try deepDir.checkResourceIsReachable())
        #expect(try FileManager.default.attributesOfItem(atPath: midDir.path)[.posixPermissions] as? mode_t == 0o700)
        #expect(try FileManager.default.attributesOfItem(atPath: deepDir.path)[.posixPermissions] as? mode_t == 0o700)
    }
#endif

    @Test
    func testCopyItems() throws {
        let testDir = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: testDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: testDir) }

        let src = testDir.appending(path: UUID().uuidString)
        let dst = testDir.appending(path: UUID().uuidString)

        let fileContents = "some file contents".data(using: .utf8)!
        let attribute = ExtendedAttribute(
            key: "com.charlessoft.CSFileManager.test-attribute",
            data: "arbitrary attribute".data(using: .utf8)!
        )

#if canImport(Darwin)
        let rsrcFork = ExtendedAttribute(
            key: XATTR_RESOURCEFORK_NAME,
            data: "you never know, something could use this".data(using: .utf8)!
        )
#endif

        func setupFile(src: URL, dst: URL) throws {
            let srcDotfile = src.deletingLastPathComponent().appending(path: "._\(src.lastPathComponent)")
            let dstDotfile = dst.deletingLastPathComponent().appending(path: "._\(dst.lastPathComponent)")

            try? CSFileManager.shared.removeItem(at: FilePath(src.path), recursively: true)
            try? CSFileManager.shared.removeItem(at: FilePath(dst.path), recursively: true)
            try? CSFileManager.shared.removeItem(at: FilePath(srcDotfile.path), recursively: true)
            try? CSFileManager.shared.removeItem(at: FilePath(dstDotfile.path), recursively: true)

            try fileContents.write(to: src)
            try attribute.write(to: FilePath(src.path))
#if canImport(Darwin)
            try rsrcFork.write(to: FilePath(src.path))
#endif
        }

        func setupFolder(src: URL, dst: URL) throws {
            let srcDotfile = src.deletingLastPathComponent().appending(path: "._\(src.lastPathComponent)")
            let dstDotfile = dst.deletingLastPathComponent().appending(path: "._\(dst.lastPathComponent)")

            try? CSFileManager.shared.removeItem(at: FilePath(src.path), recursively: true)
            try? CSFileManager.shared.removeItem(at: FilePath(dst.path), recursively: true)
            try? CSFileManager.shared.removeItem(at: FilePath(srcDotfile.path), recursively: true)
            try? CSFileManager.shared.removeItem(at: FilePath(dstDotfile.path), recursively: true)

            try CSFileManager.shared.createDirectory(at: FilePath(src.path), recursively: true)
            try attribute.write(to: FilePath(src.path))

            try setupFile(src: src.appending(path: "content_file"), dst: dst.appending(path: "content_file"))
        }

        func verifyFile(src: URL, dst: URL) throws {
            #expect(try CSFileManager.shared.itemIsReachable(at: FilePath(src.path)))
            #expect(try Data(contentsOf: dst) == fileContents)
#if canImport(Darwin)
            #expect(try Set(ExtendedAttribute.list(at: FilePath(dst.path))) == [attribute, rsrcFork])
#else
            #expect(try Set(ExtendedAttribute.list(at: FilePath(dst.path))) == [attribute])
#endif
        }

        func verifyFolder(src: URL, dst: URL) throws {
            #expect(try CSFileManager.shared.typeOfItem(at: FilePath(src.path)) == .directory)
            #expect(try CSFileManager.shared.typeOfItem(at: FilePath(dst.path)) == .directory)
            #expect(try Set(ExtendedAttribute.list(at: FilePath(dst.path))) == [attribute])
            try verifyFile(src: src.appending(path: "content_file"), dst: dst.appending(path: "content_file"))
        }

        #expect(
            #expect(throws: (any Swift.Error).self) {
                try CSFileManager.shared.copyItem(at: FilePath(src.path), to: FilePath(dst.path))
            }?.isFileNotFoundError == true
        )

#if canImport(Darwin)
        #expect(
            #expect(throws: (any Swift.Error).self) {
                try CSFileManager.shared.copyItem(atPath: src.path, toPath: dst.path)
            }?.isFileNotFoundError == true
        )
#endif

#if Foundation
        #expect(
            #expect(throws: (any Swift.Error).self) {
                try CSFileManager.shared.copyItem(at: src, to: dst)
            }?.isFileNotFoundError == true
        )
#endif

        try setupFile(src: src, dst: dst)
        try CSFileManager.shared.copyItem(at: FilePath(src.path), to: FilePath(dst.path))
        try verifyFile(src: src, dst: dst)

#if canImport(Darwin)
        try setupFile(src: src, dst: dst)
        try CSFileManager.shared.copyItem(atPath: src.path, toPath: dst.path)
        try verifyFile(src: src, dst: dst)
#endif

#if Foundation
        try setupFile(src: src, dst: dst)
        try CSFileManager.shared.copyItem(at: src, to: dst)
        try verifyFile(src: src, dst: dst)
#endif

        try setupFolder(src: src, dst: dst)
        try CSFileManager.shared.copyItem(at: FilePath(src.path), to: FilePath(dst.path))
        try verifyFolder(src: src, dst: dst)

#if canImport(Darwin)
        try setupFolder(src: src, dst: dst)
        try CSFileManager.shared.copyItem(atPath: src.path, toPath: dst.path)
        try verifyFolder(src: src, dst: dst)
#endif

#if Foundation
        try setupFolder(src: src, dst: dst)
        try CSFileManager.shared.copyItem(at: src, to: dst)
        try verifyFolder(src: src, dst: dst)
#endif
    }

    @Test(arguments: [nil] + withFixtures.images, [nil] + withFixtures.images)
    func testMoveItems(image1: DiskImage?, image2: DiskImage?) throws {
        let rsrcFork = image1.supportsResourceFork && image2.supportsResourceFork
        try self.testMoveItems(fromVolume: image1.mountPoint, toVolume: image2.mountPoint, testRsrcFork: rsrcFork)
    }

    private func testMoveItems(fromVolume vol1: URL, toVolume vol2: URL, testRsrcFork: Bool) throws {
        let test1 = vol1.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: test1, withIntermediateDirectories: true)
        defer { _ = try? FileManager.default.removeItem(at: test1) }

        let test2 = vol1.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: test2, withIntermediateDirectories: true)
        defer { _ = try? FileManager.default.removeItem(at: test2) }

        let src = test1.appending(path: UUID().uuidString)
        let dst = test2.appending(path: UUID().uuidString)

        let fileContents = "some file contents".data(using: .utf8)!
        let attribute = ExtendedAttribute(
            key: "com.charlessoft.CSFileManager.test-attribute",
            data: "arbitrary attribute".data(using: .utf8)!
        )

#if canImport(Darwin)
        let rsrcFork = ExtendedAttribute(
            key: XATTR_RESOURCEFORK_NAME,
            data: "you never know, something could use this".data(using: .utf8)!
        )
#endif

        func setupFile(src: URL, dst: URL) throws {
            try? CSFileManager.shared.removeItem(at: FilePath(src.path))
            try? CSFileManager.shared.removeItem(at: FilePath(dst.path))

            try fileContents.write(to: src)
            try attribute.write(to: FilePath(src.path))

#if canImport(Darwin)
            if testRsrcFork {
                try rsrcFork.write(to: FilePath(src.path))
            }
#endif
        }

        func setupFolder(src: URL, dst: URL) throws {
            try? CSFileManager.shared.removeItem(at: FilePath(src.path))
            try? CSFileManager.shared.removeItem(at: FilePath(dst.path))

            try CSFileManager.shared.createDirectory(at: FilePath(src.path), recursively: true)
            try attribute.write(to: FilePath(src.path))

            try setupFile(src: src.appending(path: "content_file"), dst: dst.appending(path: "content_file"))
        }

        func verifyFile(src: URL, dst: URL) throws {
            #expect(try !CSFileManager.shared.itemIsReachable(at: FilePath(src.path)))
            #expect(try Data(contentsOf: dst) == fileContents)


#if canImport(Darwin)
            let expectedAttributes: Set<ExtendedAttribute> = testRsrcFork ? [attribute, rsrcFork] : [attribute]
#else
            let expectedAttributes: Set<ExtendedAttribute> = [attribute]
#endif

            #expect(try Set(ExtendedAttribute.list(at: FilePath(dst.path))) == expectedAttributes)
        }

        func verifyFolder(src: URL, dst: URL) throws {
            #expect(try !CSFileManager.shared.itemIsReachable(at: FilePath(src.path)))
            #expect(try CSFileManager.shared.typeOfItem(at: FilePath(dst.path)) == .directory)
            #expect(try Set(ExtendedAttribute.list(at: FilePath(dst.path))) == [attribute])
            try verifyFile(src: src.appending(path: "content_file"), dst: dst.appending(path: "content_file"))
        }

        #expect(
            #expect(throws: (any Swift.Error).self) {
                try CSFileManager.shared.moveItem(at: FilePath(src.path), to: FilePath(dst.path))
            }?.isFileNotFoundError == true
        )

#if canImport(Darwin)
        #expect(
            #expect(throws: (any Swift.Error).self) {
                try CSFileManager.shared.moveItem(atPath: src.path, toPath: dst.path)
            }?.isFileNotFoundError == true
        )
#endif

#if Foundation
        #expect(
            #expect(throws: (any Swift.Error).self) {
                try CSFileManager.shared.moveItem(at: src, to: dst)
            }?.isFileNotFoundError == true
        )
#endif

        try setupFile(src: src, dst: dst)
        try CSFileManager.shared.moveItem(at: FilePath(src.path), to: FilePath(dst.path))
        try verifyFile(src: src, dst: dst)

#if canImport(Darwin)
        try setupFile(src: src, dst: dst)
        try CSFileManager.shared.moveItem(atPath: src.path, toPath: dst.path)
        try verifyFile(src: src, dst: dst)
#endif

#if Foundation
        try setupFile(src: src, dst: dst)
        try CSFileManager.shared.moveItem(at: src, to: dst)
        try verifyFile(src: src, dst: dst)
#endif

        try setupFolder(src: src, dst: dst)
        try CSFileManager.shared.moveItem(at: FilePath(src.path), to: FilePath(dst.path))
        try verifyFolder(src: src, dst: dst)

#if canImport(Darwin)
        try setupFolder(src: src, dst: dst)
        try CSFileManager.shared.moveItem(atPath: src.path, toPath: dst.path)
        try verifyFolder(src: src, dst: dst)
#endif

#if Foundation
        try setupFolder(src: src, dst: dst)
        try CSFileManager.shared.moveItem(at: src, to: dst)
        try verifyFolder(src: src, dst: dst)
#endif
    }

    @Test
    func testRemoveRegularFile() throws {
        let testDir = CSFileManager.shared.temporaryDirectory.appending(UUID().uuidString)
        try CSFileManager.shared.createDirectory(at: testDir, mode: 0o755, recursively: false)
        defer { try? CSFileManager.shared.removeItem(at: testDir, recursively: true) }

        let child = testDir.appending(UUID().uuidString)

        try "testing 1 2 3".data(using: .utf8)!.write(to: URL(filePath: child.string))
        #expect(try URL(filePath: child.string).checkResourceIsReachable())
        try CSFileManager.shared.removeItem(at: child, recursively: false)
        self.expectNoSuchFile(child)

        try "testing 1 2 3".data(using: .utf8)!.write(to: URL(filePath: child.string))
        #expect(try URL(filePath: child.string).checkResourceIsReachable())
        try CSFileManager.shared.removeItem(at: child, recursively: true)
        self.expectNoSuchFile(child)

#if canImport(Darwin)
        try "testing 1 2 3".data(using: .utf8)!.write(to: URL(filePath: child.string))
        #expect(try URL(filePath: child.string).checkResourceIsReachable())
        try CSFileManager.shared.removeItem(atPath: child.string, recursively: false)
        self.expectNoSuchFile(child)

        try "testing 1 2 3".data(using: .utf8)!.write(to: URL(filePath: child.string))
        #expect(try URL(filePath: child.string).checkResourceIsReachable())
        try CSFileManager.shared.removeItem(atPath: child.string, recursively: true)
        self.expectNoSuchFile(child)
#endif

#if Foundation
        try "testing 1 2 3".data(using: .utf8)!.write(to: URL(filePath: child.string))
        #expect(try URL(filePath: child.string).checkResourceIsReachable())
        try CSFileManager.shared.removeItem(at: URL(filePath: child.string), recursively: false)
        self.expectNoSuchFile(child)

        try "testing 1 2 3".data(using: .utf8)!.write(to: URL(filePath: child.string))
        #expect(try URL(filePath: child.string).checkResourceIsReachable())
        try CSFileManager.shared.removeItem(at: URL(filePath: child.string), recursively: true)
        self.expectNoSuchFile(child)
#endif
    }

    @Test
    func testRemoveEmptyDirectory() throws {
        let testDir = CSFileManager.shared.temporaryDirectory.appending(UUID().uuidString)
        try CSFileManager.shared.createDirectory(at: testDir, mode: 0o755, recursively: false)
        defer { try? CSFileManager.shared.removeItem(at: testDir, recursively: true) }

        let child = testDir.appending(UUID().uuidString)

        try CSFileManager.shared.createDirectory(at: child)
        #expect(try URL(filePath: child.string).checkResourceIsReachable())
        try CSFileManager.shared.removeItem(at: child, recursively: false)
        self.expectNoSuchFile(child)

        try CSFileManager.shared.createDirectory(at: child)
        #expect(try URL(filePath: child.string).checkResourceIsReachable())
        try CSFileManager.shared.removeItem(at: child, recursively: true)
        self.expectNoSuchFile(child)

#if canImport(Darwin)
        try CSFileManager.shared.createDirectory(at: child)
        #expect(try URL(filePath: child.string).checkResourceIsReachable())
        try CSFileManager.shared.removeItem(atPath: child.string, recursively: false)
        self.expectNoSuchFile(child)

        try CSFileManager.shared.createDirectory(at: child)
        #expect(try URL(filePath: child.string).checkResourceIsReachable())
        try CSFileManager.shared.removeItem(atPath: child.string, recursively: true)
        self.expectNoSuchFile(child)
#endif

#if Foundation
        try CSFileManager.shared.createDirectory(at: child)
        #expect(try URL(filePath: child.string).checkResourceIsReachable())
        try CSFileManager.shared.removeItem(at: URL(filePath: child.string), recursively: false)
        self.expectNoSuchFile(child)

        try CSFileManager.shared.createDirectory(at: child)
        #expect(try URL(filePath: child.string).checkResourceIsReachable())
        try CSFileManager.shared.removeItem(at: URL(filePath: child.string), recursively: true)
        self.expectNoSuchFile(child)
#endif
    }

    @Test
    func testRemoveDirectoryWithContents() throws {
        let testDir = CSFileManager.shared.temporaryDirectory.appending(UUID().uuidString)
        try CSFileManager.shared.createDirectory(at: testDir, mode: 0o755, recursively: false)
        defer {
            #expect((try? URL(filePath: testDir.string).checkResourceIsReachable()) == true)

            try? CSFileManager.shared.removeItem(at: testDir, recursively: true)
            self.expectNoSuchFile(testDir)
        }
        
        let child = testDir.appending(UUID().uuidString)
        let grandchild = child.appending(UUID().uuidString)

        try CSFileManager.shared.createDirectory(at: child)
        try "testing 1 2 3".data(using: .utf8)!.write(to: URL(filePath: grandchild.string))
        #expect(try URL(filePath: child.string).checkResourceIsReachable())
        #expect(throws: Errno.directoryNotEmpty) {
            try CSFileManager.shared.removeItem(at: child, recursively: false)
        }
#if canImport(Darwin)
        #expect(throws: Errno.directoryNotEmpty) {
            try CSFileManager.shared.removeItem(atPath: child.string, recursively: false)
        }
#endif
#if Foundation
        #expect(throws: Errno.directoryNotEmpty) {
            try CSFileManager.shared.removeItem(at: URL(filePath: child.string), recursively: false)
        }
#endif
        #expect(try URL(filePath: child.string).checkResourceIsReachable())

        try CSFileManager.shared.removeItem(at: child, recursively: true)
        self.expectNoSuchFile(child)

#if canImport(Darwin)
        try CSFileManager.shared.createDirectory(at: child)
        try "testing 1 2 3".data(using: .utf8)!.write(to: URL(filePath: grandchild.string))
        #expect(try URL(filePath: child.string).checkResourceIsReachable())
        try CSFileManager.shared.removeItem(atPath: child.string, recursively: true)
        self.expectNoSuchFile(child)
#endif

#if Foundation
        try CSFileManager.shared.createDirectory(at: child)
        try "testing 1 2 3".data(using: .utf8)!.write(to: URL(filePath: grandchild.string))
        #expect(try URL(filePath: child.string).checkResourceIsReachable())
        try CSFileManager.shared.removeItem(at: URL(filePath: child.string), recursively: true)
        self.expectNoSuchFile(child)
#endif
    }

    @Test(arguments: [nil] + withFixtures.images, [nil] + withFixtures.images)
    func testReplaceItems(image1: DiskImage?, image2: DiskImage?) throws {
        try self.testReplaceItems(fromVolume: image1.mountPoint, toVolume: image2.mountPoint)
    }

    private func testReplaceItems(fromVolume vol1: URL, toVolume vol2: URL) throws {
        let testDir1 = FilePath(vol1.path).appending(UUID().uuidString)
        try CSFileManager.shared.createDirectory(at: testDir1, mode: 0o755, recursively: false)
        defer { try? CSFileManager.shared.removeItem(at: testDir1, recursively: true) }

        let testDir2 = FilePath(vol2.path).appending(UUID().uuidString)
        try CSFileManager.shared.createDirectory(at: testDir2, mode: 0o755, recursively: false)
        defer { try? CSFileManager.shared.removeItem(at: testDir2, recursively: true) }

        let file1 = testDir1.appending(UUID().uuidString)
        let file2 = testDir2.appending(UUID().uuidString)

        let file1Data = "testing 1 2 3".data(using: .utf8)!
        let file2Data = "testing 2 3 4".data(using: .utf8)!

        let xattrName1 = "xattr1"
        let xattrName2 = "xattr2"

        let xattrValue1 = "some xattr string"
        let xattrValue2 = "something else"

        func setUpFiles() throws {
            try? CSFileManager.shared.removeItem(at: file1)
            try? CSFileManager.shared.removeItem(at: file2)

            try file1Data.write(to: URL(filePath: file1.string), options: .atomic)
            try file2Data.write(to: URL(filePath: file2.string), options: .atomic)

            try xattrValue1.data(using: .utf8)!.withUnsafeBytes { str in
                try ExtendedAttribute(key: xattrName1, data: str).write(to: file1)
            }
            
            try xattrValue2.data(using: .utf8)!.withUnsafeBytes { str in
                try ExtendedAttribute(key: xattrName2, data: str).write(to: file2)
            }
        }

        func xattrNames(at path: FilePath) throws -> Set<String> {
            let xattr = try ExtendedAttribute.list(at: path)

            return Set(xattr.map(\.key))
        }

        func xattr(at path: FilePath, forKey key: String) throws -> String {
            let xattr = try ExtendedAttribute(at: path, key: key)

            guard let stringValue = String(data: Data(xattr.data), encoding: .utf8) else {
                throw CocoaError(.fileReadUnknown)
            }

            return stringValue
        }

        try setUpFiles()
        #expect(try xattrNames(at: file1) == [xattrName1])
        #expect(try xattr(at: file1, forKey: xattrName1) == xattrValue1)
        #expect(try xattrNames(at: file2) == [xattrName2])
        #expect(try xattr(at: file2, forKey: xattrName2) == xattrValue2)
        try CSFileManager.shared.replaceItem(at: file1, withItemAt: file2)
        #expect(try xattrNames(at: file1) == [xattrName1, xattrName2])
        #expect(try xattr(at: file1, forKey: xattrName1) == xattrValue1)
        #expect(try xattr(at: file1, forKey: xattrName2) == xattrValue2)
        self.expectNoSuchFile(file2)

        try setUpFiles()
        #expect(try xattrNames(at: file1) == [xattrName1])
        #expect(try xattr(at: file1, forKey: xattrName1) == xattrValue1)
        #expect(try xattrNames(at: file2) == [xattrName2])
        #expect(try xattr(at: file2, forKey: xattrName2) == xattrValue2)
        try CSFileManager.shared.replaceItem(at: file1, withItemAt: file2, options: .withoutDeletingBackupItem)
        #expect(try xattrNames(at: file1) == [xattrName1, xattrName2])
        #expect(try xattr(at: file1, forKey: xattrName1) == xattrValue1)
        #expect(try xattr(at: file1, forKey: xattrName2) == xattrValue2)
        #expect(try xattrNames(at: file2) == [xattrName1])
        #expect(try xattr(at: file2, forKey: xattrName1) == xattrValue1)

        try setUpFiles()
        #expect(try xattrNames(at: file1) == [xattrName1])
        #expect(try xattr(at: file1, forKey: xattrName1) == xattrValue1)
        #expect(try xattrNames(at: file2) == [xattrName2])
        #expect(try xattr(at: file2, forKey: xattrName2) == xattrValue2)
        try CSFileManager.shared.replaceItem(at: file1, withItemAt: file2, options: .usingNewMetadataOnly)
        #expect(try xattrNames(at: file1) == [xattrName2])
        #expect(try xattr(at: file1, forKey: xattrName2) == xattrValue2)
        self.expectNoSuchFile(file2)

        try setUpFiles()
        #expect(try xattrNames(at: file1) == [xattrName1])
        #expect(try xattr(at: file1, forKey: xattrName1) == xattrValue1)
        #expect(try xattrNames(at: file2) == [xattrName2])
        #expect(try xattr(at: file2, forKey: xattrName2) == xattrValue2)
        try CSFileManager.shared.replaceItem(
            at: file1,
            withItemAt: file2,
            options: [.usingNewMetadataOnly, .withoutDeletingBackupItem]
        )
        #expect(try xattrNames(at: file1) == [xattrName2])
        #expect(try xattr(at: file1, forKey: xattrName2) == xattrValue2)
        #expect(try xattrNames(at: file2) == [xattrName1])
        #expect(try xattr(at: file2, forKey: xattrName1) == xattrValue1)

#if canImport(Darwin)
        try setUpFiles()
        #expect(try xattrNames(at: file1) == [xattrName1])
        #expect(try xattr(at: file1, forKey: xattrName1) == xattrValue1)
        #expect(try xattrNames(at: file2) == [xattrName2])
        #expect(try xattr(at: file2, forKey: xattrName2) == xattrValue2)
        try CSFileManager.shared.replaceItem(atPath: file1.string, withItemAtPath: file2.string)
        #expect(try xattrNames(at: file1) == [xattrName1, xattrName2])
        #expect(try xattr(at: file1, forKey: xattrName1) == xattrValue1)
        #expect(try xattr(at: file1, forKey: xattrName2) == xattrValue2)
        self.expectNoSuchFile(file2)

        try setUpFiles()
        #expect(try xattrNames(at: file1) == [xattrName1])
        #expect(try xattr(at: file1, forKey: xattrName1) == xattrValue1)
        #expect(try xattrNames(at: file2) == [xattrName2])
        #expect(try xattr(at: file2, forKey: xattrName2) == xattrValue2)
        try CSFileManager.shared.replaceItem(
            atPath: file1.string,
            withItemAtPath: file2.string,
            options: .withoutDeletingBackupItem
        )
        #expect(try xattrNames(at: file1) == [xattrName1, xattrName2])
        #expect(try xattr(at: file1, forKey: xattrName1) == xattrValue1)
        #expect(try xattr(at: file1, forKey: xattrName2) == xattrValue2)
        #expect(try xattrNames(at: file2) == [xattrName1])
        #expect(try xattr(at: file2, forKey: xattrName1) == xattrValue1)

        try setUpFiles()
        #expect(try xattrNames(at: file1) == [xattrName1])
        #expect(try xattr(at: file1, forKey: xattrName1) == xattrValue1)
        #expect(try xattrNames(at: file2) == [xattrName2])
        #expect(try xattr(at: file2, forKey: xattrName2) == xattrValue2)
        try CSFileManager.shared.replaceItem(
            atPath: file1.string,
            withItemAtPath: file2.string,
            options: .usingNewMetadataOnly
        )
        #expect(try xattrNames(at: file1) == [xattrName2])
        #expect(try xattr(at: file1, forKey: xattrName2) == xattrValue2)
        self.expectNoSuchFile(file2)

        try setUpFiles()
        #expect(try xattrNames(at: file1) == [xattrName1])
        #expect(try xattr(at: file1, forKey: xattrName1) == xattrValue1)
        #expect(try xattrNames(at: file2) == [xattrName2])
        #expect(try xattr(at: file2, forKey: xattrName2) == xattrValue2)
        try CSFileManager.shared.replaceItem(
            atPath: file1.string,
            withItemAtPath: file2.string,
            options: [.usingNewMetadataOnly, .withoutDeletingBackupItem]
        )
        #expect(try xattrNames(at: file1) == [xattrName2])
        #expect(try xattr(at: file1, forKey: xattrName2) == xattrValue2)
        #expect(try xattrNames(at: file2) == [xattrName1])
        #expect(try xattr(at: file2, forKey: xattrName1) == xattrValue1)
#endif

#if Foundation
        try setUpFiles()
        #expect(try xattrNames(at: file1) == [xattrName1])
        #expect(try xattr(at: file1, forKey: xattrName1) == xattrValue1)
        #expect(try xattrNames(at: file2) == [xattrName2])
        #expect(try xattr(at: file2, forKey: xattrName2) == xattrValue2)
        try CSFileManager.shared.replaceItem(at: URL(filePath: file1.string), withItemAt: URL(filePath: file2.string))
        #expect(try xattrNames(at: file1) == [xattrName1, xattrName2])
        #expect(try xattr(at: file1, forKey: xattrName1) == xattrValue1)
        #expect(try xattr(at: file1, forKey: xattrName2) == xattrValue2)
        #expect(
            #expect(throws: (any Swift.Error).self) {
                try URL(filePath: file2.string).checkResourceIsReachable()
            }?.isFileNotFoundError == true
        )

        try setUpFiles()
        #expect(try xattrNames(at: file1) == [xattrName1])
        #expect(try xattr(at: file1, forKey: xattrName1) == xattrValue1)
        #expect(try xattrNames(at: file2) == [xattrName2])
        #expect(try xattr(at: file2, forKey: xattrName2) == xattrValue2)
        try CSFileManager.shared.replaceItem(
            at: URL(filePath: file1.string),
            withItemAt: URL(filePath: file2.string),
            options: .withoutDeletingBackupItem
        )
        #expect(try xattrNames(at: file1) == [xattrName1, xattrName2])
        #expect(try xattr(at: file1, forKey: xattrName1) == xattrValue1)
        #expect(try xattr(at: file1, forKey: xattrName2) == xattrValue2)
        #expect(try xattrNames(at: file2) == [xattrName1])
        #expect(try xattr(at: file2, forKey: xattrName1) == xattrValue1)

        try setUpFiles()
        #expect(try xattrNames(at: file1) == [xattrName1])
        #expect(try xattr(at: file1, forKey: xattrName1) == xattrValue1)
        #expect(try xattrNames(at: file2) == [xattrName2])
        #expect(try xattr(at: file2, forKey: xattrName2) == xattrValue2)
        try CSFileManager.shared.replaceItem(
            at: URL(filePath: file1.string),
            withItemAt: URL(filePath: file2.string),
            options: .usingNewMetadataOnly
        )
        #expect(try xattrNames(at: file1) == [xattrName2])
        #expect(try xattr(at: file1, forKey: xattrName2) == xattrValue2)
        self.expectNoSuchFile(file2)

        try setUpFiles()
        #expect(try xattrNames(at: file1) == [xattrName1])
        #expect(try xattr(at: file1, forKey: xattrName1) == xattrValue1)
        #expect(try xattrNames(at: file2) == [xattrName2])
        #expect(try xattr(at: file2, forKey: xattrName2) == xattrValue2)
        try CSFileManager.shared.replaceItem(
            at: URL(filePath: file1.string),
            withItemAt: URL(filePath: file2.string),
            options: [.usingNewMetadataOnly, .withoutDeletingBackupItem]
        )
        #expect(try xattrNames(at: file1) == [xattrName2])
        #expect(try xattr(at: file1, forKey: xattrName2) == xattrValue2)
        #expect(try xattrNames(at: file2) == [xattrName1])
        #expect(try xattr(at: file2, forKey: xattrName1) == xattrValue1)
#endif
    }
}

fileprivate extension CSFileManagerTests.DiskImage? {
    var supportsResourceFork: Bool {
        self?.info.fileSystem.supportsResourceFork ?? CSFileManagerTests.hostSupportsResourceFork
    }

    var mountPoint: URL { self?.mountPoint ?? FileManager.default.temporaryDirectory }
}
