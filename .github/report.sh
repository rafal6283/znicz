#!/usr/bin/env bash
# Wypisuje istotne fragmenty logów jako adnotacje ::error:: (czytelne bez dostępu do pełnych logów).
pattern='error|Error|ERROR|FAILED|failed|What went wrong|Expected:|Actual:|Exception|Could not|requires|not found|isn.t defined|undefined|incompatible|Some tests failed'
chunk=""; n=0; count=0
emit() { if [ -n "$chunk" ] && [ $count -lt 9 ]; then echo "::error::${chunk}"; count=$((count+1)); fi; chunk=""; n=0; }
for f in "$@"; do
  [ -f "$f" ] || continue
  grep -E "$pattern" -A4 "$f" | grep -v -- '^--$' | head -250 > /tmp/report_lines.txt
  while IFS= read -r line; do
    line="${line//%/%25}"
    chunk="${chunk}${line:0:300}%0A"; n=$((n+1))
    if [ $n -ge 28 ]; then emit; fi
  done < /tmp/report_lines.txt
  emit
  echo "::error::TAIL $f%0A$(tail -25 "$f" | sed 's/%/%25/g' | cut -c1-250 | sed ':a;N;$!ba;s/\n/%0A/g')"
done
