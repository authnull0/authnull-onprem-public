#!/usr/bin/env bash
#
# Build the licence-enforcing on-premise image.
#
# WHY THIS EXISTS RATHER THAN A DOCUMENTED docker build LINE
#
# Whether an image enforces licensing is decided by one build argument, and if it is missing the
# build SUCCEEDS and produces a working image that simply never asks for a licence. Push that under
# the -onprem tag and every customer who pulls it has the product for free, permanently, with
# nothing in the console or the logs to say so. The mistake is invisible at the only moment anyone
# would look.
#
# So the checks below are the point of the script, not decoration:
#
#   * a key is required, and the -onprem tag cannot be produced without one;
#   * the key is validated as an Ed25519 PUBLIC key before a build is spent on it;
#   * a PRIVATE key handed over by mistake is refused, loudly -- it is the one input that must never
#     reach a build, an image or a registry;
#   * the finished image is inspected to confirm the key really is in the binary, because the
#     build-arg could be silently dropped by a stale cache layer or a typo in the arg name;
#   * the key's fingerprint is printed so the operator can check it against what the CEO sent.
#
# See LICENSE-KEY-CUSTODY.md for where the key comes from. Nothing here ever touches the private half.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REGISTRY="${REGISTRY:-docker-repo-public.authnull.com}"
IMAGE="${IMAGE:-authnull-service}"

bold() { printf '\033[1m%s\033[0m\n' "$*"; }
green() { printf '\033[32m%s\033[0m\n' "$*"; }
warn() { printf '\033[33m%s\033[0m\n' "$*" >&2; }
fail() { printf '\033[31merror: %s\033[0m\n' "$*" >&2; exit 1; }

usage() {
  cat <<'USAGE'
Build the licence-enforcing on-premise image.

  ./build-image.sh --key license.pub --version 1.0.0 [--push]

  --key FILE       the PUBLIC licence key from the CEO (license.pub). Required.
  --version X.Y.Z  image version. Required. The tag becomes X.Y.Z-onprem.
  --push           push after building. Omit to build locally only.
  --check          validate the key and print the fingerprint, then stop.

The private key (license.key) must never be passed to this script, must never enter a build
argument, and must never leave the CEO's machine. See LICENSE-KEY-CUSTODY.md.
USAGE
  exit 0
}

KEY_FILE="" VERSION="" PUSH=false CHECK_ONLY=false
while [ $# -gt 0 ]; do
  case "$1" in
    --key)     KEY_FILE="${2:-}"; shift 2 ;;
    --version) VERSION="${2:-}"; shift 2 ;;
    --push)    PUSH=true; shift ;;
    --check)   CHECK_ONLY=true; shift ;;
    -h|--help) usage ;;
    *) fail "unknown option: $1 (try --help)" ;;
  esac
done

[ -n "$KEY_FILE" ] || fail "--key is required. An image built without one does not enforce licensing,
       and must not be tagged -onprem. See LICENSE-KEY-CUSTODY.md."
[ -f "$KEY_FILE" ] || fail "no such file: $KEY_FILE"

# ── Refuse the private key ───────────────────────────────────────────────────────────────────────
#
# Checked before anything else, and by content rather than by filename: renaming license.key to
# license.pub must not get it through. An Ed25519 private key is 64 bytes where the public half is
# 32, which is what the length test below catches. The filename check is a second, cheaper net for
# the common slip.
case "$(basename "$KEY_FILE")" in
  *.key|*private*|*secret*)
    fail "$KEY_FILE looks like the PRIVATE key. Only the public half (license.pub) may be built
       into an image. If this really is the public key, rename it to license.pub."
    ;;
esac

KEY="$(tr -d '[:space:]' < "$KEY_FILE")"
[ -n "$KEY" ] || fail "$KEY_FILE is empty"

