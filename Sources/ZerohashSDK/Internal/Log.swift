import Foundation
import os.log

internal enum Log {

    private static let subsystem = "com.zerohash.sdk"
    private static let osLog = OSLog(subsystem: subsystem, category: "ZerohashSDK")

    static func error(_ message: @autoclosure () -> String) {
        #if DEBUG
        os_log("%{public}@", log: osLog, type: .error, message())
        #endif
    }

    static func debug(_ message: @autoclosure () -> String) {
        #if DEBUG
        os_log("%{public}@", log: osLog, type: .debug, message())
        #endif
    }
}
