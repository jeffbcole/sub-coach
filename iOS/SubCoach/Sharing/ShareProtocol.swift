import CoreBluetooth
import Foundation

/// Bluetooth identifiers for coach-to-coach sharing.
enum ShareBLE {
    static let service = CBUUID(string: "8B3E1A70-5C2D-4F7A-9E61-2A4C7D9B0E11")
    /// Host -> coaches (notify): the host's current bundle, in chunks.
    static let stream = CBUUID(string: "8B3E1A71-5C2D-4F7A-9E61-2A4C7D9B0E11")
    /// Coaches -> host (write): a short reply such as "accepted" or "following".
    static let reply = CBUUID(string: "8B3E1A72-5C2D-4F7A-9E61-2A4C7D9B0E11")
}

/// Who this coach is, as shown to other coaches.
enum Coach {
    private static let idKey = "coachID", nameKey = "coachName"

    static var id: String {
        if let id = UserDefaults.standard.string(forKey: idKey) { return id }
        let id = UUID().uuidString
        UserDefaults.standard.set(id, forKey: idKey)
        return id
    }

    static var name: String {
        get { UserDefaults.standard.string(forKey: nameKey)?.trimmingCharacters(in: .whitespaces) ?? "" }
        set { UserDefaults.standard.set(String(newValue.prefix(40)), forKey: nameKey) }
    }

    static var displayName: String { name.isEmpty ? "A coach" : name }
}

/// Everything a host is sharing right now. Sent whole whenever it changes.
struct ShareBundle: Codable, Equatable {
    var hostID: String
    var hostName: String
    /// Host's clock when sent, so followers can line their clock up with it.
    var sentAt: Date
    var roster: RosterOffer?
    var game: GameOffer?
}

struct RosterOffer: Codable, Equatable {
    /// New each time the host taps Share, so coaches are only asked once per share.
    var session: String
    var players: [RosterPlayer]
}

struct GameOffer: Codable, Equatable {
    /// New each time the host turns Broadcast on.
    var session: String
    /// Goes up with every change, so stale updates can be ignored.
    var rev: Int
    var lineup: SavedLineup
    var players: [RosterPlayer]
    var clock: GameClock
    /// The host stopped broadcasting or reset the game.
    var ended: Bool
}

struct ShareReply: Codable, Equatable {
    enum Status: String, Codable { case received, accepted, declined, following, left }
    var session: String
    var coachID: String
    var coachName: String
    var status: Status
}

/// Splits messages into pieces small enough for one Bluetooth packet and puts them back together.
/// Each piece starts with a 6-byte header: message number, piece index, piece count.
enum Framer {
    static let headerSize = 6

    static func encode<T: Encodable>(_ value: T) -> Data? {
        guard let json = try? JSONEncoder().encode(value) else { return nil }
        return (try? (json as NSData).compressed(using: .zlib)) as Data?
    }

    static func decode<T: Decodable>(_ type: T.Type, from data: Data) -> T? {
        guard let json = try? (data as NSData).decompressed(using: .zlib) as Data else { return nil }
        return try? JSONDecoder().decode(type, from: json)
    }

    static func chunks(_ data: Data, message: UInt16, maxPacket: Int) -> [Data] {
        let size = max(20, maxPacket - headerSize)
        let count = max(1, (data.count + size - 1) / size)
        return (0..<count).map { i in
            var out = Data()
            for v in [message, UInt16(i), UInt16(count)] { withUnsafeBytes(of: v.littleEndian) { out.append(contentsOf: $0) } }
            let lo = data.startIndex + i * size
            out.append(data[lo..<min(data.endIndex, lo + size)])
            return out
        }
    }
}

/// Collects pieces from one sender until a message is complete.
struct Reassembler {
    private var parts: [UInt16: [Int: Data]] = [:]

    mutating func add(_ chunk: Data) -> Data? {
        guard chunk.count >= Framer.headerSize else { return nil }
        let b = [UInt8](chunk.prefix(Framer.headerSize))
        func u16(_ i: Int) -> Int { Int(b[i]) | Int(b[i + 1]) << 8 }
        let message = UInt16(u16(0)), index = u16(2), count = u16(4)
        guard count > 0, index < count else { return nil }
        parts[message, default: [:]][index] = chunk.dropFirst(Framer.headerSize)
        guard let got = parts[message], got.count == count else { return nil }
        parts[message] = nil
        // Drop leftovers from older, unfinished messages.
        if parts.count > 4 { parts.removeAll() }
        return (0..<count).reduce(into: Data()) { $0.append(got[$1]!) }
    }
}
