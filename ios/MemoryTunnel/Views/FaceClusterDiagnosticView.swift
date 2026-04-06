// FaceClusterDiagnosticView.swift
// Diagnostic for testing face clustering quality on a real photo library.
// Tests two approaches: landmark geometry (current) vs. feature print on cropped faces.
// Remove before App Store submission.

import SwiftUI
import Photos
import Vision

// MARK: - Models

struct FaceClusterResult: Identifiable {
    let id: UUID
    let crop: UIImage
    let photoCount: Int
    let oldestDate: Date?
    let newestDate: Date?
    let daysSinceLastPhoto: Int
    let decayScore: Double
    var name: String
    let assets: [PHAsset]

    var dateRange: String {
        let fmt = DateFormatter()
        fmt.dateFormat = "MMM yyyy"
        let oldest = oldestDate.map { fmt.string(from: $0) } ?? "?"
        let newest = newestDate.map { fmt.string(from: $0) } ?? "?"
        return "\(oldest) — \(newest)"
    }

    var decayLabel: String {
        if decayScore > 15 { return "Lost touch" }
        if decayScore > 8  { return "Going cold" }
        if decayScore > 3  { return "Cooling" }
        return "Active"
    }

    var decayColor: Color {
        if decayScore > 15 { return .red }
        if decayScore > 8  { return .orange }
        if decayScore > 3  { return Color(red: 0.8, green: 0.6, blue: 0.2) }
        return .green
    }
}

enum EmbeddingMode: String, CaseIterable {
    case landmarks = "Landmarks (current)"
    case featurePrint = "Feature Print (cropped face)"
    case mobileFaceNet = "MobileFaceNet (CoreML)"
}

// MARK: - Diagnostic View

