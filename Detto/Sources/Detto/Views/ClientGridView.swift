import SwiftUI

struct ClientGridView: View {
    let clients: [ClientInfo]
    let moreClients: [ClientInfo]
    @Binding var selectedClient: ClientInfo?
    let isRecording: Bool

    var body: some View {
        VStack(spacing: 0) {
            Text("CLIENTS")
                .font(.dMono(size: 10, weight: .black))
                .tracking(1)
                .foregroundStyle(Color.dDim)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.top, 12)
                .padding(.bottom, 8)

            ScrollView {
                VStack(spacing: 6) {
                    ForEach(clients + moreClients) { client in
                        clientCard(client)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.bottom, 10)
            }
        }
        .background(Color.dSurface)
        .opacity(isRecording ? 0.5 : 1.0)
        .allowsHitTesting(!isRecording)
    }

    private func clientCard(_ client: ClientInfo) -> some View {
        ClientCardButton(
            client: client,
            isSelected: selectedClient?.id == client.id,
            onSelect: {
                withAnimation(.easeInOut(duration: 0.15)) {
                    selectedClient = selectedClient?.id == client.id ? nil : client
                }
            }
        )
    }
}

private struct ClientCardButton: View {
    let client: ClientInfo
    let isSelected: Bool
    let onSelect: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: onSelect) {
            Text(client.name)
                .font(.dMono(size: 12, weight: .semibold))
                .foregroundStyle(isSelected ? Color.dAmber : Color.dText)
                .lineLimit(1)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    isSelected ? Color.dAmber.opacity(0.08)
                    : isHovered ? Color.dText.opacity(0.04)
                    : Color.dBg
                )
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(
                            isSelected ? Color.dAmber : isHovered ? Color.dSecondary : Color.dRule,
                            lineWidth: isSelected ? 2 : 1.5
                        )
                )
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

// MARK: - Shared Metadata Section

struct MetadataSection: View {
    let header: String
    let items: [String]
    var iconName: String? = nil
    var itemFontSize: CGFloat = 13

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                if let iconName {
                    Image(systemName: iconName)
                        .font(.system(size: 9))
                        .foregroundStyle(Color.dDim)
                }
                Text(header)
                    .font(.dMono(size: 10, weight: .black))
                    .foregroundStyle(Color.dDim)
                    .tracking(1)
            }
            ForEach(items, id: \.self) { item in
                let isSubheading = item.hasPrefix("###")
                let display = isSubheading ? String(item.drop(while: { $0 == "#" || $0 == " " })) : item
                Text(display)
                    .font(.dBody(size: itemFontSize, weight: isSubheading ? .semibold : .light))
                    .foregroundStyle(Color.dText)
                    .lineLimit(4)
                    .padding(.top, isSubheading ? 4 : 0)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Color.dSurface)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.dRule, lineWidth: 1.5))
    }
}
