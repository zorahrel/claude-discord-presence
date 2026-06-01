#!/bin/bash
# Conta le sessioni Claude Code.
# Stampa due interi separati da spazio:  "<APERTE> <AL_LAVORO>"
#   APERTE    = processi `claude` interattivi (escl. daemon / bg helpers)
#   AL_LAVORO = sessioni che stanno realmente consumando CPU adesso (generano
#               output / eseguono tool), misurato come DELTA di CPU-time del
#               processo su una finestra di campionamento.
#
# Perché CPU-delta e non la mtime della transcript: Claude Code scrive la
# transcript .jsonl a fine turno, quindi una sessione che sta generando ORA
# risulterebbe "idle" guardando il file. Il delta di CPU invece la becca.
# (Il %cpu di `ps` da solo è la media a vita: inutile → serve il delta.)

INTERVAL="${SAMPLE_INTERVAL:-1.2}"   # secondi di campionamento
THRESHOLD_PCT="${WORKING_THRESHOLD_PCT:-3}"  # %CPU sopra cui = "al lavoro"

# pid -> cpu_seconds (TIME di ps, formato [dd-]hh:mm:ss[.cc])
snapshot() {
  ps -axo pid,time,command | awk '
  {
    m = split($3, a, "/"); base = a[m]
    if (base != "claude") next
    if ($4 == "daemon") next
    if (index($0, "--bg-pty-host") || index($0, "--bg-spare")) next
    # somma campi separati da ":" (e "-" per i giorni) -> secondi
    t = $2; gsub("-", ":", t)
    n = split(t, p, ":"); s = 0
    for (i = 1; i <= n; i++) s = s * 60 + p[i]
    print $1, s
  }'
}

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

[ "$ALVORO" -gt "$APERTE" ] && ALVORO="$APERTE"
echo "$APERTE $ALVORO"
