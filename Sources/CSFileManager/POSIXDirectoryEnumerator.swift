//
//  POSIXDirectoryEnumerator.swift
//
//  Created by Charles Srstka on 10/6/23.
//

import CSErrors
import System

#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

struct POSIXDirectoryEnumerator: Sequence {
    let path: String
    let recursive: Bool

    func makeIterator() -> Iterator { Iterator(recursive: recursive, path: path) }

    struct Iterator: IteratorProtocol {
        typealias Element = String

        private class StackItem {
            let absolutePath: String
            let relativePath: String?
            let dir: UnsafeMutablePointer<DIR>

            init(absolutePath: String, relativePath: String?) throws {
                self.absolutePath = absolutePath
                self.relativePath = relativePath
                self.dir = try callPOSIXFunction(path: absolutePath) { opendir(absolutePath) }
            }

            deinit {
                closedir(self.dir)
            }
        }

        let recursive: Bool
        private var dirStack: ContiguousArray<StackItem>

        init(recursive: Bool, path: String) {
            self.recursive = recursive

            if let stackItem = try? StackItem(absolutePath: path, relativePath: nil) {
                self.dirStack = [stackItem]
            } else {
                self.dirStack = []
            }
        }

        mutating func next() -> String? {
            guard let stackItem = self.dirStack.last else { return nil }
            guard let entry = readdir(stackItem.dir) else {
                self.dirStack.removeLast()
                return self.next()
            }

            let name: String = withUnsafePointer(to: &entry.pointee.d_name) {
                let count = Int(entry.pointee.d_namlen)

                return $0.withMemoryRebound(to: UInt8.self, capacity: count) {
                    String(decoding: UnsafeBufferPointer(start: $0, count: count), as: UTF8.self)
                }
            }

            if name == "." || name == ".." { return self.next() }

            let relativePath = stackItem.relativePath.map { self.childPath(ofPath: $0, withName: name) } ?? name

            if entry.pointee.d_type == DT_DIR, self.recursive {
                let absolutePath = self.childPath(ofPath: stackItem.absolutePath, withName: name)

                if let childItem = try? StackItem(absolutePath: absolutePath, relativePath: relativePath) {
                    self.dirStack.append(childItem)
                }
            }

            return relativePath
        }

        private func childPath(ofPath parentPath: String, withName name: String) -> String {
            guard #available(macOS 12.0, iOS 15.0, watchOS 8.0, tvOS 15.0, macCatalyst 15.0, *), versionCheck(12) else {
                return "\(parentPath)/\(name)"
            }

            return FilePath(parentPath).appending(name).string
        }
    }
}
