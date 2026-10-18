import ActivityKit
import SwiftUI
import WidgetKit

// Uygulamanın Pomodoro halkasıyla aynı tonlar: Odaklanma = uygulama accent'i,
// Mola = yeşil.
private let focusColor = Color(red: 0.459, green: 0.404, blue: 0.910)
private let breakColor = Color(red: 0.298, green: 0.624, blue: 0.439)

@available(iOS 16.2, *)
private extension PomodoroAttributes.ContentState {
  var tint: Color { isBreak ? breakColor : focusColor }
  var title: String { isBreak ? "Kısa Mola" : "Odaklanma" }
  var symbol: String { isBreak ? "cup.and.saucer.fill" : "timer" }
  var statusText: String { isRunning ? "Devam ediyor" : "Duraklatıldı" }

  var pausedText: String {
    let minutes = remainingSeconds / 60
    let seconds = remainingSeconds % 60
    return String(format: "%02d:%02d", minutes, seconds)
  }

  var pausedFraction: Double {
    guard totalSeconds > 0 else { return 0 }
    return min(max(Double(remainingSeconds) / Double(totalSeconds), 0), 1)
  }
}

// Çalışırken süre iOS'un yerel zamanlayıcısı ile (uygulama arka planda
// olsa bile) akar; duraklatılmışken sabit değer gösterilir.
@available(iOS 16.2, *)
private struct PomodoroTimeText: View {
  let state: PomodoroAttributes.ContentState

  var body: some View {
    if state.isRunning {
      Text(timerInterval: state.startDate...state.endDate, pauseTime: nil, countsDown: true, showsHours: false)
        .monospacedDigit()
    } else {
      Text(state.pausedText)
        .monospacedDigit()
    }
  }
}

@available(iOS 16.2, *)
private struct PomodoroProgress: View {
  let state: PomodoroAttributes.ContentState

  var body: some View {
    Group {
      if state.isRunning {
        ProgressView(timerInterval: state.startDate...state.endDate, countsDown: true) {
          EmptyView()
        } currentValueLabel: {
          EmptyView()
        }
      } else {
        ProgressView(value: state.pausedFraction)
      }
    }
    .tint(state.tint)
  }
}

@available(iOS 16.2, *)
private struct PomodoroLockScreenView: View {
  let state: PomodoroAttributes.ContentState

  var body: some View {
    VStack(spacing: 14) {
      HStack(alignment: .center, spacing: 12) {
        ZStack {
          Circle().fill(state.tint.opacity(0.16))
          Image(systemName: state.symbol)
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(state.tint)
        }
        .frame(width: 36, height: 36)

        VStack(alignment: .leading, spacing: 2) {
          Text(state.title)
            .font(.system(size: 16, weight: .semibold))
          Text(state.statusText)
            .font(.system(size: 12.5))
            .foregroundStyle(.secondary)
        }

        Spacer(minLength: 8)

        PomodoroTimeText(state: state)
          .font(.system(size: 34, weight: .semibold, design: .rounded))
          .foregroundStyle(state.tint)
          .multilineTextAlignment(.trailing)
          .frame(maxWidth: 120, alignment: .trailing)
      }

      PomodoroProgress(state: state)
    }
    .padding(.horizontal, 18)
    .padding(.vertical, 16)
  }
}

@available(iOS 16.2, *)
struct PomodoroLiveActivityWidget: Widget {
  var body: some WidgetConfiguration {
    ActivityConfiguration(for: PomodoroAttributes.self) { context in
      PomodoroLockScreenView(state: context.state)
    } dynamicIsland: { context in
      let state = context.state

      return DynamicIsland {
        DynamicIslandExpandedRegion(.leading) {
          Label(state.title, systemImage: state.symbol)
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(state.tint)
            .padding(.leading, 4)
        }
        DynamicIslandExpandedRegion(.trailing) {
          PomodoroTimeText(state: state)
            .font(.system(size: 26, weight: .semibold, design: .rounded))
            .foregroundStyle(state.tint)
            .multilineTextAlignment(.trailing)
            .frame(maxWidth: 96, alignment: .trailing)
            .padding(.trailing, 4)
        }
        DynamicIslandExpandedRegion(.bottom) {
          VStack(spacing: 8) {
            PomodoroProgress(state: state)
            Text(state.statusText)
              .font(.system(size: 12))
              .foregroundStyle(.secondary)
          }
          .padding(.horizontal, 4)
        }
      } compactLeading: {
        Image(systemName: state.symbol)
          .foregroundStyle(state.tint)
      } compactTrailing: {
        PomodoroTimeText(state: state)
          .font(.system(size: 14, weight: .semibold, design: .rounded))
          .foregroundStyle(state.tint)
          .multilineTextAlignment(.trailing)
          .frame(width: 46)
      } minimal: {
        Image(systemName: state.symbol)
          .foregroundStyle(state.tint)
      }
      .keylineTint(state.tint)
    }
  }
}
