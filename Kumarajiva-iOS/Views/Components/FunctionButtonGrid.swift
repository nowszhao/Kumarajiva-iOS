import SwiftUI

// MARK: - 功能按钮网格组件
struct FunctionButtonGrid: View {
    let buttons: [FunctionButton]
    
    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: 5), spacing: 8) {
            ForEach(buttons) { button in
                buttonContent(for: button)
            }
        }
        .padding(.horizontal, 8)
    }
    
    @ViewBuilder
    private func buttonContent(for button: FunctionButton) -> some View {
        if button.isNavigationLink, let destination = button.navigationDestination {
            NavigationLink(destination: destination) {
                FunctionButtonView(button: button)
            }
            .disabled(button.isDisabled)
        } else if let action = button.action {
            Button(action: action) {
                FunctionButtonView(button: button)
            }
            .disabled(button.isDisabled)
        } else {
            FunctionButtonView(button: button)
                .opacity(button.isDisabled ? 0.4 : 1.0)
                .allowsHitTesting(!button.isDisabled)
        }
    }
}

// MARK: - 单个功能按钮视图
struct FunctionButtonView: View {
    let button: FunctionButton
    
    var body: some View {
        VStack(spacing: 2) {
            ZStack {
                Image(systemName: button.icon)
                    .font(.system(size: 22, weight: .medium))
                    .foregroundColor(button.isActive ? .accentColor : (button.isDisabled ? .secondary : .primary))
                
                if button.showProgress {
                    ProgressView()
                        .scaleEffect(0.7)
                        .offset(x: 12, y: 12)
                }
            }
            .frame(height: 24)
            
            Text(button.title)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(button.isActive ? .accentColor : (button.isDisabled ? .secondary : .primary))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 40)
    }
}
