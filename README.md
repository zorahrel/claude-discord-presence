# claude-discord-presence

Mostra sul **tuo profilo Discord** quante sessioni Claude Code stai spinnando sul Mac.
Rich Presence via socket IPC (`discord-ipc-0`), zero dipendenze npm.

Esempio: header **Jarvis** · `11 sessioni attive` · `Claude Code` · timer.

## Come funziona
- `count-sessions.sh` — conta i processi `claude` interattivi (esclude daemon/bg).
- `presence.mjs` — daemon: si connette all'app Discord desktop e ogni 15s aggiorna
  la presence solo se il numero è cambiato. Se le sessioni vanno a 0, pulisce la presence.
- `config.json` — `clientId` = Application ID Discord (ora: app "Jarvis", `1467514747988611174`).

## Requisiti
- **Discord desktop aperto** sul Mac (non funziona da web/mobile).
- Node (`/opt/homebrew/bin/node`).

## Gestione (launchd)
```bash
# stato
launchctl list | grep discord-presence
# restart
launchctl kickstart -k gui/$(id -u)/com.jarvis.discord-presence
# stop / disattiva
launchctl bootout gui/$(id -u)/com.jarvis.discord-presence
# riattiva
launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.jarvis.discord-presence.plist
# log
tail -f ~/.openclaw/workspace/claude-discord-presence/presence.log
```

## Aperte vs Al lavoro
`count-sessions.sh` stampa due numeri: `<aperte> <al_lavoro>`.
- **Aperte** = processi `claude` interattivi.
- **Al lavoro** = sessioni la cui transcript `.jsonl` è stata scritta negli ultimi
  `WORKING_WINDOW` secondi (default 15) → stanno generando output / girando tool.
  È il segnale affidabile di "spinning adesso"; il `%cpu` di `ps` è media a vita, inutile.

La presence mostra `N al lavoro · M aperte` + stato 🟢 quando qualcosa gira.

## Tray (SwiftBar)
Plugin: `~/Library/Application Support/SwiftBar/Plugins/claude-sessions.5s.sh`
Menubar: `✻ <aperte> ·<al_lavoro> ▶` (verde se qualcosa gira). Dropdown con elenco
sessioni + azioni (restart presence, apri log/cartella). Refresh ogni 5s.

## Icona
Icona app impostata via API (`PATCH /applications/@me`, sunburst Claude su scuro,
`icon.png`/`icon.svg`). Discord usa quella dell'app. Per un'immagine grande dedicata
nella presence serve caricare un art-asset nel Developer Portal (opzionale).
