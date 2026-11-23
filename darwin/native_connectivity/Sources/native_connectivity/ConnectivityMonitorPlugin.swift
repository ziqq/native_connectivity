#if os(macOS)
import FlutterMacOS
#else
import Flutter
#endif
import Network

public final class ConnectivityMonitorPlugin: NSObject, FlutterPlugin, FlutterStreamHandler {
    private let queue = DispatchQueue(label: "com.github.ziqq.connectivity_monitor")
    private var monitor: NWPathMonitor?

    public static func register(with registrar: FlutterPluginRegistrar) {
        #if os(macOS)
        let messenger = registrar.messenger
        #else
        let messenger = registrar.messenger()
        #endif
        let channel = FlutterEventChannel(name: "github.com/ziqq/connectivity_monitor", binaryMessenger: messenger)
        let plugin = ConnectivityMonitorPlugin()
        channel.setStreamHandler(plugin)
        registrar.publish(plugin)
    }

    public func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        stop()
        let next = NWPathMonitor()
        monitor = next
        next.pathUpdateHandler = { [weak self, weak next] path in
            let state: String
            switch path.status {
            case .satisfied:
                state = "satisfied"
            case .unsatisfied:
                state = "unsatisfied"
            case .requiresConnection:
                // An ordinary request can activate a path that requires a connection.
                state = "unknown"
            @unknown default:
                state = "unknown"
            }
            DispatchQueue.main.async {
                guard let self, let next, self.monitor === next else { return }
                events(state)
            }
        }
        next.start(queue: queue)
        return nil
    }

    public func onCancel(withArguments arguments: Any?) -> FlutterError? {
        stop()
        return nil
    }

    public func detachFromEngine(for registrar: FlutterPluginRegistrar) {
        stop()
    }

    private func stop() {
        monitor?.cancel()
        monitor = nil
    }
}
