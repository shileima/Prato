import Foundation
@preconcurrency import Combine

/// Used by replace-clip callbacks so only the
/// first successful asset of an N-image generation swaps the clip
@MainActor
final class FirstOnlyFlag {
    private var fired = false
    func fire() -> Bool {
        guard !fired else { return false }
        fired = true
        return true
    }
}

@MainActor
final class GenerationService {

    private static let uploadCacheTTL: TimeInterval = 6 * 24 * 60 * 60

    @discardableResult
    func generate(
        genInput: GenerationInput,
        assetType: ClipType,
        placeholderDuration: Double,
        references: [MediaAsset] = [],
        trimmedSourceOverride: TrimmedSource? = nil,
        preUploadedURLs: [String]? = nil,
        name: String? = nil,
        numImages: Int = 1,
        folderId: String? = nil,
        buildParams: @escaping ([String]) -> BackendGenerationParams,
        snapshotRefs: (@Sendable (inout GenerationInput, [String]) -> Void)? = nil,
        preprocessRef: (@Sendable (Int, MediaAsset) async throws -> URL?)? = nil,
        fileExtension: String,
        projectURL: URL?,
        editor: EditorViewModel,
        onComplete: (@MainActor (MediaAsset) -> Void)? = nil,
        onFailure: (@MainActor () -> Void)? = nil
    ) -> String {
        let count = max(1, min(4, numImages))
        let baseName = name ?? String(genInput.prompt.prefix(30))

        let resolvedFolderId = folderId.flatMap { id in
            editor.folder(id: id) != nil ? id : nil
        }
        var placeholders: [MediaAsset] = []
        let destDir = Self.destinationDirectory(for: projectURL)

        for _ in 0..<count {
            let placeholder = createPlaceholder(
                type: assetType,
                name: baseName,
                duration: placeholderDuration,
                genInput: genInput,
                folderId: resolvedFolderId,
                destDir: destDir,
                fileExtension: fileExtension,
                editor: editor
            )
            placeholders.append(placeholder)
        }
        let primaryId = placeholders[0].id
        let refURLs = references.map(\.url)

        Task { @MainActor in
            var tempToCleanup: [URL] = []
            defer { Self.cleanupTempFiles(tempToCleanup) }
            do {
                let uploaded: [String]
                if let preUploadedURLs, !preUploadedURLs.isEmpty {
                    uploaded = preUploadedURLs
                } else {
                    var urlsToUpload = refURLs
                    let refTypes = references.map(\.type)
                    if let trim = trimmedSourceOverride, trim.hasTrim, !urlsToUpload.isEmpty {
                        Log.generation.notice("using trimmed source: frames \(trim.trimStartFrame)+\(trim.sourceFramesConsumed) of \(urlsToUpload[0].lastPathComponent)")
                        let extracted = try await VideoTrimExtractor.extract(trim)
                        urlsToUpload[0] = extracted
                        tempToCleanup.append(extracted)
                    }
                    if let preprocessRef, !references.isEmpty {
                        let snapshot = references
                        let rewrites: [(Int, URL?)] = try await withThrowingTaskGroup(of: (Int, URL?).self) { group in
                            for (i, asset) in snapshot.enumerated() {
                                group.addTask { (i, try await preprocessRef(i, asset)) }
                            }
                            var results: [(Int, URL?)] = []
                            for try await r in group { results.append(r) }
                            return results
                        }
                        for (i, rewritten) in rewrites {
                            if let rewritten {
                                urlsToUpload[i] = rewritten
                                tempToCleanup.append(rewritten)
                            }
                        }
                    }
                    // Cache against the MediaAsset only when asset bytes are pristine (not trimmed, not preprocessed)
                    let trimmedFirst = trimmedSourceOverride?.hasTrim == true
                    let cacheKeys: [MediaAsset?] = references.enumerated().map { (i, asset) in
                        if preprocessRef != nil { return nil }
                        if i == 0 && trimmedFirst { return nil }
                        return asset
                    }
                    uploaded = try await uploadReferences(
                        at: urlsToUpload,
                        types: refTypes,
                        cacheKeys: cacheKeys,
                    )
                }

                var finalGenInput = genInput
                if let snapshotRefs {
                    snapshotRefs(&finalGenInput, uploaded)
                } else {
                    finalGenInput.imageURLs = uploaded.isEmpty ? nil : uploaded
                }
                if finalGenInput.createdAt == nil {
                    finalGenInput.createdAt = Date()
                }
                for placeholder in placeholders {
                    placeholder.generationInput = finalGenInput
                }

                let params = buildParams(uploaded)

                await self.runJob(
                    placeholders: placeholders,
                    params: params,
                    genInput: finalGenInput,
                    editor: editor,
                    onComplete: onComplete,
                    onFailure: onFailure
                )
            } catch {
                let message = error.localizedDescription
                Log.generation.error("upload failed model=\(genInput.model) error=\(message)")
                for placeholder in placeholders {
                    placeholder.generationStatus = .failed("Upload failed: \(message)")
                }
                onFailure?()
            }
        }

        return primaryId
    }

