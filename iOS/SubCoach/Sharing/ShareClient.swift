import CoreBluetooth
import Foundation

/// The receiving coach's side. While the app is open it connects to every nearby coach who is
/// sharing and passes along what they send. In the background it only keeps the connection to
/// the game being followed, which iOS keeps alive (and reconnects) even with the phone locked.
final class ShareClient: NSObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    var onBundle: (ShareBundle, UUID) -> Void = { _, _ in }
    var log: (String) -> Void = { _ in }

    private var manager: CBCentralManager?
    private var peers: [UUID: CBPeripheral] = [:]
    private var reassemblers: [UUID: Reassembler] = [:]
    private var replyCharacteristics: [UUID: CBCharacteristic] = [:]
    private var active = false

    /// The host whose game we're following, if any. Kept connected in the background.
    var followed: UUID? {
        didSet { if let followed { ensureConnected(followed) } }
    }

    func start() {
        guard manager == nil else { return }
        manager = CBCentralManager(delegate: self, queue: nil,
                                   options: [CBCentralManagerOptionRestoreIdentifierKey: "lineup.share.client"])
    }

    /// App came to the front or went to the background.
    func setActive(_ on: Bool) {
        active = on
        guard let manager, manager.state == .poweredOn else { return }
        if on {
            scan()
        } else {
            manager.stopScan()
            for (id, p) in peers where id != followed { manager.cancelPeripheralConnection(p) }
        }
    }

    /// Stop listening to this host (declined, or stopped following).
    func drop(_ id: UUID) {
        if followed == id { followed = nil }
        if let p = peers[id] { manager?.cancelPeripheralConnection(p) }
    }

    func send(_ reply: ShareReply, to id: UUID) {
        guard let p = peers[id], let c = replyCharacteristics[id], let data = try? JSONEncoder().encode(reply) else { return }
        p.writeValue(data, for: c, type: .withResponse)
    }

    private func scan() {
        manager?.scanForPeripherals(withServices: [ShareBLE.service], options: nil)
    }

    private func ensureConnected(_ id: UUID) {
        guard let manager, manager.state == .poweredOn else { return }
        let p = peers[id] ?? manager.retrievePeripherals(withIdentifiers: [id]).first
        guard let p else { return }
        adopt(p)
        if p.state == .disconnected { manager.connect(p) }
    }

    private func adopt(_ p: CBPeripheral) {
        peers[p.identifier] = p
        p.delegate = self
    }

    // MARK: CBCentralManagerDelegate

    func centralManager(_ central: CBCentralManager, willRestoreState dict: [String: Any]) {
        let restored = dict[CBCentralManagerRestoredStatePeripheralsKey] as? [CBPeripheral] ?? []
        restored.forEach(adopt)
        log("client restored \(restored.count) connection(s)")
    }

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        log("client bluetooth state \(central.state.rawValue)")
        guard central.state == .poweredOn else { return }
        if let followed { ensureConnected(followed) }
        if active { scan() }
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                        advertisementData: [String: Any], rssi RSSI: NSNumber) {
        guard active, peers[peripheral.identifier]?.state != .connected, peripheral.state == .disconnected else { return }
        log("client found host \(peripheral.identifier.uuidString.prefix(4))")
        adopt(peripheral)
        central.connect(peripheral)
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        log("client connected \(peripheral.identifier.uuidString.prefix(4))")
        reassemblers[peripheral.identifier] = Reassembler()
        peripheral.discoverServices([ShareBLE.service])
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        disconnected(peripheral)
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        log("client disconnected \(peripheral.identifier.uuidString.prefix(4))")
        disconnected(peripheral)
    }

    private func disconnected(_ p: CBPeripheral) {
        let id = p.identifier
        replyCharacteristics[id] = nil
        reassemblers[id] = nil
        if id == followed {
            // Waits (without timing out) until the host is back in range, even in the background.
            manager?.connect(p)
        } else {
            peers[id] = nil
            if active { manager?.stopScan(); scan() }
        }
    }

    // MARK: CBPeripheralDelegate

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard let s = peripheral.services?.first(where: { $0.uuid == ShareBLE.service }) else {
            manager?.cancelPeripheralConnection(peripheral)
            return
        }
        peripheral.discoverCharacteristics([ShareBLE.stream, ShareBLE.reply], for: s)
    }

    func peripheral(_ peripheral: CBPeripheral, didModifyServices invalidatedServices: [CBService]) {
        // The host stopped sharing.
        if invalidatedServices.contains(where: { $0.uuid == ShareBLE.service }) {
            peripheral.discoverServices([ShareBLE.service])
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        for c in service.characteristics ?? [] {
            if c.uuid == ShareBLE.stream { peripheral.setNotifyValue(true, for: c) }
            if c.uuid == ShareBLE.reply { replyCharacteristics[peripheral.identifier] = c }
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard characteristic.uuid == ShareBLE.stream, let chunk = characteristic.value else { return }
        let id = peripheral.identifier
        var r = reassemblers[id] ?? Reassembler()
        let done = r.add(chunk)
        reassemblers[id] = r
        guard let done else { return }
        guard let bundle = Framer.decode(ShareBundle.self, from: done) else { log("client: bad message"); return }
        onBundle(bundle, id)
    }
}
