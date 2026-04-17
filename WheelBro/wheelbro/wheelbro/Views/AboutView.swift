// AboutView.swift
// Tab 3 — app version, build number, and copyright information.

import SwiftUI

struct AboutView: View {

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
    }
    private var buildNumber: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—"
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                VStack(spacing: 0) {

                    // ── Logo ─────────────────────────────────────────────────
                    Image("wheelbro_logo")
                        .resizable()
                        .scaledToFit()
                        .frame(height: 96)
                        .padding(.top, 48)
                        .padding(.bottom, 12)

                    Text(AppInfo.appDisplayName)
                        .font(.title)
                        .fontWeight(.bold)
                        .foregroundStyle(.white)

                    Text(AppInfo.appDisplayDesc)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding(.top, 4)

                    // ── Version card ─────────────────────────────────────────
                    VStack(spacing: 0) {
                        infoRow(label: "Version",  value: appVersion)
                        Divider().background(Color.white.opacity(0.08))
                        infoRow(label: "Build",    value: buildNumber)
                        Divider().background(Color.white.opacity(0.08))
                        Link(destination: URL(string: "https://wheelbro.app/")!) {
                            infoRow(label: "Website", value: "wheelbro.app")
                        }
                        //Divider().background(Color.white.opacity(0.08))
                        //infoRow(label: "Vehicle",  value: AppInfo.vehicleName)
                    }
                    .background(Color.cardBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(Color.wheelBroYellow.opacity(0.18), lineWidth: 1)
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 36)

                    Spacer()

                    // ── Copyright ─────────────────────────────────────────────
                    VStack(spacing: 4) {
                        Text(AppInfo.copyrightHolder)
                            .font(.footnote)
                            .fontWeight(.medium)
                            .foregroundStyle(.secondary)
                        Text(AppInfo.copyrightRights)
                            .font(.caption2)
                            .foregroundStyle(Color.secondary.opacity(0.7))
                    }
                    .padding(.bottom, 32)
                }
            }
            .navigationTitle("About")
            .navigationBarTitleDisplayMode(.large)
            .toolbarBackground(Color.black, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
    }

    private func infoRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundStyle(.white)
                .multilineTextAlignment(.trailing)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

// MARK: - Preview
#Preview {
    AboutView()
}