    private static func cleanupTempFiles(_ urls: [URL]) {
        for url in urls {
            try? FileManager.default.removeItem(at: url)
        }
    }

    // MARK: - Shared

    private func createPlaceholder(
        type: ClipType,
        name: String,
        duration: Double,
        genInput: GenerationInput,
        folderId: String?,
        destDir: URL,
        fileExtension: String,
        editor: EditorViewModel
    ) -> MediaAsset {
        let id = UUID().uuidString
        let destURL = destDir.appendingPathComponent("gen-\(id.prefix(8)).\(fileExtension)")
        let placeholder = MediaAsset(
            id: id,
            url: destURL,
            type: type,
            name: name,
            duration: duration,
            generationInput: genInput
        )
        placeholder.generationStatus = .generating
        placeholder.folderId = folderId
        editor.mediaAssets.append(placeholder)
        return placeholder
    }

    private static func destinationDirectory(for projectURL: URL?) -> URL {
        if let projectURL {
            let dir = projectURL.appendingPathComponent(Project.mediaDirectoryName, isDirectory: true)
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            return dir
        }
        return FileManager.default.temporaryDirectory
    }

    @discardableResult
    private func downloadAndFinalize(asset: MediaAsset, remoteURL: URL, editor: EditorViewModel) async -> Bool {
        asset.generationStatus = .downloading
        do {
            let (tempURL, _) = try await URLSession.shared.download(from: remoteURL)
            let realExt = remoteURL.pathExtension.lowercased()
            if !realExt.isEmpty, realExt != asset.url.pathExtension.lowercased(),
               ClipType(fileExtension: realExt) != nil {
                asset.url = asset.url.deletingPathExtension().appendingPathExtension(realExt)
            }
            try? FileManager.default.removeItem(at: asset.url)
            try FileManager.default.moveItem(at: tempURL, to: asset.url)

            asset.pendingDownloadURL = nil
            asset.generationStatus = .none
            editor.importMediaAsset(asset, skipAppend: true)
            editor.appendGenerationLog(for: asset)
            await editor.finalizeImportedAsset(asset)
            return true
        } catch {
            let message = error.localizedDescription
            Log.generation.error("download failed url=\(remoteURL.absoluteString) error=\(message)")
            asset.pendingDownloadURL = remoteURL
            asset.generationStatus = .failed(message)
            return false
        }
    }

    func retryDownload(asset: MediaAsset, editor: EditorViewModel) {
        guard let remoteURL = asset.pendingDownloadURL else { return }
        Task { @MainActor in
            await downloadAndFinalize(asset: asset, remoteURL: remoteURL, editor: editor)
        }
    }

    /// Uploads each reference and returns the hosted URLs.
    private func uploadReferences(
        at urls: [URL],
        types: [ClipType],
        cacheKeys: [MediaAsset?],
    ) async throws -> [String] {
        guard !urls.isEmpty else { return [] }
        return try await withThrowingTaskGroup(of: (Int, String).self) { group in
            for (i, url) in urls.enumerated() {
                let type = types.indices.contains(i) ? types[i] : .image
                let cacheKey = cacheKeys.indices.contains(i) ? cacheKeys[i] : nil
                if let cacheKey, let hit = cacheKey.freshRemoteURL {
                    group.addTask { (i, hit) }
                    continue
                }
                let contentType = Self.contentType(for: url, fallback: type)
                group.addTask {
                    let uploaded = try await GenerationBackend.uploadReference(
                        fileURL: url,
                        contentType: contentType,
                    )
                    if let cacheKey {
                        await Self.recordUploadCache(asset: cacheKey, url: uploaded)
                    }
                    return (i, uploaded)
                }
            }
            var results = [(Int, String)]()
            for try await r in group { results.append(r) }
            return results.sorted(by: { $0.0 < $1.0 }).map(\.1)
        }
    }

    @MainActor
    private static func recordUploadCache(asset: MediaAsset, url: String) {
        asset.cachedRemoteURL = url
        asset.cachedRemoteURLExpiresAt = Date().addingTimeInterval(uploadCacheTTL)
    }

