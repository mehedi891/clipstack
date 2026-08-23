#!/bin/bash
# Create a stable self-signed code-signing certificate named "Clipstack Dev".
#
# Why this is needed: macOS binds Accessibility permission to an app's code
# signature. Ad-hoc signing (the default without a certificate) produces a new
# signature on every build, so the permission is revoked each time you rebuild.
# A fixed certificate keeps the signature stable, and the grant survives.
#
# This is for local development only. It does NOT satisfy Gatekeeper on other
# people's Macs — that needs an Apple Developer ID. See README.md.
#
# Run once:  ./scripts/create-signing-cert.sh
# macOS will ask for your login password when the certificate is trusted.
set -euo pipefail

NAME="Clipstack Dev"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"

if security find-certificate -c "$NAME" >/dev/null 2>&1; then
    echo "\"$NAME\" already exists — nothing to do."
    echo "scripts/build-app.sh will pick it up automatically."
    exit 0
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "==> Generating a code-signing certificate"
# extendedKeyUsage=codeSigning is what makes codesign accept the identity.
openssl req -x509 -newkey rsa:2048 -nodes -days 3650 \
    -keyout "$WORK/key.pem" -out "$WORK/cert.pem" \
    -subj "/CN=$NAME/O=Clipstack/C=US" \
    -addext "basicConstraints=critical,CA:false" \
    -addext "keyUsage=critical,digitalSignature" \
    -addext "extendedKeyUsage=critical,codeSigning" 2>/dev/null

openssl pkcs12 -export -out "$WORK/cert.p12" \
    -inkey "$WORK/key.pem" -in "$WORK/cert.pem" \
    -passout pass: 2>/dev/null

echo "==> Importing into your login keychain"
# -T authorises codesign to use the key without prompting on every build.
security import "$WORK/cert.p12" -k "$KEYCHAIN" -P "" \
    -T /usr/bin/codesign -T /usr/bin/security >/dev/null

echo "==> Trusting it for code signing (macOS will ask for your password)"
security add-trusted-cert -r trustRoot -p codeSign -k "$KEYCHAIN" "$WORK/cert.pem"

# Stops the keychain prompting on every single build.
security set-key-partition-list -S apple-tool:,apple:,codesign: \
    -s -k "" "$KEYCHAIN" >/dev/null 2>&1 || true

echo
if security find-identity -v -p codesigning | grep -q "$NAME"; then
    echo "==> Done. \"$NAME\" is ready."
    echo "    Rebuild with ./scripts/build-app.sh — it detects the certificate."
    echo
    echo "    Then reset the old permission once, and grant it one final time:"
    echo "      tccutil reset Accessibility com.efoli.Clipstack"
else
    echo "!! The certificate was created but is not valid for code signing." >&2
    echo "   Create it via Keychain Access instead — see README.md." >&2
    exit 1
fi
