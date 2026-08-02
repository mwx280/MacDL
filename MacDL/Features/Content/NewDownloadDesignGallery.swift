import SwiftUI
import AppKit

// 新建下载界面的设计方案预览画廊（临时视图，选完方案后删除）
struct NewDownloadDesignGallery: View {
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: 24) {
                galleryCard("方案 A · 卡片式", variant: CardVariant())
                galleryCard("方案 B · 极简单列", variant: MinimalVariant())
                galleryCard("方案 C · 表单+实时预览", variant: SplitVariant())
                galleryCard("方案 D · 设置风格分组", variant: GroupedVariant())
            }
            .padding(28)
        }
        .frame(width: 1180, height: 620)
    }

    private func galleryCard(_ title: String, variant: some View) -> some View {
        VStack(spacing: 10) {
            Text(title)
                .font(.headline)
            variant
                .frame(width: 400, height: 470)
                .scaleEffect(0.88)
                .frame(width: 400, height: 470)
                .background(Color(nsColor: .windowBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay {
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(.separator, lineWidth: 1)
                }
        }
    }
}

// MARK: - 共用样例数据
private let sampleURL = "https://example.com/ubuntu-24.04.iso"
private let samplePath = "/Users/xiaowu/Downloads"
private let sampleName = "ubuntu-24.04.iso"

// MARK: - 方案 A：卡片式（字段分组为圆角卡片）
private struct CardVariant: View {
    var body: some View {
        VStack(spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: "square.and.arrow.down")
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(.tint)
                Text("New Download")
                    .font(.headline)
            }

            fieldCard {
                Label { Text("Download URLs").font(.caption) } icon: { Image(systemName: "link") }
                    .foregroundStyle(.secondary)
                Text(sampleURL)
                    .font(.system(size: 12, design: .monospaced))
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
                    .background(.quaternary.opacity(0.5))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }

            fieldCard {
                Label { Text("Save to").font(.caption) } icon: { Image(systemName: "folder") }
                    .foregroundStyle(.secondary)
                HStack(spacing: 6) {
                    Text(samplePath)
                        .font(.system(size: 11, design: .monospaced))
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .padding(6)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.quaternary.opacity(0.5))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    Image(systemName: "folder")
                        .foregroundStyle(.secondary)
                }
            }

            fieldCard {
                HStack {
                    Label { Text("Speed Limit").font(.caption) } icon: { Image(systemName: "gauge") }
                    Spacer()
                    Text("Unlimited").font(.caption).foregroundStyle(.secondary)
                }
                Divider()
                HStack {
                    Label { Text("Connections").font(.caption) } icon: { Image(systemName: "square.grid.3x2") }
                    Spacer()
                    HStack(spacing: 6) {
                        ForEach([1, 2, 4, 8], id: \.self) { n in
                            Chip(number: n, selected: n == 4)
                        }
                    }
                }
            }

            HStack(spacing: 10) {
                Spacer()
                Text("Cancel").font(.body)
                    .padding(.horizontal, 18).padding(.vertical, 5)
                    .background(.quaternary)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                Text("Download").font(.body.weight(.medium))
                    .padding(.horizontal, 18).padding(.vertical, 5)
                    .background(Color.accentColor)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }
        }
        .padding(18)
    }

    private func fieldCard<C: View>(@ViewBuilder content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            content()
        }
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay { RoundedRectangle(cornerRadius: 8).stroke(.separator, lineWidth: 1) }
    }
}

// MARK: - 方案 B：极简单列（紧凑，无卡片背景）
private struct MinimalVariant: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "arrow.down.to.line")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(.tint)
                Spacer()
            }

            VStack(alignment: .leading, spacing: 5) {
                Text("Download URLs").font(.caption).foregroundStyle(.secondary)
                Text(sampleURL)
                    .font(.system(size: 12, design: .monospaced))
                    .frame(maxWidth: .infinity, minHeight: 60, alignment: .topLeading)
                    .padding(8)
                    .background(.quaternary.opacity(0.35))
                    .clipShape(RoundedRectangle(cornerRadius: 7))
            }

            VStack(alignment: .leading, spacing: 5) {
                Text("Save to").font(.caption).foregroundStyle(.secondary)
                HStack(spacing: 6) {
                    Text(samplePath)
                        .font(.system(size: 11, design: .monospaced))
                        .lineLimit(1).truncationMode(.middle)
                        .padding(6)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.quaternary.opacity(0.35))
                        .clipShape(RoundedRectangle(cornerRadius: 7))
                    Image(systemName: "folder").foregroundStyle(.secondary)
                }
            }

            Divider().padding(.vertical, 4)

            HStack {
                Text("Speed Limit").font(.body)
                Spacer()
                Text("Unlimited").font(.body).foregroundStyle(.secondary)
            }
            HStack {
                Text("Connections").font(.body)
                Spacer()
                Text("4 connections").font(.body).foregroundStyle(.secondary)
            }

            Spacer()

            HStack(spacing: 10) {
                Spacer()
                Text("Cancel")
                    .padding(.horizontal, 20).padding(.vertical, 6)
                    .background(.quaternary.opacity(0.7))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                Text("Download").fontWeight(.medium)
                    .padding(.horizontal, 20).padding(.vertical, 6)
                    .background(Color.accentColor)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }
        }
        .padding(20)
    }
}

