import Foundation

enum FileIO {
    enum FileIOError: LocalizedError {
        case readFailed(URL, underlying: Error)
        case writeFailed(URL, underlying: Error)
        case notUTF8(URL)

        var errorDescription: String? {
            switch self {
            case .readFailed(let url, let err):
                "Couldn't read \(url.lastPathComponent): \(err.localizedDescription)"
            case .writeFailed(let url, let err):
                "Couldn't save \(url.lastPathComponent): \(err.localizedDescription)"
            case .notUTF8(let url):
                "\(url.lastPathComponent) isn't valid UTF-8."
            }
        }
    }

    static func read(_ url: URL) throws -> String {
        do {
            let data = try Data(contentsOf: url)
            guard let text = String(data: data, encoding: .utf8) else {
                throw FileIOError.notUTF8(url)
            }
            return text
        } catch let error as FileIOError {
            throw error
        } catch {
            throw FileIOError.readFailed(url, underlying: error)
        }
    }

    static func write(_ text: String, to url: URL) throws {
        do {
            try text.data(using: .utf8)?.write(to: url, options: .atomic)
        } catch {
            throw FileIOError.writeFailed(url, underlying: error)
        }
    }
}