    private static func contentType(for url: URL, fallback: ClipType) -> String {
        switch url.pathExtension.lowercased() {
        case "jpg", "jpeg": return "image/jpeg"
        case "png": return "image/png"
        case "webp": return "image/webp"
        case "heic": return "image/heic"
        case "gif": return "image/gif"
        case "mp4", "m4v": return "video/mp4"
        case "mov": return "video/quicktime"
        case "mp3": return "audio/mpeg"
        case "wav": return "audio/wav"
        case "m4a": return "audio/mp4"
        default:
            switch fallback {
            case .image: return "image/jpeg"
            case .video: return "video/mp4"
            case .audio: return "audio/mpeg"
            case .text: return "application/octet-stream"
            case .lottie: return "application/json"
            }
        }
    }

    // MARK: - Job execution

    private func runJob(
        placeholders: [MediaAsset],
        params: BackendGenerationParams,
        genInput: GenerationInput,
        editor: EditorViewModel,
        onComplete: (@MainActor (MediaAsset) -> Void)?,
        onFailure: (@MainActor () -> Void)?
    ) async {
        let runId = String(UUID().uuidString.prefix(8))
        Log.generation.notice("run \(runId) start model=\(genInput.model) placeholders=\(placeholders.count)")
        defer { Log.generation.notice("run \(runId) settled") }

        // Direct API path — bypasses Prato when custom generation is configured
        if case .image(let imageParams) = params,
           let client = DirectGenerationConfig.makeImageClient() {
            await runDirectImageJob(
                client: client, params: imageParams,
                placeholders: placeholders, editor: editor,
                onComplete: onComplete, onFailure: onFailure
            )
            return
        }

        if case .video(let videoParams) = params,
           let client = DirectGenerationConfig.makeVideoClient() {
            await runDirectVideoJob(
                client: client, params: videoParams,
                placeholders: placeholders, editor: editor,
                onComplete: onComplete, onFailure: onFailure
            )
            return
        }

        let jobId: String
        do {
            jobId = try await GenerationBackend.submit(
                model: genInput.model,
                params: params,
                projectId: editor.projectId,
            )
        } catch {
            let message = error.localizedDescription
            Log.generation.error("submit failed model=\(genInput.model) error=\(message)")
            for placeholder in placeholders {
                placeholder.generationStatus = .failed(message)
            }
            onFailure?()
            return
        }

        guard let publisher = GenerationBackend.subscribe(jobId: jobId) else {
            for placeholder in placeholders {
                placeholder.generationStatus = .failed("Backend not configured")
            }
            onFailure?()
            return
        }

        let stream = AsyncStream<BackendGenerationJob?> { continuation in
            let cancellable = publisher
                .receive(on: DispatchQueue.main)
                .sink(
                    receiveCompletion: { _ in continuation.finish() },
                    receiveValue: { value in continuation.yield(value) },
                )
            continuation.onTermination = { _ in cancellable.cancel() }
        }

        for await jobOpt in stream {
            guard let job = jobOpt else { continue }
            switch job.status {
            case .succeeded:
                await finalizeSuccess(
                    job: job,
                    placeholders: placeholders,
                    editor: editor,
                    onComplete: onComplete,
                    onFailure: onFailure,
                )
                return
            case .failed:
                let message = job.errorMessage ?? "Generation failed"
                Log.generation.error("job \(jobId) failed: \(message)")
                for placeholder in placeholders {
                    placeholder.generationStatus = .failed(message)
                }
                onFailure?()
                return
            case .queued, .running:
                continue
            }
        }
    }

    private func runDirectImageJob(
        client: DirectImageGenerationClient,
        params: ImageGenerationParams,
        placeholders: [MediaAsset],
        editor: EditorViewModel,
        onComplete: (@MainActor (MediaAsset) -> Void)?,
        onFailure: (@MainActor () -> Void)?
    ) async {
        do {
            let urls = try await client.generate(
                prompt: params.prompt,
                count: params.numImages,
                aspectRatio: params.aspectRatio
            )
            var finalized: [MediaAsset] = []
            for (i, placeholder) in placeholders.enumerated() {
                guard i < urls.count else {
                    placeholder.generationStatus = .failed("No URL for placeholder")
                    continue
                }
                if await downloadAndFinalize(asset: placeholder, remoteURL: urls[i], editor: editor) {
                    onComplete?(placeholder)
                    finalized.append(placeholder)
                }
            }
            if let first = finalized.first {
                AppNotifications.generationComplete(
                    assetId: first.id,
                    projectURL: editor.projectURL,
                    assetName: first.name,
                    assetType: first.type,
                    count: finalized.count
                )
            } else {
                onFailure?()
            }
        } catch {
            let message = error.localizedDescription
            Log.generation.error("direct image generation failed: \(message)")
            for placeholder in placeholders {
                placeholder.generationStatus = .failed(message)
            }
            onFailure?()
        }
    }

