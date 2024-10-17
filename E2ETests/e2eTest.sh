#!/bin/bash

swift build || exit 1

result=0

# Pipe test
if [[ $(echo 'echo | cat -n | grep -o 1' | .build/debug/swift-sh 2>/dev/null) != "1" ]]; then
  echo "Pipe test failed" >&2
  result=1
fi

# Redirect-out test
tmpfile=$(mktemp /tmp/swift-sh.XXXXXX)
echo "echo | cat -n | grep -o 1 > ${tmpfile}" | .build/debug/swift-sh 2>/dev/null
if [[ $(cat "${tmpfile}") != "1" ]]; then
  echo "Out-redirect test failed" >&2
  result=1
fi
rm "${tmpfile}"

# Redirect-in test
tmpfile=$(mktemp /tmp/swift-sh.XXXXXX)
echo "1" > "${tmpfile}"
if [[ $(echo "cat < ${tmpfile}" | .build/debug/swift-sh 2>/dev/null) != "1" ]]; then
  echo "In-redirect test failed" >&2
  result=1
fi
rm "${tmpfile}"

# Built-in comamnd cd test
if [[ $(echo $'cd / \n pwd \n cd /tmp \n pwd' | ./.build/debug/swift-sh 2>/dev/null) != $'/\n/tmp' ]]; then
  echo "Built-in command cd failed " >&2
  result=1
fi

exit "${result}"