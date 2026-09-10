import Foundation

/// Separate from the sign-in record so revocation/sign-out cannot erase unfinished cleanup.
struct PendingAccountDeletion: Codable {
    let authentication: StoredAuthentication
    var serverConfirmed = false

    var namespace: String {
        authentication.apiBaseURL.absoluteString + "|" + authentication.appleUserID
    }
}
