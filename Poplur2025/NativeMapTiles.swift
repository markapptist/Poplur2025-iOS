import Foundation
import Network
import zlib

/// Bounded, range-only PMTiles v3 reader. It uses the same immutable archive
/// as the web app; no Mac, WebView tile proxy, or whole-world download.
actor NativePMTilesArchive {
    struct Tile { let data: Data; let gzip: Bool }
    private struct Header {
        let root: UInt64, rootLength: Int, leaf: UInt64, tiles: UInt64
        let compression: UInt8, tileCompression: UInt8, minZoom: Int, maxZoom: Int
    }
    private struct Entry { var id: UInt64 = 0; var run: UInt64 = 0; var offset: UInt64 = 0; var length: Int = 0 }
    private let url: URL
    private let session: URLSession
    private var header: Header?
    private var directories: [String: [Entry]] = [:]
    private var order: [String] = []
    init(url: URL, session: URLSession) { self.url = url; self.session = session }
    private func range(_ offset: UInt64, _ length: Int) async throws -> Data {
        guard (1...16_777_216).contains(length) else { throw URLError(.badServerResponse) }
        var request = URLRequest(url: url, timeoutInterval: 20)
        request.setValue("bytes=\(offset)-\(offset + UInt64(length) - 1)", forHTTPHeaderField: "Range")
        request.setValue("identity", forHTTPHeaderField: "Accept-Encoding")
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse, response.statusCode == 206,
              response.value(forHTTPHeaderField: "Content-Range")?.hasPrefix("bytes \(offset)-\(offset + UInt64(length) - 1)/") == true,
              data.count == length else { throw URLError(.badServerResponse) }
        return data
    }
    private func readHeader() async throws -> Header {
        if let header { return header }
        let data = try await range(0, 127)
        guard String(data: data.prefix(7), encoding: .ascii) == "PMTiles", data[7] == 3,
              data[99] == 1, (1...2).contains(data[97]), (1...2).contains(data[98]) else { throw URLError(.cannotDecodeContentData) }
        func uint64(_ offset: Int) -> UInt64 { (0..<8).reduce(0) { $0 | (UInt64(data[offset+$1]) << ($1*8)) } }
        let result = Header(root: uint64(8), rootLength: Int(uint64(16)), leaf: uint64(40), tiles: uint64(56),
                            compression: data[97], tileCompression: data[98], minZoom: Int(data[100]), maxZoom: Int(data[101]))
        header = result
        return result
    }
    private func directory(_ offset: UInt64, _ length: Int, _ compression: UInt8) async throws -> [Entry] {
        let key = "\(offset):\(length)"
        if let cached = directories[key] { order.removeAll { $0 == key }; order.append(key); return cached }
        let raw = try await range(offset, length)
        let data = try compression == 2 ? raw.mapGunzip() : raw
        var cursor = 0
        func varint() throws -> UInt64 {
            var value: UInt64 = 0
            for shift in stride(from: 0, through: 63, by: 7) {
                guard cursor < data.count else { throw URLError(.cannotDecodeContentData) }
                let byte = data[cursor]; cursor += 1
                value |= UInt64(byte & 127) << shift
                if byte < 128 { return value }
            }
            throw URLError(.cannotDecodeContentData)
        }
        let count = Int(try varint())
        guard count <= 1_000_000 else { throw URLError(.dataLengthExceedsMaximum) }
        var entries = [Entry](repeating: Entry(), count: count), lastID: UInt64 = 0
        for index in entries.indices { lastID += try varint(); entries[index].id = lastID }
        for index in entries.indices { entries[index].run = try varint() }
        for index in entries.indices { entries[index].length = Int(try varint()) }
        for index in entries.indices {
            let value = try varint()
            if value == 0 && index > 0 { entries[index].offset = entries[index-1].offset + UInt64(entries[index-1].length) }
            else { guard value > 0 else { throw URLError(.cannotDecodeContentData) }; entries[index].offset = value - 1 }
        }
        directories[key] = entries; order.append(key)
        while order.count > 16 { directories.removeValue(forKey: order.removeFirst()) }
        return entries
    }
    func tile(z: Int, x: Int, y: Int) async throws -> Tile? {
        let h = try await readHeader()
        guard (h.minZoom...h.maxZoom).contains(z), (0..<(1 << z)).contains(x), (0..<(1 << z)).contains(y) else { return nil }
        let id = Self.tileID(z: z, x: x, y: y)
        var offset = h.root, length = h.rootLength
        for _ in 0..<4 {
            let entries = try await directory(offset, length, h.compression)
            var low = 0, high = entries.count
            while low < high { let middle = (low+high)/2; if entries[middle].id <= id { low = middle+1 } else { high = middle } }
            guard low > 0 else { return nil }
            let entry = entries[low-1]
            if entry.run == 0 { offset = h.leaf + entry.offset; length = entry.length }
            else if id - entry.id < entry.run { return Tile(data: try await range(h.tiles+entry.offset, entry.length), gzip: h.tileCompression == 2) }
            else { return nil }
        }
        throw URLError(.cannotDecodeContentData)
    }
    static func tileID(z: Int, x: Int, y: Int) -> UInt64 {
        precondition((0...26).contains(z))
        var value = ((UInt64(1) << (2*z))-1)/3, tx = x, ty = y, s = (1 << z) >> 1
        while s > 0 {
            let rx = tx & s == 0 ? 0 : 1, ry = ty & s == 0 ? 0 : 1
            value += UInt64(s*s*((3*rx)^ry))
            if ry == 0 { if rx != 0 { tx = s-1-tx; ty = s-1-ty }; swap(&tx,&ty) }
            s >>= 1
        }
        return value
    }
}

