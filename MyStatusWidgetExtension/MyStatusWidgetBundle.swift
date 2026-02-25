import WidgetKit
import SwiftUI

@main
struct OpenCodeQuotaWidgetBundle: WidgetBundle {
  var body: some Widget {
    OpenCodeQuotaWidget()
    OpenAIQuotaWidget()
    ZhipuQuotaWidget()
    ZAIQuotaWidget()
    GoogleQuotaWidget()
    CopilotQuotaWidget()
  }
}
