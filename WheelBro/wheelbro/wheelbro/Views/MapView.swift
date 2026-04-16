// MapView.swift
// Tab 5 — Full-screen satellite map with live location tracking.
// Shows the user's current position as the system blue dot, auto-recenters
// as they move, and lets them share their coordinates via Apple Maps or
// plain-text. Close button returns to the TTE tab.

import SwiftUI
import MapKit

struct MapView: View {

    @Binding var selectedTab: Int

    @Environment(LocationManager.self) private var locationManager

    // Camera tracks the user's live position
    @State private var position: MapCameraPosition = .userLocation(
        followsHeading: false,
        fallback: .automatic
    )

    // Satellite by default; user can toggle to standard
    @State private var isSatellite: Bool = true

    // MARK: - Derived State

    private var hasLocation: Bool {
        locationManager.isAuthorized &&
        !(locationManager.latitude == 0.0 && locationManager.longitude == 0.0)
    }

    // Google Maps URL — iMessage on macOS hard-codes maps.apple.com detection
    // and always renders it as a non-interactive card regardless of share type.
    // Google Maps is a standard https URL that Messages treats as a normal
    // clickable link on all platforms. On iOS, tapping it opens Safari which
    // offers to open in Maps.
    private var mapsLinkText: String {
        String(format: "https://www.google.com/maps?q=%.6f,%.6f",
               locationManager.latitude, locationManager.longitude)
    }

    private var coordinateText: String {
        let lat = locationManager.latitude
        let lon = locationManager.longitude
        let latDir = lat >= 0 ? "N" : "S"
        let lonDir = lon >= 0 ? "E" : "W"
        return String(
            format: "%.5f° %@, %.5f° %@",
            abs(lat), latDir, abs(lon), lonDir
        )
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            map
            overlay
        }
        .ignoresSafeArea()
        .toolbar(.hidden, for: .tabBar)
    }

    // MARK: - Map

    private var map: some View {
        Map(position: $position) {
            UserAnnotation()
        }
        .mapStyle(isSatellite ? .imagery(elevation: .flat) : .standard)
    }

    // MARK: - Overlay

    private var overlay: some View {
        VStack {
            // ── Top bar ────────────────────────────────────────────────────
            HStack {
                closeButton
                Spacer()
                styleToggleButton
            }
            .padding(.top, 56)
            .padding(.horizontal, 20)

            Spacer()

            // ── Bottom bar ─────────────────────────────────────────────────
            if hasLocation {
                shareButton
                    .padding(.bottom, 48)
            } else {
                noLocationBanner
                    .padding(.bottom, 48)
            }
        }
    }

    // MARK: - Close Button

    private var closeButton: some View {
        Button {
            selectedTab = Tab.tte
        } label: {
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: CameraConstants.exitButtonSize))
                .symbolRenderingMode(.palette)
                .foregroundStyle(Color.white, Color.black.opacity(0.5))
        }
    }

    // MARK: - Style Toggle Button

    private var styleToggleButton: some View {
        Button {
            isSatellite.toggle()
        } label: {
            Image(systemName: isSatellite ? "map.fill" : "globe.americas.fill")
                .font(.system(size: 28))
                .symbolRenderingMode(.palette)
                .foregroundStyle(Color.white, Color.black.opacity(0.5))
        }
    }

    // MARK: - Share Button

    private var shareButton: some View {
        HStack(spacing: 12) {
            ShareLink(item: mapsLinkText) {
                Label("Share Link", systemImage: "link")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(.black)
                    .padding(.vertical, 14)
                    .padding(.horizontal, 20)
                    .background(Color.wheelBroYellow)
                    .clipShape(Capsule())
            }
            ShareLink(item: coordinateText) {
                Label("Share Geo", systemImage: "location.fill")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(.black)
                    .padding(.vertical, 14)
                    .padding(.horizontal, 20)
                    .background(Color.wheelBroYellow)
                    .clipShape(Capsule())
            }
        }
    }

    // MARK: - No Location Banner

    private var noLocationBanner: some View {
        Label("Location not found", systemImage: "location.slash.fill")
            .font(.subheadline)
            .fontWeight(.semibold)
            .foregroundStyle(.white)
            .padding(.vertical, 14)
            .padding(.horizontal, 28)
            .background(.black.opacity(0.6))
            .clipShape(Capsule())
    }
}

// MARK: - Preview

#Preview {
    MapView(selectedTab: .constant(Tab.map))
        .environment(LocationManager())
}
