import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var appState: AppState
    @ObservedObject private var config = AppConfig.shared
    @State private var showLogoutConfirm = false

    var body: some View {
        NavigationView {
            Form {
                Section("账号") {
                    LabeledContent("账号", value: config.username)
                    LabeledContent("学号", value: config.studentID)
                    LabeledContent("Client ID", value: String(config.clientID.prefix(8)))
                }

                Section("签到设置") {
                    Toggle("自动定位签到", isOn: $config.autoLocationCheckin)
                    Toggle("暂停接收共享签到", isOn: $config.pauseSharedRollcall)
                    Stepper("课前 \(config.curriculumPreMinutes) 分钟开始轮询", value: $config.curriculumPreMinutes, in: 1...30)
                }

                Section("服务器") {
                    VStack(alignment: .leading) {
                        Text("Center 地址").font(.caption).foregroundStyle(.secondary)
                        TextField("wss://...", text: $config.centerServerURL)
                            .font(.subheadline)
                            .autocapitalization(.none)
                    }
                }

                Section {
                    Button(role: .destructive) {
                        showLogoutConfirm = true
                    } label: {
                        HStack {
                            Spacer()
                            Text("退出登录")
                            Spacer()
                        }
                    }
                }
            }
            .navigationTitle("设置")
            .confirmationDialog("确定退出登录?", isPresented: $showLogoutConfirm) {
                Button("退出登录", role: .destructive) {
                    appState.logout()
                }
            }
        }
    }
}
