import SwiftUI

struct LoginView: View {
    @EnvironmentObject var appState: AppState
    @State private var username = ""
    @State private var password = ""
    @State private var studentID = ""
    @State private var showAdvanced = false

    private var canLogin: Bool {
        !username.isEmpty && !password.isEmpty && !appState.isLoggingIn
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(spacing: 10) {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 64))
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(.tint)
                        Text("CQUPT 签到")
                            .font(.largeTitle.bold())
                        Text("重庆邮电大学自动签到系统")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                }

                Section {
                    TextField("IDS 账号", text: $username)
                        .textContentType(.username)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                    SecureField("IDS 密码", text: $password)
                        .textContentType(.password)
                    TextField("学号", text: $studentID)
                        .keyboardType(.numberPad)
                        .textContentType(.username)
                }

                Section {
                    DisclosureGroup("高级设置", isExpanded: $showAdvanced) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Center 服务器")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            TextField("wss://...", text: $appState.config.centerServerURL)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                        }
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Center 密钥")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            TextField("可选", text: $appState.config.centerServerSecret)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                        }
                    }
                }

                if let error = appState.loginError {
                    Section {
                        Label(error, systemImage: "exclamationmark.triangle")
                            .font(.callout)
                            .foregroundStyle(.red)
                    }
                }

                Section {
                    Button {
                        appState.config.username = username
                        appState.config.password = password
                        appState.config.studentID = studentID
                        Task { await appState.login() }
                    } label: {
                        HStack {
                            Spacer()
                            if appState.isLoggingIn {
                                ProgressView().tint(.white)
                            } else {
                                Text("登录").fontWeight(.semibold)
                            }
                            Spacer()
                        }
                    }
                    .disabled(!canLogin)
                    .listRowBackground(canLogin ? Color.accentColor : Color(.systemGray4))
                    .foregroundStyle(.white)
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .onAppear {
                username = appState.config.username
                password = appState.config.password
                studentID = appState.config.studentID
            }
        }
    }
}
