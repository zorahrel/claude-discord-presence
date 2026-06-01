#!/bin/bash
# <xbar.title>Claude Sessions</xbar.title>
# <xbar.desc>Sessioni Claude Code aperte / al lavoro</xbar.desc>
# <swiftbar.runInBash>true</swiftbar.runInBash>
#
# Menubar: ✻ <aperte> (·<al_lavoro> ▶ se >0). Refresh ogni 5s (dal nome file).
# __DIR__ viene sostituito da install.sh con il path del repo.

DIR="__DIR__"
read -r OPEN WORKING < <(bash "$DIR/count-sessions.sh" 2>/dev/null)
OPEN=${OPEN:-0}; WORKING=${WORKING:-0}

if [ "$OPEN" = "0" ]; then
  echo "✻ –"
else
  if [ "$WORKING" -gt 0 ]; then
    echo "✻ $OPEN ·$WORKING ▶ | color=#22c55e"
  else
    echo "✻ $OPEN | color=#9ca3af"
  fi
fi

echo "---"
echo "Claude Code | font=Menlo"
echo "Aperte: $OPEN"
echo "Al lavoro: $WORKING"
echo "---"
echo "Dettaglio sessioni | font=Menlo"
ps -axo pid,command | awk '
{
  n=split($2,a,"/"); base=a[n]
  if(base!="claude") next
  if($3=="daemon") next
  if(index($0,"--bg-")) next
  label=$3" "$4
  printf "  %s  %s\n", $1, label
}' | while read -r line; do echo "$line | font=Menlo size=11"; done
echo "---"
echo "Restart presence Discord | bash=/bin/launchctl param1=kickstart param2=-k param3=gui/$(id -u)/com.jarvis.discord-presence terminal=false"
echo "Apri cartella | bash=/usr/bin/open param1=$DIR terminal=false"
echo "Log presence | bash=/usr/bin/open param1=$DIR/presence.log terminal=false"
