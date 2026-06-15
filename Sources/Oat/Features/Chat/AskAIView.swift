import SwiftUI

struct AskAIView: View {
    @StateObject var viewModel: ChatViewModel
    @State private var input = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(scopeTitle).font(.headline)
                Spacer()
                Button("Clear") { viewModel.clear() }
                    .disabled(viewModel.messages.isEmpty && !viewModel.isStreaming)
            }
            .padding()

            Divider()

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        ForEach(viewModel.messages) { msg in
                            ChatBubble(role: msg.role, content: msg.content).id(msg.id)
                        }
                        if viewModel.isStreaming, !viewModel.streamingContent.isEmpty {
                            ChatBubble(role: "assistant", content: viewModel.streamingContent).id("streaming")
                        }
                    }
                    .padding()
                }
                .onChange(of: viewModel.messages.count) { _, _ in
                    if let last = viewModel.messages.last?.id {
                        withAnimation { proxy.scrollTo(last, anchor: .bottom) }
                    }
                }
                .onChange(of: viewModel.streamingContent) { _, _ in
                    proxy.scrollTo("streaming", anchor: .bottom)
                }
            }

            if let err = viewModel.error {
                Text(err).font(.caption).foregroundStyle(.red).padding(.horizontal)
            }

            Divider()

            HStack(alignment: .bottom, spacing: 8) {
                TextField("Ask about these meetings…", text: $input, axis: .vertical)
                    .lineLimit(1...5)
                    .textFieldStyle(.plain)
                    .focused($focused)
                    .onSubmit { submit() }

                Button(action: submit) {
                    Image(systemName: viewModel.isStreaming ? "stop.circle.fill" : "arrow.up.circle.fill")
                        .font(.title2)
                        .foregroundStyle(input.isEmpty && !viewModel.isStreaming ? .secondary : .accentColor)
                }
                .buttonStyle(.plain)
                .disabled(input.isEmpty && !viewModel.isStreaming)
            }
            .padding()
        }
        .frame(width: 480, height: 600)
        .onAppear { focused = true }
    }

    private var scopeTitle: String {
        switch viewModel.scope {
        case .meeting(let m): return "Ask about: \(m.title)"
        case .folder(let f):  return "Ask: \(f.name)"
        case .global:         return "Ask across all meetings"
        }
    }

    private func submit() {
        if viewModel.isStreaming {
            viewModel.stopStream()
        } else {
            let text = input
            input = ""
            viewModel.send(text)
        }
    }
}

private struct ChatBubble: View {
    let role: String
    let content: String

    var body: some View {
        let isUser = role == ChatMessage.Role.user.rawValue
        HStack(alignment: .top) {
            if isUser { Spacer(minLength: 40) }
            VStack(alignment: isUser ? .trailing : .leading, spacing: 2) {
                Text(isUser ? "You" : "Oat")
                    .font(.caption.bold()).foregroundStyle(.secondary)
                Text(content)
                    .padding(10)
                    .background(isUser ? Color.accentColor : Color.secondary.opacity(0.12))
                    .foregroundStyle(isUser ? .white : .primary)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .textSelection(.enabled)
            }
            if !isUser { Spacer(minLength: 40) }
        }
    }
}