# The character set is checked before decoding, because GNU base64 -d is lenient: it silently
# skips characters it does not recognise, so "not-base64-at-all!!!" decodes to 20 bytes rather
# than failing. That still gets refused by the length test below, but with the wrong reason --
# an operator who pasted a garbled key would be told "this is not a licence key" instead of
# "that is not base64", and would go looking for the wrong problem.
case "$KEY" in
  *[!A-Za-z0-9+/=]*)
    fail "$KEY_FILE is not valid base64. Expected the contents of license.pub as produced by
       'authnull-license keygen'." ;;
esac

DECODED_LEN=$(printf '%s' "$KEY" | base64 -d 2>/dev/null | wc -c || echo 0)
case "$DECODED_LEN" in
  32) ;;  # Ed25519 public key. Correct.
  64) fail "$KEY_FILE decodes to 64 bytes, which is an Ed25519 PRIVATE key.
       The private key must never enter a build or an image. Stopping." ;;
  0)  fail "$KEY_FILE is not valid base64. Expected the contents of license.pub as produced by
       'authnull-license keygen'." ;;
  *)  fail "$KEY_FILE decodes to $DECODED_LEN bytes; an Ed25519 public key is 32.
       This is not a licence key." ;;
esac

# A fingerprint the CEO can read out over the phone, so the right key is confirmed before a release
# rather than after a customer cannot install their licence.
FINGERPRINT=$(printf '%s' "$KEY" | base64 -d | sha256sum | cut -c1-16)
green "Public key accepted: 32 bytes, Ed25519."
echo "  fingerprint: ${FINGERPRINT}   <- confirm this matches the key the CEO issued"
echo "  key:         ${KEY}"

if [ "$CHECK_ONLY" = true ]; then
  green "Key is valid. Nothing was built."
  exit 0
fi

[ -n "$VERSION" ] || fail "--version is required (for example --version 1.0.0)"
case "$VERSION" in
  *-onprem) fail "give the version alone (1.0.0); the -onprem suffix is added for you" ;;
  [0-9]*.[0-9]*.[0-9]*) ;;
  *) fail "--version should look like 1.0.0, got '$VERSION'" ;;
esac

TAG="${REGISTRY}/${IMAGE}:${VERSION}-onprem"

echo
bold "Building ${TAG}"
echo

# --pull so the base images are current, and no --no-cache: the build arg is part of the cache key
# for the layer that uses it, so a changed key cannot be served from cache. The verification step
# below is what actually proves that, rather than trusting it.
docker build \
  --pull \
  --build-arg LICENSE_PUBLIC_KEY="$KEY" \
  -t "$TAG" \
  -f "$REPO_ROOT/Dockerfile" \
  "$REPO_ROOT"

# ── Confirm the key is really in the image ───────────────────────────────────────────────────────
#
# The build argument could have been dropped by a typo in the arg name, or by a Dockerfile change
# that stopped passing it through -- and the build would still succeed. Grepping the binary is the
# only check that cannot be fooled by any of that.
echo
bold "Verifying the image"
if docker run --rm --entrypoint sh "$TAG" -c "grep -c -F '$KEY' /app/main 2>/dev/null || strings /app/main 2>/dev/null | grep -c -F '$KEY'" 2>/dev/null | grep -qv '^0$'; then
  green "The public key is compiled into the binary. This image enforces licensing."
else
  fail "the key is NOT in the built binary, so this image would not enforce licensing.
       Do not push it. Check that Dockerfile still declares ARG LICENSE_PUBLIC_KEY and passes it
       to the go build ldflags."
fi

echo
if [ "$PUSH" = true ]; then
  bold "Pushing ${TAG}"
  docker push "$TAG"
  green "Pushed."
else
  green "Built ${TAG}"
  echo "  Not pushed. Re-run with --push when you are ready."
fi

echo
cat <<NEXT
Next:
  1. Set this tag in onprem/docker-compose.yml if the version changed.
  2. Install it on a clean VM and confirm /system/v1/health reports
     "license": { "state": "trial" }  --  NOT "not_enforced".
     "not_enforced" means the key did not make it in and the customer would never be asked
     for a licence.
  3. Issue a test licence with 'authnull-license sign', upload it, and confirm the state
     becomes "valid".
NEXT