struct FaceClusterDiagnosticView: View {
    @State private var results: [FaceClusterResult] = []
    @State private var isScanning = false
    @State private var photosProcessed = 0
    @State private var photosWithFaces = 0
    @State private var facesDetected = 0
    @State private var facesSkipped = 0
    @State private var facesAligned = 0
    @State private var facesUnaligned = 0
    @State private var scanDuration: TimeInterval = 0
    @State private var scanLimit = 500
    @State private var threshold: Float = 0.45
    @State private var embeddingMode: EmbeddingMode = .mobileFaceNet
    @State private var statusMessage = "Ready to scan"
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            List {
                configSection
                if photosProcessed > 0 { statsSection }
                if !results.isEmpty {
                    reconnectionSection
                    allClustersSection
                }
            }
            .navigationTitle("Face Cluster Test")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if isScanning {
                        ProgressView()
                    } else {
                        Button("Scan") { startScan() }
                            .fontWeight(.semibold)
                    }
                }
            }
        }
    }

    // MARK: - Config

    private var configSection: some View {
        Section("Configuration") {
            Stepper("Photos: \(scanLimit)", value: $scanLimit, in: 100...5000, step: 100)
                .disabled(isScanning)

            Picker("Embedding", selection: $embeddingMode) {
                ForEach(EmbeddingMode.allCases, id: \.self) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .disabled(isScanning)

            VStack(alignment: .leading, spacing: 4) {
                Text("Cluster threshold: \(String(format: "%.2f", threshold))")
                    .font(.subheadline)
                Slider(value: $threshold, in: 0.08...0.50, step: 0.02)
                    .disabled(isScanning)
                HStack {
                    Text("Tight").font(.caption2).foregroundStyle(.secondary)
                    Spacer()
                    Text("Loose").font(.caption2).foregroundStyle(.secondary)
                }
            }

            switch embeddingMode {
            case .mobileFaceNet:
                Text("MobileFaceNet: try threshold 0.40–0.55. Cosine similarity on 512-dim neural face embeddings. This is the real deal.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            case .featurePrint:
                Text("Feature Print: try threshold 0.30–0.42. Apple's neural image embedding on cropped faces.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            case .landmarks:
                Text("Landmarks: try threshold 0.18–0.22. 76-point facial geometry vectors (known broken).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack {
                Text("Status")
                Spacer()
                Text(statusMessage)
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }
        }
    }

    // MARK: - Stats

    private var statsSection: some View {
        Section("Pipeline Stats") {
            LabeledContent("Photos processed", value: "\(photosProcessed)")
            LabeledContent("Photos with faces", value: "\(photosWithFaces) (\(pct(photosWithFaces, photosProcessed)))")
            LabeledContent("Total faces detected", value: "\(facesDetected)")
            LabeledContent("Aligned (good)", value: "\(facesAligned)")
                .foregroundStyle(.green)
            LabeledContent("Unaligned (fallback)", value: "\(facesUnaligned)")
            LabeledContent("Skipped (both failed)", value: "\(facesSkipped)")
                .foregroundStyle(facesSkipped > facesAligned ? .red : .primary)
            LabeledContent("Clusters (2+ photos)", value: "\(results.count)")
            LabeledContent("Scan time", value: String(format: "%.1fs", scanDuration))

            if results.count >= 3 {
                HStack {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                    Text("Pipeline viable — \(results.count) people found")
                        .font(.footnote).foregroundStyle(.green)
                }
            } else if !isScanning && photosProcessed > 0 {
                HStack {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.red)
                    Text("Not enough people. Try different threshold or mode.")
                        .font(.footnote).foregroundStyle(.red)
                }
            }
        }
    }

    // MARK: - Reconnection / All Clusters

    private var reconnectionSection: some View {
        let candidates = results.filter { $0.decayScore > 5.0 }.sorted { $0.decayScore > $1.decayScore }
        return Group {
            if !candidates.isEmpty {
                Section("Reconnection Candidates (decay > 5.0)") {
                    ForEach(candidates) { clusterRow($0) }
                }
            }
        }
    }

    private var allClustersSection: some View {
        Section("All Clusters (by photo count)") {
            ForEach(results) { clusterRow($0) }
        }
    }

    private func clusterRow(_ result: FaceClusterResult) -> some View {
        HStack(spacing: 12) {
            Image(uiImage: result.crop)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 56, height: 56)
                .clipShape(Circle())
            VStack(alignment: .leading, spacing: 4) {
                Text("\(result.photoCount) photos")
                    .font(.subheadline.weight(.semibold))
                Text(result.dateRange)
                    .font(.caption).foregroundStyle(.secondary)
                HStack(spacing: 4) {
                    Circle().fill(result.decayColor).frame(width: 8, height: 8)
                    Text("\(result.decayLabel) — \(String(format: "%.1f", result.decayScore))")
                        .font(.caption2).foregroundStyle(result.decayColor)
                    Text("(\(result.daysSinceLastPhoto)d ago)")
                        .font(.caption2).foregroundStyle(.tertiary)
                }
            }
            Spacer()
        }
        .padding(.vertical, 4)
    }

    // MARK: - Scan

    private func startScan() {
        isScanning = true
        results = []
        photosProcessed = 0
        photosWithFaces = 0
        facesDetected = 0
        facesSkipped = 0
        facesAligned = 0
        facesUnaligned = 0
        statusMessage = "Requesting photo access..."

        let mode = embeddingMode
        let limit = scanLimit
        let thresh = threshold

        Task.detached(priority: .userInitiated) {
            let startTime = Date()

            let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
            guard status == .authorized || status == .limited else {
                await MainActor.run { statusMessage = "Photo access denied"; isScanning = false }
                return
            }

            await MainActor.run { statusMessage = "Fetching photos..." }

            let fetchOptions = PHFetchOptions()
            fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
            fetchOptions.fetchLimit = limit
            let assets = PHAsset.fetchAssets(with: .image, options: fetchOptions)
            var assetList: [PHAsset] = []
            assets.enumerateObjects { asset, _, _ in assetList.append(asset) }

            guard !assetList.isEmpty else {
                await MainActor.run { statusMessage = "No photos found"; isScanning = false }
                return
            }

            struct Cluster {
                let id: UUID
                var landmarkDesc: [Float]?
                var featurePrint: VNFeaturePrintObservation?
                var mlEmbedding: [Float]?       // centroid (average of all embeddings)
                var embeddingSum: [Float]?       // running sum for centroid calculation
                var count: Int
                var bestCrop: UIImage?
                var assets: [PHAsset]

                /// Update centroid after adding a new embedding
                mutating func addEmbedding(_ emb: [Float]) {
                    if var sum = embeddingSum {
                        for i in 0 ..< sum.count { sum[i] += emb[i] }
                        embeddingSum = sum
                        // Recompute centroid: average then L2-normalize
                        var avg = sum.map { $0 / Float(count) }
                        var norm: Float = 0
                        for x in avg { norm += x * x }
                        norm = norm.squareRoot()
                        if norm > 0 { avg = avg.map { $0 / norm } }
                        mlEmbedding = avg
                    }
                }
            }

            var clusters: [Cluster] = []
            var processed = 0, withFaces = 0, detected = 0, skipped = 0
            var aligned = 0, unaligned = 0

            // Load model directly (avoid actor isolation issues)
            let mlModel: MLModel?
            do {
                let cfg = MLModelConfiguration()
                cfg.computeUnits = .cpuAndNeuralEngine
                mlModel = try MobileFaceNet(configuration: cfg).model
            } catch {
                print("[Diagnostic] Model load failed: \(error)")
                mlModel = nil
            }

            for (index, asset) in assetList.enumerated() {
                if index % 10 == 0 {
                    await Task.yield()
                    if Task.isCancelled { break }
                    let p = processed, f = withFaces
                    let c = clusters.filter { $0.count >= 2 }.count
                    await MainActor.run {
                        photosProcessed = p; photosWithFaces = f
                        statusMessage = "Processing \(p)/\(assetList.count)... (\(c) clusters)"
                    }
                }

                guard let image = await loadImage(for: asset, targetSize: 1024) else {
                    processed += 1; continue
                }
                guard let cgImage = image.cgImage else { processed += 1; continue }

                // Step 1: Detect face bounding boxes + landmarks
                let observations = await detectFaces(in: cgImage)
                processed += 1
                if observations.isEmpty { continue }
                withFaces += 1

                for obs in observations {
                    // Filter: minimum face size (40px)
                    let faceW = obs.boundingBox.width * CGFloat(cgImage.width)
                    let faceH = obs.boundingBox.height * CGFloat(cgImage.height)
                    if faceW < 40 || faceH < 40 {
                        skipped += 1; continue
                    }

                    // Crop the face (used for display and non-MobileFaceNet modes)
                    guard let faceCrop = cropFace(from: cgImage, boundingBox: obs.boundingBox) else {
                        skipped += 1; continue
                    }

                    detected += 1

                    switch mode {
                    case .mobileFaceNet:
                        guard let mlModel else { skipped += 1; continue }

                        var finalEmb: [Float]?
                        var displayCrop: UIImage = faceCrop
                        var isAligned = false

                        // Try aligned path via FaceEmbeddingService
                        if let result = await FaceEmbeddingService.shared.embedding(
                            for: obs, in: cgImage
                        ) {
                            finalEmb = result.embedding
                            displayCrop = result.crop
                            isAligned = result.method == .aligned
                        }

                        // Fallback: inline unaligned inference
                        if finalEmb == nil {
                            let box = obs.boundingBox
                            let imgW = CGFloat(cgImage.width), imgH = CGFloat(cgImage.height)
                            let rect = CGRect(
                                x: box.origin.x * imgW,
                                y: (1 - box.origin.y - box.height) * imgH,
                                width: box.width * imgW,
                                height: box.height * imgH
                            ).insetBy(dx: -box.width * imgW * 0.15, dy: -box.height * imgH * 0.15)
                                .intersection(CGRect(x: 0, y: 0, width: imgW, height: imgH))

                            guard rect.width > 10, rect.height > 10 else {
                                print("[FALLBACK] rect too small: \(rect)")
                                skipped += 1; continue
                            }
                            guard let cropped = cgImage.cropping(to: rect) else {
                                print("[FALLBACK] cgImage.cropping failed")
                                skipped += 1; continue
                            }

                            var pb: CVPixelBuffer?
                            let pbStatus = CVPixelBufferCreate(kCFAllocatorDefault, 112, 112,
                                                kCVPixelFormatType_32BGRA,
                                                [kCVPixelBufferCGImageCompatibilityKey: true] as CFDictionary,
                                                &pb)
                            guard let pb else {
                                print("[FALLBACK] CVPixelBufferCreate failed: \(pbStatus)")
                                skipped += 1; continue
                            }

                            CVPixelBufferLockBaseAddress(pb, [])
                            let ctx = CGContext(
                                data: CVPixelBufferGetBaseAddress(pb),
                                width: 112, height: 112, bitsPerComponent: 8,
                                bytesPerRow: CVPixelBufferGetBytesPerRow(pb),
                                space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
                            )
                            guard let ctx else {
                                print("[FALLBACK] CGContext creation failed")
                                CVPixelBufferUnlockBaseAddress(pb, [])
                                skipped += 1; continue
                            }
                            ctx.draw(cropped, in: CGRect(x: 0, y: 0, width: 112, height: 112))
                            CVPixelBufferUnlockBaseAddress(pb, [])

                            do {
                                let input = try MLDictionaryFeatureProvider(
                                    dictionary: ["faceImage": MLFeatureValue(pixelBuffer: pb)]
                                )
                                let out = try await mlModel.prediction(from: input)
                                guard let arr = out.featureValue(for: "embedding")?.multiArrayValue else {
                                    print("[FALLBACK] no embedding in output")
                                    skipped += 1; continue
                                }
                                var v = [Float](repeating: 0, count: arr.count)
                                for i in 0 ..< arr.count { v[i] = arr[i].floatValue }
                                var s: Float = 0
                                for x in v { s += x * x }
                                let n = s.squareRoot()
                                if n > 0 { v = v.map { $0 / n } }
                                finalEmb = v
                                isAligned = false
                            } catch {
                                print("[FALLBACK] model prediction failed: \(error)")
                            }
                        }

                        guard let finalEmb else { skipped += 1; continue }
                        if isAligned { aligned += 1 } else { unaligned += 1 }

                        var bestIdx: Int?
                        var bestSim: Float = -1
                        for (i, cluster) in clusters.enumerated() {
                            guard let ce = cluster.mlEmbedding else { continue }
                            let sim = FaceEmbeddingService.shared.cosineSimilarity(finalEmb, ce)
                            if sim > bestSim { bestSim = sim; bestIdx = i }
                        }

                        if let idx = bestIdx, bestSim >= thresh {
                            // Match — add to cluster
                            clusters[idx].count += 1
                            clusters[idx].assets.append(asset)
                            if isAligned { clusters[idx].addEmbedding(finalEmb) }
                            if clusters[idx].bestCrop == nil { clusters[idx].bestCrop = displayCrop }
                        } else {
                            // No match — create new cluster (aligned or unaligned)
                            clusters.append(Cluster(
                                id: UUID(), landmarkDesc: nil, featurePrint: nil,
                                mlEmbedding: finalEmb, embeddingSum: finalEmb,
                                count: 1, bestCrop: displayCrop, assets: [asset]
                            ))
                        }

                    case .featurePrint:
                        guard let cropCG = faceCrop.cgImage,
                              let fp = await generateFeaturePrint(for: cropCG) else { continue }

                        var bestIdx: Int?
                        var bestDist: Float = .infinity
                        for (i, cluster) in clusters.enumerated() {
                            guard let clusterFP = cluster.featurePrint else { continue }
                            var dist: Float = 0
                            try? fp.computeDistance(&dist, to: clusterFP)
                            if dist < bestDist { bestDist = dist; bestIdx = i }
                        }

                        if let idx = bestIdx, bestDist <= thresh {
                            clusters[idx].count += 1
                            clusters[idx].assets.append(asset)
                            if clusters[idx].bestCrop == nil { clusters[idx].bestCrop = faceCrop }
                        } else {
                            clusters.append(Cluster(
                                id: UUID(), landmarkDesc: nil, featurePrint: fp, mlEmbedding: nil,
                                embeddingSum: nil, count: 1, bestCrop: faceCrop, assets: [asset]
                            ))
                        }

                    case .landmarks:
                        guard let desc = extractLandmarkDescriptor(from: obs) else {
                            skipped += 1; continue
                        }

                        var bestIdx: Int?
                        var bestDist: Float = .infinity
                        for (i, cluster) in clusters.enumerated() {
                            guard let cd = cluster.landmarkDesc else { continue }
                            let dist = l2Distance(desc, cd)
                            if dist < bestDist { bestDist = dist; bestIdx = i }
                        }

                        if let idx = bestIdx, bestDist <= thresh {
                            clusters[idx].count += 1
                            clusters[idx].assets.append(asset)
                            if clusters[idx].bestCrop == nil { clusters[idx].bestCrop = faceCrop }
                        } else {
                            clusters.append(Cluster(
                                id: UUID(), landmarkDesc: desc, featurePrint: nil, mlEmbedding: nil, embeddingSum: nil,
                                count: 1, bestCrop: faceCrop, assets: [asset]
                            ))
                        }
                    }
                }
            }

            let elapsed = Date().timeIntervalSince(startTime)
            let now = Date()

            // Post-clustering merge: merge clusters whose centroids are similar
            if mode == .mobileFaceNet {
                var merged = true
                while merged {
                    merged = false
                    for i in 0 ..< clusters.count {
                        guard clusters[i].mlEmbedding != nil else { continue }
                        for j in (i + 1) ..< clusters.count {
                            guard let ei = clusters[i].mlEmbedding,
                                  let ej = clusters[j].mlEmbedding else { continue }
                            let sim = FaceEmbeddingService.shared.cosineSimilarity(ei, ej)
                            // Merge threshold slightly below clustering threshold
                            if sim >= (thresh - 0.05) {
                                // Merge j into i
                                clusters[i].count += clusters[j].count
                                clusters[i].assets.append(contentsOf: clusters[j].assets)
                                // Recompute centroid
                                if var sumI = clusters[i].embeddingSum, let sumJ = clusters[j].embeddingSum {
                                    for k in 0 ..< sumI.count { sumI[k] += sumJ[k] }
                                    clusters[i].embeddingSum = sumI
                                    var avg = sumI.map { $0 / Float(clusters[i].count) }
                                    var norm: Float = 0
                                    for x in avg { norm += x * x }
                                    norm = norm.squareRoot()
                                    if norm > 0 { avg = avg.map { $0 / norm } }
                                    clusters[i].mlEmbedding = avg
                                }
                                clusters.remove(at: j)
                                merged = true
                                break
                            }
                        }
                        if merged { break }
                    }
                }
            }

            let scored: [FaceClusterResult] = clusters
                .filter { $0.count >= 2 && $0.bestCrop != nil }
                .map { cluster in
                    let dates = cluster.assets.compactMap(\.creationDate)
                    let oldest = dates.min()
                    let newest = dates.max()
                    let daysSince = newest.map {
                        Calendar.current.dateComponents([.day], from: $0, to: now).day ?? 0
                    } ?? 9999
                    let decay = (Double(daysSince) / 365.0) * log2(Double(cluster.count) + 1)
                    return FaceClusterResult(
                        id: cluster.id, crop: cluster.bestCrop!, photoCount: cluster.count,
                        oldestDate: oldest, newestDate: newest, daysSinceLastPhoto: daysSince,
                        decayScore: decay, name: "", assets: cluster.assets
                    )
                }
                .sorted { $0.photoCount > $1.photoCount }

            await MainActor.run {
                results = scored
                photosProcessed = processed
                photosWithFaces = withFaces
                facesDetected = detected
                facesSkipped = skipped
                facesAligned = aligned
                facesUnaligned = unaligned
                scanDuration = elapsed
                isScanning = false
                let candidates = scored.filter { $0.decayScore > 5.0 }
                statusMessage = "Done — \(scored.count) people, \(candidates.count) reconnection candidates"
            }
        }
    }

    // MARK: - Vision Helpers

    private func detectFaces(in cgImage: CGImage) async -> [VNFaceObservation] {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let request = VNDetectFaceLandmarksRequest { req, _ in
                    continuation.resume(returning: (req.results as? [VNFaceObservation]) ?? [])
                }
                try? VNImageRequestHandler(cgImage: cgImage, options: [:]).perform([request])
            }
        }
    }

    private func generateFeaturePrint(for cgImage: CGImage) async -> VNFeaturePrintObservation? {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let request = VNGenerateImageFeaturePrintRequest { req, _ in
                    let result = req.results?.first as? VNFeaturePrintObservation
                    continuation.resume(returning: result)
                }
                try? VNImageRequestHandler(cgImage: cgImage, options: [:]).perform([request])
                // If perform threw, we need to resume
            }
        }
    }

    private func extractLandmarkDescriptor(from obs: VNFaceObservation) -> [Float]? {
        guard let allPoints = obs.landmarks?.allPoints else { return nil }
        let points = allPoints.normalizedPoints
        guard points.count >= 76 else { return nil }
        let box = obs.boundingBox
        let cx = box.midX, cy = box.midY
        let scale = max(box.width, box.height)
        guard scale > 0 else { return nil }
        var desc = [Float]()
        desc.reserveCapacity(152)
        for point in points.prefix(76) {
            desc.append(Float((point.x - cx) / scale))
            desc.append(Float((point.y - cy) / scale))
        }
        return desc
    }

    private func cropFace(from image: CGImage, boundingBox box: CGRect) -> UIImage? {
        let w = CGFloat(image.width), h = CGFloat(image.height)
        let rect = CGRect(x: box.origin.x * w,
                          y: (1 - box.origin.y - box.height) * h,
                          width: box.width * w, height: box.height * h)
        let padded = rect.insetBy(dx: -rect.width * 0.2, dy: -rect.height * 0.2)
            .intersection(CGRect(x: 0, y: 0, width: w, height: h))
        return image.cropping(to: padded).map(UIImage.init)
    }

    private func loadImage(for asset: PHAsset, targetSize: CGFloat) async -> UIImage? {
        await withCheckedContinuation { continuation in
            let size = CGSize(width: targetSize, height: targetSize)
            let options = PHImageRequestOptions()
            options.deliveryMode = .highQualityFormat  // Force full quality, not thumbnails
            options.resizeMode = .exact
            options.isSynchronous = false
            options.isNetworkAccessAllowed = false
            var resumed = false
            PHImageManager.default().requestImage(
                for: asset, targetSize: size, contentMode: .aspectFit, options: options
            ) { image, info in
                guard !resumed else { return }
                let isInCloud = (info?[PHImageResultIsInCloudKey] as? Bool) ?? false
                if isInCloud { resumed = true; continuation.resume(returning: nil); return }
                if image != nil { resumed = true; continuation.resume(returning: image) }
            }
        }
    }

    private func l2Distance(_ a: [Float], _ b: [Float]) -> Float {
        var sumSq: Float = 0
        for i in 0 ..< min(a.count, b.count) { sumSq += (a[i] - b[i]) * (a[i] - b[i]) }
        return sumSq.squareRoot()
    }

    private func pct(_ a: Int, _ b: Int) -> String {
        b > 0 ? "\(a * 100 / b)%" : "—"
    }
}

#Preview {
    FaceClusterDiagnosticView()
}
