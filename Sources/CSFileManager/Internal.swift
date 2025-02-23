//
//  Internal.swift
//  
//
//  Created by Charles Srstka on 3/8/23.
//

#if DEBUG
import SyncPolyfill

private let emulatedVersionMutex = Mutex<Int>(.max)

func emulateOSVersion(_ version: Int, closure: () throws -> Void) rethrows {
    emulatedVersionMutex.withLock { $0 = version }
    defer { emulatedVersionMutex.withLock { $0 = .max } }

    try closure()
}

internal func versionCheck(_ version: Int) -> Bool { emulatedVersionMutex.withLock { $0 >= version } }
#else
@inline(__always) func versionCheck(_: Int) -> Bool { true }
#endif
