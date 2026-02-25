import Foundation

func clampPercent(_ value: Int) -> Int {
  max(0, min(100, value))
}

func percentRemaining(fromUsedPercent usedPercent: Double) -> Int {
  clampPercent(Int((100.0 - usedPercent).rounded()))
}

func formatShortDuration(seconds: Int) -> String {
  let safeSeconds = max(0, seconds)
  let days = safeSeconds / 86_400
  let hours = (safeSeconds % 86_400) / 3_600
  let minutes = (safeSeconds % 3_600) / 60

  var parts: [String] = []
  if days > 0 { parts.append("\(days)d") }
  if hours > 0 { parts.append("\(hours)h") }
  if minutes > 0 || parts.isEmpty { parts.append("\(minutes)m") }
  return parts.joined(separator: " ")
}

func formatResetCountdown(to date: Date, now: Date) -> String {
  let diff = Int(date.timeIntervalSince(now))
  if diff <= 0 { return "reset" }
  return formatShortDuration(seconds: diff)
}

func parseNumeric(_ value: Any?) -> Double? {
  switch value {
  case let number as NSNumber:
    return number.doubleValue
  case let string as String:
    let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return nil }

    let normalized = trimmed.replacingOccurrences(of: ",", with: "")
    if let direct = Double(normalized) {
      return direct
    }

    let pattern = "^-?\\d+(?:\\.\\d+)?"
    guard
      let regex = try? NSRegularExpression(pattern: pattern),
      let match = regex.firstMatch(in: normalized, range: NSRange(location: 0, length: normalized.count)),
      let range = Range(match.range, in: normalized)
    else {
      return nil
    }
    return Double(normalized[range])
  default:
    return nil
  }
}

func firstNumeric(in dictionary: [String: Any], keys: [String]) -> Double? {
  for key in keys {
    if let parsed = parseNumeric(dictionary[key]) {
      return parsed
    }
  }
  return nil
}

func formatIntLike(_ value: Double?) -> String? {
  guard let value else { return nil }
  if value.rounded() == value {
    return String(Int(value))
  }
  return String(format: "%.1f", value)
}

func formatTokensMillions(_ value: Double?) -> String? {
  guard let value else { return nil }
  return String(format: "%.1fM", value / 1_000_000.0)
}

func parseJSONObject(from data: Data) throws -> [String: Any] {
  let object = try JSONSerialization.jsonObject(with: data)
  guard let dictionary = object as? [String: Any] else {
    throw ProviderClientError(kind: .decoding, message: "Expected top-level JSON object")
  }
  return dictionary
}

func parseISO8601(_ string: String?) -> Date? {
  guard let string else { return nil }
  let formatter = ISO8601DateFormatter()
  formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
  if let date = formatter.date(from: string) {
    return date
  }
  formatter.formatOptions = [.withInternetDateTime]
  return formatter.date(from: string)
}

func monthEndDate(year: Int, month: Int) -> Date? {
  var components = DateComponents()
  components.year = year
  components.month = month
  components.day = 1
  components.hour = 0
  components.minute = 0
  components.second = 0

  let calendar = Calendar(identifier: .gregorian)
  guard let startOfMonth = calendar.date(from: components) else { return nil }

  var plusOne = DateComponents()
  plusOne.month = 1
  return calendar.date(byAdding: plusOne, to: startOfMonth)
}
