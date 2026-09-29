import SwiftUI

struct OnboardingInvitedFeatureVisual: View {
    let snapshot: CompanionInviteSnapshot

    var body: some View {
        VStack(spacing: BSSpacing.compact) {
            ZStack {
                if let coverURL = snapshot.coverImageURL {
                    ShowCoverImageView(
                        urlString: coverURL.absoluteString,
                        aspectRatio: 1,
                        contentMode: .fill,
                        cornerRadius: 0
                    )
                    .frame(width: 260, height: 260)
                    .blur(radius: 55)
                    .opacity(0.35)
                    .accessibilityHidden(true)
                } else {
                    Circle()
                        .fill(BSColor.Stage.accent.opacity(0.18))
                        .frame(width: 260, height: 260)
                        .blur(radius: 50)
                }

                VStack(spacing: 12) {
                    HStack(spacing: 6) {
                        Image(systemName: "person.2.fill")
                            .font(.system(size: 11, weight: .bold))
                        Text(BSLocalization.format("%@ 邀请你同行", snapshot.ownerName))
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .foregroundStyle(BSColor.Stage.accent)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .background(BSColor.Stage.accent.opacity(0.14), in: Capsule())

                    VStack(alignment: .leading, spacing: 14) {
                        if let coverURL = snapshot.coverImageURL {
                            HStack {
                                Spacer(minLength: 0)
                                ShowCoverImageView(
                                    urlString: coverURL.absoluteString,
                                    aspectRatio: 3.0 / 4.0,
                                    contentMode: .fit,
                                    cornerRadius: 14
                                )
                                .frame(width: 150, height: 200)
                                .shadow(color: .black.opacity(0.45), radius: 14, y: 7)
                                Spacer(minLength: 0)
                            }
                        }

                        VStack(alignment: .leading, spacing: 6) {
                            Text(snapshot.showName)
                                .font(.system(size: 17, weight: .bold))
                                .foregroundStyle(BSColor.Stage.foreground)
                                .lineLimit(2)
                                .fixedSize(horizontal: false, vertical: true)

                            HStack(spacing: 12) {
                                Label(
                                    showDateText,
                                    systemImage: "calendar"
                                )
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(BSColor.Stage.muted)

                                if let location = snapshot.location, !location.isEmpty {
                                    Label(
                                        location,
                                        systemImage: "mappin.and.ellipse"
                                    )
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundStyle(BSColor.Stage.muted)
                                    .lineLimit(1)
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(14)
                    .background {
                        ZStack {
                            if let coverURL = snapshot.coverImageURL {
                                ShowCoverImageView(
                                    urlString: coverURL.absoluteString,
                                    aspectRatio: 16.0 / 9.0,
                                    contentMode: .fill,
                                    cornerRadius: 0
                                )
                                .blur(radius: 40)
                                .opacity(0.22)
                                .clipped()
                            }
                            BSColor.Stage.surfaceRaised.opacity(0.88)
                            Rectangle()
                                .fill(.ultraThinMaterial)
                                .opacity(0.5)
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(BSColor.Stage.border))
                    .shadow(color: .black.opacity(0.35), radius: 24, y: 12)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            BSLocalization.format("%@ 邀请你一起去 %@", snapshot.ownerName, snapshot.showName)
        )
    }

    private var showDateText: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        if let tzID = snapshot.timeZoneIdentifier, let tz = TimeZone(identifier: tzID) {
            formatter.timeZone = tz
        } else if let seconds = snapshot.timeZoneSecondsFromGMT, let tz = TimeZone(secondsFromGMT: seconds) {
            formatter.timeZone = tz
        } else {
            formatter.timeZone = .current
        }
        return formatter.string(from: snapshot.showStartTime)
    }
}
