import Foundation

public struct NagramRegistrationDateResult: Equatable {
    public enum Kind: Equatable {
        case approximately
        case newerThan
        case olderThan
    }

    public let kind: Kind
    public let date: String
}

/// Estimates a registration month from the user ID by interpolating the bundled reference table
/// (`NagramIdDate.json`, mirrored from Nnngram's `id_date.json`).
public final class NagramRegistrationDateTable {
    private struct Payload: Decodable {
        struct Point: Decodable {
            let id: Int64
            let date: Int64
        }

        let data: [Point]
    }

    /// `nil` when the bundled table is missing or malformed.
    public static let shared: NagramRegistrationDateTable? = {
        guard let url = Bundle.main.url(forResource: "NagramIdDate", withExtension: "json"), let data = try? Data(contentsOf: url) else {
            return nil
        }
        return NagramRegistrationDateTable(data: data)
    }()

    private let points: [Payload.Point]
    private let dateFormatter: DateFormatter

    public init?(data: Data) {
        guard let payload = try? JSONDecoder().decode(Payload.self, from: data), !payload.data.isEmpty else {
            return nil
        }
        for i in 1 ..< payload.data.count {
            if payload.data[i].id <= payload.data[i - 1].id {
                return nil
            }
        }
        self.points = payload.data

        let dateFormatter = DateFormatter()
        dateFormatter.calendar = Calendar(identifier: .gregorian)
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateFormatter.dateFormat = "yyyy-MM"
        self.dateFormatter = dateFormatter
    }

    public func estimate(userId: Int64) -> NagramRegistrationDateResult {
        let first = self.points[0]
        let last = self.points[self.points.count - 1]
        if userId < first.id {
            return self.result(.olderThan, timestamp: Double(first.date))
        }
        if userId > last.id {
            return self.result(.newerThan, timestamp: Double(last.date))
        }
        for i in 1 ..< self.points.count {
            let lower = self.points[i - 1]
            let upper = self.points[i]
            if userId <= upper.id {
                let t = Double(userId - lower.id) / Double(upper.id - lower.id)
                return self.result(.approximately, timestamp: Double(lower.date) + t * Double(upper.date - lower.date))
            }
        }
        return self.result(.approximately, timestamp: Double(first.date))
    }

    private func result(_ kind: NagramRegistrationDateResult.Kind, timestamp: Double) -> NagramRegistrationDateResult {
        return NagramRegistrationDateResult(kind: kind, date: self.dateFormatter.string(from: Date(timeIntervalSince1970: timestamp)))
    }
}
