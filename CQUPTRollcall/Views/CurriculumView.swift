import SwiftUI

struct CurriculumView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        NavigationStack {
            Group {
                if appState.todayCourses.isEmpty {
                    ContentUnavailableView(
                        "今天没有课程",
                        systemImage: "calendar.badge.checkmark",
                        description: Text("享受休息时间吧")
                    )
                } else {
                    List(appState.todayCourses) { course in
                        CourseRow(course: course)
                    }
                }
            }
            .navigationTitle("今日课表")
        }
    }
}

struct CourseRow: View {
    let course: CurriculumInstance

    var body: some View {
        HStack(spacing: 12) {
            VStack(spacing: 2) {
                Text(course.startTime)
                    .font(.subheadline.bold().monospacedDigit())
                Text(course.endTime)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .frame(width: 50)

            RoundedRectangle(cornerRadius: 2)
                .fill(course.isNow ? .green : .quaternary)
                .frame(width: 4)

            VStack(alignment: .leading, spacing: 4) {
                Text(course.course)
                    .font(.headline)
                if !course.location.isEmpty {
                    Label(course.location, systemImage: "mappin.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            if course.isNow {
                Text("进行中")
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.green.opacity(0.12))
                    .foregroundStyle(.green)
                    .clipShape(Capsule())
            }
        }
        .padding(.vertical, 2)
    }
}
