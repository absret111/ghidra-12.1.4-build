# Ghidra 12.1.4 – vorgebaut fuer Linux x86_64

Inhalt: Ghidra 12.1.4, aus dem offiziellen Quellcode gebaut
(Tag `Ghidra_12.1.4_build`, Commit `8b6bbb857accdfa20dc5b2f5dea471178c2e9fbc`,
Daten aus `ghidra-data` Tag `Ghidra_12.1.4`), mit `gradle buildGhidra`.
`application.release.name=DEV` (Eigenbau). Ohne PostgreSQL-Quellarchiv (BSim)
und ohne Eclipse CDT (GhidraDev).

Zweck: schnelle Installation im Setup-Script der Claude-Code-Cloud-Umgebung
„REA-Ghidra“ (Bau dauert ~18 min, Entpacken ~15 s).

## Installation

```bash
git clone --depth 1 https://github.com/absret111/ghidra-12.1.4-build
cd ghidra-12.1.4-build
sha256sum -c SHA256SUMS
cat ghidra_12.1.4_linux_x86_64.tar.gz.part_* | tar -xzf - -C /root/.local/opt
# Ergebnis: /root/.local/opt/ghidra_12.1.4_PUBLIC
```

## Lizenz

Ghidra steht unter der Apache License 2.0 (National Security Agency).
LICENSE, NOTICE und die Lizenzen der Drittkomponenten liegen im Archiv
unter `ghidra_12.1.4_PUBLIC/LICENSE` bzw. `ghidra_12.1.4_PUBLIC/licenses/`.
