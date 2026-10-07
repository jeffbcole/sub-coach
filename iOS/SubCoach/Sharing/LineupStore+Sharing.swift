import Foundation

/// Coach-to-coach sharing over Bluetooth: sharing the roster and broadcasting a live game.
extension LineupStore {
    private static let followingKey = "followingGame"
    private static let handledKey = "handledShareSessions"

    func setUpSharing() {
        shareHost.log = shareLog
        shareClient.log = shareLog
        shareHost.onReply = { [weak self] reply in
            MainActor.assumeIsolated { self?.shareReplies[reply.coachID] = reply }
        }
        shareClient.onBundle = { [weak self] bundle, peer in
            MainActor.assumeIsolated { self?.received(bundle, from: peer) }
        }
        handledSessions = UserDefaults.standard.stringArray(forKey: Self.handledKey) ?? []
        if let data = UserDefaults.standard.data(forKey: Self.followingKey),
           let f = try? JSONDecoder().decode(FollowedGame.self, from: data), !f.ended {
            following = f
            shareClient.followed = f.peer
        }
        shareClient.start()
        runShareDebugActions()
    }

    /// The app came to the front or went to the background.
    func setAppActive(_ active: Bool) {
        shareClient.setActive(active)
        if active { refreshLiveActivity() }
    }

    // MARK: Host: share roster

    func startSharingRoster() {
        sharingRoster = RosterOffer(session: Game.newID(), players: team.roster)
        publish()
    }

    func stopSharingRoster() {
        sharingRoster = nil
        publish()
    }

    /// Keep a roster share current if the roster is edited while sharing.
    func rosterChanged() {
        guard var r = sharingRoster, r.players != team.roster else { return }
        r.players = team.roster
        sharingRoster = r
        publish()
    }

    /// Coaches who have answered the current roster share.
    var rosterShareReplies: [ShareReply] {
        guard let s = sharingRoster?.session else { return [] }
        return shareReplies.values.filter { $0.session == s }.sorted { $0.coachName < $1.coachName }
    }

    // MARK: Host: broadcast game

    var isBroadcasting: Bool { broadcastSession != nil }

