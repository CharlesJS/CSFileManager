import CSFileInfo
import CSFileInfo_Foundation
@testable import CSFileManager
@testable import CSFileManager_Foundation
import CSErrors
import System
import XCTest

@available(macOS 13.0, *)
final class CSFileManagerTests: XCTestCase {
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
                try self.testCreateItemReplacementDirectory()
                self.testReachablePaths()
                self.testUnreachablePaths()
                try self.testReachabilityCheckError()
                try self.testGetTypeOfItem()
                try self.testContentsOfDirectory()
                try self.testCreateDirectory()
                try self.testCreateDirectoryWithStringPaths()
                try self.testCreateDirectoryWithURLs()
                try self.testMoveItems()
                try self.testRemoveRegularFile()
                try self.testRemoveEmptyDirectory()
                try self.testRemoveDirectoryWithContents()
                try self.testReplaceItems()
            }
        }
    }

    private struct DiskImage {
        let imageURL: URL
        let mountPoint: URL
        let devEntry: URL
        let supportResourceFork: Bool
    }
    private static var diskImages: [String : DiskImage] = [:]

    override class func setUp() {
        do {
            let tempURL = FileManager.default.temporaryDirectory
            let fileSystems = ["APFS", "HFS+", "ExFAT"]

            self.diskImages = try fileSystems.reduce(into: [:]) { diskImages, eachFS in
                let dmgURL = try self.createDiskImage(fs: eachFS, at: tempURL.appending(path: UUID().uuidString), megabytes: 10)

                let (mountPoint: mountPoint, devEntry: devEntry) = try self.mountDiskImage(at: dmgURL)

                let rsrcFork = !["ExFAT"].contains(eachFS)

                diskImages[eachFS] = DiskImage(
                    imageURL: dmgURL,
                    mountPoint: mountPoint,
                    devEntry: devEntry,
                    supportResourceFork: rsrcFork
                )
            }
        } catch {
            XCTFail(error.localizedDescription)
        }
    }

    override class func tearDown() {
        do {
            for eachDMG in self.diskImages.values {
                try self.unmountDiskImage(at: eachDMG.devEntry)
                try FileManager.default.removeItem(at: eachDMG.imageURL)
            }
        } catch {
            XCTFail(error.localizedDescription)
        }
    }

    func testRootDirectory() {
        XCTAssertEqual(CSFileManager.shared.rootDirectory, "/")
        XCTAssertEqual(CSFileManager.shared.rootDirectoryStringPath, "/")
        XCTAssertEqual(CSFileManager.shared.rootDirectoryURL, URL(filePath: "/"))
    }

    func testHomeDirectory() {
        XCTAssertEqual(CSFileManager.shared.homeDirectoryForCurrentUser, FilePath(NSHomeDirectory()))
        XCTAssertEqual(CSFileManager.shared.homeDirectoryStringPathForCurrentUser, NSHomeDirectory())
        XCTAssertEqual(
            CSFileManager.shared.homeDirectoryURLForCurrentUser,
            URL(filePath: NSHomeDirectory(), directoryHint: .isDirectory)
        )
    }

    func testTemporaryDirectory() {
        XCTAssertEqual(CSFileManager.shared.temporaryDirectory, FilePath(FileManager.default.temporaryDirectory.path))
        XCTAssertEqual(CSFileManager.shared.temporaryDirectoryStringPath, FileManager.default.temporaryDirectory.path + "/")
        XCTAssertEqual(CSFileManager.shared.temporaryDirectoryURL, FileManager.default.temporaryDirectory)
    }

    func testTemporaryDirectoryFallback() {
        let oldTmpDir = String(cString: getenv("TMPDIR"))
        defer { setenv("TMPDIR", oldTmpDir, 1) }
        unsetenv("TMPDIR")

        XCTAssertEqual(CSFileManager.shared.temporaryDirectory, FilePath("/tmp"))
        XCTAssertEqual(CSFileManager.shared.temporaryDirectoryStringPath, "/tmp")
        XCTAssertEqual(CSFileManager.shared.temporaryDirectoryURL, URL(filePath: "/tmp/"))
    }

    func testCreateTemporaryFile() throws {
        let (desc, path) = try CSFileManager.shared.createTemporaryFile()
        defer {
            _ = try? desc.close()
            _ = try? CSFileManager.shared.removeItem(at: path)
        }

        XCTAssertTrue(path.starts(with: CSFileManager.shared.temporaryDirectory))
        XCTAssertEqual(path.lastComponent?.string.count, 32)
        try desc.writeAll("Foo Bar".data(using: .ascii)!)

        XCTAssertEqual(try String(data: Data(contentsOf: URL(filePath: path.string)), encoding: .ascii)!, "Foo Bar")

        let (fdInt, pathString) = try CSFileManager.shared.createTemporaryFileWithStringPath()
        defer {
            close(fdInt)
            _ = try? CSFileManager.shared.removeItem(atPath: pathString)
        }

        XCTAssertTrue(pathString.starts(with: CSFileManager.shared.temporaryDirectoryStringPath))
        XCTAssertEqual(URL(filePath: pathString).lastPathComponent.count, 32)
        XCTAssertEqual(write(fdInt, "Foo Bar Baz", 11), 11)
        XCTAssertEqual(try String(data: Data(contentsOf: URL(filePath: pathString)), encoding: .ascii)!, "Foo Bar Baz")
            
        let (handle, url) = try CSFileManager.shared.createTemporaryFileURL()
        defer {
            _ = try? handle.close()
            _ = try? CSFileManager.shared.removeItem(at: url)
        }

        XCTAssertTrue(url.path.starts(with: CSFileManager.shared.temporaryDirectoryStringPath))
        XCTAssertEqual(url.lastPathComponent.count, 32)
        try handle.write(contentsOf: "Foo Bar Baz".data(using: .ascii)!)
        XCTAssertEqual(try String(data: Data(contentsOf: url), encoding: .ascii)!, "Foo Bar Baz")
    }

    func testCreateTemporaryFileWithDirectory() throws {
        let directory = FilePath("/tmp/\(UUID().uuidString)")
        try CSFileManager.shared.createDirectory(at: directory)
        defer { _ = try? CSFileManager.shared.removeItem(at: directory) }

        let (desc, path) = try CSFileManager.shared.createTemporaryFile(directory: directory)
        defer { _ = try? desc.close() }

        XCTAssertTrue(path.starts(with: directory))
        XCTAssertEqual(path.lastComponent?.string.count, 32)
        try desc.writeAll("Foo Bar".data(using: .ascii)!)

        XCTAssertEqual(try String(data: Data(contentsOf: URL(filePath: path.string)), encoding: .ascii)!, "Foo Bar")

        let (fdInt, pathString) = try CSFileManager.shared.createTemporaryFileWithStringPath(directory: directory.string)
        defer { close(fdInt) }

        XCTAssertTrue(pathString.starts(with: directory.string))
        XCTAssertEqual(URL(filePath: pathString).lastPathComponent.count, 32)
        XCTAssertEqual(write(fdInt, "Foo Bar Baz", 11), 11)
        XCTAssertEqual(try String(data: Data(contentsOf: URL(filePath: pathString)), encoding: .ascii)!, "Foo Bar Baz")
            
        let (handle, url) = try CSFileManager.shared.createTemporaryFileURL(directory: URL(filePath: directory))
        defer { _ = try? handle.close() }

        XCTAssertTrue(url.path.starts(with: directory.string))
        XCTAssertEqual(url.lastPathComponent.count, 32)
        try handle.write(contentsOf: "Foo Bar Baz".data(using: .ascii)!)
        XCTAssertEqual(try String(data: Data(contentsOf: url), encoding: .ascii)!, "Foo Bar Baz")
    }

    func testCreateTemporaryFileWithTemplate() throws {
        let (desc, path) = try CSFileManager.shared.createTemporaryFile(template: "fooXXXXX")
        defer {
            _ = try? desc.close()
            _ = try? CSFileManager.shared.removeItem(at: path)
        }

        XCTAssertTrue(path.starts(with: CSFileManager.shared.temporaryDirectory))
        XCTAssertEqual(path.lastComponent?.string.count, 8)
        XCTAssertEqual(path.lastComponent?.string.prefix(3), "foo")
        XCTAssertNotEqual(path.lastComponent?.string.suffix(5), "XXXXX")
        XCTAssertNil(path.extension)
        try desc.writeAll("Foo Bar".data(using: .ascii)!)

        XCTAssertEqual(try String(data: Data(contentsOf: URL(filePath: path.string)), encoding: .ascii)!, "Foo Bar")

        let (fdInt, pathString) = try CSFileManager.shared.createTemporaryFileWithStringPath(template: "quxXXX")
        defer {
            close(fdInt)
            _ = try? CSFileManager.shared.removeItem(atPath: pathString)
        }

        XCTAssertTrue(pathString.starts(with: CSFileManager.shared.temporaryDirectoryStringPath))
        XCTAssertEqual(URL(filePath: pathString).lastPathComponent.count, 6)
        XCTAssertEqual(URL(filePath: pathString).lastPathComponent.prefix(3), "qux")
        XCTAssertNotEqual(URL(filePath: pathString).lastPathComponent.suffix(3), "XXX")
        XCTAssertEqual(URL(filePath: pathString).pathExtension, "")
        XCTAssertEqual(write(fdInt, "Foo Bar Baz", 11), 11)
        XCTAssertEqual(try String(data: Data(contentsOf: URL(filePath: pathString)), encoding: .ascii)!, "Foo Bar Baz")
        
        let (handle, url) = try CSFileManager.shared.createTemporaryFileURL(template: "fooXXXXX")
        defer {
            _ = try? handle.close()
            _ = try? CSFileManager.shared.removeItem(at: url)
        }

        XCTAssertTrue(url.path.starts(with: CSFileManager.shared.temporaryDirectoryStringPath))
        XCTAssertEqual(url.lastPathComponent.count, 8)
        XCTAssertEqual(url.lastPathComponent.prefix(3), "foo")
        XCTAssertNotEqual(url.lastPathComponent.suffix(5), "XXXXX")
        XCTAssertEqual(url.pathExtension, "")
        try handle.write(contentsOf: "Foo Bar Baz".data(using: .ascii)!)
        XCTAssertEqual(try String(data: Data(contentsOf: url), encoding: .ascii)!, "Foo Bar Baz")
    }

    func testCreateTemporaryFileWithTemplateAndSuffix() throws {
        let (desc, path) = try CSFileManager.shared.createTemporaryFile(template: "fooXXXXX", suffix: "bar.baz")
        defer {
            _ = try? desc.close()
            _ = try? CSFileManager.shared.removeItem(at: path)
        }

        XCTAssertTrue(path.starts(with: CSFileManager.shared.temporaryDirectory))
        XCTAssertEqual(path.lastComponent?.string.count, 15)
        XCTAssertEqual(path.lastComponent?.string.prefix(3), "foo")
        XCTAssertNotEqual(path.lastComponent?.string.prefix(8).suffix(5), "XXXXX")
        XCTAssertEqual(path.lastComponent?.string.suffix(7), "bar.baz")
        XCTAssertEqual(path.extension, "baz")
        try desc.writeAll("Foo Bar".data(using: .ascii)!)

        XCTAssertEqual(try String(data: Data(contentsOf: URL(filePath: path.string)), encoding: .ascii)!, "Foo Bar")

        let (fdInt, pathString) = try CSFileManager.shared.createTemporaryFileWithStringPath(
            template: "quxXXX",
            suffix: "quux.foo"
        )
        defer {
            close(fdInt)
            _ = try? CSFileManager.shared.removeItem(atPath: pathString)
        }

        XCTAssertTrue(pathString.starts(with: CSFileManager.shared.temporaryDirectoryStringPath))
        XCTAssertEqual(URL(filePath: pathString).lastPathComponent.count, 14)
        XCTAssertEqual(URL(filePath: pathString).lastPathComponent.prefix(3), "qux")
        XCTAssertNotEqual(URL(filePath: pathString).lastPathComponent.prefix(6).suffix(3), "XXX")
        XCTAssertEqual(URL(filePath: pathString).lastPathComponent.suffix(8), "quux.foo")
        XCTAssertEqual(URL(filePath: pathString).pathExtension, "foo")
        XCTAssertEqual(write(fdInt, "Foo Bar Baz", 11), 11)
        XCTAssertEqual(try String(data: Data(contentsOf: URL(filePath: pathString)), encoding: .ascii)!, "Foo Bar Baz")
        
        let (handle, url) = try CSFileManager.shared.createTemporaryFileURL(template: "fooXXXXX", suffix: "bar.baz")
        defer {
            _ = try? handle.close()
            _ = try? CSFileManager.shared.removeItem(at: url)
        }

        XCTAssertTrue(url.path.starts(with: CSFileManager.shared.temporaryDirectoryStringPath))
        XCTAssertEqual(url.lastPathComponent.count, 15)
        XCTAssertEqual(url.lastPathComponent.prefix(3), "foo")
        XCTAssertNotEqual(url.lastPathComponent.prefix(8).suffix(5), "XXXXX")
        XCTAssertEqual(url.lastPathComponent.suffix(7), "bar.baz")
        XCTAssertEqual(url.pathExtension, "baz")
        try handle.write(contentsOf: "Foo Bar Baz".data(using: .ascii)!)
        XCTAssertEqual(try String(data: Data(contentsOf: url), encoding: .ascii)!, "Foo Bar Baz")
    }
    
    func testCreateTemporaryFileWithTemplateAndFallback() throws {
        let oldTmpDir = String(cString: getenv("TMPDIR"))
        defer { setenv("TMPDIR", oldTmpDir, 1) }
        unsetenv("TMPDIR")

        let (desc, path) = try CSFileManager.shared.createTemporaryFile(template: "fooXXXXX", suffix: "bar.baz")
        defer {
            _ = try? desc.close()
            _ = try? CSFileManager.shared.removeItem(at: path)
        }

        XCTAssertTrue(path.starts(with: "/tmp/"))
        XCTAssertEqual(path.lastComponent?.string.count, 15)
        XCTAssertEqual(path.lastComponent?.string.prefix(3), "foo")
        XCTAssertNotEqual(path.lastComponent?.string.prefix(8).suffix(5), "XXXXX")
        XCTAssertEqual(path.lastComponent?.string.suffix(7), "bar.baz")
        XCTAssertEqual(path.extension, "baz")
        try desc.writeAll("Foo Bar".data(using: .ascii)!)

        XCTAssertEqual(try String(data: Data(contentsOf: URL(filePath: path.string)), encoding: .ascii)!, "Foo Bar")

        let (fdInt, pathString) = try CSFileManager.shared.createTemporaryFileWithStringPath(
            template: "quxXXX",
            suffix: "quux.foo"
        )
        defer {
            close(fdInt)
            _ = try? CSFileManager.shared.removeItem(atPath: pathString)
        }

        XCTAssertTrue(pathString.starts(with: "/tmp/"))
        XCTAssertEqual(URL(filePath: pathString).lastPathComponent.count, 14)
        XCTAssertEqual(URL(filePath: pathString).lastPathComponent.prefix(3), "qux")
        XCTAssertNotEqual(URL(filePath: pathString).lastPathComponent.prefix(6).suffix(3), "XXX")
        XCTAssertEqual(URL(filePath: pathString).lastPathComponent.suffix(8), "quux.foo")
        XCTAssertEqual(URL(filePath: pathString).pathExtension, "foo")
        XCTAssertEqual(write(fdInt, "Foo Bar Baz", 11), 11)
        XCTAssertEqual(try String(data: Data(contentsOf: URL(filePath: pathString)), encoding: .ascii)!, "Foo Bar Baz")
        
        let (handle, url) = try CSFileManager.shared.createTemporaryFileURL(template: "fooXXXXX", suffix: "bar.baz")
        defer {
            _ = try? handle.close()
            _ = try? CSFileManager.shared.removeItem(at: url)
        }

        XCTAssertTrue(url.path.starts(with: "/tmp/"))
        XCTAssertEqual(url.lastPathComponent.count, 15)
        XCTAssertEqual(url.lastPathComponent.prefix(3), "foo")
        XCTAssertNotEqual(url.lastPathComponent.prefix(8).suffix(5), "XXXXX")
        XCTAssertEqual(url.lastPathComponent.suffix(7), "bar.baz")
        XCTAssertEqual(url.pathExtension, "baz")
        try handle.write(contentsOf: "Foo Bar Baz".data(using: .ascii)!)
        XCTAssertEqual(try String(data: Data(contentsOf: url), encoding: .ascii)!, "Foo Bar Baz")
    }

    func testCreateTemporaryFileWithTemplateAndNoSlashOnTMPDIR() throws {
        let oldTmpDir = String(cString: getenv("TMPDIR"))
        defer { setenv("TMPDIR", oldTmpDir, 1) }
        setenv("TMPDIR", "/tmp", 1)

        let (desc, path) = try CSFileManager.shared.createTemporaryFile(template: "fooXXXXX", suffix: "bar.baz")
        defer {
            _ = try? desc.close()
            _ = try? CSFileManager.shared.removeItem(at: path)
        }

        XCTAssertTrue(path.starts(with: "/tmp/"))
        XCTAssertEqual(path.lastComponent?.string.count, 15)
        XCTAssertEqual(path.lastComponent?.string.prefix(3), "foo")
        XCTAssertNotEqual(path.lastComponent?.string.prefix(8).suffix(5), "XXXXX")
        XCTAssertEqual(path.lastComponent?.string.suffix(7), "bar.baz")
        XCTAssertEqual(path.extension, "baz")
        try desc.writeAll("Foo Bar".data(using: .ascii)!)

        XCTAssertEqual(try String(data: Data(contentsOf: URL(filePath: path.string)), encoding: .ascii)!, "Foo Bar")

        let (fdInt, pathString) = try CSFileManager.shared.createTemporaryFileWithStringPath(
            template: "quxXXX",
            suffix: "quux.foo"
        )
        defer {
            close(fdInt)
            _ = try? CSFileManager.shared.removeItem(atPath: pathString)
        }

        XCTAssertTrue(pathString.starts(with: "/tmp/"))
        XCTAssertEqual(URL(filePath: pathString).lastPathComponent.count, 14)
        XCTAssertEqual(URL(filePath: pathString).lastPathComponent.prefix(3), "qux")
        XCTAssertNotEqual(URL(filePath: pathString).lastPathComponent.prefix(6).suffix(3), "XXX")
        XCTAssertEqual(URL(filePath: pathString).lastPathComponent.suffix(8), "quux.foo")
        XCTAssertEqual(URL(filePath: pathString).pathExtension, "foo")
        XCTAssertEqual(write(fdInt, "Foo Bar Baz", 11), 11)
        XCTAssertEqual(try String(data: Data(contentsOf: URL(filePath: pathString)), encoding: .ascii)!, "Foo Bar Baz")
        
        let (handle, url) = try CSFileManager.shared.createTemporaryFileURL(template: "fooXXXXX", suffix: "bar.baz")
        defer {
            _ = try? handle.close()
            _ = try? CSFileManager.shared.removeItem(at: url)
        }

        XCTAssertTrue(url.path.starts(with: "/tmp/"))
        XCTAssertEqual(url.lastPathComponent.count, 15)
        XCTAssertEqual(url.lastPathComponent.prefix(3), "foo")
        XCTAssertEqual(url.lastPathComponent.suffix(7), "bar.baz")
        XCTAssertEqual(url.pathExtension, "baz")
        try handle.write(contentsOf: "Foo Bar Baz".data(using: .ascii)!)
        XCTAssertEqual(try String(data: Data(contentsOf: url), encoding: .ascii)!, "Foo Bar Baz")
    }

    func testCreateTemporaryFileFailure() throws {
        XCTAssertThrowsError(try CSFileManager.shared.createTemporaryFile(template: "nonexist/dir/XXXX")) {
            XCTAssertTrue($0.isFileNotFoundError)
        }

        XCTAssertThrowsError(try CSFileManager.shared.createTemporaryFileWithStringPath(template: "nonexist/dir/XXXX")) {
            XCTAssertTrue($0.isFileNotFoundError)
        }
    }

    func testCreateItemReplacementDirectory() throws {
        func testFilePath(target: FilePath?, mode: mode_t, closure: (FilePath) throws -> Void) throws {
            let path = try CSFileManager.shared.createItemReplacementDirectory(for: target, mode: mode)
            defer { _ = try? CSFileManager.shared.removeItem(at: path) }

            try closure(path)
        }

        func testString(target: String?, mode: mode_t, closure: (String) throws -> Void) throws {
            let path = try CSFileManager.shared.createItemReplacementDirectoryWithStringPath(forPath: target, mode: mode)
            defer { _ = try? CSFileManager.shared.removeItem(atPath: path) }

            try closure(path)
        }

        func testURL(target: URL?, mode: mode_t, closure: (URL) throws -> Void) throws {
            let path = try CSFileManager.shared.createItemReplacementDirectoryWithURL(for: target, mode: mode)
            defer { _ = try? CSFileManager.shared.removeItem(at: path) }

            try closure(path)
        }

        let imageMount = FilePath(Self.diskImages.values.first!.mountPoint.path)
        let imageParentDir = imageMount.appending(UUID().uuidString)
        let imageTargetFile = imageParentDir.appending(UUID().uuidString)

        try CSFileManager.shared.createDirectory(at: imageParentDir, recursively: true)
        defer { _ = try? CSFileManager.shared.removeItem(at: imageParentDir) }

        try Data().write(to: URL(filePath: imageTargetFile.string))

        try testFilePath(target: nil, mode: 0o755) { path in
            XCTAssertTrue(path.starts(with: CSFileManager.shared.temporaryDirectory))
            XCTAssertEqual(try FileInfo(at: path, keys: .permissionsMode).permissionsMode, 0o755)
        }
        
        try testFilePath(target: FilePath(NSHomeDirectory()), mode: 0o600) { path in
            XCTAssertTrue(path.starts(with: CSFileManager.shared.temporaryDirectory))
            XCTAssertEqual(try FileInfo(at: path, keys: .permissionsMode).permissionsMode, 0o600)
        }

        try testFilePath(target: imageTargetFile, mode: 0o700) { path in
            XCTAssertTrue(path.starts(with: imageParentDir))
            XCTAssertEqual(try FileInfo(at: path, keys: .permissionsMode).permissionsMode, 0o700)
        }

        try testString(target: nil, mode: 0o755) { path in
            XCTAssertTrue(path.starts(with: CSFileManager.shared.temporaryDirectoryStringPath))
            XCTAssertEqual(try FileInfo(atPath: path, keys: .permissionsMode).permissionsMode, 0o755)
        }
        
        try testString(target: NSHomeDirectory(), mode: 0o600) { path in
            XCTAssertTrue(path.starts(with: CSFileManager.shared.temporaryDirectoryStringPath))
            XCTAssertEqual(try FileInfo(atPath: path, keys: .permissionsMode).permissionsMode, 0o600)
        }

        try testString(target: imageTargetFile.string, mode: 0o700) { path in
            XCTAssertTrue(path.starts(with: imageParentDir.string))
            XCTAssertEqual(try FileInfo(atPath: path, keys: .permissionsMode).permissionsMode, 0o700)
        }

        try testURL(target: nil, mode: 0o755) { url in
            XCTAssertTrue(url.path.starts(with: CSFileManager.shared.temporaryDirectoryStringPath))
            XCTAssertEqual(try FileInfo(at: url, keys: .permissionsMode).permissionsMode, 0o755)
        }

        try testURL(target: FileManager.default.homeDirectoryForCurrentUser, mode: 0o600) { url in
            XCTAssertTrue(url.path.starts(with: CSFileManager.shared.temporaryDirectoryStringPath))
            XCTAssertEqual(try FileInfo(at: url, keys: .permissionsMode).permissionsMode, 0o600)
        }

        try testURL(target: URL(filePath: imageTargetFile.string), mode: 0o700) { url in
            XCTAssertTrue(url.path.starts(with: imageParentDir.string))
            XCTAssertEqual(try FileInfo(at: url, keys: .permissionsMode).permissionsMode, 0o700)
        }
    }

    func testReachablePaths() {
        XCTAssertTrue(try CSFileManager.shared.itemIsReachable(at: "/bin/ls"))
        XCTAssertTrue(try CSFileManager.shared.itemIsReachable(atPath: "/bin/ls"))
        XCTAssertTrue(try CSFileManager.shared.itemIsReachable(at: URL(filePath: "/bin/ls")))

        XCTAssertTrue(try CSFileManager.shared.itemIsReachable(at: "/usr/bin"))
        XCTAssertTrue(try CSFileManager.shared.itemIsReachable(atPath: "/usr/bin"))
        XCTAssertTrue(try CSFileManager.shared.itemIsReachable(at: URL(filePath: "/usr/bin")))
    }

    func testUnreachablePaths() {
        let bogusPath = "/bin/does_not_exist.\(UUID().uuidString)"

        XCTAssertFalse(try CSFileManager.shared.itemIsReachable(at: FilePath(bogusPath)))
        XCTAssertFalse(try CSFileManager.shared.itemIsReachable(atPath: bogusPath))
        XCTAssertFalse(try CSFileManager.shared.itemIsReachable(at: URL(filePath: bogusPath)))
    }

    func testReachabilityCheckError() throws {
        let noPermissionsDir = CSFileManager.shared.temporaryDirectory.appending(UUID().uuidString)
        let unreachableFile = noPermissionsDir.appending("unreachable.file")

        try CSFileManager.shared.createDirectory(at: noPermissionsDir)
        defer { 
            chmod(noPermissionsDir.string, 0o755)
            _ = try? CSFileManager.shared.removeItem(at: noPermissionsDir, recursively: true)
        }

        try Data().write(to: URL(filePath: unreachableFile.string))

        XCTAssertTrue(try CSFileManager.shared.itemIsReachable(at: unreachableFile))
        XCTAssertTrue(try CSFileManager.shared.itemIsReachable(atPath: unreachableFile.string))

        try callPOSIXFunction(expect: .zero) { chmod(noPermissionsDir.string, 0o400) }

        XCTAssertThrowsError(try CSFileManager.shared.itemIsReachable(at: unreachableFile)) {
            XCTAssertTrue($0.isPermissionError)
        }
        
        XCTAssertThrowsError(try CSFileManager.shared.itemIsReachable(atPath: unreachableFile.string)) {
            XCTAssertTrue($0.isPermissionError)
        }

        XCTAssertThrowsError(try CSFileManager.shared.itemIsReachable(at: URL(filePath: unreachableFile.string))) {
            XCTAssertTrue($0.isPermissionError)
        }
    }

    func testGetTypeOfItem() throws {
        func checkType(path: FilePath, expect expectedType: CSFileManager.FileType, canOpen: Bool = true) throws {
            try XCTAssertEqual(CSFileManager.shared.typeOfItem(at: path), expectedType)
            try XCTAssertEqual(CSFileManager.shared.typeOfItem(atPath: path.string), expectedType)
            try XCTAssertEqual(CSFileManager.shared.typeOfItem(at: URL(filePath: path.string)), expectedType)

            if canOpen {
                let desc = try FileDescriptor.open(path, .readOnly, options: .symlink)
                defer { _ = try? desc.close() }
                
                try XCTAssertEqual(CSFileManager.shared.typeOfItem(fileDescriptor: desc), expectedType)
                try XCTAssertEqual(CSFileManager.shared.typeOfItem(fileDescriptor: desc.rawValue), expectedType)
            }
        }

        try checkType(path: "/bin/ls", expect: .regular)
        try checkType(path: "/bin", expect: .directory)
        try checkType(path: "/etc", expect: .symbolicLink)
        try checkType(path: "/dev/null", expect: .characterSpecial)
        try checkType(path: "/dev/disk0", expect: .blockSpecial, canOpen: false)

        let fifoPath = CSFileManager.shared.temporaryDirectory.appending("myfifo")
        mkfifo(fifoPath.string, 0o755)
        defer { _ = try? CSFileManager.shared.removeItem(at: fifoPath) }
        try checkType(path: fifoPath, expect: .fifo, canOpen: false)

        let socket = socket(PF_LOCAL, SOCK_STREAM, 0)
        defer { close(socket) }
        try XCTAssertEqual(CSFileManager.shared.typeOfItem(fileDescriptor: FileDescriptor(rawValue: socket)), .socket)
        try XCTAssertEqual(CSFileManager.shared.typeOfItem(fileDescriptor: socket), .socket)

        XCTAssertThrowsError(try CSFileManager.shared.typeOfItem(at: "/this/should/not/exist")) {
            XCTAssertTrue($0.isFileNotFoundError)
        }
        
        XCTAssertThrowsError(try CSFileManager.shared.typeOfItem(atPath: "/this/should/not/exist")) {
            XCTAssertTrue($0.isFileNotFoundError)
        }
        
        XCTAssertThrowsError(try CSFileManager.shared.typeOfItem(at: URL(filePath: "/this/should/not/exist"))) {
            XCTAssertTrue($0.isFileNotFoundError)
        }
    }
    
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

        XCTAssertEqual(try Set(manager.contentsOfDirectory(at: root)), [child1, child2])
        XCTAssertEqual(try Set(manager.contentsOfDirectory(at: child1)), [grandchild1, grandchild2])
        XCTAssertEqual(try Set(manager.contentsOfDirectory(at: child2)), [grandchild3])
        XCTAssertEqual(
            try Set(manager.contentsOfDirectory(at: root, recursively: true)),
            [child1, child2, grandchild1, grandchild2, grandchild3]
        )
        
        XCTAssertEqual(try Set(manager.contentsOfDirectory(atPath: root.string)), [childName1, childName2])
        XCTAssertEqual(try Set(manager.contentsOfDirectory(atPath: child1.string)), [grandchildName1, grandchildName2])
        XCTAssertEqual(try Set(manager.contentsOfDirectory(atPath: child2.string)), [grandchildName3])
        XCTAssertEqual(
            try Set(manager.contentsOfDirectory(atPath: root.string, recursively: true)),
            [
                childName1, "\(childName1)/\(grandchildName1)", "\(childName1)/\(grandchildName2)",
                childName2, "\(childName2)/\(grandchildName3)"
            ]
        )

        XCTAssertEqual(
            try Set(manager.contentsOfDirectory(at: URL(filePath: root.string))),
            [
                URL(filePath: child1.string, directoryHint: .isDirectory),
                URL(filePath: child2.string, directoryHint: .isDirectory)
            ]
        )
        XCTAssertEqual(
            try Set(manager.contentsOfDirectory(at: URL(filePath: child1.string))),
            [
                URL(filePath: grandchild1.string, directoryHint: .isDirectory),
                URL(filePath: grandchild2.string, directoryHint: .isDirectory)
            ]
        )
        XCTAssertEqual(
            try Set(manager.contentsOfDirectory(at: URL(filePath: child2.string))),
            [URL(filePath: grandchild3, directoryHint: .isDirectory)]
        )
        XCTAssertEqual(
            try Set(manager.contentsOfDirectory(at: URL(filePath: root.string), recursively: true)),
            [
                URL(filePath: child1.string, directoryHint: .isDirectory),
                URL(filePath: child1.string).appending(path: grandchildName1, directoryHint: .isDirectory),
                URL(filePath: child1.string).appending(path: grandchildName2, directoryHint: .isDirectory),
                URL(filePath: child2.string, directoryHint: .isDirectory),
                URL(filePath: child2.string).appending(path: grandchildName3, directoryHint: .isDirectory)
            ]
        )
    }

    func testEnumerateNonexistentPath() {
        let nonexistentPath = FilePath("/does/not/exist/\(UUID().uuidString)")

        XCTAssertEqual(try Set(CSFileManager.shared.contentsOfDirectory(atPath: nonexistentPath.string)), [])
        XCTAssertEqual(try Set(CSFileManager.shared.contentsOfDirectory(at: nonexistentPath)), [])
        XCTAssertEqual(try Set(CSFileManager.shared.contentsOfDirectory(at: URL(filePath: nonexistentPath.string))), [])
    }

    func testCreateDirectory() throws {
        let testDir = CSFileManager.shared.temporaryDirectory.appending(UUID().uuidString)
        defer { _ = try? CSFileManager.shared.removeItem(at: testDir, recursively: true) }

        XCTAssertThrowsError(try URL(filePath: testDir.string).checkResourceIsReachable())
        try CSFileManager.shared.createDirectory(at: testDir, mode: 0o755, recursively: false)
        XCTAssertTrue(try URL(filePath: testDir.string).checkResourceIsReachable())
        XCTAssertEqual(try FileManager.default.attributesOfItem(atPath: testDir.string)[.posixPermissions] as? mode_t, 0o755)

        let midDir = testDir.appending(UUID().uuidString)
        let deepDir = midDir.appending(UUID().uuidString)
        XCTAssertThrowsError(try CSFileManager.shared.createDirectory(at: deepDir, recursively: false)) {
            XCTAssertTrue($0.isFileNotFoundError)
        }
        XCTAssertThrowsError(try URL(filePath: midDir.string).checkResourceIsReachable())
        XCTAssertThrowsError(try URL(filePath: deepDir.string).checkResourceIsReachable())
        try CSFileManager.shared.createDirectory(at: deepDir, mode: 0o700, recursively: true)
        XCTAssertTrue(try URL(filePath: deepDir.string).checkResourceIsReachable())
        XCTAssertEqual(try FileManager.default.attributesOfItem(atPath: midDir.string)[.posixPermissions] as? mode_t, 0o700)
        XCTAssertEqual(try FileManager.default.attributesOfItem(atPath: deepDir.string)[.posixPermissions] as? mode_t, 0o700)
    }
    
    func testCreateDirectoryWithStringPaths() throws {
        let testDir = CSFileManager.shared.temporaryDirectory.appending(UUID().uuidString).string
        defer { _ = try? CSFileManager.shared.removeItem(atPath: testDir, recursively: true) }

        XCTAssertThrowsError(try URL(filePath: testDir).checkResourceIsReachable())
        try CSFileManager.shared.createDirectory(atPath: testDir, mode: 0o755, recursively: false)
        XCTAssertTrue(try URL(filePath: testDir).checkResourceIsReachable())
        XCTAssertEqual(try FileManager.default.attributesOfItem(atPath: testDir)[.posixPermissions] as? mode_t, 0o755)

        let midDir = FilePath(testDir).appending(UUID().uuidString).string
        let deepDir = FilePath(midDir).appending(UUID().uuidString).string
        XCTAssertThrowsError(try CSFileManager.shared.createDirectory(atPath: deepDir, recursively: false)) {
            XCTAssertTrue($0.isFileNotFoundError)
        }
        XCTAssertThrowsError(try URL(filePath: midDir).checkResourceIsReachable())
        XCTAssertThrowsError(try URL(filePath: deepDir).checkResourceIsReachable())
        try CSFileManager.shared.createDirectory(atPath: deepDir, mode: 0o700, recursively: true)
        XCTAssertTrue(try URL(filePath: deepDir).checkResourceIsReachable())
        XCTAssertEqual(try FileManager.default.attributesOfItem(atPath: midDir)[.posixPermissions] as? mode_t, 0o700)
        XCTAssertEqual(try FileManager.default.attributesOfItem(atPath: deepDir)[.posixPermissions] as? mode_t, 0o700)
    }

    func testCreateDirectoryWithURLs() throws {
        let testDir = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { _ = try? FileManager.default.removeItem(at: testDir) }

        XCTAssertThrowsError(try testDir.checkResourceIsReachable())
        try CSFileManager.shared.createDirectory(at: testDir, mode: 0o755, recursively: false)
        XCTAssertTrue(try testDir.checkResourceIsReachable())
        XCTAssertEqual(try FileManager.default.attributesOfItem(atPath: testDir.path)[.posixPermissions] as? mode_t, 0o755)

        let midDir = testDir.appending(path: UUID().uuidString)
        let deepDir = midDir.appending(path: UUID().uuidString)
        XCTAssertThrowsError(try CSFileManager.shared.createDirectory(at: deepDir, recursively: false)) {
            XCTAssertTrue($0.isFileNotFoundError)
        }
        XCTAssertThrowsError(try midDir.checkResourceIsReachable())
        XCTAssertThrowsError(try deepDir.checkResourceIsReachable())
        try CSFileManager.shared.createDirectory(at: deepDir, mode: 0o700, recursively: true)
        XCTAssertTrue(try deepDir.checkResourceIsReachable())
        XCTAssertEqual(try FileManager.default.attributesOfItem(atPath: midDir.path)[.posixPermissions] as? mode_t, 0o700)
        XCTAssertEqual(try FileManager.default.attributesOfItem(atPath: deepDir.path)[.posixPermissions] as? mode_t, 0o700)
    }

    func testMoveItems() throws {
        for image1 in Self.diskImages.values {
            for image2 in Self.diskImages.values {
                let rsrcFork = image1.supportResourceFork && image2.supportResourceFork
                try self.testMoveItems(fromVolume: image1.mountPoint, toVolume: image2.mountPoint, testRsrcFork: rsrcFork)
            }
        }
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

        let rsrcFork = ExtendedAttribute(
            key: XATTR_RESOURCEFORK_NAME,
            data: "you never know, something could use this".data(using: .utf8)!
        )

        func setupFile(src: URL, dst: URL) throws {
            _ = try? CSFileManager.shared.removeItem(at: src)
            _ = try? CSFileManager.shared.removeItem(at: dst)

            try fileContents.write(to: src)
            try attribute.write(to: src)

            if testRsrcFork {
                try rsrcFork.write(to: src)
            }
        }

        func setupFolder(src: URL, dst: URL) throws {
            _ = try? CSFileManager.shared.removeItem(at: src)
            _ = try? CSFileManager.shared.removeItem(at: dst)

            try CSFileManager.shared.createDirectory(at: src, recursively: true)
            try attribute.write(to: src)

            try setupFile(src: src.appending(path: "content_file"), dst: dst.appending(path: "content_file"))
        }

        func verifyFile(src: URL, dst: URL) {
            XCTAssertFalse(try CSFileManager.shared.itemIsReachable(at: src))
            XCTAssertEqual(try Data(contentsOf: dst), fileContents)

            if testRsrcFork {
                XCTAssertEqual(try Set(ExtendedAttribute.list(at: dst)), [attribute, rsrcFork])
            } else {
                XCTAssertEqual(try Set(ExtendedAttribute.list(at: dst)), [attribute])
            }
        }

        func verifyFolder(src: URL, dst: URL) {
            XCTAssertEqual(try CSFileManager.shared.typeOfItem(at: dst), .directory)
            XCTAssertEqual(try Set(ExtendedAttribute.list(at: dst)), [attribute])
            verifyFile(src: src.appending(path: "content_file"), dst: dst.appending(path: "content_file"))
        }

        XCTAssertThrowsError(try CSFileManager.shared.moveItem(at: FilePath(src.path), to: FilePath(dst.path))) {
            XCTAssertTrue($0.isFileNotFoundError)
        }
        
        XCTAssertThrowsError(try CSFileManager.shared.moveItem(atPath: src.path, toPath: dst.path)) {
            XCTAssertTrue($0.isFileNotFoundError)
        }
        
        XCTAssertThrowsError(try CSFileManager.shared.moveItem(at: src, to: dst)) {
            XCTAssertTrue($0.isFileNotFoundError)
        }

        try setupFile(src: src, dst: dst)
        try CSFileManager.shared.moveItem(at: FilePath(src.path), to: FilePath(dst.path))
        verifyFile(src: src, dst: dst)

        try setupFile(src: src, dst: dst)
        try CSFileManager.shared.moveItem(atPath: src.path, toPath: dst.path)
        verifyFile(src: src, dst: dst)

        try setupFile(src: src, dst: dst)
        try CSFileManager.shared.moveItem(at: src, to: dst)
        verifyFile(src: src, dst: dst)

        try setupFolder(src: src, dst: dst)
        try CSFileManager.shared.moveItem(at: FilePath(src.path), to: FilePath(dst.path))
        verifyFolder(src: src, dst: dst)

        try setupFolder(src: src, dst: dst)
        try CSFileManager.shared.moveItem(atPath: src.path, toPath: dst.path)
        verifyFolder(src: src, dst: dst)

        try setupFolder(src: src, dst: dst)
        try CSFileManager.shared.moveItem(at: src, to: dst)
        verifyFolder(src: src, dst: dst)
    }

    func testRemoveRegularFile() throws {
        let testDir = CSFileManager.shared.temporaryDirectory.appending(UUID().uuidString)
        try CSFileManager.shared.createDirectory(at: testDir, mode: 0o755, recursively: false)
        defer { _ = try? CSFileManager.shared.removeItem(at: testDir, recursively: true) }

        let child = testDir.appending(UUID().uuidString)

        try "testing 1 2 3".data(using: .utf8)!.write(to: URL(filePath: child.string))
        XCTAssertTrue(try URL(filePath: child.string).checkResourceIsReachable())
        try CSFileManager.shared.removeItem(at: child, recursively: false)
        XCTAssertFalse((try? URL(filePath: child.string).checkResourceIsReachable()) ?? false)
        
        try "testing 1 2 3".data(using: .utf8)!.write(to: URL(filePath: child.string))
        XCTAssertTrue(try URL(filePath: child.string).checkResourceIsReachable())
        try CSFileManager.shared.removeItem(at: child, recursively: true)
        XCTAssertFalse((try? URL(filePath: child.string).checkResourceIsReachable()) ?? false)
        
        try "testing 1 2 3".data(using: .utf8)!.write(to: URL(filePath: child.string))
        XCTAssertTrue(try URL(filePath: child.string).checkResourceIsReachable())
        try CSFileManager.shared.removeItem(atPath: child.string, recursively: false)
        XCTAssertFalse((try? URL(filePath: child.string).checkResourceIsReachable()) ?? false)
        
        try "testing 1 2 3".data(using: .utf8)!.write(to: URL(filePath: child.string))
        XCTAssertTrue(try URL(filePath: child.string).checkResourceIsReachable())
        try CSFileManager.shared.removeItem(atPath: child.string, recursively: true)
        XCTAssertFalse((try? URL(filePath: child.string).checkResourceIsReachable()) ?? false)
        
        try "testing 1 2 3".data(using: .utf8)!.write(to: URL(filePath: child.string))
        XCTAssertTrue(try URL(filePath: child.string).checkResourceIsReachable())
        try CSFileManager.shared.removeItem(at: URL(filePath: child.string), recursively: false)
        XCTAssertFalse((try? URL(filePath: child.string).checkResourceIsReachable()) ?? false)
        
        try "testing 1 2 3".data(using: .utf8)!.write(to: URL(filePath: child.string))
        XCTAssertTrue(try URL(filePath: child.string).checkResourceIsReachable())
        try CSFileManager.shared.removeItem(at: URL(filePath: child.string), recursively: true)
        XCTAssertFalse((try? URL(filePath: child.string).checkResourceIsReachable()) ?? false)
    }

    func testRemoveEmptyDirectory() throws {
        let testDir = CSFileManager.shared.temporaryDirectory.appending(UUID().uuidString)
        try CSFileManager.shared.createDirectory(at: testDir, mode: 0o755, recursively: false)
        defer { _ = try? CSFileManager.shared.removeItem(at: testDir, recursively: true) }

        let child = testDir.appending(UUID().uuidString)

        try CSFileManager.shared.createDirectory(at: child)
        XCTAssertTrue(try URL(filePath: child.string).checkResourceIsReachable())
        try CSFileManager.shared.removeItem(at: child, recursively: false)
        XCTAssertFalse((try? URL(filePath: child.string).checkResourceIsReachable()) ?? false)
        
        try CSFileManager.shared.createDirectory(at: child)
        XCTAssertTrue(try URL(filePath: child.string).checkResourceIsReachable())
        try CSFileManager.shared.removeItem(at: child, recursively: true)
        XCTAssertFalse((try? URL(filePath: child.string).checkResourceIsReachable()) ?? false)
        
        try CSFileManager.shared.createDirectory(at: child)
        XCTAssertTrue(try URL(filePath: child.string).checkResourceIsReachable())
        try CSFileManager.shared.removeItem(atPath: child.string, recursively: false)
        XCTAssertFalse((try? URL(filePath: child.string).checkResourceIsReachable()) ?? false)
        
        try CSFileManager.shared.createDirectory(at: child)
        XCTAssertTrue(try URL(filePath: child.string).checkResourceIsReachable())
        try CSFileManager.shared.removeItem(atPath: child.string, recursively: true)
        XCTAssertFalse((try? URL(filePath: child.string).checkResourceIsReachable()) ?? false)
        
        try CSFileManager.shared.createDirectory(at: child)
        XCTAssertTrue(try URL(filePath: child.string).checkResourceIsReachable())
        try CSFileManager.shared.removeItem(at: URL(filePath: child.string), recursively: false)
        XCTAssertFalse((try? URL(filePath: child.string).checkResourceIsReachable()) ?? false)
        
        try CSFileManager.shared.createDirectory(at: child)
        XCTAssertTrue(try URL(filePath: child.string).checkResourceIsReachable())
        try CSFileManager.shared.removeItem(at: URL(filePath: child.string), recursively: true)
        XCTAssertFalse((try? URL(filePath: child.string).checkResourceIsReachable()) ?? false)
    }

    func testRemoveDirectoryWithContents() throws {
        let testDir = CSFileManager.shared.temporaryDirectory.appending(UUID().uuidString)
        try CSFileManager.shared.createDirectory(at: testDir, mode: 0o755, recursively: false)
        defer {
            XCTAssertTrue(try URL(filePath: testDir.string).checkResourceIsReachable())
            _ = try? CSFileManager.shared.removeItem(at: testDir, recursively: true)
            XCTAssertFalse((try? URL(filePath: testDir.string).checkResourceIsReachable()) ?? false)
        }
        
        let child = testDir.appending(UUID().uuidString)
        let grandchild = child.appending(UUID().uuidString)

        try CSFileManager.shared.createDirectory(at: child)
        try "testing 1 2 3".data(using: .utf8)!.write(to: URL(filePath: grandchild.string))
        XCTAssertTrue(try URL(filePath: child.string).checkResourceIsReachable())
        XCTAssertThrowsError(try CSFileManager.shared.removeItem(at: child, recursively: false)) {
            XCTAssertEqual($0 as? Errno, .directoryNotEmpty)
        }
        XCTAssertThrowsError(try CSFileManager.shared.removeItem(atPath: child.string, recursively: false)) {
            XCTAssertEqual($0 as? Errno, .directoryNotEmpty)
        }
        XCTAssertThrowsError(try CSFileManager.shared.removeItem(at: URL(filePath: child.string), recursively: false)) {
            XCTAssertEqual($0 as? Errno, .directoryNotEmpty)
        }
        XCTAssertTrue(try URL(filePath: child.string).checkResourceIsReachable())

        try CSFileManager.shared.removeItem(at: child, recursively: true)
        XCTAssertFalse((try? URL(filePath: child.string).checkResourceIsReachable()) ?? false)
        
        try CSFileManager.shared.createDirectory(at: child)
        try "testing 1 2 3".data(using: .utf8)!.write(to: URL(filePath: grandchild.string))
        XCTAssertTrue(try URL(filePath: child.string).checkResourceIsReachable())
        try CSFileManager.shared.removeItem(atPath: child.string, recursively: true)
        XCTAssertFalse((try? URL(filePath: child.string).checkResourceIsReachable()) ?? false)
        
        try CSFileManager.shared.createDirectory(at: child)
        try "testing 1 2 3".data(using: .utf8)!.write(to: URL(filePath: grandchild.string))
        XCTAssertTrue(try URL(filePath: child.string).checkResourceIsReachable())
        try CSFileManager.shared.removeItem(at: URL(filePath: child.string), recursively: true)
        XCTAssertFalse((try? URL(filePath: child.string).checkResourceIsReachable()) ?? false)
    }

    func testReplaceItems() throws {
        for image1 in Self.diskImages.values {
            for image2 in Self.diskImages.values {
                try self.testReplaceItems(fromVolume: image1.mountPoint, toVolume: image2.mountPoint)
            }
        }
    }

    private static func createDiskImage(fs: String, at url: URL, megabytes: Int) throws -> URL {
        let process = Process()
        let pipe = Pipe()
        let handle = pipe.fileHandleForReading

        process.executableURL = URL(filePath: "/usr/bin/hdiutil")
        process.arguments = ["create", "-megabytes", String(megabytes), "-fs", fs, "-volname", fs, url.path, "-plist"]
        process.standardOutput = pipe

        try process.run()
        process.waitUntilExit()

        guard let stdout = try handle.readToEnd(),
              let array = try PropertyListSerialization.propertyList(from: stdout, format: nil) as? [String],
              let path = array.first else {
            throw CocoaError(.fileReadUnknown)
        }

        return URL(filePath: path)
    }
    
    private static func mountDiskImage(at url: URL) throws -> (mountPoint: URL, devEntry: URL) {
        let process = Process()
        let pipe = Pipe()
        let handle = pipe.fileHandleForReading

        process.executableURL = URL(filePath: "/usr/bin/hdiutil")
        process.arguments = ["attach", url.path, "-plist"]
        process.standardOutput = pipe

        try process.run()
        process.waitUntilExit()

        guard let stdout = try handle.readToEnd(),
              let dict = try PropertyListSerialization.propertyList(from: stdout, format: nil) as? [String : Any],
              let entities = dict["system-entities"] as? [[String : Any]],
              let entity = entities.first(where: { $0["mount-point"] as? String != nil }),
              let mountPoint = entity["mount-point"] as? String,
              let devEntry = entity["dev-entry"] as? String else {
            throw CocoaError(.fileReadUnknown)
        }

        return (mountPoint: URL(filePath: mountPoint), devEntry: URL(filePath: devEntry))
    }

    private static func unmountDiskImage(at url: URL) throws {
        let process = Process()

        process.executableURL = URL(filePath: "/usr/bin/hdiutil")
        process.arguments = ["detach", url.path]

        try process.run()
        process.waitUntilExit()
    }

    private func testReplaceItems(fromVolume vol1: URL, toVolume vol2: URL) throws {
        let testDir1 = FilePath(vol1.path).appending(UUID().uuidString)
        try CSFileManager.shared.createDirectory(at: testDir1, mode: 0o755, recursively: false)
        defer { _ = try? CSFileManager.shared.removeItem(at: testDir1, recursively: true) }

        let testDir2 = FilePath(vol2.path).appending(UUID().uuidString)
        try CSFileManager.shared.createDirectory(at: testDir2, mode: 0o755, recursively: false)
        defer { _ = try? CSFileManager.shared.removeItem(at: testDir2, recursively: true) }

        let file1 = testDir1.appending(UUID().uuidString)
        let file2 = testDir2.appending(UUID().uuidString)

        let file1Data = "testing 1 2 3".data(using: .utf8)!
        let file2Data = "testing 2 3 4".data(using: .utf8)!

        let xattrName1 = "xattr1"
        let xattrName2 = "xattr2"

        let xattrValue1 = "some xattr string"
        let xattrValue2 = "something else"

        func setUpFiles() throws {
            _ = try? CSFileManager.shared.removeItem(at: file1)
            _ = try? CSFileManager.shared.removeItem(at: file2)

            try file1Data.write(to: URL(filePath: file1.string), options: .atomic)
            try file2Data.write(to: URL(filePath: file2.string), options: .atomic)

            xattrValue1.data(using: .utf8)!.withUnsafeBytes { str in
                XCTAssertEqual(setxattr(file1.string, xattrName1, str.baseAddress, str.count, 0, 0), 0)
            }
            
            xattrValue2.data(using: .utf8)!.withUnsafeBytes { str in
                XCTAssertEqual(setxattr(file2.string, xattrName2, str.baseAddress, str.count, 0, 0), 0)
            }
        }

        func xattrNames(at path: FilePath) throws -> Set<String> {
            let bufsize = try callPOSIXFunction(expect: .nonNegative) { listxattr(path.string, nil, 0, 0) }
            let buf = UnsafeMutableBufferPointer<UInt8>.allocate(capacity: bufsize)
            defer { buf.deallocate() }

            let size = try callPOSIXFunction(expect: .nonNegative) { listxattr(path.string, buf.baseAddress, buf.count, 0) }

            return Set(buf[..<size].split(separator: 0).map { String(decoding: $0, as: UTF8.self) })
        }

        func xattr(at path: FilePath, forKey key: String) throws -> String {
            let bufsize = try callPOSIXFunction(expect: .nonNegative) { getxattr(path.string, key, nil, 0, 0, 0) }
            let buf = UnsafeMutableBufferPointer<UInt8>.allocate(capacity: bufsize)
            defer { buf.deallocate() }

            let size = try callPOSIXFunction(expect: .nonNegative) {
                getxattr(path.string, key, buf.baseAddress, buf.count, 0, 0)
            }

            return String(decoding: buf[..<size], as: UTF8.self)
        }

        try setUpFiles()
        XCTAssertEqual(try xattrNames(at: file1), [xattrName1])
        XCTAssertEqual(try xattr(at: file1, forKey: xattrName1), xattrValue1)
        XCTAssertEqual(try xattrNames(at: file2), [xattrName2])
        XCTAssertEqual(try xattr(at: file2, forKey: xattrName2), xattrValue2)
        try CSFileManager.shared.replaceItem(at: file1, withItemAt: file2)
        XCTAssertEqual(try xattrNames(at: file1), [xattrName1, xattrName2])
        XCTAssertEqual(try xattr(at: file1, forKey: xattrName1), xattrValue1)
        XCTAssertEqual(try xattr(at: file1, forKey: xattrName2), xattrValue2)
        XCTAssertThrowsError(try URL(filePath: file2.string).checkResourceIsReachable()) {
            XCTAssertEqual(($0 as? CocoaError)?.code, .fileReadNoSuchFile)
        }
        
        try setUpFiles()
        XCTAssertEqual(try xattrNames(at: file1), [xattrName1])
        XCTAssertEqual(try xattr(at: file1, forKey: xattrName1), xattrValue1)
        XCTAssertEqual(try xattrNames(at: file2), [xattrName2])
        XCTAssertEqual(try xattr(at: file2, forKey: xattrName2), xattrValue2)
        try CSFileManager.shared.replaceItem(at: file1, withItemAt: file2, options: .withoutDeletingBackupItem)
        XCTAssertEqual(try xattrNames(at: file1), [xattrName1, xattrName2])
        XCTAssertEqual(try xattr(at: file1, forKey: xattrName1), xattrValue1)
        XCTAssertEqual(try xattr(at: file1, forKey: xattrName2), xattrValue2)
        XCTAssertEqual(try xattrNames(at: file2), [xattrName1])
        XCTAssertEqual(try xattr(at: file2, forKey: xattrName1), xattrValue1)

        try setUpFiles()
        XCTAssertEqual(try xattrNames(at: file1), [xattrName1])
        XCTAssertEqual(try xattr(at: file1, forKey: xattrName1), xattrValue1)
        XCTAssertEqual(try xattrNames(at: file2), [xattrName2])
        XCTAssertEqual(try xattr(at: file2, forKey: xattrName2), xattrValue2)
        try CSFileManager.shared.replaceItem(at: file1, withItemAt: file2, options: .usingNewMetadataOnly)
        XCTAssertEqual(try xattrNames(at: file1), [xattrName2])
        XCTAssertEqual(try xattr(at: file1, forKey: xattrName2), xattrValue2)
        XCTAssertThrowsError(try URL(filePath: file2.string).checkResourceIsReachable()) {
            XCTAssertEqual(($0 as? CocoaError)?.code, .fileReadNoSuchFile)
        }
        
        try setUpFiles()
        XCTAssertEqual(try xattrNames(at: file1), [xattrName1])
        XCTAssertEqual(try xattr(at: file1, forKey: xattrName1), xattrValue1)
        XCTAssertEqual(try xattrNames(at: file2), [xattrName2])
        XCTAssertEqual(try xattr(at: file2, forKey: xattrName2), xattrValue2)
        try CSFileManager.shared.replaceItem(
            at: file1,
            withItemAt: file2,
            options: [.usingNewMetadataOnly, .withoutDeletingBackupItem]
        )
        XCTAssertEqual(try xattrNames(at: file1), [xattrName2])
        XCTAssertEqual(try xattr(at: file1, forKey: xattrName2), xattrValue2)
        XCTAssertEqual(try xattrNames(at: file2), [xattrName1])
        XCTAssertEqual(try xattr(at: file2, forKey: xattrName1), xattrValue1)

        try setUpFiles()
        XCTAssertEqual(try xattrNames(at: file1), [xattrName1])
        XCTAssertEqual(try xattr(at: file1, forKey: xattrName1), xattrValue1)
        XCTAssertEqual(try xattrNames(at: file2), [xattrName2])
        XCTAssertEqual(try xattr(at: file2, forKey: xattrName2), xattrValue2)
        try CSFileManager.shared.replaceItem(atPath: file1.string, withItemAtPath: file2.string)
        XCTAssertEqual(try xattrNames(at: file1), [xattrName1, xattrName2])
        XCTAssertEqual(try xattr(at: file1, forKey: xattrName1), xattrValue1)
        XCTAssertEqual(try xattr(at: file1, forKey: xattrName2), xattrValue2)
        XCTAssertThrowsError(try URL(filePath: file2.string).checkResourceIsReachable()) {
            XCTAssertEqual(($0 as? CocoaError)?.code, .fileReadNoSuchFile)
        }
        
        try setUpFiles()
        XCTAssertEqual(try xattrNames(at: file1), [xattrName1])
        XCTAssertEqual(try xattr(at: file1, forKey: xattrName1), xattrValue1)
        XCTAssertEqual(try xattrNames(at: file2), [xattrName2])
        XCTAssertEqual(try xattr(at: file2, forKey: xattrName2), xattrValue2)
        try CSFileManager.shared.replaceItem(
            atPath: file1.string,
            withItemAtPath: file2.string,
            options: .withoutDeletingBackupItem
        )
        XCTAssertEqual(try xattrNames(at: file1), [xattrName1, xattrName2])
        XCTAssertEqual(try xattr(at: file1, forKey: xattrName1), xattrValue1)
        XCTAssertEqual(try xattr(at: file1, forKey: xattrName2), xattrValue2)
        XCTAssertEqual(try xattrNames(at: file2), [xattrName1])
        XCTAssertEqual(try xattr(at: file2, forKey: xattrName1), xattrValue1)
        
        try setUpFiles()
        XCTAssertEqual(try xattrNames(at: file1), [xattrName1])
        XCTAssertEqual(try xattr(at: file1, forKey: xattrName1), xattrValue1)
        XCTAssertEqual(try xattrNames(at: file2), [xattrName2])
        XCTAssertEqual(try xattr(at: file2, forKey: xattrName2), xattrValue2)
        try CSFileManager.shared.replaceItem(
            atPath: file1.string,
            withItemAtPath: file2.string,
            options: .usingNewMetadataOnly
        )
        XCTAssertEqual(try xattrNames(at: file1), [xattrName2])
        XCTAssertEqual(try xattr(at: file1, forKey: xattrName2), xattrValue2)
        XCTAssertThrowsError(try URL(filePath: file2.string).checkResourceIsReachable()) {
            XCTAssertEqual(($0 as? CocoaError)?.code, .fileReadNoSuchFile)
        }

        try setUpFiles()
        XCTAssertEqual(try xattrNames(at: file1), [xattrName1])
        XCTAssertEqual(try xattr(at: file1, forKey: xattrName1), xattrValue1)
        XCTAssertEqual(try xattrNames(at: file2), [xattrName2])
        XCTAssertEqual(try xattr(at: file2, forKey: xattrName2), xattrValue2)
        try CSFileManager.shared.replaceItem(
            atPath: file1.string,
            withItemAtPath: file2.string,
            options: [.usingNewMetadataOnly, .withoutDeletingBackupItem]
        )
        XCTAssertEqual(try xattrNames(at: file1), [xattrName2])
        XCTAssertEqual(try xattr(at: file1, forKey: xattrName2), xattrValue2)
        XCTAssertEqual(try xattrNames(at: file2), [xattrName1])
        XCTAssertEqual(try xattr(at: file2, forKey: xattrName1), xattrValue1)
        
        try setUpFiles()
        XCTAssertEqual(try xattrNames(at: file1), [xattrName1])
        XCTAssertEqual(try xattr(at: file1, forKey: xattrName1), xattrValue1)
        XCTAssertEqual(try xattrNames(at: file2), [xattrName2])
        XCTAssertEqual(try xattr(at: file2, forKey: xattrName2), xattrValue2)
        try CSFileManager.shared.replaceItem(at: URL(filePath: file1.string), withItemAt: URL(filePath: file2.string))
        XCTAssertEqual(try xattrNames(at: file1), [xattrName1, xattrName2])
        XCTAssertEqual(try xattr(at: file1, forKey: xattrName1), xattrValue1)
        XCTAssertEqual(try xattr(at: file1, forKey: xattrName2), xattrValue2)
        XCTAssertThrowsError(try URL(filePath: file2.string).checkResourceIsReachable()) {
            XCTAssertEqual(($0 as? CocoaError)?.code, .fileReadNoSuchFile)
        }

        try setUpFiles()
        XCTAssertEqual(try xattrNames(at: file1), [xattrName1])
        XCTAssertEqual(try xattr(at: file1, forKey: xattrName1), xattrValue1)
        XCTAssertEqual(try xattrNames(at: file2), [xattrName2])
        XCTAssertEqual(try xattr(at: file2, forKey: xattrName2), xattrValue2)
        try CSFileManager.shared.replaceItem(
            at: URL(filePath: file1.string),
            withItemAt: URL(filePath: file2.string),
            options: .withoutDeletingBackupItem
        )
        XCTAssertEqual(try xattrNames(at: file1), [xattrName1, xattrName2])
        XCTAssertEqual(try xattr(at: file1, forKey: xattrName1), xattrValue1)
        XCTAssertEqual(try xattr(at: file1, forKey: xattrName2), xattrValue2)
        XCTAssertEqual(try xattrNames(at: file2), [xattrName1])
        XCTAssertEqual(try xattr(at: file2, forKey: xattrName1), xattrValue1)
        
        try setUpFiles()
        XCTAssertEqual(try xattrNames(at: file1), [xattrName1])
        XCTAssertEqual(try xattr(at: file1, forKey: xattrName1), xattrValue1)
        XCTAssertEqual(try xattrNames(at: file2), [xattrName2])
        XCTAssertEqual(try xattr(at: file2, forKey: xattrName2), xattrValue2)
        try CSFileManager.shared.replaceItem(
            at: URL(filePath: file1.string),
            withItemAt: URL(filePath: file2.string),
            options: .usingNewMetadataOnly
        )
        XCTAssertEqual(try xattrNames(at: file1), [xattrName2])
        XCTAssertEqual(try xattr(at: file1, forKey: xattrName2), xattrValue2)
        XCTAssertThrowsError(try URL(filePath: file2.string).checkResourceIsReachable()) {
            XCTAssertEqual(($0 as? CocoaError)?.code, .fileReadNoSuchFile)
        }
        
        try setUpFiles()
        XCTAssertEqual(try xattrNames(at: file1), [xattrName1])
        XCTAssertEqual(try xattr(at: file1, forKey: xattrName1), xattrValue1)
        XCTAssertEqual(try xattrNames(at: file2), [xattrName2])
        XCTAssertEqual(try xattr(at: file2, forKey: xattrName2), xattrValue2)
        try CSFileManager.shared.replaceItem(
            at: URL(filePath: file1.string),
            withItemAt: URL(filePath: file2.string),
            options: [.usingNewMetadataOnly, .withoutDeletingBackupItem]
        )
        XCTAssertEqual(try xattrNames(at: file1), [xattrName2])
        XCTAssertEqual(try xattr(at: file1, forKey: xattrName2), xattrValue2)
        XCTAssertEqual(try xattrNames(at: file2), [xattrName1])
        XCTAssertEqual(try xattr(at: file2, forKey: xattrName1), xattrValue1)
    }
}
