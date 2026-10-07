import Foundation

/// A game another coach is broadcasting that this phone is following.
struct FollowedGame: Codable, Equatable {
    /// Bluetooth identity of the host's phone, used to reconnect.
    var peer: UUID
    var hostName: String
    /// The host coach's id (missing for follows saved by earlier builds).
    var hostID: String?
    var offer: GameOffer
    /// Add to the host's times to get this phone's times (phone clocks can differ by a few seconds).
    var clockOffset: TimeInterval
    var lastUpdate: Date

    var ended: Bool { offer.ended }

    var state: LineupState {
        let team = TeamData(roster: offer.players, lineups: [offer.lineup], currentID: offer.lineup.id)
        return team.state(for: offer.lineup.id) ?? LineupState()
    }

    /// The host's clock in this phone's time. After the host ends the broadcast it reads as not started,
    /// which clears this phone's alerts and lock screen countdown.
    var clock: GameClock {
        guard !offer.ended else { return GameClock() }
        var c = offer.clock
        c.startedAt = c.startedAt.map { $0.addingTimeInterval(clockOffset) }
        return c
    }
}

/// Small wrappers for the popups shown to a receiving coach.
struct PendingRoster: Equatable {
    var offer: RosterOffer
    var hostName: String
    var peer: UUID
}

struct PendingGame: Equatable {
    var offer: GameOffer
    var hostName: String
    var hostID: String
    var peer: UUID
    /// Measured when the offer arrived (not when Follow was tapped).
    var clockOffset: TimeInterval
}

/// A broadcast this phone can currently hear, so a coach can follow (or re-follow) it from its lineup.
struct LiveBroadcast: Equatable {
    var offer: GameOffer
    var hostName: String
    var hostID: String
    var peer: UUID
    var clockOffset: TimeInterval
}
