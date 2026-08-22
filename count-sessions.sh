#!/bin/bash
# Conta le sessioni Claude Code.
# Stampa due interi separati da spazio:  "<APERTE> <AL_LAVORO>"
#   APERTE    = processi `claude` interattivi + sessioni task headless spawnate
#               da Topics (binario versionato ~/.local/share/claude/versions/x.y.z),
#               esclusi daemon / bg helpers
#   AL_LAVORO = max tra:
#               (a) sessioni che consumano CPU adesso (delta CPU-time su una
#                   finestra di campionamento), e
#               (b) task "in_progress" secondo la board di Topics
#                   (GET /api/all-boards/tasks) — così un task che sta
#                   aspettando un tool lungo (CPU ~0) conta comunque.
#               Se Topics è giù, (b) vale 0 → comportamento solo-CPU.
#
# Perché CPU-delta e non la mtime della transcript: Claude Code scrive la
# transcript .jsonl a fine turno, quindi una sessione che sta generando ORA
# risulterebbe "idle" guardando il file. Il delta di CPU invece la becca.
# (Il %cpu di `ps` da solo è la media a vita: inutile → serve il delta.)

INTERVAL="${SAMPLE_INTERVAL:-1.2}"   # secondi di campionamento
THRESHOLD_PCT="${WORKING_THRESHOLD_PCT:-3}"  # %CPU sopra cui = "al lavoro"
TOPICS_TASKS_URL="${TOPICS_TASKS_URL:-https://127.0.0.1:3333/api/all-boards/tasks}"

# pid -> cpu_seconds (TIME di ps, formato [dd-]hh:mm:ss[.cc])
snapshot() {
  ps -axo pid,time,command | awk '
  {
    m = split($3, a, "/"); base = a[m]
    # match: basename "claude" (CLI/shim/app) OPPURE binario versionato
    # (~/.local/share/claude/versions/2.1.x) usato dalle sessioni task di
    # Topics (--print stream-json, --fork-session), che altrimenti sfuggono
    if (base != "claude" && index($3, "claude/versions/") == 0) next
    if ($4 == "daemon") next
    if (index($0, "--bg-pty-host") || index($0, "--bg-spare")) next
    # somma campi separati da ":" (e "-" per i giorni) -> secondi
    t = $2; gsub("-", ":", t)
    n = split(t, p, ":"); s = 0
    for (i = 1; i <= n; i++) s = s * 60 + p[i]
    print $1, s
  }'
}

# fetch Topics in parallelo alla finestra di campionamento (self-signed TLS -> -k)
TOPICS_TMP="$(mktemp -t topics-tasks)"
trap 'rm -f "$TOPICS_TMP"' EXIT
curl -sk --max-time 2 "$TOPICS_TASKS_URL" -o "$TOPICS_TMP" 2>/dev/null &
CURL_PID=$!

A="$(snapshot)"
sleep "$INTERVAL"
B="$(snapshot)"

APERTE=$(echo "$B" | grep -c .)

# soglia di delta in secondi sull'intervallo
THR=$(awk -v p="$THRESHOLD_PCT" -v i="$INTERVAL" 'BEGIN{ print (p/100.0)*i }')

ALVORO=$(awk -v thr="$THR" '
  NR==FNR { a[$1]=$2; next }
  {
    if ($1 in a) {
      d = $2 - a[$1]
      if (d >= thr) c++
    }
  }
  END { print c + 0 }
' <(echo "$A") <(echo "$B"))

wait "$CURL_PID" 2>/dev/null
TASKS=$(grep -o '"status":"in_progress"' "$TOPICS_TMP" 2>/dev/null | wc -l | tr -d ' ')
TASKS=${TASKS:-0}

[ "$TASKS" -gt "$ALVORO" ] && ALVORO="$TASKS"
[ "$ALVORO" -gt "$APERTE" ] && ALVORO="$APERTE"
echo "$APERTE $ALVORO"