// MARK: - 方案 C：表单 + 实时预览（左右分栏）
private struct SplitVariant: View {
    var body: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 6) {
                    Image(systemName: "square.and.arrow.down").foregroundStyle(.tint)
                    Text("New Download").font(.headline)
                }

                VStack(alignment: .leading, spacing: 5) {
                    Text("URL").font(.caption).foregroundStyle(.secondary)
                    Text(sampleURL)
                        .font(.system(size: 11, design: .monospaced))
                        .lineLimit(2)
                        .padding(7)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.quaternary.opacity(0.4))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }

                VStack(alignment: .leading, spacing: 5) {
                    Text("Save to").font(.caption).foregroundStyle(.secondary)
                    Text(samplePath)
                        .font(.system(size: 10, design: .monospaced))
                        .lineLimit(1).truncationMode(.middle)
                        .padding(7)
                        .background(.quaternary.opacity(0.4))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }

                HStack {
                    Text("Limit").font(.caption)
                    Spacer()
                    Text("Unlimited").font(.caption).foregroundStyle(.secondary)
                }
                HStack {
                    Text("Connections").font(.caption)
                    Spacer()
                    Text("4").font(.caption).foregroundStyle(.secondary)
                }

                Spacer()

                HStack(spacing: 8) {
                    Text("Cancel").font(.callout)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 5)
                        .background(.quaternary)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    Text("Download").font(.callout.weight(.medium))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 5)
                        .background(Color.accentColor)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // 实时预览卡片
            VStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 8)
                    .fill(.quaternary.opacity(0.5))
                    .frame(height: 90)
                    .overlay {
                        VStack(spacing: 4) {
                            Image(systemName: "doc.fill").font(.system(size: 26)).foregroundStyle(.secondary)
                            Text(sampleName).font(.caption).lineLimit(1)
                        }
                    }

                row("Name", sampleName)
                row("Size", "4.1 GB")
                row("Resume", "Supported")
                row("Save to", "Downloads")

                Spacer()
            }
            .padding(10)
            .frame(width: 150)
            .background(Color.accentColor.opacity(0.07))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay { RoundedRectangle(cornerRadius: 8).stroke(Color.accentColor.opacity(0.3), lineWidth: 1) }
        }
        .padding(16)
    }

    private func row(_ k: String, _ v: String) -> some View {
        HStack {
            Text(k).font(.caption2).foregroundStyle(.secondary)
            Spacer()
            Text(v).font(.caption2).lineLimit(1)
        }
    }
}

// MARK: - 方案 D：设置风格分组（bordered group + 行分隔）
private struct GroupedVariant: View {
    var body: some View {
        VStack(spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: "arrow.down.circle.fill")
                    .font(.system(size: 24))
                    .foregroundStyle(.tint)
                Text("New Download").font(.headline)
            }

            VStack(spacing: 0) {
                groupRow("Download URLs") {
                    Text(sampleURL)
                        .font(.system(size: 11, design: .monospaced))
                        .lineLimit(1).truncationMode(.middle)
                        .foregroundStyle(.secondary)
                }
                Divider().padding(.leading, 16)
                groupRow("Save to") {
                    Text(samplePath)
                        .font(.system(size: 10, design: .monospaced))
                        .lineLimit(1).truncationMode(.middle)
                        .foregroundStyle(.secondary)
                }
                Divider().padding(.leading, 16)
                groupRow("Speed Limit") {
                    Text("Unlimited").foregroundStyle(.secondary)
                }
                Divider().padding(.leading, 16)
                groupRow("Connections") {
                    Text("4").foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 4)
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay { RoundedRectangle(cornerRadius: 8).stroke(.separator, lineWidth: 1) }

            Spacer()

            HStack(spacing: 10) {
                Spacer()
                Text("Cancel")
                    .padding(.horizontal, 20).padding(.vertical, 6)
                    .background(.quaternary)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                Text("Download").fontWeight(.medium)
                    .padding(.horizontal, 20).padding(.vertical, 6)
                    .background(Color.accentColor)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }
        }
        .padding(20)
    }

    private func groupRow<C: View>(_ label: String, @ViewBuilder trailing: () -> C) -> some View {
        HStack {
            Text(label).font(.body)
            Spacer()
            trailing()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }
}


// 方案 A 的连接数 chip
private struct Chip: View {
    let number: Int
    let selected: Bool
    var body: some View {
        Text("\(number)")
            .font(.caption)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(selected ? Color.accentColor.opacity(0.18) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 5))
            .overlay {
                RoundedRectangle(cornerRadius: 5)
                    .stroke(selected ? Color.accentColor : Color.gray.opacity(0.4), lineWidth: 1)
            }
    }
}

#Preview {
    NewDownloadDesignGallery()
}
