#!/bin/sh
# Red repro for PR #42 (08e09710f41b): WeatherTemperatureUnit.degrees traps on a
# finite temperature that does not fit in Int. Exits 1 (child signal) while present.
set -eu
cd "$(CDPATH= cd -P "$(dirname "$0")/../.." && pwd)"
if ! command -v swiftc >/dev/null 2>&1; then
    if [ -x "$HOME/swift-toolchain/swift-6.2.1-RELEASE-ubuntu24.04/usr/bin/swiftc" ]; then
        PATH="$HOME/swift-toolchain/swift-6.2.1-RELEASE-ubuntu24.04/usr/bin:$PATH"
        export PATH
    fi
fi
command -v swiftc >/dev/null 2>&1 || { echo "swiftc is required" >&2; exit 2; }
SHA=08e09710f41b
git cat-file -e "$SHA^{commit}" || { echo "missing commit $SHA (fetch zeus-bot/settings-weather)" >&2; exit 2; }
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
git show "$SHA:Sources/ZeusCore/Settings/Sections/Weather/WeatherTemperatureUnit.swift" > "$work/WeatherTemperatureUnit.swift"
cat > "$work/main.swift" << 'EOF'
import Foundation
@main
struct Main {
    static func main() {
        let degrees = WeatherTemperatureUnit.degrees(celsius: 1e20, unit: .celsius)
        print("degrees=\(String(describing: degrees))")
        let wind = WeatherTemperatureUnit.wind(kilometersPerHour: 1e20, unit: .fahrenheit)
        print("wind=\(String(describing: wind))")
    }
}
EOF
swiftc -parse-as-library -o "$work/repro" "$work/WeatherTemperatureUnit.swift" "$work/main.swift"
set +e
"$work/repro"
code=$?
set -e
if [ "$code" -eq 0 ]; then
    echo "conversion returned instead of trapping" >&2
    exit 0
fi
echo "BUG: weather conversion exited $code"
exit 1
