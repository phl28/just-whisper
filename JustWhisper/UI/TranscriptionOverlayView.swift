import SwiftUI

struct TranscriptionOverlayView: View {
    @Bindable var appState: AppState

    var body: some View {
        HStack(spacing: 12) {
            recordingIndicator

            VStack(alignment: .leading, spacing: 2) {
                if !appState.finalizedText.isEmpty || !appState.volatileText.isEmpty {
                    textContent
                } else if appState.isTranscribing {
                    Text("Listening...")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button {
                appState.stopTranscription()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: 400, minHeight: 50)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder
    private var recordingIndicator: some View {
        Circle()
            .fill(appState.isTranscribing ? Color.red : Color.gray)
            .frame(width: 10, height: 10)
            .opacity(appState.isTranscribing ? 1 : 0.5)
            .animation(
                appState.isTranscribing
                    ? .easeInOut(duration: 0.8).repeatForever(autoreverses: true)
                    : .default,
                value: appState.isTranscribing
            )
    }

    @ViewBuilder
    private var textContent: some View {
        Group {
            if !appState.finalizedText.isEmpty && !appState.volatileText.isEmpty {
                Text("\(appState.finalizedText)\(Text(appState.volatileText).foregroundColor(.secondary))")
            } else if !appState.finalizedText.isEmpty {
                Text(appState.finalizedText)
            } else {
                Text(appState.volatileText)
                    .foregroundStyle(.secondary)
            }
        }
        .font(.system(size: 13))
        .lineLimit(3)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
