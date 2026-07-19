//
//  DiskImage.swift
//  CSFileManager
//
//  Created by Charles Srstka on 7/18/26.
//

import Foundation
import SyncPolyfill
import Testing

struct DiskImage {
    let imageURL: URL
    let mountPoint: URL
    let devEntry: URL
    let supportResourceFork: Bool
    
    struct MountTrait: SuiteTrait, TestScoping {
        @TaskLocal static var diskImages: [String : DiskImage] = [:]
        
        func provideScope(for test: Test, testCase: Test.Case?, performing f: @Sendable () async throws -> Void) async throws {
            let tempURL = FileManager.default.temporaryDirectory
            let fileSystems = ["APFS", "HFS+", "ExFAT"]
            
            let diskImages: [String : DiskImage] = try fileSystems.reduce(into: [:]) { diskImages, eachFS in
                let dmgURL = try self.createDiskImage(
                    fs: eachFS,
                    at: tempURL.appending(path: UUID().uuidString),
                    megabytes: 10
                )
                
                let (mountPoint: mountPoint, devEntry: devEntry) = try self.mountDiskImage(at: dmgURL)
                
                let rsrcFork = !["ExFAT"].contains(eachFS)
                
                diskImages[eachFS] = DiskImage(
                    imageURL: dmgURL,
                    mountPoint: mountPoint,
                    devEntry: devEntry,
                    supportResourceFork: rsrcFork
                )
            }
            
            defer {
                #expect(throws: Never.self) {
                    for eachDMG in diskImages.values {
                        try self.unmountDiskImage(at: eachDMG.devEntry)
                        try FileManager.default.removeItem(at: eachDMG.imageURL)
                    }
                }
            }
            
            try await Self.$diskImages.withValue(diskImages) {
                try await f()
            }
        }
        
        private func createDiskImage(fs: String, at url: URL, megabytes: Int) throws -> URL {
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
        
        private func mountDiskImage(at url: URL) throws -> (mountPoint: URL, devEntry: URL) {
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
        
        private func unmountDiskImage(at url: URL) throws {
            let process = Process()
            
            process.executableURL = URL(filePath: "/usr/bin/hdiutil")
            process.arguments = ["detach", url.path]
            
            try process.run()
            process.waitUntilExit()
        }
    }
}
