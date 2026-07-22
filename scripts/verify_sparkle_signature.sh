#!/bin/bash
# Verify a Sparkle EdDSA (Ed25519) update signature against a public key.
#
# Usage: verify_sparkle_signature.sh <file> <base64-signature> <base64-public-key>
#
# Exits 0 if the signature is valid, 1 if not. Used by the release workflow to
# refuse to publish an appcast whose signature the shipped SUPublicEDKey would
# reject ("The update is improperly signed"), and handy for checking a live
# release by hand:
#
#   curl -sL <appcast-url>            # grab sparkle:edSignature
#   curl -sLO <dmg-url>
#   ./scripts/verify_sparkle_signature.sh Detto.dmg "<edSignature>" \
#       "$(/usr/libexec/PlistBuddy -c 'Print :SUPublicEDKey' Detto/Sources/Detto/Info.plist)"
set -euo pipefail

if [[ $# -ne 3 ]]; then
  echo "Usage: $0 <file> <base64-signature> <base64-public-key>" >&2
  exit 64
fi

python3 - "$1" "$2" "$3" <<'PY'
import base64, os, subprocess, sys, tempfile

path, sig_b64, pub_b64 = sys.argv[1:4]
sig = base64.b64decode(sig_b64)
pub = base64.b64decode(pub_b64)

if len(pub) != 32:
    print(f"Public key is {len(pub)} bytes after base64-decode; expected 32.")
    sys.exit(1)

def report(ok):
    if ok:
        print("Sparkle EdDSA signature: VALID")
        sys.exit(0)
    print("Sparkle EdDSA signature: INVALID — the signing key does not match this public key.")
    print("An appcast published with this signature will fail in-app with")
    print("\"The update is improperly signed\" on every install shipping this SUPublicEDKey.")
    sys.exit(1)

# A broken cryptography install can raise more than ImportError — treat any
# import-time failure as "not available" and fall through to OpenSSL.
try:
    from cryptography.exceptions import InvalidSignature
    from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PublicKey
except BaseException:
    InvalidSignature = None

if InvalidSignature is not None:
    try:
        Ed25519PublicKey.from_public_bytes(pub).verify(sig, open(path, "rb").read())
        report(True)
    except InvalidSignature:
        report(False)

# Fallback: OpenSSL 3+ raw Ed25519 verify (Apple's bundled LibreSSL won't work;
# on macOS install cryptography via pip or openssl@3 via brew).
der = bytes.fromhex("302a300506032b6570032100") + pub
with tempfile.TemporaryDirectory() as td:
    pem = os.path.join(td, "pub.pem")
    sigf = os.path.join(td, "sig.bin")
    with open(pem, "w") as f:
        f.write("-----BEGIN PUBLIC KEY-----\n")
        f.write(base64.encodebytes(der).decode())
        f.write("-----END PUBLIC KEY-----\n")
    with open(sigf, "wb") as f:
        f.write(sig)
    r = subprocess.run(
        ["openssl", "pkeyutl", "-verify", "-pubin", "-inkey", pem,
         "-rawin", "-in", path, "-sigfile", sigf],
        capture_output=True, text=True)
    if "no supported" in (r.stderr or "").lower() or r.returncode == 64:
        print("Neither python-cryptography nor an Ed25519-capable openssl is available.")
        sys.exit(64)
    report(r.returncode == 0)
PY
