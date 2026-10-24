import SwiftUI

/// Estado vacío: qué es esto y qué hacer (acción opcional).
public struct EmptyStateView: View {
    let symbol: String
    let title: String
    let message: String
    let actionTitle: String?
    let action: (() -> Void)?

    public init(symbol: String, title: String, message: String, actionTitle: String? = nil, action: (() -> Void)? = nil) {
        self.symbol = symbol; self.title = title; self.message = message
        self.actionTitle = actionTitle; self.action = action
    }

    public var body: some View {
        VStack(spacing: Space.sm) {
            Image(systemName: symbol).font(.title2).foregroundStyle(AuraColor.secondaryText.color)
                .accessibilityHidden(true)
            Text(title).font(AuraFont.moduleTitle).foregroundStyle(AuraColor.primaryText.color)
            Text(message).font(AuraFont.secondary).foregroundStyle(AuraColor.secondaryText.color)
                .multilineTextAlignment(.center)
            if let actionTitle, let action {
                Button(actionTitle, action: action).buttonStyle(AuraButtonStyle(emphasis: .filled))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .contain)
    }
}

/// UI-18: causa + solución + reintentar (+ abrir ajustes si procede).
public struct ErrorStateView: View {
    let title: String
    let cause: String
    let solution: String
    let onRetry: () -> Void
    let onOpenSettings: (() -> Void)?

    public init(title: String, cause: String, solution: String,
                onRetry: @escaping () -> Void, onOpenSettings: (() -> Void)? = nil) {
        self.title = title; self.cause = cause; self.solution = solution
        self.onRetry = onRetry; self.onOpenSettings = onOpenSettings
    }

    public var body: some View {
        VStack(spacing: Space.sm) {
            Image(systemName: "exclamationmark.triangle").font(.title2)
                .foregroundStyle(AuraColor.warning.color).accessibilityHidden(true)
            Text(title).font(AuraFont.moduleTitle).foregroundStyle(AuraColor.primaryText.color)
                .accessibilityAddTraits(.isHeader)
            VStack(spacing: Space.xs) {
                Text(cause).accessibilityLabel("\(Strings.cause): \(cause)")
                Text(solution).accessibilityLabel("\(Strings.solution): \(solution)")
            }
            .font(AuraFont.secondary).foregroundStyle(AuraColor.secondaryText.color)
            .multilineTextAlignment(.center)
            HStack(spacing: Space.sm) {
                Button(Strings.retry, action: onRetry).buttonStyle(AuraButtonStyle(emphasis: .filled))
                if let onOpenSettings {
                    Button(Strings.openSettings, action: onOpenSettings).buttonStyle(AuraButtonStyle(emphasis: .filled))
                }
            }
            .padding(.top, Space.xs)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .contain)
    }
}
