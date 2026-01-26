// CI-only stub for Secrets to allow builds without local credentials.
#if CI
enum Secrets {
    static let clientID = ProcessInfo.processInfo.environment["TESLA_CLIENT_ID"] ?? ""
    static let clientSecret = ProcessInfo.processInfo.environment["TESLA_CLIENT_SECRET"] ?? ""
}
#endif
