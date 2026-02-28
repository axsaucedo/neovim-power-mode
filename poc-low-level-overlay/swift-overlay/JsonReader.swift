import Foundation

class JsonReader {
    let onEvent: ([String: Any]) -> Void
    private var thread: Thread?

    init(onEvent: @escaping ([String: Any]) -> Void) {
        self.onEvent = onEvent
    }

    func start() {
        thread = Thread {
            let handle = FileHandle.standardInput
            while true {
                let data = handle.availableData
                if data.isEmpty { break }
                guard let line = String(data: data, encoding: .utf8) else { continue }
                for jsonLine in line.components(separatedBy: "\n") where !jsonLine.isEmpty {
                    if let jsonData = jsonLine.data(using: .utf8),
                       let event = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] {
                        self.onEvent(event)
                    }
                }
            }
        }
        thread?.start()
    }
}
