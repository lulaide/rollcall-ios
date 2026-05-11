import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var appState: AppState
    @ObservedObject private var config = AppConfig.shared
    @State private var showLogoutConfirm = false

    var body: some View {
        NavigationStack {
            Form {
                Section("账号信息") {
                    LabeledContent("账号", value: config.username)
                    LabeledContent("学号", value: config.studentID)
                    LabeledContent("Client ID", value: String(config.clientID.prefix(8)) + "...")
                }

                Section("签到设置") {
                    Toggle("自动定位签到", isOn: $config.autoLocationCheckin)
                    Toggle("暂停接收共享签到", isOn: $config.pauseSharedRollcall)
                    Stepper(value: $config.curriculumPreMinutes, in: 1...30) {
                        Label("课前 \(config.curriculumPreMinutes) 分钟轮询", systemImage: "clock")
                    }
                }

                Section("服务器") {
                    LabeledContent("Center") {
                        Text(config.centerServerURL)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }

                Section {
                    Button(role: .destructive) {
                        showLogoutConfirm = true
                    } label: {
                        HStack {
                            Spacer()
                            Label("退出登录", systemImage: "rectangle.portrait.and.arrow.right")
                            Spacer()
                        }
                    }
                }
            }
            .navigationTitle("设置")
            .confirmationDialog("确定退出登录?", isPresented: $showLogoutConfirm, titleVisibility: .visible) {
                Button("退出登录", role: .destructive) {
                    appState.logout()
                }
            }
        }
    }
}
