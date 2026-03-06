import WidgetKit
import SwiftUI

@main
struct OpenCodeQuotaWidgetBundle: WidgetBundle {
  var body: some Widget {
    OpenCodeQuotaWidget()
    QuotaTrendChartWidget()
    OpenAIQuotaWidget()
    ZhipuQuotaWidget()
    ZAIQuotaWidget()
    GoogleQuotaWidget()
    CopilotQuotaWidget()
  }
}
