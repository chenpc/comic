import SwiftUI
import AppKit

struct ReaderView: View {
    @ObservedObject var vm: ReaderViewModel
    var isFullscreen: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                Color.black.ignoresSafeArea()

                // 圖片顯示（自動 fit 螢幕，支援 animated WebP / GIF）
                if let image = vm.currentImage {
                    AnimatingImageView(image: image)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .transition(.opacity)
                        .animation(.easeInOut(duration: 0.15), value: vm.currentIndex)
                }

                // 讀取中指示器
                if vm.isLoading {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .scaleEffect(1.5)
                        .tint(.white)
                }

                // 錯誤訊息
                if let error = vm.error {
                    VStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 40))
                            .foregroundColor(.yellow)
                        Text(error)
                            .foregroundColor(.white)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }
                }

                // 鍵盤事件處理（隱形覆蓋層）
                KeyboardHandler(
                    onLeft: { vm.prevPage() },
                    onRight: { vm.nextPage() },
                    onToggleFullscreen: {
                        NSApp.keyWindow?.toggleFullScreen(nil)
                    }
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .allowsHitTesting(false)
            }

            // 頁碼顯示（全螢幕時隱藏）
            if vm.totalPages > 0 && !isFullscreen {
                HStack {
                        // 上一集按鈕
                        if vm.hasPrevChapter {
                            Button {
                                vm.goToPrevChapter()
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: "chevron.left.2")
                                        .font(.system(size: 12))
                                    Text("上一集")
                                        .font(.system(size: 13, weight: .medium))
                                }
                                .foregroundColor(.white)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 10)
                                .background(.ultraThinMaterial)
                                .clipShape(Capsule())
                            }
                            .buttonStyle(.plain)
                        }

                        // 上一頁按鈕
                        Button {
                            vm.prevPage()
                        } label: {
                            Image(systemName: "chevron.left")
                                .font(.title2)
                                .foregroundColor(.white)
                                .frame(width: 44, height: 44)
                                .background(.ultraThinMaterial)
                                .clipShape(Circle())
                        }
                        .buttonStyle(.plain)
                        .disabled(vm.currentIndex == 0 && !vm.hasPrevChapter)

                        Spacer()

                        // 頁碼
                        Text("\(vm.currentIndex + 1) / \(vm.totalPages)")
                            .foregroundColor(.white)
                            .font(.system(size: 14, weight: .medium))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(.ultraThinMaterial)
                            .cornerRadius(8)

                        Spacer()

                        // 下一頁按鈕
                        Button {
                            vm.nextPage()
                        } label: {
                            Image(systemName: "chevron.right")
                                .font(.title2)
                                .foregroundColor(.white)
                                .frame(width: 44, height: 44)
                                .background(.ultraThinMaterial)
                                .clipShape(Circle())
                        }
                        .buttonStyle(.plain)
                        .disabled(vm.currentIndex + 1 >= vm.totalPages)

                        // 下一集按鈕（有下一集時才顯示）
                        if vm.hasNextChapter {
                            Button {
                                vm.goToNextChapter()
                            } label: {
                                HStack(spacing: 4) {
                                    Text("下一集")
                                        .font(.system(size: 13, weight: .medium))
                                    Image(systemName: "chevron.right.2")
                                        .font(.system(size: 12))
                                }
                                .foregroundColor(.white)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 10)
                                .background(.ultraThinMaterial)
                                .clipShape(Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
                .background(Color.black)
            }
        }
    }
}

// MARK: - 動圖顯示（支援 animated WebP / GIF）

struct AnimatingImageView: NSViewRepresentable {
    let image: NSImage

    func makeNSView(context: Context) -> NSImageView {
        let view = NSImageView()
        view.imageScaling = .scaleProportionallyUpOrDown
        view.animates = true
        view.image = image
        // 確保 NSImageView 不會超出容器
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        view.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        return view
    }

    func updateNSView(_ nsView: NSImageView, context: Context) {
        if nsView.image !== image {
            nsView.image = image
        }
    }
}

// MARK: - 鍵盤處理（NSViewRepresentable）

struct KeyboardHandler: NSViewRepresentable {
    let onLeft: () -> Void
    let onRight: () -> Void
    let onToggleFullscreen: () -> Void

    func makeNSView(context: Context) -> KeyboardHandlerNSView {
        let view = KeyboardHandlerNSView()
        view.onLeft = onLeft
        view.onRight = onRight
        view.onToggleFullscreen = onToggleFullscreen
        return view
    }

    func updateNSView(_ nsView: KeyboardHandlerNSView, context: Context) {
        nsView.onLeft = onLeft
        nsView.onRight = onRight
        nsView.onToggleFullscreen = onToggleFullscreen
    }
}

final class KeyboardHandlerNSView: NSView {
    var onLeft: (() -> Void)?
    var onRight: (() -> Void)?
    var onToggleFullscreen: (() -> Void)?

    override var acceptsFirstResponder: Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.makeFirstResponder(self)
    }

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 123: onLeft?()      // 左箭頭
        case 124: onRight?()     // 右箭頭
        case 126: onLeft?()      // 上箭頭
        case 125: onRight?()     // 下箭頭
        case 3:   onToggleFullscreen?()  // f 鍵
        default: super.keyDown(with: event)
        }
    }
}
