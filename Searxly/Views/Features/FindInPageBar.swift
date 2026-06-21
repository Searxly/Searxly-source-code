//
//  FindInPageBar.swift
//  Searxly
//
//  Dedicated, reusable Find in Page bar.
//  Extracted for maintainability and to keep MainContentView cleaner.
//

import SwiftUI

struct FindInPageBar: View {
    @Binding var searchTerm: String
    let onFind: (String) -> Void
    let onDismiss: () -> Void

    @FocusState private var isFieldFocused: Bool

    var body: some View {
        HStack(spacing: 8) {
            TextField("Find in page", text: $searchTerm)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 280)
                .focused($isFieldFocused)
                .onSubmit {
                    onFind(searchTerm)
                }
                .onChange(of: searchTerm) { _, newValue in
                    // Incremental find as you type (feels responsive for "search in web page").
                    let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty {
                        onFind(trimmed)
                    }
                }

            Button("Find") {
                onFind(searchTerm)
            }
            .buttonStyle(.bordered)

            Spacer()

            Button("Done", action: onDismiss)
                .keyboardShortcut(.cancelAction)
                .buttonStyle(.bordered)
        }
        .padding(8)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .onAppear {
            isFieldFocused = true
        }
    }
}

#Preview {
    FindInPageBar(
        searchTerm: .constant("example"),
        onFind: { _ in },
        onDismiss: {}
    )
    .padding()
}