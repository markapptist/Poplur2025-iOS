// In AppDelegate.swift
func application(_ app: UIApplication, open url: URL, options: [UIApplication.OpenURLOptionsKey : Any] = [:]) -> Bool {
    // Forward to Snap Kit login handler if it’s the login callback
    // return SCSDKLoginClient.application(app, open: url, options: options)
    return false
}
