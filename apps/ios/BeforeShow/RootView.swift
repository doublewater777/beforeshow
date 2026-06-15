import SwiftUI

struct RootView: View {
    @State private var hasFinishedSplash = false

    var body: some View {
        ZStack {
            CurrentHomePlaceholderView()
                .opacity(hasFinishedSplash ? 1 : 0)

            if !hasFinishedSplash {
                SplashView {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        hasFinishedSplash = true
                    }
                }
            }
        }
        .preferredColorScheme(.dark)
        .statusBarHidden(!hasFinishedSplash)
    }
}

private var brandGradient: LinearGradient {
    LinearGradient(
        colors: [
            Color(red: 0.49, green: 0.81, blue: 1.0),
            Color(red: 0.70, green: 0.53, blue: 1.0),
            Color(red: 1.0, green: 0.70, blue: 0.28)
        ],
        startPoint: .leading,
        endPoint: .trailing
    )
}

// MARK: - Splash

private struct SplashView: View {
    let onFinish: () -> Void

    @State private var backgroundOpacity = 0.0
    @State private var titleOpacity = 0.0
    @State private var englishNameOpacity = 0.0
    @State private var sloganOpacity = 0.0
    @State private var wholeOpacity = 1.0
    @State private var canAccelerate = false
    @State private var didFinish = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            GeometryReader { geometry in
                Image("splash_bg")
                    .resizable()
                    .scaledToFill()
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                    .opacity(backgroundOpacity)
                    .accessibilityHidden(true)
            }
            .ignoresSafeArea()

            VStack(spacing: 16) {
                Spacer()

                Text("开场前")
                    .font(.system(size: 52, weight: .light))
                    .tracking(6)
                    .foregroundStyle(brandGradient)
                    .opacity(titleOpacity)
                    .accessibilityAddTraits(.isHeader)

                Text("BeforeShow")
                    .font(.system(size: 16, weight: .light))
                    .tracking(8)
                    .foregroundStyle(brandGradient.opacity(0.7))
                    .opacity(englishNameOpacity)

                Text("灯亮之前，先进入状态")
                    .font(.system(size: 14, weight: .light))
                    .tracking(3)
                    .foregroundStyle(.white.opacity(0.6))
                    .opacity(sloganOpacity)
                    .padding(.top, 34)

                Spacer()
                    .frame(height: 142)
            }
            .padding(.horizontal, 28)
        }
        .opacity(wholeOpacity)
        .contentShape(Rectangle())
        .onTapGesture {
            guard canAccelerate else { return }
            finish()
        }
        .onAppear(perform: startAnimation)
        .accessibilityElement(children: .combine)
    }

    private func startAnimation() {
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(0.3))
            withAnimation(.easeOut(duration: 0.8)) {
                backgroundOpacity = 1
            }

            try? await Task.sleep(for: .seconds(0.8))
            withAnimation(.easeInOut(duration: 0.4)) {
                titleOpacity = 1
            }

            try? await Task.sleep(for: .seconds(0.3))
            withAnimation(.easeInOut(duration: 0.4)) {
                englishNameOpacity = 1
            }

            try? await Task.sleep(for: .seconds(0.3))
            withAnimation(.easeInOut(duration: 0.4)) {
                sloganOpacity = 1
            }

            try? await Task.sleep(for: .seconds(0.2))
            canAccelerate = true

            try? await Task.sleep(for: .seconds(0.4))
            finish()
        }
    }

    private func finish() {
        guard !didFinish else { return }
        didFinish = true
        withAnimation(.easeInOut(duration: 0.32)) {
            wholeOpacity = 0
        }

        Task { @MainActor in
            try? await Task.sleep(for: .seconds(0.32))
            onFinish()
        }
    }
}

// MARK: - Home Placeholder

private struct CurrentHomePlaceholderView: View {
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
        }
    }
}

#Preview {
    RootView()
}
