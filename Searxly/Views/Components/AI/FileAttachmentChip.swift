//
//  FileAttachmentChip.swift
//  Searxly
//
//  NEW FILE (chatbot v2 + file attachments support).
//  Small, reusable pill/chip shown for each user-attached local file inside the Local AI Chat.
//  - Shows SF Symbol icon based on rough file type
//  - Filename (truncated if long)
//  - Size
//  - Prominent remove (X) button
//  - Tap the chip body can show a quick preview (future: excerpt sheet or popover)
//  Follows glass / liquid style of other AI components and toolbar controls.
//  Nothing here touches the network or persists content.
//

import SwiftUI

struct FileAttachmentChip: View {
    let attachment: ChatAttachment
    let onRemove: () -> Void
    var onTap: (() -> Void)? = nil   // for future preview of excerpt

    private var systemImage: String {
        let ext = (attachment.filename as NSString).pathExtension.lowercased()
        switch ext {
        case "pdf": return "doc.richtext"
        case "md", "markdown": return "text.badge.star"
        case "txt", "log": return "doc.text"
        case "csv", "json": return "tablecells"
        default: return "doc"
        }
    }

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
                .font(.caption)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 1) {
                Text(attachment.filename)
                    .font(.caption.weight(.medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(attachment.sizeDescription)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            Spacer(minLength: 4)

            Button {
                onRemove()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Remove attachment (stays private on your Mac)")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            Capsule()
                .fill(.thinMaterial)
                .overlay(Capsule().fill(Color.white.opacity(0.025)))
        )
        .overlay(
            Capsule()
                .strokeBorder(Color.white.opacity(0.09), lineWidth: 0.6)
        )
        .onTapGesture {
            onTap?()
        }
        .contextMenu {
            Button("Remove", role: .destructive, action: onRemove)
        }
    }
}