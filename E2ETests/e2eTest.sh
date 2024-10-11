#!/bin/bash

swift build || exit 1

result=0

if [[ $(echo 'ps | head -1 | grep -o PID' | .build/debug/swift-sh 2>/dev/null) != "PID" ]]; then
    echo "Pipe test failed" >&2
    result=1
fi

tmpfile=$(mktemp /tmp/swift-sh.XXXXXX)
echo "ps | head -1 | grep -o PID > ${tmpfile}" | .build/debug/swift-sh 2>/dev/null
if [[ $(cat "${tmpfile}") != "PID" ]]; then
    echo "Out-redirect test failed" >&2
    result=1
fi
rm "${tmpfile}"

tmpfile=$(mktemp /tmp/swift-sh.XXXXXX)
echo ABC > "${tmpfile}"
if [[ $(echo "cat < ${tmpfile}" | .build/debug/swift-sh 2>/dev/null) != "ABC" ]]; then
    echo "In-redirect test failed" >&2
    result=1
fi
rm "${tmpfile}"

exit "${result}"