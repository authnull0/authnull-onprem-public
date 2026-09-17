#!/usr/bin/env bash
#
# Builds the RADIUS bridge binaries into this directory, so the on-prem package the
# customer receives contains everything their RADIUS install needs.
#
# Usage:
#   ./build.sh                          clone/pull the bridge repo into a temp dir
#   ./build.sh /path/to/radius-bridge   build from an existing checkout
#
# Run at RELEASE time, not at install time. The output is deliberately NOT committed:
# nothing else in this repository is a binary, and a 6MB artifact per revision bloats
# the history for something that is reproducible from a commit id.
#
# The customer never sees the bridge repository. They get the binary and
# install-bridge.sh, which is the whole reason this script exists.

set -euo pipefail

readonly BRIDGE_REPO="${BRIDGE_REPO:-git@github.com:authnull0/radius-bridge.git}"

# The branch carrying the five RADIUS context fields. An older build compiles and runs
# but sends none of them, so device / calling-station / service-type / domain scoping
# silently does nothing -- and since no match means allow, a policy scoped that way
# quietly stops applying. Pin it here rather than trusting whatever is checked out.
readonly BRIDGE_REF="${BRIDGE_REF:-radius-doauthnv4}"

readonly HERE="$(cd "$(dirname "$0")" && pwd)"

die() { printf '  \033[31mfail\033[0m  %s\n' "$*" >&2; exit 1; }
ok()  { printf '  \033[32mok\033[0m    %s\n' "$*"; }

command -v go >/dev/null 2>&1 || die "go toolchain not found"

if [ $# -ge 1 ]; then
	SRC="$1"
	[ -f "${SRC}/golangScript.go" ] || die "not a radius-bridge checkout: ${SRC}"
	ok "using checkout        ${SRC}"
else
	SRC="$(mktemp -d)"
	trap 'rm -rf "$SRC"' EXIT
	git clone --quiet --branch "$BRIDGE_REF" --depth 1 "$BRIDGE_REPO" "$SRC" \
		|| die "clone failed. Pass a local checkout path instead, or set BRIDGE_REPO"
	ok "cloned                ${BRIDGE_REF}"
fi

cd "$SRC"
COMMIT="$(git rev-parse --short HEAD 2>/dev/null || echo unknown)"

# Refuse to ship a build that cannot scope a policy. The fields are what the whole
# feature turns on, and their absence is invisible at runtime -- it presents as policies
# that simply never fire.
for field in nasIdentifier nasIp callingStation serviceType; do
	grep -q "\"${field},omitempty\"" golangScript.go \
		|| die "this checkout does not send ${field} -- wrong branch? expected ${BRIDGE_REF}"
done
ok "source sends all five RADIUS context fields"

go test ./... >/dev/null 2>&1 || die "bridge tests fail -- not shipping this"
ok "tests pass"

for arch in amd64 arm64; do
	CGO_ENABLED=0 GOOS=linux GOARCH="$arch" \
		go build -trimpath -ldflags "-s -w" -o "${HERE}/authnull-radius-mfa-linux-${arch}" .
	ok "built                 linux/${arch}"
done

# NOT copied from the bridge repo: that copy is a DEVELOPMENT config carrying real
# values -- ORG_ID=2, TENANT_ID=1, DOMAIN=authnull.lab. Shipping it would point a
# customer's VPN at our test tenant. The package keeps its own template with the
# required values deliberately blank.

cd "$HERE"
sha256sum authnull-radius-mfa-linux-* > SHA256SUMS
printf 'built from %s @ %s on %s\n' "$BRIDGE_REF" "$COMMIT" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > BUILD-INFO
ok "checksums + BUILD-INFO"

echo
echo "Package contents:"
ls -1 authnull-radius-mfa-linux-* SHA256SUMS BUILD-INFO install-bridge.sh radius-bridge.env.example | sed 's/^/  /'
echo
echo "The customer then runs, on their FreeRADIUS host:"
echo "  sudo ./install-bridge.sh ./authnull-radius-mfa-linux-amd64"