    private func runDirectVideoJob(
        client: DirectVideoGenerationClient,
        params: VideoGenerationParams,
        placeholders: [MediaAsset],
        editor: EditorViewModel,
        onComplete: (@MainActor (MediaAsset) -> Void)?,
        onFailure: (@MainActor () -> Void)?
    ) async {
        // Pick resolution based on aspect ratio
        let resolution: String? = {
            switch params.aspectRatio {
            case "16:9": return "1080P"
            case "9:16": return "720P"
            default:     return "1080P"
            }
        }()

        let taskId: String
        do {
            taskId = try await client.submitTask(
                prompt: params.prompt,
                duration: params.duration > 0 ? params.duration : 6,
                resolution: resolution,
                firstFrameURL: params.startFrameURL
            )
            Log.generation.notice("direct video submitted taskId=\(taskId)")
        } catch {
            let message = error.localizedDescription
            Log.generation.error("direct video submit failed: \(message)")
            for placeholder in placeholders {
                placeholder.generationStatus = .failed(message)
            }
            onFailure?()
            return
        }

        // Poll every 5 seconds until completed / failed (max ~10 minutes)
        let maxAttempts = 120
        for attempt in 0..<maxAttempts {
            if attempt > 0 { try? await Task.sleep(nanoseconds: 5_000_000_000) }
            let status: DirectVideoTaskStatus
            do {
                status = try await client.pollTask(taskId: taskId)
            } catch {
                Log.generation.warning("direct video poll error: \(error.localizedDescription)")
                continue
            }

            // Update progress on placeholder
            let pct = status.progress
            Log.generation.notice("direct video poll taskId=\(taskId) status=\(status.status) progress=\(pct)")

            switch status.status {
            case "completed":
                guard let videoURL = status.videoURL else {
                    for placeholder in placeholders {
                        placeholder.generationStatus = .failed("No video URL in response")
                    }
                    onFailure?()
                    return
                }
                var finalized: [MediaAsset] = []
                for placeholder in placeholders {
                    if await downloadAndFinalize(asset: placeholder, remoteURL: videoURL, editor: editor) {
                        onComplete?(placeholder)
                        finalized.append(placeholder)
                    }
                }
                if let first = finalized.first {
                    AppNotifications.generationComplete(
                        assetId: first.id,
                        projectURL: editor.projectURL,
                        assetName: first.name,
                        assetType: first.type,
                        count: finalized.count
                    )
                } else {
                    onFailure?()
                }
                return

            case "failed":
                let message = status.errorMessage ?? "Video generation failed"
                Log.generation.error("direct video failed taskId=\(taskId): \(message)")
                for placeholder in placeholders {
                    placeholder.generationStatus = .failed(message)
                }
                onFailure?()
                return

            default:
                // pending / in_progress — keep polling
                continue
            }
        }

        // Timed out
        for placeholder in placeholders {
            placeholder.generationStatus = .failed("Video generation timed out")
        }
        onFailure?()
    }

    private func finalizeSuccess(
        job: BackendGenerationJob,
        placeholders: [MediaAsset],
        editor: EditorViewModel,
        onComplete: (@MainActor (MediaAsset) -> Void)?,
        onFailure: (@MainActor () -> Void)?
    ) async {
        let urlStrings = job.resultUrls ?? []
        guard !urlStrings.isEmpty else {
            Log.generation.error("backend job succeeded with no resultUrls")
            for placeholder in placeholders {
                placeholder.generationStatus = .failed("No URL in response")
            }
            onFailure?()
            return
        }
        if urlStrings.count < placeholders.count {
            Log.generation.notice("backend returned \(urlStrings.count) URL(s) for \(placeholders.count) placeholder(s); marking extras as failed")
        }

        var finalized: [MediaAsset] = []
        for (i, placeholder) in placeholders.enumerated() {
            guard i < urlStrings.count, let remote = URL(string: urlStrings[i]) else {
                placeholder.generationStatus = .failed("No URL for placeholder")
                continue
            }
            if await downloadAndFinalize(asset: placeholder, remoteURL: remote, editor: editor) {
                onComplete?(placeholder)
                finalized.append(placeholder)
            }
        }

        if let first = finalized.first {
            AppNotifications.generationComplete(
                assetId: first.id,
                projectURL: editor.projectURL,
                assetName: first.name,
                assetType: first.type,
                count: finalized.count
            )
        } else {
            onFailure?()
        }
    }

}