    func setBroadcasting(_ on: Bool) {
        if on {
            guard broadcastSession == nil else { return }
            broadcastSession = Game.newID()
            broadcastRev = 0
            endedBroadcast = nil
            publish()
        } else {
            guard broadcastSession != nil else { return }
            var last = currentGameOffer()
            last?.ended = true
            last?.rev += 1
            broadcastSession = nil
            endedBroadcast = last
            publish()
            // Keep the "ended" message out for a few seconds so followers hear it, then go quiet.
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(8))
                guard let self, self.broadcastSession == nil else { return }
                self.endedBroadcast = nil
                self.publish()
            }
        }
    }

    /// Coaches following the current broadcast.
    var followers: [ShareReply] {
        guard let s = broadcastSession else { return [] }
        return shareReplies.values.filter { $0.session == s && $0.status == .following }.sorted { $0.coachName < $1.coachName }
    }

    /// Send the latest game to followers after any change.
    func pushBroadcast() {
        guard broadcastSession != nil else { return }
        broadcastRev += 1
        publish()
    }

    private func currentGameOffer() -> GameOffer? {
        guard let session = broadcastSession else { return nil }
        let id = gameLineupID ?? team.currentID
        guard let lineup = team.lineup(id) else { return nil }
        return GameOffer(session: session, rev: broadcastRev, lineup: lineup, players: team.roster, clock: clock, ended: false)
    }

    private func publish() {
        let roster = sharingRoster, game = currentGameOffer() ?? endedBroadcast
        if roster == nil && game == nil {
            shareHost.stop()
            return
        }
        // Stamped when actually sent, which may be later for a coach who connects afterwards.
        shareHost.publish {
            Framer.encode(ShareBundle(hostID: Coach.id, hostName: Coach.displayName, sentAt: .now, roster: roster, game: game))
        }
    }

    // MARK: Receiver

    private func received(_ bundle: ShareBundle, from peer: UUID) {
        guard bundle.hostID != Coach.id else { return }
        let offset = Date.now.timeIntervalSince(bundle.sentAt)

        if let r = bundle.roster, !handledSessions.contains(r.session), pendingRoster?.offer.session != r.session {
            shareLog("roster offer from \(bundle.hostName): \(r.players.count) players")
            pendingRoster = PendingRoster(offer: r, hostName: bundle.hostName, peer: peer)
            reply(.received, session: r.session, to: peer)
            if debugFlag("shareDebugAutoAccept") { acceptRoster() }
        }

        if let g = bundle.game {
            if var f = following, f.offer.session == g.session {
                guard g.rev >= f.offer.rev else { return }
                f.offer = g
                f.clockOffset = offset
                f.lastUpdate = .now
                f.hostName = bundle.hostName
                following = f
                shareLog("game update rev \(g.rev)\(g.ended ? " (ended)" : "") phase \(g.clock.phase.rawValue) half \(g.clock.half)")
                saveFollowing()
                refreshGameOutputs()
                if g.ended { shareClient.drop(peer) } // the host is done; don't keep the connection
            } else if !g.ended, !handledSessions.contains(g.session), pendingGame?.offer.session != g.session {
                shareLog("game offer from \(bundle.hostName): \(g.lineup.displayName)")
                pendingGame = PendingGame(offer: g, hostName: bundle.hostName, peer: peer, clockOffset: offset)
                if debugFlag("shareDebugAutoAccept") { acceptGame() }
            } else if let p = pendingGame, p.offer.session == g.session {
                // Keep the waiting popup's copy current; drop it if the broadcast ended.
                if g.ended { pendingGame = nil } else { pendingGame?.offer = g; pendingGame?.clockOffset = offset }
            }
        }
    }

    func acceptRoster() {
        guard let p = pendingRoster else { return }
        pendingRoster = nil
        markHandled(p.offer.session)
        var t = team
        t.roster = p.offer.players
        clearUndo()
        setTeam(t)
        save()
        reply(.accepted, session: p.offer.session, to: p.peer)
        shareLog("roster accepted: \(p.offer.players.count) players")
    }

    func declineRoster() {
        guard let p = pendingRoster else { return }
        pendingRoster = nil
        markHandled(p.offer.session)
        reply(.declined, session: p.offer.session, to: p.peer)
    }

    func acceptGame() {
        guard let p = pendingGame else { return }
        pendingGame = nil
        markHandled(p.offer.session)
        following = FollowedGame(peer: p.peer, hostName: p.hostName, offer: p.offer,
                                 clockOffset: p.clockOffset, lastUpdate: .now)
        shareClient.followed = p.peer
        saveFollowing()
        reply(.following, session: p.offer.session, to: p.peer)
        presentGameDay = true
        refreshGameOutputs()
        SubAlerts.requestPermission { [weak self] in self?.refreshGameOutputs() }
        shareLog("following \(p.hostName)'s game")
    }

    func declineGame() {
        guard let p = pendingGame else { return }
        pendingGame = nil
        markHandled(p.offer.session)
        reply(.declined, session: p.offer.session, to: p.peer)
    }

    /// Leave the followed game (or close it after the host ended it).
    func stopFollowing() {
        guard let f = following else { return }
        if !f.ended { reply(.left, session: f.offer.session, to: f.peer) }
        shareClient.drop(f.peer)
        following = nil
        saveFollowing()
        refreshGameOutputs()
    }

    /// Save the followed game's lineup as one of this coach's own saved lineups.
    func saveFollowedLineup() {
        guard var f = following, f.savedLineupID == nil else { return }
        var t = team
        // Bring along any players this coach's roster doesn't have yet.
        for p in f.offer.players where !t.roster.contains(where: { $0.id == p.id }) { t.roster.append(p) }
        var copy = f.offer.lineup
        copy.id = Game.newID()
        copy.name = copy.displayName + " (from \(f.hostName))"
        copy.updated = .now
        t.lineups.append(copy)
        setTeam(t)
        save()
        f.savedLineupID = copy.id
        following = f
        saveFollowing()
    }

    private func reply(_ status: ShareReply.Status, session: String, to peer: UUID) {
        shareClient.send(ShareReply(session: session, coachID: Coach.id, coachName: Coach.displayName, status: status), to: peer)
    }

    private func markHandled(_ session: String) {
        handledSessions.append(session)
        if handledSessions.count > 50 { handledSessions.removeFirst(handledSessions.count - 50) }
        UserDefaults.standard.set(handledSessions, forKey: Self.handledKey)
    }

    private func saveFollowing() {
        if let following, let data = try? JSONEncoder().encode(following) {
            UserDefaults.standard.set(data, forKey: Self.followingKey)
        } else {
            UserDefaults.standard.removeObject(forKey: Self.followingKey)
        }
    }

    // MARK: Debugging

    func shareLog(_ message: String) {
        #if DEBUG
        print("[share] \(Date.now.formatted(date: .omitted, time: .standard)) \(message)")
        #endif
    }

    private func debugFlag(_ key: String) -> Bool {
        #if DEBUG
        return UserDefaults.standard.bool(forKey: key)
        #else
        return false
        #endif
    }

    /// Test hooks for driving sharing between two devices from Xcode, e.g. launch arguments
    /// `-shareDebugHostRoster YES`, `-shareDebugHostGame YES`, `-shareDebugAutoAccept YES`, `-shareDebugReset YES`.
    private func runShareDebugActions() {
        #if DEBUG
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(1))
            guard let self else { return }
            if self.debugFlag("shareDebugReset") {
                self.setBroadcasting(false)
                self.stopFollowing()
                self.resetClock()
                self.shareLog("debug: reset")
            }
            if self.debugFlag("shareDebugHostRoster") { self.startSharingRoster(); self.shareLog("debug: sharing roster") }
            if self.debugFlag("shareDebugHostGame") {
                if self.clock.phase == .ready { self.startGame() }
                self.setBroadcasting(true)
                self.shareLog("debug: broadcasting game")
            }
        }
        #endif
    }
}
