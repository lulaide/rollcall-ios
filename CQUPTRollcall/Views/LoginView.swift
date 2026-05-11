import SwiftUI

struct LoginView: View {
    @EnvironmentObject var appState: AppState
    @State private var username = ""
    @State private var password = ""
    @State private var studentID = ""
    @State private var showAdvanced = false

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 24) {
                    // Logo
                    VStack(spacing: 8) {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 60))
                            .foregroundStyle(.blue)
                        Text("CQUPT 签到")
                            .font(.title.bold())
                        Text("重庆邮电大学自动签到系统")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, 40)

                    // Form
                    VStack(spacing: 16) {
                        TextField("IDS 账号", text: $username)
                            .textFieldStyle(.roundedBorder)
                            .textContentType(.username)
                            .autocapitalization(.none)

                        SecureField("IDS 密码", text: $password)
                            .textFieldStyle(.roundedBorder)
                            .textContentType(.password)

                        TextField("学号", text: $studentID)
                            .textFieldStyle(.roundedBorder)
                            .keyboardType(.numberPad)

                        DisclosureGroup("高级设置", isExpanded: $showAdvanced) {
                            VStack(spacing: 12) {
                                LabeledField("Center 服务器", text: $appState.config.centerServerURL)
                                LabeledField("Center 密钥", text: $appState.config.centerServerSecret)
                            }
                            .padding(.top, 8)
                        }
                    }
                    .padding(.horizontal)

                    // Error
                    if let error = appState.loginError {
                        Text(error)
                            .font(.caption)
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
                        if appState.isLoggingIn {
                            ProgressView()
                                .frame(maxWidth: .infinity)
                                .frame(height: 44)
                        } else {
                            Text("登录")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .frame(height: 44)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(username.isEmpty || password.isEmpty || appState.isLoggingIn)
                    .padding(.horizontal)
                }
            }
            .navigationBarHidden(true)
            .onAppear {
                username = appState.config.username
                password = appState.config.password
                studentID = appState.config.studentID
            }
        }
    }
}

struct LabeledField: View {
    let label: String
    @Binding var text: String

    init(_ label: String, text: Binding<String>) {
        self.label = label
        self._text = text
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            TextField(label, text: $text)
                .textFieldStyle(.roundedBorder)
                .autocapitalization(.none)
        }
    }
}
