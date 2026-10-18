#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
developer="$(xcode-select -p)"
frameworks="$developer/Library/Developer/Frameworks"
if [ -d "$frameworks/Testing.framework" ]; then
    swift test --disable-xctest -Xswiftc -F -Xswiftc "$frameworks" -Xlinker "-F$frameworks" -Xlinker -rpath -Xlinker "$frameworks" -Xlinker -rpath -Xlinker "$developer/Library/Developer/usr/lib"
else
    swift test --disable-xctest
fi
