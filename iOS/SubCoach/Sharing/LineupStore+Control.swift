import Foundation

/// What a following coach just did, as shown on the host's Game Day.
struct RemoteNote: Equatable {
    var text: String
    var at: Date
}

/// A change this phone sent to the host of the game it follows.
struct CommandStatus: Equatable {
    enum State: Equatable { case sending, done, failed }
    var id: String
    var action: GameCommand.Action
    var state: State
    var at: Date
}

/// Running the game from any phone: the clock buttons and subs on Game Day all go through
/// `game(_:)`. On the host (or with no broadcast) the change is made here; on a follower's
/// phone it's sent to the host, which makes it and sends the result to everyone following.
extension LineupStore {
    /// How long to wait for the host to confirm a change before saying it didn't get through.
    private static let commandTimeout: TimeInterval = 8

    /// Game Day's controls work here: this phone's own game, or a followed game whose host
    /// lets followers make changes.
    var canControlGame: Bool {
        guard let f = following else { return true }
        return !f.ended && f.offer.control == true
    }

    func game(_ action: GameCommand.Action) {
        guard let f = following else {
            apply(action, by: nil)
            return
        }
        guard canControlGame else { return }
        let command = GameCommand(session: f.offer.session, id: Game.newID(), coachID: Coach.id,
                                  coachName: Coach.displayName, action: action)
        let sent = shareClient.send(command, to: f.peer)
        commandStatus = CommandStatus(id: command.id, action: action, state: sent ? .sending : .failed, at: .now)
        shareLog("sent \(action.pastTense) to \(f.hostName)\(sent ? "" : " (not connected)")")
        guard sent else { return }
        let id = command.id
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(Self.commandTimeout))
            guard let self, self.commandStatus?.id == id, self.commandStatus?.state == .sending else { return }
            self.commandStatus?.state = .failed
            self.commandStatus?.at = .now
        }
    }

    /// Host: a following coach changed the game.
    func received(_ command: GameCommand) {
        guard let session = broadcastSession, command.session == session,
              !appliedCommands.contains(command.id) else { return }
        appliedCommands.append(command.id)
        if appliedCommands.count > 30 { appliedCommands.removeFirst(appliedCommands.count - 30) }
        shareLog("\(command.coachName) \(command.action.pastTense)")
        lastCommand = command.id
        apply(command.action, by: command.coachName)
        if case .subs = command.action {} else {
            remoteNote = RemoteNote(text: "\(command.coachName) \(command.action.pastTense)", at: .now)
        }
        // Make sure the sender hears it went through, even if nothing changed.
        pushBroadcast()
    }

    /// Follower: a game update arrived; was it the change this phone sent?
    func confirmCommand(in offer: GameOffer) {
        guard let c = commandStatus, c.state != .done, offer.lastCommand == c.id else { return }
        commandStatus?.state = .done
        commandStatus?.at = .now
    }

    /// Make the change on this phone. Each one only applies when it still makes sense (two
    /// coaches tapping Kick off at once kicks off once).
    private func apply(_ action: GameCommand.Action, by coach: String?) {
        let r = clock.reading(at: .now, gameState)
        switch action {
        case .kickoff:
            guard clock.phase == .ready else { return }
            startGame()
        case .pause:
            pauseClock()
        case .resume:
            guard !r.halfOver else { return }
            resumeClock()
        case .adjust(let seconds):
            adjustClock(by: seconds)
        case .endHalf:
            guard clock.phase != .ready, !r.halfOver else { return }
            endHalfNow()
        case .startSecondHalf:
            guard r.halfOver, r.half == 0 else { return }
            startSecondHalf()
        case .subs(let swaps, let out):
            makeSubs(swaps.map { ($0.off, $0.on) }, out: Set(out), by: coach)
        }
    }
}
