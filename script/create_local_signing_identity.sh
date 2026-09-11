#!/usr/bin/env zsh
set -euo pipefail

IDENTITY_NAME="${CAPTURELY_LOCAL_SIGNING_IDENTITY:-Capturely Local Development}"
KEYCHAIN="${CAPTURELY_SIGNING_KEYCHAIN:-$(security login-keychain | tr -d ' "')}"
P12_PASSWORD="capturely-local-dev"

if security find-identity -p codesigning -v "$KEYCHAIN" 2>/dev/null | grep -F "\"$IDENTITY_NAME\"" >/dev/null; then
  echo "Code signing identity already exists: $IDENTITY_NAME"
  echo "Use it with:"
  echo "  CAPTURELY_CODE_SIGN_IDENTITY=\"$IDENTITY_NAME\" ./script/build_and_run.sh --verify"
  exit 0
fi

TMP_DIR="$(mktemp -d /tmp/capturely-signing.XXXXXX)"
trap 'rm -rf "$TMP_DIR"' EXIT

KEY_FILE="$TMP_DIR/capturely-local.key"
CERT_FILE="$TMP_DIR/capturely-local.cer"
P12_FILE="$TMP_DIR/capturely-local.p12"

openssl req \
  -new \
  -x509 \
  -newkey rsa:2048 \
  -keyout "$KEY_FILE" \
  -out "$CERT_FILE" \
  -days 3650 \
  -nodes \
  -subj "/CN=$IDENTITY_NAME/O=Capturely/OU=Local Development" \
  -addext "keyUsage=critical,digitalSignature" \
  -addext "extendedKeyUsage=codeSigning" >/dev/null 2>&1

openssl pkcs12 \
  -legacy \
  -export \
  -out "$P12_FILE" \
  -inkey "$KEY_FILE" \
  -in "$CERT_FILE" \
  -passout "pass:$P12_PASSWORD" >/dev/null 2>&1

security import "$P12_FILE" \
  -k "$KEYCHAIN" \
  -P "$P12_PASSWORD" \
  -A \
  -T /usr/bin/codesign >/dev/null

security add-trusted-cert \
  -r trustRoot \
  -p codeSign \
  -k "$KEYCHAIN" \
  "$CERT_FILE" >/dev/null

if ! security find-identity -p codesigning -v "$KEYCHAIN" 2>/dev/null | grep -F "\"$IDENTITY_NAME\"" >/dev/null; then
  echo "Created certificate, but it is not visible as a valid code signing identity yet." >&2
  echo "Open Keychain Access and confirm '$IDENTITY_NAME' is trusted for Code Signing." >&2
  exit 1
fi

echo "Created local code signing identity: $IDENTITY_NAME"
echo "Use it with:"
echo "  CAPTURELY_CODE_SIGN_IDENTITY=\"$IDENTITY_NAME\" ./script/build_and_run.sh --verify"
