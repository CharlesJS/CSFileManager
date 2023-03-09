@testable import CSFileManager
import System
import XCTest

@available(macOS 13.0, *)
final class CSFileManagerTests: XCTestCase {
    func testAll() throws {
        for version in [10, 11, 12, 13] {
            try emulateOSVersion(version) {
                self.testTemporaryDirectory()
                self.testTemporaryDirectoryFallback()
                try self.testCreateTemporaryFile()
                try self.testCreateTemporaryFileWithTemplate()
                try self.testCreateTemporaryFileFailure()
            }
        }
    }

    func testTemporaryDirectory() {
        XCTAssertEqual(CSFileManager.shared.temporaryDirectory, FilePath(FileManager.default.temporaryDirectory.path))
        XCTAssertEqual(CSFileManager.shared.temporaryDirectoryStringPath, FileManager.default.temporaryDirectory.path + "/")
    }

    func testTemporaryDirectoryFallback() {
        let oldTmpDir = String(cString: getenv("TMPDIR"))
        defer { setenv("TMPDIR", oldTmpDir, 1) }
        unsetenv("TMPDIR")

        XCTAssertEqual(CSFileManager.shared.temporaryDirectory, FilePath("/tmp"))
        XCTAssertEqual(CSFileManager.shared.temporaryDirectoryStringPath, "/tmp")
    }

    func testCreateTemporaryFile() throws {
        let (desc, path) = try CSFileManager.shared.createTemporaryFile()
        defer {
            _ = try? desc.close()
            _ = try? FileManager.default.removeItem(at: URL(filePath: path.string))
        }

        XCTAssertTrue(path.starts(with: CSFileManager.shared.temporaryDirectory))
        XCTAssertEqual(path.lastComponent?.string.count, 32)
        try desc.writeAll("Foo Bar".data(using: .ascii)!)

        XCTAssertEqual(try String(data: Data(contentsOf: URL(filePath: path.string)), encoding: .ascii)!, "Foo Bar")

        let (fdInt, pathString) = try CSFileManager.shared.createTemporaryFileWithStringPath()
        defer {
            close(fdInt)
            _ = try? FileManager.default.removeItem(at: URL(filePath: pathString))
        }

        XCTAssertTrue(pathString.starts(with: CSFileManager.shared.temporaryDirectoryStringPath + "/"))
        XCTAssertEqual(URL(filePath: pathString).lastPathComponent.count, 32)
        XCTAssertEqual(write(fdInt, "Foo Bar Baz", 11), 11)
        XCTAssertEqual(try String(data: Data(contentsOf: URL(filePath: pathString)), encoding: .ascii)!, "Foo Bar Baz")
    }

    func testCreateTemporaryFileWithTemplate() throws {
        let (desc, path) = try CSFileManager.shared.createTemporaryFile(template: "fooXXXXXbar.baz")
        defer {
            _ = try? desc.close()
            _ = try? FileManager.default.removeItem(at: URL(filePath: path.string))
        }

        XCTAssertTrue(path.starts(with: CSFileManager.shared.temporaryDirectory))
        XCTAssertEqual(path.lastComponent?.string.count, 15)
        XCTAssertEqual(path.lastComponent?.string.prefix(3), "foo")
        XCTAssertEqual(path.lastComponent?.string.suffix(7), "bar.baz")
        XCTAssertEqual(path.extension, "baz")
        try desc.writeAll("Foo Bar".data(using: .ascii)!)

        XCTAssertEqual(try String(data: Data(contentsOf: URL(filePath: path.string)), encoding: .ascii)!, "Foo Bar")

        let (fdInt, pathString) = try CSFileManager.shared.createTemporaryFileWithStringPath(template: "quxXXXquux.foo")
        defer {
            close(fdInt)
            _ = try? FileManager.default.removeItem(at: URL(filePath: pathString))
        }

        XCTAssertTrue(pathString.starts(with: CSFileManager.shared.temporaryDirectoryStringPath + "/"))
        XCTAssertEqual(URL(filePath: pathString).lastPathComponent.count, 14)
        XCTAssertEqual(URL(filePath: pathString).lastPathComponent.prefix(3), "qux")
        XCTAssertEqual(URL(filePath: pathString).lastPathComponent.suffix(8), "quux.foo")
        XCTAssertEqual(URL(filePath: pathString).pathExtension, "foo")
        XCTAssertEqual(write(fdInt, "Foo Bar Baz", 11), 11)
        XCTAssertEqual(try String(data: Data(contentsOf: URL(filePath: pathString)), encoding: .ascii)!, "Foo Bar Baz")
    }

    func testCreateTemporaryFileFailure() throws {
        XCTAssertThrowsError(try CSFileManager.shared.createTemporaryFile(template: "nonexist/dir/XXXX")) {
            XCTAssertEqual($0 as? Errno, .noSuchFileOrDirectory)
        }

        XCTAssertThrowsError(try CSFileManager.shared.createTemporaryFileWithStringPath(template: "nonexist/dir/XXXX")) {
            XCTAssertEqual($0 as? Errno, .noSuchFileOrDirectory)
        }
    }
}
