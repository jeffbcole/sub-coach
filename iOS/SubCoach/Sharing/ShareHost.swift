import CoreBluetooth
import Foundation

/// The sharing coach's side: advertises nearby and sends the current bundle to every coach
/// who connects, and again whenever it changes.
final class ShareHost: NSObject, CBPeripheralManagerDelegate {
    var onReply: (ShareReply) -> Void = { _ in }
    /// A coach's phone disconnected (stopped following, out of range, or app closed).
    var onCoachGone: (String) -> Void = { _ in }
    /// Which coach is behind each connection, learned from their replies.
    private var coachByCentral: [UUID: String] = [:]
    var log: (String) -> Void = { _ in }

    private var manager: CBPeripheralManager?
    private var stream: CBMutableCharacteristic?
    private var serviceAdded = false
    private var wanted = false
    /// Builds the bundle to send. Called at the moment of sending, so its timestamp is accurate
    /// even for a coach who connects later (followers use it to line their clock up with ours).
    private var current: (() -> Data?)?
    private var messageNumber: UInt16 = 0
    private var subscribers: [CBCentral] = []
    /// Pieces waiting to go out when Bluetooth's send buffer frees up.
    private var outbox: [(chunk: Data, to: [CBCentral]?)] = []

    /// Start (or keep) advertising, and send the bundle to everyone connected.
    func publish(_ makeData: @escaping () -> Data?) {
        current = makeData
        wanted = true
        if manager == nil {
            manager = CBPeripheralManager(delegate: self, queue: nil)
        } else {
            setUp()
        }
        if let data = makeData() { send(data, to: nil) }
    }

    func stop() {
        wanted = false
        current = nil
        outbox.removeAll()
        subscribers.removeAll()
        manager?.stopAdvertising()
        manager?.removeAllServices()
        // Let go of the Bluetooth session completely. If the app is later killed while still
        // holding one, iOS can leave it behind and the next launch can't advertise until the
        // phone restarts. A fresh session is opened the next time sharing starts.
        manager?.delegate = nil
        manager = nil
        serviceAdded = false
        stream = nil
        log("host stopped")
    }

    private func setUp() {
        guard wanted, let manager, manager.state == .poweredOn else { return }
        if !serviceAdded {
            let stream = CBMutableCharacteristic(type: ShareBLE.stream, properties: [.notify], value: nil, permissions: [.readable])
            let reply = CBMutableCharacteristic(type: ShareBLE.reply, properties: [.write], value: nil, permissions: [.writeable])
            let service = CBMutableService(type: ShareBLE.service, primary: true)
            service.characteristics = [stream, reply]
            self.stream = stream
            serviceAdded = true
            manager.add(service)
        } else if !manager.isAdvertising {
            advertise()
        }
    }

    private func advertise() {
        // Only the service ID: a 128-bit ID (18 bytes) plus a name doesn't fit in the 31-byte
        // advertisement, and iOS then sometimes drops the ID, so coaches can't find each other.
        // The coach's name travels in the shared data instead.
        manager?.startAdvertising([CBAdvertisementDataServiceUUIDsKey: [ShareBLE.service]])
    }

    private func send(_ data: Data, to centrals: [CBCentral]?) {
        let targets = centrals ?? subscribers
        guard stream != nil, !targets.isEmpty else { return }
        messageNumber &+= 1
        // Pieces addressed to everyone also reach a coach who connects mid-send, so stay within a
        // size every iPhone and iPad accepts (182 bytes) rather than the current coaches' maximum.
        let packet = min(182, targets.map(\.maximumUpdateValueLength).min() ?? 182)
        for c in Framer.chunks(data, message: messageNumber, maxPacket: packet) { outbox.append((c, centrals)) }
        log("host sending \(data.count) bytes to \(targets.count) coach(es)")
        flush()
    }

    private func flush() {
        guard let manager, let stream else { return }
        while let next = outbox.first {
            guard manager.updateValue(next.chunk, for: stream, onSubscribedCentrals: next.to) else { return }
            outbox.removeFirst()
        }
    }

    // MARK: CBPeripheralManagerDelegate

    func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
        log("host bluetooth state \(peripheral.state.rawValue)")
        if peripheral.state == .poweredOn {
            serviceAdded = false
            setUp()
        }
    }

    func peripheralManager(_ peripheral: CBPeripheralManager, didAdd service: CBService, error: Error?) {
        if let error { log("host add service failed: \(error)"); return }
        advertise()
    }

    func peripheralManagerDidStartAdvertising(_ peripheral: CBPeripheralManager, error: Error?) {
        log(error.map { "host advertising failed: \($0)" } ?? "host advertising")
    }

    func peripheralManager(_ peripheral: CBPeripheralManager, central: CBCentral, didSubscribeTo characteristic: CBCharacteristic) {
        if !subscribers.contains(where: { $0.identifier == central.identifier }) { subscribers.append(central) }
        log("host: coach connected (\(subscribers.count))")
        if let data = current?() { send(data, to: [central]) }
    }

    func peripheralManager(_ peripheral: CBPeripheralManager, central: CBCentral, didUnsubscribeFrom characteristic: CBCharacteristic) {
        subscribers.removeAll { $0.identifier == central.identifier }
        log("host: coach disconnected (\(subscribers.count))")
        if let coach = coachByCentral.removeValue(forKey: central.identifier) { onCoachGone(coach) }
    }

    func peripheralManagerIsReady(toUpdateSubscribers peripheral: CBPeripheralManager) {
        flush()
    }

    func peripheralManager(_ peripheral: CBPeripheralManager, didReceiveWrite requests: [CBATTRequest]) {
        for r in requests {
            if let v = r.value, let reply = try? JSONDecoder().decode(ShareReply.self, from: v) {
                coachByCentral[r.central.identifier] = reply.coachID
                onReply(reply)
            }
        }
        if let first = requests.first { peripheral.respond(to: first, withResult: .success) }
    }
}
