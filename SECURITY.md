# Security Boundaries

This repository contains client code and synthetic tests, not credentials.
Knowing the server URL, sensor names or source code does not authorize access
to production data. The server must enforce authentication and authorization
for every request, independently of the app's sign-in screen.

Do not commit passwords, tokens, session exports, signing certificates, private
keys or real telemetry. Runtime sessions belong in the device Keychain only.
Do not disable TLS checks or same-origin protections to diagnose connectivity.
Do not include credentials or real readings in a public issue or build log.

Debug preview flags must be absent from the Release IPA. The packaging verifier
checks these flags and rejects private key/session filenames in the archive.
