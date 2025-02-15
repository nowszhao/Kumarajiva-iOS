import Foundation

@MainActor
class ProfileViewModel: ObservableObject {
    @Published var stats: Stats?
    @Published var isLoading = false
    @Published var error: String?
    
    func loadStats() async {
        isLoading = true
        do {
            stats = try await APIService.shared.getStats()
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }
} 