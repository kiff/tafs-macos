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
]
