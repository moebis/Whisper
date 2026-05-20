import OSLog
import Foundation

struct AppLogger {
    private static let logger = Logger(subsystem: "com.moebis.Whisper", category: "App")
    
    static func info(_ message: String) {
        print(message)
        logger.info("\(message, privacy: .public)")
        appendToFile(message)
    }
    
    static func error(_ message: String) {
        print(message)
        logger.error("\(message, privacy: .public)")
        appendToFile("ERROR: " + message)
    }
    
    private static func appendToFile(_ message: String) {
        let fileManager = FileManager.default
        guard let libraryDirectory = fileManager.urls(for: .libraryDirectory, in: .userDomainMask).first else { return }
        let logsDirectory = libraryDirectory.appendingPathComponent("Logs")
        
        do {
            try fileManager.createDirectory(at: logsDirectory, withIntermediateDirectories: true, attributes: nil)
            let logFileURL = logsDirectory.appendingPathComponent("Whisper.log")
            
            let timestamp = DateFormatter.localizedString(from: Date(), dateStyle: .short, timeStyle: .medium)
            let logLine = "[\(timestamp)] \(message)\n"
            
            if let data = logLine.data(using: .utf8) {
                if fileManager.fileExists(atPath: logFileURL.path) {
                    if let fileHandle = try? FileHandle(forWritingTo: logFileURL) {
                        try fileHandle.seekToEnd()
                        fileHandle.write(data)
                        try fileHandle.close()
                    } else {
                        // Fallback if file handle failed
                        try data.write(to: logFileURL, options: .atomic)
                    }
                } else {
                    try data.write(to: logFileURL, options: .atomic)
                }
            }
        } catch {
            print("Failed to write to log file: \(error.localizedDescription)")
        }
    }
}
