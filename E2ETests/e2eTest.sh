#!/bin/bash

swift build || exit 1

result=0

if [[ $(echo 'echo | cat -n | grep -o 1' | .build/debug/swift-sh 2>/dev/null) != "1" ]]; then
    echo "Pipe test failed" >&2
    result=1
fi

tmpfile=$(mktemp /tmp/swift-sh.XXXXXX)
echo "echo | cat -n | grep -o 1 > ${tmpfile}" | .build/debug/swift-sh 2>/dev/null
if [[ $(cat "${tmpfile}") != "1" ]]; then
    echo "Out-redirect test failed" >&2
    result=1
fi
rm "${tmpfile}"

tmpfile=$(mktemp /tmp/swift-sh.XXXXXX)
echo "1" > "${tmpfile}"
if [[ $(echo "cat < ${tmpfile}" | .build/debug/swift-sh 2>/dev/null) != "1" ]]; then
    echo "In-redirect test failed" >&2
    result=1
fi
rm "${tmpfile}"

exit "${result}"