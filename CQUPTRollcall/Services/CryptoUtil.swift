import Foundation
import CommonCrypto

enum CryptoUtil {
    private static let charset = Array("ABCDEFGHJKMNPQRSTWXYZabcdefhijkmnprstwxyz2345678")

    private static func randomString(_ length: Int) -> String {
        String((0..<length).map { _ in charset.randomElement()! })
    }

    /// AES-128-CBC encrypt password with salt key, matching Python/Go implementation.
    static func encryptPassword(_ password: String, key: String) -> String {
        guard !key.isEmpty else { return password }

        let iv = randomString(16)
        let padding = randomString(64)
        let plaintext = padding + password

        guard let keyData = key.data(using: .utf8),
              let ivData = iv.data(using: .utf8),
              let plaintextData = plaintext.data(using: .utf8) else {
            return password
        }

        // PKCS7 padding
        let blockSize = kCCBlockSizeAES128
        let paddingSize = blockSize - (plaintextData.count % blockSize)
        var padded = plaintextData
        padded.append(Data(repeating: UInt8(paddingSize), count: paddingSize))

        var encrypted = Data(count: padded.count)
        var numBytesEncrypted = 0

        let status = encrypted.withUnsafeMutableBytes { encryptedPtr in
            padded.withUnsafeBytes { paddedPtr in
                keyData.withUnsafeBytes { keyPtr in
                    ivData.withUnsafeBytes { ivPtr in
                        CCCrypt(
                            CCOperation(kCCEncrypt),
                            CCAlgorithm(kCCAlgorithmAES),
                            0, // no extra options, we already did PKCS7
                            keyPtr.baseAddress, kCCKeySizeAES128,
                            ivPtr.baseAddress,
                            paddedPtr.baseAddress, padded.count,
                            encryptedPtr.baseAddress, padded.count,
                            &numBytesEncrypted
                        )
                    }
                }
            }
        }

        guard status == kCCSuccess else { return password }
        encrypted.count = numBytesEncrypted
        return encrypted.base64EncodedString()
    }
}

enum QRUtil {
    private static let qrRegex = try! NSRegularExpression(pattern: "^[a-f0-9]{42}$", options: .caseInsensitive)
    private static let urlRegex = try! NSRegularExpression(pattern: "!3~([a-fA-F0-9]+)")

    /// Extract 42-char hex QR data from raw scan. No timestamp validation —
    /// the iOS app is a scanner for Center sharing, let server-side validate.
    static func extractQRData(_ rawData: String) -> String {
        var data = rawData

        if data.contains("!3~") {
            let range = NSRange(data.startIndex..., in: data)
            if let match = urlRegex.firstMatch(in: data, range: range),
               let captureRange = Range(match.range(at: 1), in: data) {
                data = String(data[captureRange])
            } else {
                return ""
            }
        }

        data = data.lowercased()

        let range = NSRange(data.startIndex..., in: data)
        guard qrRegex.firstMatch(in: data, range: range) != nil else { return "" }

        return data
    }
}
