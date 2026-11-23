import Foundation

private func file(_ id: String, type: String = "CSV") -> DeliveredFile {
    DeliveredFile(id: id, name: id + ".csv", type: type, bytes: 10, tafID: "t1", tafName: "Refunds", runID: "r1",
                  runAt: Date(timeIntervalSince1970: 1_794_679_800), goesAt: Date(timeIntervalSince1970: 1_797_271_800))
}

let accountFilesMacTests: [Test] = [
    Test("a failed Download says it didn't reach the server, never a bare status; nothing is written", awaiting: { @MainActor in
        let destination = FileManager.default.temporaryDirectory.appendingPathComponent("files-test-\(UUID().uuidString).csv")
        let model = FilesModel(readAll: { [file("f1")] }, readPreview: { _ in nil },
                               readDownload: { _ in URL(string: "https://storage.test/x")! }, delete: { _ in },
                               fetch: { _ in throw KIFFError.refused(status: 403, code: "") })
        await model.load()
        await model.download(file("f1"), to: destination)
        try expectEqual(model.notes["f1"], Words.app("error.offline"))
        try expect(!FileManager.default.fileExists(atPath: destination.path), "nothing written")
    }),
    Test("a Delete tafs cloud answers 404 takes the file out of the list: it's already gone", awaiting: { @MainActor in
        let model = FilesModel(readAll: { [file("f1"), file("f2")] }, readPreview: { _ in nil }, readDownload: { _ in throw KIFFError.unreadable },
                               delete: { _ in throw CloudRefusal(status: 404, body: Data(#"{"error":"not_found"}"#.utf8)) })
        await model.load()
        let gone = await model.delete(file("f1"))
        try expect(gone, "taken out")
        try expectEqual(model.files().map(\.id), ["f2"])
        let refused = FilesModel(readAll: { [file("f1")] }, readPreview: { _ in nil }, readDownload: { _ in throw KIFFError.unreadable },
                                 delete: { _ in throw CloudRefusal(status: 500, body: Data()) })
        await refused.load()
        let kept = await refused.delete(file("f1"))
        try expect(!kept, "kept")
        try expectEqual(refused.notes["f1"], Words.app("error.offline"))
        try expectEqual(refused.files().map(\.id), ["f1"])
    }),
    Test("a file's start that answers after the file closed isn't kept", awaiting: { @MainActor in
        var model: FilesModel?
        model = FilesModel(readAll: { [file("f1")] }, readPreview: { _ in
            await MainActor.run { model?.close(file("f1")) }
            return FilePreviewText(text: "secret", truncated: false)
        }, readDownload: { _ in throw KIFFError.unreadable }, delete: { _ in })
        await model?.load()
        await model?.preview(file("f1"))
        try expectEqual(model?.previews["f1"], nil)
    }),
    Test("a type with no text start is drawn by the system from a private copy that goes when it closes; a text type's bytes never are", awaiting: { @MainActor in
        var fetched: [URL] = []
        let pdf = DeliveredFile(id: "f2", name: "report.pdf", type: "PDF", bytes: 4, tafID: "t1", tafName: "Refunds", runID: "r1",
                                runAt: Date(timeIntervalSince1970: 1_794_679_800), goesAt: Date(timeIntervalSince1970: 1_797_271_800))
        let model = FilesModel(readAll: { [file("f1"), pdf] }, readPreview: { _ in nil },
                               readDownload: { id in URL(string: "https://storage.test/\(id)")! }, delete: { _ in },
                               fetch: { url in fetched.append(url); return Data("%PDF".utf8) })
        await model.load()
        // A text type tafs cloud answered with no start: no preview, and no bytes read.
        await model.preview(file("f1"))
        try expectEqual(model.previews["f1"], .noPreview)
        try expectEqual(fetched, [])
        // A PDF: its bytes, in a copy of its own, drawn by the system.
        await model.preview(pdf)
        guard case .copy(let copy)? = model.previews["f2"] else { throw Failure(description: "no copy: \(String(describing: model.previews["f2"]))") }
        try expectEqual(copy.lastPathComponent, "report.pdf")
        try expectEqual(try Data(contentsOf: copy), Data("%PDF".utf8))
        try expect(copy.path.hasPrefix(FilesModel.copiesFolder.path), "under the app's own copies")
        // Share uses the same copy, read once.
        let shared = await model.shareCopy(of: pdf)
        try expectEqual(shared, copy)
        try expectEqual(fetched.count, 1)
        // Closed: the copy is gone.
        model.close(pdf)
        try expect(!FileManager.default.fileExists(atPath: copy.path), "the copy went with the screen")
    }),
    Test("Share reads the file only when it's shared, and a failed read says it didn't reach the server", awaiting: { @MainActor in
        let model = FilesModel(readAll: { [file("f1")] }, readPreview: { _ in FilePreviewText(text: "a,b", truncated: false) },
                               readDownload: { _ in URL(string: "https://storage.test/x")! }, delete: { _ in },
                               fetch: { _ in throw KIFFError.refused(status: 403, code: "") })
        await model.load()
        await model.preview(file("f1"))
        try expectEqual(model.previews["f1"], .text(FilePreviewText(text: "a,b", truncated: false)))
        let shared = await model.shareCopy(of: file("f1"))
        try expectEqual(shared, nil)
        try expectEqual(model.notes["f1"], Words.app("error.offline"))
    }),
]
