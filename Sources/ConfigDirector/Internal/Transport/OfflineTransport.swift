import Foundation

struct OfflineTransport: Transport {
    private let configSet: ConfigSet
    private let onConfigSet: ConfigSetHandler

    init(configs: [String: ConfigState], onConfigSet: @escaping ConfigSetHandler) {
        configSet = ConfigSet(configs: configs)
        self.onConfigSet = onConfigSet
    }

    func connect(
        context _: ConfigDirectorContext,
        timeout _: TimeInterval,
        reason _: ConnectReason
    ) async throws {
        onConfigSet(configSet)
    }

    func disconnect() {}

    func close() {}
}
