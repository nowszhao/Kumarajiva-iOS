import SwiftUI

struct FunctionButton: Identifiable {
    let id: UUID
    let icon: String
    let title: String
    var isActive: Bool
    var isDisabled: Bool
    var showProgress: Bool
    var isNavigationLink: Bool
    var navigationDestination: AnyView?
    var action: (() -> Void)?
    
    init(
        id: UUID = UUID(),
        icon: String,
        title: String,
        isActive: Bool = false,
        isDisabled: Bool = false,
        showProgress: Bool = false,
        isNavigationLink: Bool = false,
        navigationDestination: AnyView? = nil,
        action: (() -> Void)? = nil
    ) {
        self.id = id
        self.icon = icon
        self.title = title
        self.isActive = isActive
        self.isDisabled = isDisabled
        self.showProgress = showProgress
        self.isNavigationLink = isNavigationLink
        self.navigationDestination = navigationDestination
        self.action = action
    }
}