private extension Data {
    func mapGunzip() throws -> Data {
        try withUnsafeBytes { input in
            var stream = z_stream()
            stream.next_in = UnsafeMutablePointer(mutating: input.bindMemory(to: Bytef.self).baseAddress)
            stream.avail_in = uInt(count)
            guard inflateInit2_(&stream, 31, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size)) == Z_OK else { throw URLError(.cannotDecodeContentData) }
            defer { inflateEnd(&stream) }
            var result = Data(), buffer = [UInt8](repeating: 0, count: 32_768), status: Int32 = Z_OK
            repeat {
                let written = buffer.withUnsafeMutableBytes { output -> Int in
                    stream.next_out = output.bindMemory(to: Bytef.self).baseAddress
                    stream.avail_out = uInt(output.count)
                    status = inflate(&stream, Z_NO_FLUSH)
                    return output.count - Int(stream.avail_out)
                }
                guard status == Z_OK || status == Z_STREAM_END, result.count + written <= 16_777_216 else { throw URLError(.cannotDecodeContentData) }
                result.append(contentsOf: buffer.prefix(written))
            } while status != Z_STREAM_END
            return result
        }
    }
}

/// An app-owned loopback endpoint lets the native SDK request PMTiles as
/// ordinary vector tiles. It lives and dies with the native map renderer.
final class NativeMapTileServer: @unchecked Sendable {
    private let listener: NWListener
    private let queue = DispatchQueue(label: "Poplur.NativeMapTiles")
    private let nonce = UUID().uuidString
    private let session: URLSession
    private var archives: [String: NativePMTilesArchive] = [:]
    private var waiting: [(Result<UInt16, Error>) -> Void] = []
    private var port: UInt16?
    private var closed = false
    init() throws {
        let configuration = URLSessionConfiguration.default
        configuration.urlCache = URLCache(memoryCapacity: 4*1024*1024, diskCapacity: 48*1024*1024, directory: nil)
        configuration.httpMaximumConnectionsPerHost = 4
        session = URLSession(configuration: configuration)
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
        listener = try NWListener(using: parameters)
        listener.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .ready:
                guard let port = self.listener.port?.rawValue else { return }
                self.port = port; self.waiting.forEach { $0(.success(port)) }; self.waiting.removeAll()
            case .failed(let error):
                self.closed = true; self.waiting.forEach { $0(.failure(error)) }; self.waiting.removeAll()
            default: break
            }
        }
        listener.newConnectionHandler = { [weak self] connection in self?.accept(connection) }
        listener.start(queue: queue)
    }
    func tiles(for url: URL) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            queue.async { [self] in
                guard !closed, url.scheme == "https", url.pathExtension == "pmtiles" else { continuation.resume(throwing: URLError(.badURL)); return }
                let id = url.absoluteString.data(using: .utf8)!.base64EncodedString().replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "+", with: "-")
                if archives[id] == nil { archives[id] = NativePMTilesArchive(url: url, session: session) }
                if let port { continuation.resume(returning: "http://127.0.0.1:\(port)/\(nonce)/\(id)/{z}/{x}/{y}/tile.mvt") }
                else {
                    waiting.append { result in
                        continuation.resume(with: result.map { "http://127.0.0.1:\($0)/\(self.nonce)/\(id)/{z}/{x}/{y}/tile.mvt" })
                    }
                }
            }
        }
    }
    private func accept(_ connection: NWConnection) {
        connection.start(queue: queue)
        connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) { [weak self] data, _, _, _ in
            guard let self, let data, let request = String(data: data, encoding: .utf8)?.components(separatedBy: "\r\n").first else { connection.cancel(); return }
            let words = request.split(separator: " "), pieces = words.count > 1 ? words[1].split(separator: "/").map(String.init) : []
            guard words.first == "GET", pieces.count == 6, pieces[0] == self.nonce, let archive = self.archives[pieces[1]],
                  let z = Int(pieces[2]), let x = Int(pieces[3]), let y = Int(pieces[4]), pieces[5] == "tile.mvt" else { self.reply(connection, status: "404 Not Found", tile: nil); return }
            Task {
                do { let tile = try await archive.tile(z:z,x:x,y:y); self.reply(connection, status: tile == nil ? "204 No Content" : "200 OK", tile: tile) }
                catch { self.reply(connection, status: "503 Service Unavailable", tile: nil) }
            }
        }
    }
    private func reply(_ connection: NWConnection, status: String, tile: NativePMTilesArchive.Tile?) {
        let body = tile?.data ?? Data(), encoding = tile?.gzip == true ? "Content-Encoding: gzip\r\n" : ""
        var response = Data("HTTP/1.1 \(status)\r\nContent-Type: application/vnd.mapbox-vector-tile\r\nContent-Length: \(body.count)\r\n\(encoding)Cache-Control: max-age=86400\r\nConnection: close\r\n\r\n".utf8)
        response.append(body)
        connection.send(content: response, completion: .contentProcessed { _ in connection.cancel() })
    }
    func close() {
        queue.async { [self] in
            closed = true; listener.cancel(); session.invalidateAndCancel(); archives.removeAll()
            waiting.forEach { $0(.failure(URLError(.cancelled))) }; waiting.removeAll()
        }
    }
}
