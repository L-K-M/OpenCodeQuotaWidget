import Foundation

public final class SnapshotStore: @unchecked Sendable {
  private let fileURL: URL
  private let encoder: JSONEncoder
  private let decoder: JSONDecoder

  public init(fileURL: URL) {
    self.fileURL = fileURL
    self.encoder = JSONEncoder()
    self.decoder = JSONDecoder()
    encoder.dateEncodingStrategy = .iso8601
    decoder.dateDecodingStrategy = .iso8601
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
  }

  public func load() throws -> QuotaSnapshot? {
    guard FileManager.default.fileExists(atPath: fileURL.path) else {
      return nil
    }
    let data = try Data(contentsOf: fileURL)
    return try decoder.decode(QuotaSnapshot.self, from: data)
  }

  public func save(_ snapshot: QuotaSnapshot) throws {
    try FileManager.default.createDirectory(
      at: fileURL.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    let data = try encoder.encode(snapshot)
    try data.write(to: fileURL, options: .atomic)
  }
}
