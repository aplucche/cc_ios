import Foundation
import os

enum LogCategory: String {
    case ui = "UI"
    case network = "Network"
    case system = "System"
    case agent = "Agent"
}

struct Logger {
    private static let subsystem = "com.claudemachinelauncher"
    static let debugEnabled = ProcessInfo.processInfo.environment["DEBUG_LOGGING"] != nil
    
    private static func osLog(for category: LogCategory) -> OSLog {
        return OSLog(subsystem: subsystem, category: category.rawValue)
    }
    
    static func log(_ message: String, category: LogCategory) {
        guard debugEnabled else { return }
        
        let timestamp = DateFormatter.logFormatter.string(from: Date())
        let logMessage = "[\(timestamp)] \(category.rawValue): \(message)"
        
        os_log("%{public}@", log: osLog(for: category), type: .default, logMessage)
        LogStore.shared.add(logMessage)
    }
}

// Optional: Store logs in memory for in-app inspection
class LogStore: ObservableObject {
    static let shared = LogStore()
    
    @Published private(set) var logs: [String] = []
    private let maxLogs = 100
    
    private init() {}
    
    func add(_ message: String) {
        DispatchQueue.main.async {
            self.logs.append(message)
            if self.logs.count > self.maxLogs {
                self.logs.removeFirst(self.logs.count - self.maxLogs)
            }
        }
    }
    
    func clear() {
        DispatchQueue.main.async {
            self.logs.removeAll()
        }
    }
}

private extension DateFormatter {
    static let logFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter
    }()
}