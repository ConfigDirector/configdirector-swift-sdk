import Foundation

extension Date {
    var millisecondsSince1970: Int64 {
        Int64(timeIntervalSince1970 * 1000)
    }
}
