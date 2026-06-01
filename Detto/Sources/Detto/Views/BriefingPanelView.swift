import SwiftUI

struct BriefingPanelView: View {
    let selectedClient: ClientInfo?
    let isRecording: Bool
    let silenceSeconds: Int
    @Binding var editableContext: String
    @Binding var genericAttendees: String
    let onStartCallCapture: () -> Void
    let onStartVoiceMemo: () -> Void
    let onStop: () -> Void
    let onContextChanged: (String) -> Void

    var body: some View {
        VStack(spacing: 0) {
            if let client = selectedClient {
                briefingContent(client: client)
            } else if isRecording {
                genericRecordingContent
            } else {
                genericCallForm
            }

            if !isRecording {
                actionButtons
            }
        }
    }

    // MARK: - Generic call form (no client selected)

    private var genericCallForm: some View {
        VStack(spacing: 0) {
            Text("NEW CALL")
                .font(.dMono(size: 10, weight: .black))
                .tracking(1)
                .foregroundStyle(Color.dDim)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 10)

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    fieldSection(header: "ON THIS CALL", placeholder: "e.g. John Smith, Jane Doe", text: $genericAttendees)
                    notesSection
                }
                .padding(.horizontal, 16)
            }

            Spacer(minLength: 0)
        }
    }

    // MARK: - Generic recording (no client)

    private var genericRecordingContent: some View {
        VStack(spacing: 0) {
            Text("CALL CAPTURE")
                .font(.dMono(size: 10, weight: .black))
                .tracking(1)
                .foregroundStyle(Color.dDim)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 10)

            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    fieldSection(header: "ON THIS CALL", placeholder: "e.g. John Smith, Jane Doe", text: $genericAttendees)
                    notesSection
                }
                .padding(.horizontal, 16)
            }

            Spacer(minLength: 0)
        }
    }

    // MARK: - Client briefing

    private func briefingContent(client: ClientInfo) -> some View {
        VStack(spacing: 0) {
            Text(client.name)
                .font(.dMono(size: 16, weight: .bold))
                .foregroundStyle(Color.dText)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 10)

            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    fieldSection(header: "ON THIS CALL", placeholder: "e.g. John Smith, Jane Doe", text: $genericAttendees)
                    notesSection

                    if !isRecording {
                        Rectangle()
                            .fill(Color.dRule)
                            .frame(height: 1)
                            .padding(.vertical, 4)

                        if !client.keyContacts.isEmpty {
                            MetadataSection(
                                header: "KEY CONTACTS",
                                items: client.keyContacts.map { ClientInfo.cleanMarkdown($0) },
                                iconName: "person.2",
                                itemFontSize: 14
                            )
                        }

                        if let urgent = client.urgentItem {
                            MetadataSection(
                                header: "PRIORITY",
                                items: [ClientInfo.cleanMarkdown(urgent)],
                                iconName: "exclamationmark.triangle",
                                itemFontSize: 14
                            )
                        }

                        if !client.upcomingDates.isEmpty {
                            MetadataSection(
                                header: "UPCOMING",
                                items: client.upcomingDates.map { ClientInfo.cleanMarkdown($0) },
                                iconName: "calendar",
                                itemFontSize: 14
                            )
                        }
                    }
                }
                .padding(.horizontal, 16)
            }

            Spacer(minLength: 0)
        }
    }

    // MARK: - Shared components

    private func fieldSection(header: String, placeholder: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(header)
                .font(.dMono(size: 10, weight: .black))
                .foregroundStyle(Color.dDim)
                .tracking(1)

            TextField(placeholder, text: text)
                .font(.dBody(size: 12, weight: .medium))
                .foregroundStyle(Color.dText)
                .textFieldStyle(.plain)
                .padding(8)
                .background(Color.dSurface)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.dRule, lineWidth: 1.5)
                )
        }
    }

    private var notesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("NOTES")
                .font(.dMono(size: 10, weight: .black))
                .foregroundStyle(Color.dDim)
                .tracking(1)

            TextEditor(text: $editableContext)
                .font(.dBody(size: 12, weight: .medium))
                .foregroundStyle(Color.dText)
                .scrollContentBackground(.hidden)
                .frame(minHeight: 80)
                .padding(8)
                .background(Color.dSurface)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.dRule, lineWidth: 1.5)
                )
                .onChange(of: editableContext) {
                    onContextChanged(editableContext)
                }
        }
    }

    // MARK: - Action buttons

    private var actionButtons: some View {
        VStack(spacing: 8) {
            Button(action: onStartCallCapture) {
                HStack(spacing: 8) {
                    Text("START CALL CAPTURE")
                        .font(.dMono(size: 12, weight: .bold))
                    Spacer()
                    Text("\u{2318}R")
                        .font(.dMono(size: 10, weight: .medium))
                        .foregroundStyle(Color.dDim)
                }
                .foregroundStyle(Color.dText)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity)
                .background(Color.dAmber)
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            .buttonStyle(.plain)

            Button(action: onStartVoiceMemo) {
                HStack(spacing: 8) {
                    Text("VOICE MEMO")
                        .font(.dMono(size: 12, weight: .bold))
                    Spacer()
                    Text("\u{2318}\u{21E7}R")
                        .font(.dMono(size: 10, weight: .medium))
                        .foregroundStyle(Color.dAmber.opacity(0.5))
                }
                .foregroundStyle(Color.dAmber)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.dAmber, lineWidth: 2.5))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 10)
    }
}
