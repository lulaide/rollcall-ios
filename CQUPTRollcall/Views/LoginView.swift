import SwiftUI

struct LoginView: View {
    @EnvironmentObject var appState: AppState
    @State private var username = ""
    @State private var password = ""
    @State private var studentID = ""
    @State private var showAdvanced = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 28) {
                    Spacer(minLength: 40)

                    // Logo
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

                    // Login form
                    VStack(spacing: 16) {
                        GroupBox {
                            VStack(spacing: 0) {
                                TextField("IDS 账号", text: $username)
                                    .textContentType(.username)
                                    .autocorrectionDisabled()
                                    .textInputAutocapitalization(.never)
                                    .padding(.vertical, 10)
                                Divider()
                                SecureField("IDS 密码", text: $password)
                                    .textContentType(.password)
                                    .padding(.vertical, 10)
                                Divider()
                                TextField("学号", text: $studentID)
                                    .keyboardType(.numberPad)
                                    .padding(.vertical, 10)
                            }
                        }

                        DisclosureGroup("高级设置", isExpanded: $showAdvanced) {
                            GroupBox {
                                VStack(spacing: 0) {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("Center 服务器").font(.caption).foregroundStyle(.secondary)
                                        TextField("wss://...", text: $appState.config.centerServerURL)
                                            .textInputAutocapitalization(.never)
                                            .autocorrectionDisabled()
                                    }
                                    .padding(.vertical, 8)
                                    Divider()
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("Center 密钥").font(.caption).foregroundStyle(.secondary)
                                        TextField("可选", text: $appState.config.centerServerSecret)
                                            .textInputAutocapitalization(.never)
                                            .autocorrectionDisabled()
                                    }
                                    .padding(.vertical, 8)
                                }
                            }
                        }
                        .tint(.secondary)
                    }
                    .padding(.horizontal)

                    // Error
                    if let error = appState.loginError {
                        Label(error, systemImage: "exclamationmark.triangle")
                            .font(.callout)
                            .foregroundStyle(.red)
                            .padding(.horizontal)
                    }

                    // Login button
                    Button {
                        appState.config.username = username
                        appState.config.password = password
                        appState.config.studentID = studentID
                        Task { await appState.login() }
                    } label: {
                        Group {
                            if appState.isLoggingIn {
                                ProgressView()
                            } else {
                                Text("登录")
                                    .fontWeight(.semibold)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(username.isEmpty || password.isEmpty || appState.isLoggingIn)
                    .padding(.horizontal)

                    Spacer(minLength: 20)
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
