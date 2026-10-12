import Foundation

/// Integrates `gofmt` to format Go source code.
public enum GoFormatter {
    /// Path to `gofmt`, if installed.
    public static var gofmtPath: String? {
        let candidates = [
            "/usr/local/go/bin/gofmt",
            "/opt/homebrew/bin/gofmt",
            "/usr/local/bin/gofmt",
            "/usr/bin/gofmt",
        ]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    /// Formats the provided Go source code using `gofmt`.
    /// Returns the formatted code if formatting succeeds, or `nil` if `gofmt` is unavailable
    /// or encountered a syntax error.
    public static func format(_ source: String) -> String? {
        guard let path = gofmtPath else { return nil }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        let inPipe = Pipe()
        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardInput = inPipe
        process.standardOutput = outPipe
        process.standardError = errPipe

        do {
            try process.run()
            if let data = source.data(using: .utf8) {
                inPipe.fileHandleForWriting.write(data)
                try? inPipe.fileHandleForWriting.close()
            }
            let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()

            if process.terminationStatus == 0, let formatted = String(data: outData, encoding: .utf8) {
                return formatted
            }
        } catch {
            return nil
        }
        return nil
    }
}
