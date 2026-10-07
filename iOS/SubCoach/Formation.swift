import Foundation

/// A spot on the field. Roster preferences are saved per role, so they carry across formations.
enum Role: String, Codable, CaseIterable {
    case gk = "GK"
    case ld = "LD", lcb = "LCB", cb = "CB", rcb = "RCB", rd = "RD"
    case lm = "LM", lcm = "LCM", cm = "CM", rcm = "RCM", rm = "RM"
    case lf = "LF", cf = "CF", rf = "RF"

    var name: String { rawValue }

    /// 0 = goalkeeper, 1 = defense, 2 = midfield, 3 = forward
    var group: Int {
        switch self {
        case .gk: return 0
        case .ld, .lcb, .cb, .rcb, .rd: return 1
        case .lm, .lcm, .cm, .rcm, .rm: return 2
        case .lf, .cf, .rf: return 3
        }
    }

    /// The other roles in the same line, used to guess a preference that was never set.
    var lineMates: [Role] { Role.allCases.filter { $0 != self && $0.group == group && group != 0 } }
}

/// A keeper plus field players, named by the field lines back to front (e.g. 2-3-1).
/// The name is unique across team sizes since the numbers add up to the field players.
struct Formation: Identifiable, Equatable {
    let id: String
    let roles: [Role] // keeper first, then back to front

    var name: String { id }
    /// Players on the field, keeper included.
    var size: Int { roles.count }

    static let fieldSizes = Array(4...11)

    static let all: [Formation] = [
        // 4 on the field
        Formation(id: "2-1", roles: [.gk, .ld, .rd, .cf]),
        Formation(id: "1-1-1", roles: [.gk, .cb, .cm, .cf]),
        // 5
        Formation(id: "2-2", roles: [.gk, .ld, .rd, .lf, .rf]),
        Formation(id: "1-2-1", roles: [.gk, .cb, .lm, .rm, .cf]),
        Formation(id: "2-1-1", roles: [.gk, .ld, .rd, .cm, .cf]),
        // 6
        Formation(id: "2-1-2", roles: [.gk, .ld, .rd, .cm, .lf, .rf]),
        Formation(id: "2-2-1", roles: [.gk, .ld, .rd, .lm, .rm, .cf]),
        Formation(id: "3-1-1", roles: [.gk, .ld, .cb, .rd, .cm, .cf]),
        // 7
        Formation(id: "2-2-2", roles: [.gk, .ld, .rd, .lm, .rm, .lf, .rf]),
        Formation(id: "2-3-1", roles: [.gk, .ld, .rd, .lm, .cm, .rm, .cf]),
        Formation(id: "3-2-1", roles: [.gk, .ld, .cb, .rd, .lm, .rm, .cf]),
        Formation(id: "3-1-2", roles: [.gk, .ld, .cb, .rd, .cm, .lf, .rf]),
        // 8
        Formation(id: "3-3-1", roles: [.gk, .ld, .cb, .rd, .lm, .cm, .rm, .cf]),
        Formation(id: "2-3-2", roles: [.gk, .ld, .rd, .lm, .cm, .rm, .lf, .rf]),
        Formation(id: "3-2-2", roles: [.gk, .ld, .cb, .rd, .lm, .rm, .lf, .rf]),
        // 9
        Formation(id: "3-3-2", roles: [.gk, .ld, .cb, .rd, .lm, .cm, .rm, .lf, .rf]),
        Formation(id: "3-2-3", roles: [.gk, .ld, .cb, .rd, .lm, .rm, .lf, .cf, .rf]),
        Formation(id: "4-3-1", roles: [.gk, .ld, .lcb, .rcb, .rd, .lm, .cm, .rm, .cf]),
        // 10
        Formation(id: "4-3-2", roles: [.gk, .ld, .lcb, .rcb, .rd, .lm, .cm, .rm, .lf, .rf]),
        Formation(id: "3-4-2", roles: [.gk, .ld, .cb, .rd, .lm, .lcm, .rcm, .rm, .lf, .rf]),
        Formation(id: "4-4-1", roles: [.gk, .ld, .lcb, .rcb, .rd, .lm, .lcm, .rcm, .rm, .cf]),
        // 11
        Formation(id: "4-4-2", roles: [.gk, .ld, .lcb, .rcb, .rd, .lm, .lcm, .rcm, .rm, .lf, .rf]),
        Formation(id: "4-3-3", roles: [.gk, .ld, .lcb, .rcb, .rd, .lcm, .cm, .rcm, .lf, .cf, .rf]),
        Formation(id: "3-5-2", roles: [.gk, .ld, .cb, .rd, .lm, .lcm, .cm, .rcm, .rm, .lf, .rf]),
    ]
    static let standard = named("2-2-2")

    static func named(_ id: String) -> Formation { all.first { $0.id == id } ?? all.first { $0.id == "2-2-2" }! }

    /// The formations for a team size; the first is the default.
    static func options(size: Int) -> [Formation] { all.filter { $0.size == size } }

    /// e.g. "2 defense · 3 midfield · 1 forward"
    var summary: String {
        let counts = (1...3).map { g in roles.filter { $0.group == g }.count }
        return "\(counts[0]) defense · \(counts[1]) midfield · \(counts[2]) forward"
    }
}
