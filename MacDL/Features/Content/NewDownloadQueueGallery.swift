import SwiftUI
import AppKit

// 多任务队列布局预览画廊（临时视图，选完方案后删除）
struct NewDownloadQueueGallery: View {
    var body: some View {
        ScrollView(.vertical, showsIndicators: true) {
            VStack(alignment: .leading, spacing: 28) {
                Text("New Download — 多任务队列布局")
                    .font(.title2.weight(.semibold))
                Text("共 3 个队列布局变体，选一个后告知方案名。")
                    .font(.callout)
                    .foregroundStyle(.secondary)

                item("方案 Q1 · 列表 + 移除", variant: QueueListRemove())
                item("方案 Q2 · 编号列表", variant: QueueNumbered())
                item("方案 Q3 · 卡片网格", variant: QueueGrid())
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
                .frame(width: 420, height: 560)
                .background(Color(nsColor: .windowBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay {
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(.separator, lineWidth: 1)
                }
        }
    }
}

// MARK: - 样例
private let sampleTasks: [(name: String, resumable: Bool)] = [
    ("ubuntu-24.04.iso", true),
    ("movie.mkv", false),
    ("archive.zip", true),
    ("paper.pdf", true),
]

// 续传徽标
private struct ResumeBadge: View {
    let resumable: Bool
    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: resumable ? "arrow.clockwise" : "exclamationmark.triangle")
                .font(.system(size: 8))
            Text(resumable ? "可续传" : "不可续传")
                .font(.system(size: 9))
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background((resumable ? Color.green : Color.orange).opacity(0.15))
        .clipShape(Capsule())
        .foregroundStyle(resumable ? Color.green : Color.orange)
    }
}

// MARK: - 小组件
private struct QueueCard<C: View>: View {
    @ViewBuilder let content: C
    var body: some View {
        VStack(alignment: .leading, spacing: 8) { content }
            .padding(12)
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay { RoundedRectangle(cornerRadius: 8).stroke(.separator, lineWidth: 1) }
    }
}

private struct QueueLabel: View {
    let icon: String
    let text: String
    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: icon).font(.caption).foregroundStyle(.secondary)
            Text(text).font(.caption).foregroundStyle(.secondary)
        }
    }
}

private struct QueueActions: View {
    var body: some View {
        HStack(spacing: 10) {
            Spacer()
            Text("Cancel")
                .padding(.horizontal, 18).padding(.vertical, 5)
                .background(.quaternary)
                .clipShape(RoundedRectangle(cornerRadius: 6))
            Text("Download").fontWeight(.medium)
                .padding(.horizontal, 18).padding(.vertical, 5)
                .background(Color.accentColor)
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 6))
        }
    }
}

private struct QueueHeader: View {
    var body: some View {
        HStack {
            Text("即将下载").font(.headline)
            Spacer()
            Text("\(sampleTasks.count) 个")
                .font(.caption)
                .padding(.horizontal, 8).padding(.vertical, 2)
                .background(Color.accentColor.opacity(0.15))
                .clipShape(Capsule())
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Q1：列表 + 移除
private struct QueueListRemove: View {
    var body: some View {
        VStack(spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: "square.and.arrow.down").font(.system(size: 22, weight: .medium)).foregroundStyle(.tint)
                Text("New Download").font(.headline)
            }

            QueueCard {
                QueueLabel(icon: "link", text: "Download URLs")
                RoundedRectangle(cornerRadius: 6)
                    .fill(.quaternary.opacity(0.35))
                    .frame(height: 60)
                    .overlay(alignment: .topLeading) {
                        Text("https://example.com/ubuntu-24.04.iso").font(.system(size: 10, design: .monospaced))
                            .padding(6)
                    }
            }

            QueueCard {
                QueueHeader()
                ForEach(0..<sampleTasks.count, id: \.self) { i in
                    HStack(spacing: 6) {
                        Image(systemName: "doc.fill").font(.caption).foregroundStyle(.secondary)
                        Text(sampleTasks[i].name).font(.caption).lineLimit(1)
                        Spacer()
                        ResumeBadge(resumable: sampleTasks[i].resumable)
                        Image(systemName: "xmark.circle.fill").font(.caption).foregroundStyle(.tertiary)
                    }
                    .padding(.vertical, 5)
                    .padding(.horizontal, 6)
                    .background(.quaternary.opacity(0.3))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                }
            }

            QueueCard {
                HStack {
                    QueueLabel(icon: "gauge", text: "Speed Limit")
                    Spacer()
                    Text("Unlimited").font(.caption).foregroundStyle(.secondary)
                }
            }

            QueueActions()
        }
        .padding(18)
    }
}

// MARK: - Q2：编号列表
private struct QueueNumbered: View {
    var body: some View {
        VStack(spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: "list.number").font(.system(size: 22, weight: .medium)).foregroundStyle(.tint)
                Text("New Download").font(.headline)
            }

            QueueCard {
                QueueLabel(icon: "link", text: "Download URLs")
                RoundedRectangle(cornerRadius: 6)
                    .fill(.quaternary.opacity(0.35))
                    .frame(height: 60)
            }

            QueueCard {
                QueueHeader()
                ForEach(0..<sampleTasks.count, id: \.self) { i in
                    HStack(spacing: 8) {
                        Text("\(i + 1)")
                            .font(.caption2.weight(.medium))
                            .frame(width: 18)
                            .foregroundStyle(.secondary)
                        Text(sampleTasks[i].name).font(.caption).lineLimit(1)
                        Spacer()
                        ResumeBadge(resumable: sampleTasks[i].resumable)
                    }
                    .padding(.vertical, 4)
                }
            }

            QueueCard {
                HStack {
                    QueueLabel(icon: "gauge", text: "Speed Limit")
                    Spacer()
                    Text("Unlimited").font(.caption).foregroundStyle(.secondary)
                }
            }

            QueueActions()
        }
        .padding(18)
    }
}

// MARK: - Q3：卡片网格
private struct QueueGrid: View {
    let columns = [GridItem(.adaptive(minimum: 92), spacing: 8)]

    var body: some View {
        VStack(spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: "square.grid.2x2").font(.system(size: 22, weight: .medium)).foregroundStyle(.tint)
                Text("New Download").font(.headline)
            }

            QueueCard {
                QueueLabel(icon: "link", text: "Download URLs")
                RoundedRectangle(cornerRadius: 6)
                    .fill(.quaternary.opacity(0.35))
                    .frame(height: 60)
            }

            QueueCard {
                QueueHeader()
                LazyVGrid(columns: columns, spacing: 8) {
                    ForEach(Array(sampleTasks.enumerated()), id: \.offset) { _, task in
                        VStack(spacing: 4) {
                            Image(systemName: "doc.fill").font(.system(size: 20)).foregroundStyle(.tint)
                            Text(task.name).font(.caption2).lineLimit(2).multilineTextAlignment(.center)
                            ResumeBadge(resumable: task.resumable)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(.quaternary.opacity(0.3))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                }
            }

            QueueCard {
                HStack {
                    QueueLabel(icon: "gauge", text: "Speed Limit")
                    Spacer()
                    Text("Unlimited").font(.caption).foregroundStyle(.secondary)
                }
            }

            QueueActions()
        }
        .padding(18)
    }
}

#Preview {
    NewDownloadQueueGallery()
}
