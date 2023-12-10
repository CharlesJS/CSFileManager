//
//  CSFileManager+Foundation.swift
//  
//
//  Created by Charles Srstka on 11/20/23.
//

import CSFileManager
import Foundation
import System

extension CSFileManager {
    public var rootDirectoryURL: URL {
        guard #available(macOS 11.0, iOS 14.0, watchOS 7.0, tvOS 14.0, *), versionCheck(11) else {
            return URL(fileURLWithPath: self.rootDirectoryStringPath, isDirectory: true)
        }

        guard #available(macOS 12.0, iOS 15.0, watchOS 8.0, tvOS 15.0, *), versionCheck(12) else {
            return URL(fileURLWithPath: String(describing: self.rootDirectory), isDirectory: true)
        }

        return URL(fileURLWithPath: self.rootDirectory.string, isDirectory: true)
    }

    public var homeDirectoryURLForCurrentUser: URL {
        guard #available(macOS 11.0, iOS 14.0, watchOS 7.0, tvOS 14.0, *), versionCheck(11) else {
            return URL(fileURLWithPath: self.homeDirectoryStringPathForCurrentUser, isDirectory: true)
        }

        guard #available(macOS 12.0, iOS 15.0, watchOS 8.0, tvOS 15.0, *), versionCheck(12) else {
            return URL(fileURLWithPath: String(describing: self.homeDirectoryForCurrentUser), isDirectory: true)
        }

        return URL(fileURLWithPath: self.homeDirectoryForCurrentUser.string, isDirectory: true)
    }

    public var temporaryDirectoryURL: URL {
        guard #available(macOS 12.0, iOS 15.0, watchOS 8.0, tvOS 15.0, *), versionCheck(12) else {
            guard #available(macOS 11.0, iOS 14.0, watchOS 7.0, tvOS 14.0, *), versionCheck(11) else {
                return URL(fileURLWithPath: self.temporaryDirectoryStringPath, isDirectory: true)
            }

            return URL(fileURLWithPath: String(describing: self.temporaryDirectory), isDirectory: true)
        }

        return URL(fileURLWithPath: self.temporaryDirectory.string, isDirectory: true)
    }

    public func createTemporaryFileURL(
        directory: URL? = nil,
        template: String? = nil,
        suffix: String? = nil
    ) throws -> (FileHandle, URL) {
        guard #available(macOS 11.0, iOS 14.0, watchOS 7.0, tvOS 14.0, *), versionCheck(11) else {
            let (fd, path) = try self.createTemporaryFileWithStringPath(
                directory: directory?.path,
                template: template,
                suffix: suffix
            )

            return (FileHandle(fileDescriptor: fd), URL(fileURLWithPath: path))
        }

        let (fd, path) = try self.createTemporaryFile(
            directory: directory.map { FilePath($0.path) },
            template: template, 
            suffix: suffix
        )

        guard #available(macOS 12.0, iOS 15.0, watchOS 8.0, tvOS 15.0, *), versionCheck(12) else {
            return (FileHandle(fileDescriptor: fd.rawValue), URL(fileURLWithPath: String(describing: path)))
        }
        
        return (FileHandle(fileDescriptor: fd.rawValue), URL(fileURLWithPath: path.string))
    }

    public func createItemReplacementDirectoryWithURL(for url: URL?, mode: mode_t = 0o755) throws -> URL {
        guard #available(macOS 11.0, iOS 14.0, watchOS 7.0, tvOS 14.0, *), versionCheck(11) else {
            return try URL(
                fileURLWithPath: self.createItemReplacementDirectoryWithStringPath(forPath: url?.path, mode: mode)
            )
        }

        let path = try self.createItemReplacementDirectory(for: url.map { FilePath($0.path) }, mode: mode)

        guard #available(macOS 12.0, iOS 15.0, watchOS 8.0, tvOS 15.0, *), versionCheck(12) else {
            return URL(fileURLWithPath: String(describing: path))
        }

        return URL(fileURLWithPath: path.string)
    }

    public func itemIsReachable(at url: URL) throws -> Bool {
        guard #available(macOS 11.0, iOS 14.0, watchOS 7.0, tvOS 14.0, *), versionCheck(11) else {
            return try self.itemIsReachable(atPath: url.path)
        }

        return try self.itemIsReachable(at: FilePath(url.path))
    }

    public func typeOfItem(at url: URL) throws -> FileType {
        guard #available(macOS 11.0, iOS 14.0, watchOS 7.0, tvOS 14.0, *), versionCheck(11) else {
            return try self.typeOfItem(atPath: url.path)
        }

        return try self.typeOfItem(at: FilePath(url.path))
    }

    public func contentsOfDirectory(at url: URL, recursively: Bool = false) throws -> some Sequence<URL> {
        guard #available(macOS 11.0, iOS 14.0, watchOS 7.0, tvOS 14.0, *), versionCheck(11) else {
            return try self.contentsOfDirectory(atPath: url.path, recursively: recursively).map {
                url.appendingPathComponent($0)
            }
        }

        return try self.contentsOfDirectory(at: FilePath(url.path), recursively: recursively).map { path in
            guard #available(macOS 12.0, iOS 15.0, watchOS 8.0, tvOS 15.0, *), versionCheck(12) else {
                return URL(fileURLWithPath: String(describing: path))
            }

            return URL(fileURLWithPath: path.string)
        }
    }

    public func createDirectory(at url: URL, mode: mode_t = 0o755, recursively: Bool = false) throws {
        guard #available(macOS 11.0, iOS 14.0, watchOS 7.0, tvOS 14.0, *), versionCheck(11) else {
            try self.createDirectory(atPath: url.path, mode: mode, recursively: recursively)
            return
        }

        try self.createDirectory(at: FilePath(url.path), mode: mode, recursively: recursively)
    }

    public func copyItem(at src: URL, to dst: URL) throws {
        guard #available(macOS 11.0, iOS 14.0, watchOS 7.0, tvOS 14.0, *), versionCheck(11) else {
            try self.copyItem(atPath: src.path, toPath: dst.path)
            return
        }

        try self.copyItem(at: FilePath(src.path), to: FilePath(dst.path))
    }

    public func moveItem(at src: URL, to dst: URL) throws {
        guard #available(macOS 11.0, iOS 14.0, watchOS 7.0, tvOS 14.0, *), versionCheck(11) else {
            try self.moveItem(atPath: src.path, toPath: dst.path)
            return
        }

        try self.moveItem(at: FilePath(src.path), to: FilePath(dst.path))
    }

    public func removeItem(at url: URL, recursively: Bool = false) throws {
        guard #available(macOS 11.0, iOS 14.0, watchOS 7.0, tvOS 14.0, *), versionCheck(11) else {
            try self.removeItem(atPath: url.path, recursively: recursively)
            return
        }

        try self.removeItem(at: FilePath(url.path), recursively: recursively)
    }

    public func replaceItem(at originalURL: URL, withItemAt newURL: URL, options: ItemReplacementOptions = []) throws {
        guard #available(macOS 11.0, iOS 14.0, watchOS 7.0, tvOS 14.0, *), versionCheck(11) else {
            try self.replaceItem(atPath: originalURL.path, withItemAtPath: newURL.path, options: options)
            return
        }

        try self.replaceItem(at: FilePath(originalURL.path), withItemAt: FilePath(newURL.path), options: options)
    }
}
