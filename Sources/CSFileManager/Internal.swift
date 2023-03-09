//
//  Internal.swift
//  
//
//  Created by Charles Srstka on 3/8/23.
//

#if DEBUG
private var emulatedVersion: Int = .max

func emulateOSVersion(_ version: Int, closure: () throws -> Void) rethrows {
    emulatedVersion = version
    defer { emulatedVersion = .max }

    try closure()
}

func versionCheck(_ version: Int) -> Bool { version >= emulatedVersion }
#else
@inline(__always) func versionCheck(_: Int) -> Bool { true }
#endif
