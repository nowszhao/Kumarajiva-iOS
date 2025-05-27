import Foundation
import Network

@MainActor
class NetworkMonitor: ObservableObject {
    static let shared = NetworkMonitor()
    
    @Published var isConnected = false
    @Published var connectionType: ConnectionType = .unknown
    
    /// 是否可以下载大文件（WiFi或用户允许蜂窝网络下载）
    var canDownloadLargeFiles: Bool {
        guard isConnected else { return false }
        
        switch connectionType {
        case .wifi, .ethernet:
            return true
        case .cellular:
            return UserSettings.shared.allowCellularDownload
        case .unknown:
            return false
        }
    }
    
    enum ConnectionType {
        case wifi
        case cellular
        case ethernet
        case unknown
        
        var description: String {
            switch self {
            case .wifi: return "WiFi"
            case .cellular: return "蜂窝网络"
            case .ethernet: return "以太网"
            case .unknown: return "未知"
            }
        }
    }
    
    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "NetworkMonitor")
    
    private init() {
        startMonitoring()
    }
    
    private func startMonitoring() {
        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in
                self?.isConnected = path.status == .satisfied
                self?.updateConnectionType(path)
            }
        }
        monitor.start(queue: queue)
    }
    
    private func updateConnectionType(_ path: NWPath) {
        if path.usesInterfaceType(.wifi) {
            connectionType = .wifi
        } else if path.usesInterfaceType(.cellular) {
            connectionType = .cellular
        } else if path.usesInterfaceType(.wiredEthernet) {
            connectionType = .ethernet
        } else {
            connectionType = .unknown
        }
    }
    
    deinit {
        monitor.cancel()
    }
}