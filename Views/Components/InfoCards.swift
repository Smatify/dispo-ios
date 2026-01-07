import SwiftUI

struct QuickLinkCard: View {
    let link: QuickLink
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: link.systemImage)
                .font(.system(size: 22, weight: .semibold))
                .foregroundColor(link.color)
                .padding(10)
                .background(link.color.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            
            VStack(alignment: .leading, spacing: 4) {
                Text(link.title)
                    .font(.headline)
                Text(link.subtitle)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, minHeight: 140, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.secondarySystemBackground))
        )
    }
}

struct ShiftStatusCard: View {
    let title: String
    let detail: String
    let accentColor: Color
    let icon: String
    let location: String?
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle()
                    .fill(accentColor.opacity(0.15))
                    .frame(width: 42, height: 42)
                Image(systemName: icon)
                    .foregroundColor(accentColor)
                    .font(.system(size: 18, weight: .semibold))
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                Text(detail)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                if let location = location {
                    HStack(spacing: 6) {
                        Image(systemName: "mappin.and.ellipse")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(location)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }
            }
            Spacer()
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color(.secondarySystemBackground))
        )
    }
}

struct TripCard: View {
    let title: String
    let pickup: String
    let dropoff: String
    let timeRange: String
    let accentColor: Color
    let icon: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(accentColor.opacity(0.14))
                        .frame(width: 32, height: 32)
                    Image(systemName: icon)
                        .foregroundColor(accentColor)
                        .font(.system(size: 14, weight: .semibold))
                }
                Text(timeRange)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        Capsule()
                            .fill(Color.primary.opacity(0.06))
                    )
                Spacer()
            }
            
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "mappin.circle.fill")
                        .foregroundColor(.red)
                        .font(.headline)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Pickup")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(pickup)
                            .font(.headline)
                            .fontWeight(.semibold)
                            .lineLimit(2)
                    }
                }
                
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "flag.checkered")
                        .foregroundColor(.blue)
                        .font(.headline)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Dropoff")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(dropoff)
                            .font(.headline)
                            .fontWeight(.semibold)
                            .lineLimit(2)
                    }
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.secondarySystemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.black.opacity(0.04), lineWidth: 1)
        )
    }
}

