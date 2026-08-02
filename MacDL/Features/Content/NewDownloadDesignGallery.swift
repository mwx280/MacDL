import SwiftUI
import AppKit

// 新建下载界面设计方案画廊 v2：长页面纵向滚动，方案 A 及其衍生（临时视图）
struct NewDownloadDesignGallery: View {
    var body: some View {
        ScrollView(.vertical, showsIndicators: true) {
            VStack(alignment: .leading, spacing: 28) {
                Text("New Download — Design Gallery (方案 A 系列)")
                    .font(.title2.weight(.semibold))
                Text("共 5 个变体，纵向浏览，选中一个后告知方案名。")
                    .font(.callout)
                    .foregroundStyle(.secondary)

                item("方案 A · 基础卡片", variant: CardA())
                item("方案 A1 · 渐变头部", variant: CardA1())
                item("方案 A2 · 分段控制", variant: CardA2())
                item("方案 A3 · 嵌入摘要", variant: CardA3())
                item("方案 A4 · 大圆角玻璃感", variant: CardA4())
            }
            .padding(32)
        }
        .frame(width: 520, height: 860)
    }

    private func item(_ title: String, variant: some View) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
            variant
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

// MARK: - 共用样例
private let sampleURL = "https://example.com/ubuntu-24.04.iso"
private let samplePath = "/Users/xiaowu/Downloads"

// MARK: - 小组件

// 卡片容器
private struct CardBox<C: View>: View {
    let radius: CGFloat
    @ViewBuilder let content: C
    var body: some View {
        VStack(alignment: .leading, spacing: 8) { content }
            .padding(12)
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: radius))
            .overlay { RoundedRectangle(cornerRadius: radius).stroke(.separator, lineWidth: 1) }
    }
}

// 带图标的卡片标题
private struct CardLabel: View {
    let icon: String
    let text: String
    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(text).font(.caption).foregroundStyle(.secondary)
        }
    }
}

// 连接数 chip（A / A1 / A4 用）
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

// 连接数分段控制（A2 用）
private struct Segmented: View {
    var body: some View {
        HStack(spacing: 2) {
            ForEach([1, 2, 4, 8], id: \.self) { n in
                Text("\(n)")
                    .font(.caption)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
                    .background(n == 4 ? Color.accentColor.opacity(0.15) : .clear)
                    .clipShape(RoundedRectangle(cornerRadius: 5))
            }
        }
        .padding(2)
        .background(.quaternary.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 7))
    }
}

// 底部按钮
private struct ActionButtons: View {
    var body: some View {
        HStack(spacing: 10) {
            Spacer()
            Text("Cancel")
                .padding(.horizontal, 18)
                .padding(.vertical, 5)
                .background(.quaternary)
                .clipShape(RoundedRectangle(cornerRadius: 6))
            Text("Download").fontWeight(.medium)
                .padding(.horizontal, 18)
                .padding(.vertical, 5)
                .background(Color.accentColor)
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 6))
        }
    }
}

// MARK: - 方案 A：基础卡片
private struct CardA: View {
    var body: some View {
        VStack(spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: "square.and.arrow.down")
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(.tint)
                Text("New Download").font(.headline)
            }

            CardBox(radius: 8) {
                CardLabel(icon: "link", text: "Download URLs")
                Text(sampleURL)
                    .font(.system(size: 12, design: .monospaced))
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
                    .background(.quaternary.opacity(0.5))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }

            CardBox(radius: 8) {
                CardLabel(icon: "folder", text: "Save to")
                HStack(spacing: 6) {
                    Text(samplePath)
                        .font(.system(size: 11, design: .monospaced))
                        .lineLimit(1).truncationMode(.middle)
                        .padding(6)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.quaternary.opacity(0.5))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    Image(systemName: "folder").foregroundStyle(.secondary)
                }
            }

            CardBox(radius: 8) {
                HStack {
                    CardLabel(icon: "gauge", text: "Speed Limit")
                    Spacer()
                    Text("Unlimited").font(.caption).foregroundStyle(.secondary)
                }
                Divider()
                HStack {
                    CardLabel(icon: "square.grid.3x2", text: "Connections")
                    Spacer()
                    HStack(spacing: 6) {
                        ForEach([1, 2, 4, 8], id: \.self) { n in
                            Chip(number: n, selected: n == 4)
                        }
                    }
                }
            }

            ActionButtons()
        }
        .padding(18)
    }
}

// MARK: - 方案 A1：渐变头部
private struct CardA1: View {
    var body: some View {
        VStack(spacing: 14) {
            HStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 10)
                    .fill(LinearGradient(colors: [.indigo, .blue], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 44, height: 44)
                    .overlay {
                        Image(systemName: "square.and.arrow.down")
                            .font(.system(size: 20, weight: .medium))
                            .foregroundStyle(.white)
                    }
                VStack(alignment: .leading, spacing: 2) {
                    Text("New Download").font(.headline)
                    Text("Paste one or more links").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(12)
            .background(Color.accentColor.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 10))

            CardBox(radius: 8) {
                CardLabel(icon: "link", text: "Download URLs")
                Text(sampleURL)
                    .font(.system(size: 12, design: .monospaced))
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
                    .background(.quaternary.opacity(0.5))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }

            CardBox(radius: 8) {
                CardLabel(icon: "folder", text: "Save to")
                HStack(spacing: 6) {
                    Text(samplePath)
                        .font(.system(size: 11, design: .monospaced))
                        .lineLimit(1).truncationMode(.middle)
                        .padding(6)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.quaternary.opacity(0.5))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    Image(systemName: "folder").foregroundStyle(.secondary)
                }
            }

            CardBox(radius: 8) {
                HStack {
                    CardLabel(icon: "gauge", text: "Speed Limit")
                    Spacer()
                    Text("Unlimited").font(.caption).foregroundStyle(.secondary)
                }
                Divider()
                HStack {
                    CardLabel(icon: "square.grid.3x2", text: "Connections")
                    Spacer()
                    HStack(spacing: 6) {
                        ForEach([1, 2, 4, 8], id: \.self) { n in
                            Chip(number: n, selected: n == 4)
                        }
                    }
                }
            }

            ActionButtons()
        }
        .padding(18)
    }
}

