// ZoomablePhotoView.swift
// Full-screen zoomable photo viewer.
// Pinch to zoom, double-tap to toggle zoom, drag to pan, swipe down to dismiss.
// Reusable across the entire app.

import SwiftUI

struct ZoomablePhotoView: View {
    let image: UIImage?
    let imageURL: URL?
    @Environment(\.dismiss) private var dismiss
    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero

    init(image: UIImage) {
        self.image = image
        self.imageURL = nil
    }

    init(url: URL) {
        self.image = nil
        self.imageURL = url
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            Group {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                } else if let url = imageURL {
                    AsyncImage(url: url) { phase in
                        if let img = phase.image {
                            img.resizable().scaledToFit()
                        } else {
                            ProgressView().tint(.white)
                        }
                    }
                }
            }
            .scaleEffect(scale)
            .offset(offset)
            .gesture(
                MagnificationGesture()
                    .onChanged { value in
                        scale = lastScale * value
                    }
                    .onEnded { _ in
                        lastScale = scale
                        if scale < 1.0 {
                            withAnimation(.spring()) { scale = 1.0; lastScale = 1.0; offset = .zero; lastOffset = .zero }
                        }
                    }
            )
            .simultaneousGesture(
                DragGesture()
                    .onChanged { value in
                        if scale > 1.0 {
                            offset = CGSize(
                                width: lastOffset.width + value.translation.width,
                                height: lastOffset.height + value.translation.height
                            )
                        } else {
                            // When not zoomed, allow vertical drag to dismiss
                            offset = CGSize(width: 0, height: value.translation.height)
                        }
                    }
                    .onEnded { value in
                        if scale <= 1.0 && abs(value.translation.height) > 100 {
                            dismiss()
                        } else {
                            lastOffset = offset
                            if scale <= 1.0 {
                                withAnimation(.spring()) { offset = .zero; lastOffset = .zero }
                            }
                        }
                    }
            )
            .onTapGesture(count: 2) {
                withAnimation(.spring()) {
                    if scale > 1.0 {
                        scale = 1.0; lastScale = 1.0; offset = .zero; lastOffset = .zero
                    } else {
                        scale = 3.0; lastScale = 3.0
                    }
                }
            }

            // Close button
            VStack {
                HStack {
                    Spacer()
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(10)
                            .background(.ultraThinMaterial.opacity(0.6))
                            .clipShape(Circle())
                    }
                    .padding(.trailing, 16)
                    .padding(.top, 8)
                }
                Spacer()
            }
        }
    }
}

// MARK: - Inline Zoomable Photo (for use inside TabView/ScrollView)

struct ZoomablePhotoContent: View {
    let url: URL?
    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero

    var body: some View {
        GeometryReader { geo in
            Group {
                if let url {
                    AsyncImage(url: url) { phase in
                        if let img = phase.image {
                            img.resizable().scaledToFit()
                        } else {
                            ProgressView().tint(.white)
                        }
                    }
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .scaleEffect(scale)
            .offset(offset)
            .gesture(
                MagnificationGesture()
                    .onChanged { value in scale = lastScale * value }
                    .onEnded { _ in
                        lastScale = scale
                        if scale < 1.0 {
                            withAnimation(.spring()) { scale = 1.0; lastScale = 1.0; offset = .zero; lastOffset = .zero }
                        }
                    }
            )
            .simultaneousGesture(
                scale > 1.0 ?
                DragGesture()
                    .onChanged { value in
                        offset = CGSize(
                            width: lastOffset.width + value.translation.width,
                            height: lastOffset.height + value.translation.height
                        )
                    }
                    .onEnded { _ in lastOffset = offset }
                : nil
            )
            .onTapGesture(count: 2) {
                withAnimation(.spring()) {
                    if scale > 1.0 {
                        scale = 1.0; lastScale = 1.0; offset = .zero; lastOffset = .zero
                    } else {
                        scale = 3.0; lastScale = 3.0
                    }
                }
            }
        }
    }
}

// MARK: - View Modifier for easy use

struct PhotoZoomModifier: ViewModifier {
    let url: URL?
    let image: UIImage?
    @State private var showZoom = false

    func body(content: Content) -> some View {
        content
            .onTapGesture { showZoom = true }
            .fullScreenCover(isPresented: $showZoom) {
                if let image {
                    ZoomablePhotoView(image: image)
                } else if let url {
                    ZoomablePhotoView(url: url)
                }
            }
    }
}

extension View {
    func zoomablePhoto(url: URL?) -> some View {
        modifier(PhotoZoomModifier(url: url, image: nil))
    }

    func zoomablePhoto(image: UIImage?) -> some View {
        modifier(PhotoZoomModifier(url: nil, image: image))
    }
}
