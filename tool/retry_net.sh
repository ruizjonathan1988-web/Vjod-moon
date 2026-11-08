#!/usr/bin/env bash
# Runs a build command, writing its output to the file given first, and runs it
# again (up to 5 times) when it failed only because a download from GitHub
# failed (Gradle, pdfium…): GitHub release downloads sometimes answer 504.
out=$1; shift
for attempt in 1 2 3 4 5; do
  "$@" > "$out" 2>&1
  status=$?
  [ $status -eq 0 ] && exit 0
  if ! grep -qE "_download|wrapper\.Install|Building native assets failed|Could not (resolve|download|GET)|50[234]|timed out|Connection reset" "$out"; then
    exit $status
  fi
  echo "Téléchargement raté (essai $attempt), nouvel essai dans 60 s"
  sleep 60
done
exit $status