// MARK: - 方案 A2：分段控制
private struct CardA2: View {
    var body: some View {
        VStack(spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(.tint)
                Text("New Download").font(.headline)
            }

            CardBox(radius: 8) {
                CardLabel(icon: "link", text: "Download URLs")
                Text(sampleURL)
                    .font(.system(size: 12, design: .monospaced))
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
                    .background(.quaternary.opacity(0.5))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }

            CardBox(radius: 8) {
                CardLabel(icon: "folder", text: "Save to")
                HStack(spacing: 6) {
                    Text(samplePath)
                        .font(.system(size: 11, design: .monospaced))
                        .lineLimit(1).truncationMode(.middle)
                        .padding(6)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.quaternary.opacity(0.5))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    Image(systemName: "folder").foregroundStyle(.secondary)
                }
            }

            CardBox(radius: 8) {
                VStack(spacing: 10) {
                    HStack {
                        CardLabel(icon: "gauge", text: "Speed Limit")
                        Spacer()
                        Text("Unlimited").font(.caption).foregroundStyle(.secondary)
                    }
                    Divider()
                    HStack {
                        CardLabel(icon: "square.grid.3x2", text: "Connections")
                        Spacer()
                        Segmented()
                            .frame(width: 130)
                    }
                }
            }

            ActionButtons()
        }
        .padding(18)
    }
}

// MARK: - 方案 A3：嵌入摘要条
private struct CardA3: View {
    var body: some View {
        VStack(spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: "square.and.arrow.down")
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(.tint)
                Text("New Download").font(.headline)
            }

            CardBox(radius: 8) {
                CardLabel(icon: "link", text: "Download URLs")
                Text(sampleURL)
                    .font(.system(size: 12, design: .monospaced))
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
                    .background(.quaternary.opacity(0.5))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                // 嵌入摘要
                HStack(spacing: 8) {
                    Image(systemName: "doc.fill").foregroundStyle(.secondary)
                    Text("ubuntu-24.04.iso").font(.caption).lineLimit(1)
                    Spacer()
                    Text("4.1 GB").font(.caption).foregroundStyle(.secondary)
                    Image(systemName: "arrow.clockwise").font(.caption2).foregroundStyle(.green)
                    Text("Resumable").font(.caption2).foregroundStyle(.secondary)
                }
                .padding(8)
                .background(.quaternary.opacity(0.35))
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }

            CardBox(radius: 8) {
                CardLabel(icon: "folder", text: "Save to")
                HStack(spacing: 6) {
                    Text(samplePath)
                        .font(.system(size: 11, design: .monospaced))
                        .lineLimit(1).truncationMode(.middle)
                        .padding(6)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.quaternary.opacity(0.5))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    Image(systemName: "folder").foregroundStyle(.secondary)
                }
            }

            CardBox(radius: 8) {
                HStack {
                    CardLabel(icon: "gauge", text: "Speed Limit")
                    Spacer()
                    Text("Unlimited").font(.caption).foregroundStyle(.secondary)
                }
                Divider()
                HStack {
                    CardLabel(icon: "square.grid.3x2", text: "Connections")
                    Spacer()
                    HStack(spacing: 6) {
                        ForEach([1, 2, 4, 8], id: \.self) { n in
                            Chip(number: n, selected: n == 4)
                        }
                    }
                }
            }

            ActionButtons()
        }
        .padding(18)
    }
}

// MARK: - 方案 A4：大圆角玻璃感
private struct CardA4: View {
    var body: some View {
        VStack(spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: "arrow.down.to.line")
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(.tint)
                Text("New Download").font(.headline)
            }

            CardBox(radius: 14) {
                CardLabel(icon: "link", text: "Download URLs")
                Text(sampleURL)
                    .font(.system(size: 12, design: .monospaced))
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
                    .background(.ultraThinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            }

            CardBox(radius: 14) {
                CardLabel(icon: "folder", text: "Save to")
                HStack(spacing: 6) {
                    Text(samplePath)
                        .font(.system(size: 11, design: .monospaced))
                        .lineLimit(1).truncationMode(.middle)
                        .padding(6)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.ultraThinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    Image(systemName: "folder").foregroundStyle(.secondary)
                }
            }

            CardBox(radius: 14) {
                HStack {
                    CardLabel(icon: "gauge", text: "Speed Limit")
                    Spacer()
                    Text("Unlimited").font(.caption).foregroundStyle(.secondary)
                }
                Divider()
                HStack {
                    CardLabel(icon: "square.grid.3x2", text: "Connections")
                    Spacer()
                    HStack(spacing: 6) {
                        ForEach([1, 2, 4, 8], id: \.self) { n in
                            Chip(number: n, selected: n == 4)
                        }
                    }
                }
            }

            ActionButtons()
        }
        .padding(18)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

#Preview {
    NewDownloadDesignGallery()
}
