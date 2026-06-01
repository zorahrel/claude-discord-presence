# claude-discord-presence

Mostra sul **tuo profilo Discord** quante sessioni Claude Code stai spinnando sul Mac,
e quante stanno *davvero* lavorando in quel momento. Rich Presence via socket IPC
(`discord-ipc-0`), **zero dipendenze npm**. Opzionale: indicatore in menubar (SwiftBar).

Esempio nel card "Playing": `5 al lavoro · 10 aperte` · `🟢 Claude Code in esecuzione` · timer.

## Componenti
- `count-sessions.sh` — stampa `<aperte> <al_lavoro>`.
- `presence.mjs` — daemon: si connette all'app Discord desktop via IPC e ogni 15s
  aggiorna la presence (solo se cambia). A 0 sessioni pulisce la presence.
- `config.json` — `clientId` (Application ID Discord), `largeImage` (URL/asset icona).
- `claude-sessions.5s.sh` — plugin SwiftBar per la menubar.
- `install.sh` — installa il servizio launchd + il plugin SwiftBar puntando a questa cartella.

## Aperte vs Al lavoro
- **Aperte** = processi `claude` interattivi (esclude daemon / bg helpers).
- **Al lavoro** = sessioni che stanno realmente consumando CPU *adesso* (generano
  output / eseguono tool), misurato come **delta di CPU-time** del processo su una
  finestra di campionamento (~1.2s).
  Niente mtime della transcript: Claude Code la scrive a fine turno, quindi una
  sessione che sta generando ORA risulterebbe idle. Il `%cpu` di `ps` da solo è la
  media a vita: serve il *delta*. Soglia regolabile via `WORKING_THRESHOLD_PCT` (default 3%).

## Requisiti
- **Discord desktop aperto** sul Mac (il Rich Presence non esiste da web/mobile).
- Node (`/opt/homebrew/bin/node`).
- Un'**Application ID** Discord in `config.json` (qualsiasi app del Developer Portal;
  l'header del card mostra il nome di quell'app).

## Installazione
```bash
./install.sh
```
Genera `~/Library/LaunchAgents/com.jarvis.discord-presence.plist` e il plugin SwiftBar
puntando a questa cartella, avvia il daemon e (se presente) SwiftBar.

## Gestione (launchd)
```bash
launchctl list | grep discord-presence                              # stato
launchctl kickstart -k gui/$(id -u)/com.jarvis.discord-presence     # restart
launchctl bootout   gui/$(id -u)/com.jarvis.discord-presence        # stop
tail -f presence.log                                                # log
```

## Icona nel card (large_image)
L'immagine grande del card NON è l'icona dell'app: in Rich Presence arriva solo da
`large_image`, che può essere:
- un **art-asset** caricato nel Developer Portal (Rich Presence → Art Assets), oppure
- un **URL diretto** a un'immagine pubblica (risolto client-side su Discord recenti).

Qui si usa la seconda via: `config.json.largeImage` punta a `icon.png` servito via raw
GitHub (URL permanente). `external-assets` API è vietata ai bot, quindi serve un URL pubblico.
