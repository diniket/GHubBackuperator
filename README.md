![GitHub release](https://img.shields.io/github/v/release/diniket/GHubBackuperator)


\# GHub Backuperator (ZIP + GUI) 🇮🇹



Utility Windows (.bat) per fare backup e restore delle impostazioni/profili di Logitech G Hub senza account.



\## Funzioni

\- Backup in un unico file `.zip`

\- Restore da `.zip`

\- Scelta percorso con finestre “Salva” / “Apri”

\- Ricorda l’ultimo percorso usato (config in `%LocalAppData%`)

\- Chiude i processi G Hub prima di operare

\- Richiede privilegi amministratore (ProgramData)



\## Cosa viene salvato

\- `%LocalAppData%\\LGHUB\\`

\- `%AppData%\\G HUB\\`

\- `%AppData%\\lghub\\`

\- `%ProgramData%\\LGHUB\\`



\## Come si usa

Esegui lo script come amministratore e scegli:

\- `C` = crea backup

\- `R` = ripristina backup



\## Note

Usa PowerShell integrato (Compress-Archive / Expand-Archive) e WinForms per le finestre.



