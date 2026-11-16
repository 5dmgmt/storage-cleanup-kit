#!/usr/bin/env swift
import Foundation

let manager = FileManager.default
var arguments = Array(CommandLine.arguments.dropFirst())
let shouldEvict = arguments.first == "--evict"
if shouldEvict { arguments.removeFirst() }

guard !arguments.isEmpty else {
    fputs("使い方: swift cloud-status.swift [--evict] <ファイルまたはフォルダー>...\n", stderr)
    exit(1)
}

let keys: Set<URLResourceKey> = [
    .isRegularFileKey,
    .ubiquitousItemIsUploadedKey,
    .ubiquitousItemDownloadingStatusKey,
    .fileSizeKey
]
var finalStatus: Int32 = 0

for path in arguments {
    var isDirectory: ObjCBool = false
    guard manager.fileExists(atPath: path, isDirectory: &isDirectory) else {
        fputs("存在するファイルまたはフォルダーではありません: \(path)\n", stderr)
        finalStatus = 1
        continue
    }

    let root = URL(fileURLWithPath: path, isDirectory: isDirectory.boolValue)
    let urls: [URL]
    var enumerationFailed = false
    if isDirectory.boolValue {
        guard let enumerator = manager.enumerator(at: root, includingPropertiesForKeys: Array(keys), options: [], errorHandler: { url, error in
            fputs("読めません: \(url.path): \(error.localizedDescription)\n", stderr)
            enumerationFailed = true
            return true
        }) else {
            fputs("フォルダーを調べられません: \(path)\n", stderr)
            finalStatus = 1
            continue
        }
        urls = enumerator.allObjects.compactMap { $0 as? URL }
    } else {
        urls = [root]
    }

    var total = 0
    var uploaded = 0
    var pending = 0
    var unknown = 0
    var pendingBytes: Int64 = 0
    var samples: [String] = []
    var evicted = 0
    var failed = 0
    if enumerationFailed { failed += 1 }

    for url in urls {
        // Finder が作る .DS_Store はクラウドへ上がらないことがあるので数えない
        if url.lastPathComponent == ".DS_Store" { continue }
        guard let values = try? url.resourceValues(forKeys: keys) else {
            failed += 1
            fputs("読めません: \(url.path)\n", stderr)
            continue
        }
        guard values.isRegularFile == true else { continue }
        total += 1
        guard let isUploaded = values.ubiquitousItemIsUploaded else {
            unknown += 1
            continue
        }
        if isUploaded {
            uploaded += 1
            if shouldEvict, values.ubiquitousItemDownloadingStatus == .current {
                do {
                    try manager.evictUbiquitousItem(at: url)
                    evicted += 1
                } catch {
                    failed += 1
                    fputs("外せません: \(url.path): \(error.localizedDescription)\n", stderr)
                }
            }
        } else {
            pending += 1
            pendingBytes += Int64(values.fileSize ?? 0)
            if samples.count < 3 { samples.append(url.path) }
        }
    }

    let pendingMB = Double(pendingBytes) / 1_048_576.0
    let pendingText = String(format: "%.1f", pendingMB)
    var summary = "\(path): 件数 \(total) / 上がり済み \(uploaded) / 待ち \(pending) (\(pendingText) MB)"
    if unknown > 0 { summary += " / 上がり済みが分かりません \(unknown)" }
    if shouldEvict { summary += " / 外した \(evicted) / 失敗 \(failed)" }
    print(summary)
    if !samples.isEmpty {
        print("  待ちの例:")
        for sample in samples { print("  - \(sample)") }
    }
    if unknown > 0 { print("  この場所は File Provider 以外の同期方式を含む可能性があります。") }
    if unknown > 0, finalStatus == 0 { finalStatus = 3 }
    if pending > 0, finalStatus != 1 { finalStatus = 2 }
    if failed > 0 { finalStatus = 1 }
}

exit(finalStatus)
