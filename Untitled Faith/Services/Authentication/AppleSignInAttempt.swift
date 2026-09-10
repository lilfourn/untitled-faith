import AuthenticationServices
import CryptoKit
import Security

struct AppleSignInAttempt {
    let nonce: String
    let state: String

    init() throws {
        nonce = try Self.randomValue()
        state = try Self.randomValue()
    }

    var hashedNonce: String {
        SHA256.hash(data: Data(nonce.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    func configure(_ request: ASAuthorizationAppleIDRequest) {
        request.requestedScopes = [.fullName]
        request.nonce = hashedNonce
        request.state = state
    }

    func credentials(from authorization: ASAuthorization) throws -> (userID: String, request: AppleExchangeRequest) {
        guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
              credential.state == state, !credential.user.isEmpty,
              let identityData = credential.identityToken,
              let identityToken = String(data: identityData, encoding: .utf8), !identityToken.isEmpty,
              let codeData = credential.authorizationCode,
              let code = String(data: codeData, encoding: .utf8), !code.isEmpty else {
            throw AuthenticationError.invalidCredential
        }
        return (credential.user, AppleExchangeRequest(identityToken: identityToken, authorizationCode: code, nonce: nonce,
                                                     firstName: credential.fullName?.givenName))
    }

    private static func randomValue() throws -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else {
            throw AuthenticationError.unavailable
        }
        return bytes.map { String(format: "%02x", $0) }.joined()
    }
}
