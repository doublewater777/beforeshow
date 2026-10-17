import SwiftUI

struct BSGlassEffectContainer<Content: View>: View {
    let spacing: CGFloat
    @ViewBuilder let content: () -> Content

    var body: some View {
        if #available(iOS 26, *) {
            GlassEffectContainer(spacing: spacing, content: content)
        } else {
            content()
        }
    }
}

extension View {
    @ViewBuilder
    func bsGlass<S: Shape>(clear: Bool = false, in shape: S) -> some View {
        if #available(iOS 26, *) {
            glassEffect(clear ? .clear : .regular.interactive(), in: shape)
        } else {
            background(.regularMaterial, in: shape)
        }
    }

    @ViewBuilder
    func bsGlassID<ID: Hashable & Sendable>(_ id: ID, in namespace: Namespace.ID) -> some View {
        if #available(iOS 26, *) {
            glassEffectID(id, in: namespace)
        } else {
            self
        }
    }

    @ViewBuilder
    func bsNavigationZoom<ID: Hashable & Sendable>(sourceID: ID, in namespace: Namespace.ID) -> some View {
        if #available(iOS 18, *) {
            navigationTransition(.zoom(sourceID: sourceID, in: namespace))
        } else {
            self
        }
    }

    @ViewBuilder
    func bsTransitionSource<ID: Hashable & Sendable>(id: ID, in namespace: Namespace.ID) -> some View {
        if #available(iOS 18, *) {
            matchedTransitionSource(id: id, in: namespace)
        } else {
            self
        }
    }

    @ViewBuilder
    func bsBottomBar<Bar: View>(@ViewBuilder content: () -> Bar) -> some View {
        if #available(iOS 26, *) {
            safeAreaBar(edge: .bottom, spacing: 0, content: content)
                .scrollEdgeEffectStyle(.soft, for: .bottom)
        } else {
            safeAreaInset(edge: .bottom, spacing: 0, content: content)
        }
    }
}
