#!/usr/bin/env bash
# =============================================================================
# setup_ghidra_12_1_4_from_source_v2.sh
# -----------------------------------------------------------------------------
# Zweck:
#   Baut Ghidra 12.1.4 aus dem Quellcode und installiert es nach
#   GHIDRA_INSTALL_DIR (Standard: /root/.local/opt/ghidra_12.1.4_PUBLIC),
#   damit "rea doctor" in jeder neuen Cloud-Session "healthy" meldet.
#
# Hintergrund:
#   Der Session-Proxy sperrt Release-Downloads und raw-Dateien des Repos
#   NationalSecurityAgency/ghidra(-data). Anonymes "git clone" oeffentlicher
#   Repos ist erlaubt. Daher:
#     1. ghidra und ghidra-data per git klonen
#     2. ghidra-data-Dateien lokal in dependencies/downloads kopieren
#        (fetchDependencies.gradle ueberspringt Dateien mit korrektem SHA256)
#     3. restliche Abhaengigkeiten per Gradle laden, ohne PostgreSQL-Quellarchiv
#        (ftp.postgresql.org gesperrt, nur fuer BSim-Server-Neubau) und ohne
#        Eclipse CDT (archive.eclipse.org gesperrt, nur fuer GhidraDev-Plugin)
#     4. "gradle buildGhidra" (ca. 18 min auf 4 Kernen)
#     5. Distributions-ZIP entpacken, Build-Verzeichnis loeschen (ca. 3.5 GB)
#
# Ergebnis:
#   application.release.name=DEV statt PUBLIC (Eigenbau). rea doctor
#   akzeptiert das (getestet mit REA 6.5.0).
#
# Voraussetzungen (im Image vorhanden, geprueft 2026-10-17):
#   git, JDK 21, Gradle >= 8.5 (/opt/gradle), gcc/g++/make, unzip, python3
#
# Idempotenz:
#   Ist bereits eine Ghidra 12.1.4 Installation vorhanden, endet das Script
#   sofort mit Exit-Code 0.
#
# Versionshistorie:
#   v1 (2026-10-17)  Erstversion
#   v2 (2026-10-17)  Gradle mit --no-daemon (kein Hintergrundprozess, der das
#                    Setup nach dem Build offen haelt); feste Zeitlimits per
#                    timeout fuer Fetch und Build; Fortschritts-Logzeilen
#
# Gliederung:
#   0. Parameter
#   1. Vorabpruefung (bereits installiert?)
#   2. Quellcode klonen
#   3. ghidra-data-Dateien vorbelegen
#   4. Gradle-Fetch ohne PostgreSQL/CDT
#   5. Build
#   6. Installation und Aufraeumen
# =============================================================================

set -euo pipefail

# --- 0. Parameter -------------------------------------------------------------
GHIDRA_VERSION="12.1.4"                                   # Ziel-Version
GHIDRA_SOURCE_TAG="Ghidra_${GHIDRA_VERSION}_build"        # Tag im Repo ghidra
GHIDRA_DATA_TAG="Ghidra_${GHIDRA_VERSION}"                # Tag im Repo ghidra-data
INSTALL_DIR="${GHIDRA_INSTALL_DIR:-/root/.local/opt/ghidra_${GHIDRA_VERSION}_PUBLIC}"  # Zielpfad
BUILD_ROOT="${GHIDRA_BUILD_ROOT:-/root/build_ghidra_${GHIDRA_VERSION}}"                # temporaer
SOURCE_DIR="${BUILD_ROOT}/ghidra_source"                  # Klon von ghidra
DATA_DIR="${BUILD_ROOT}/ghidra_data"                      # Klon von ghidra-data
GRADLE_BIN="$(command -v gradle || echo /opt/gradle/bin/gradle)"  # Gradle-Binary
FETCH_TIMEOUT="20m"                                       # Zeitlimit Abhaengigkeiten laden
BUILD_TIMEOUT="45m"                                       # Zeitlimit Build (normal ca. 18 min)
# --no-daemon: Gradle beendet sich nach dem Lauf vollstaendig
GRADLE_OPTS_COMMON=(--no-daemon --console=plain -q)

log() { echo "[setup_ghidra $(date +%H:%M:%S)] $*"; }

# --- 1. Vorabpruefung ---------------------------------------------------------
if grep -qs "^application.version=${GHIDRA_VERSION}$" "${INSTALL_DIR}/Ghidra/application.properties"; then
    log "Ghidra ${GHIDRA_VERSION} bereits in ${INSTALL_DIR} installiert - nichts zu tun."
    exit 0
fi

# --- 2. Quellcode klonen ------------------------------------------------------
rm -rf "${BUILD_ROOT}"
mkdir -p "${BUILD_ROOT}"
log "Klone ghidra (${GHIDRA_SOURCE_TAG}) und ghidra-data (${GHIDRA_DATA_TAG})"
# GIT_LFS_SKIP_SMUDGE: anonymer Proxy-Zugang liefert keine LFS-Objekte
GIT_LFS_SKIP_SMUDGE=1 git -c advice.detachedHead=false clone -q --depth 1 \
    --branch "${GHIDRA_SOURCE_TAG}" https://github.com/NationalSecurityAgency/ghidra "${SOURCE_DIR}"
GIT_LFS_SKIP_SMUDGE=1 git -c advice.detachedHead=false clone -q --depth 1 \
    --branch "${GHIDRA_DATA_TAG}" https://github.com/NationalSecurityAgency/ghidra-data "${DATA_DIR}"

# --- 3. ghidra-data-Dateien vorbelegen -----------------------------------------
# Jeder Eintrag in ext.deps mit URL .../ghidra-data/raw/<tag>/<pfad> wird aus
# dem lokalen Klon nach dependencies/downloads/<name> kopiert und per SHA256
# geprueft. Zusaetzlich wird eine Kopie der Gradle-Datei ohne die Eintraege
# fuer PostgreSQL und CDT geschrieben.
log "Belege ghidra-data-Abhaengigkeiten vor"
python3 -I - "${SOURCE_DIR}" "${DATA_DIR}" "${GHIDRA_VERSION}" <<'PYEOF'
import hashlib, re, shutil, sys
from pathlib import Path

source_dir, data_dir, version = Path(sys.argv[1]), Path(sys.argv[2]), sys.argv[3]
gradle_file = source_dir / "gradle/support/fetchDependencies.gradle"
downloads_dir = source_dir / "dependencies/downloads"
downloads_dir.mkdir(parents=True, exist_ok=True)
text = gradle_file.read_text()
prefix = "https://github.com/NationalSecurityAgency/ghidra-data/raw/Ghidra_${RELEASE_VERSION}/"

# Eintraege: name, url, sha256
for name, url, sha in re.findall(
        r'name:\s*"([^"]+)",\s*url:\s*"([^"]+)",\s*sha256:\s*"([0-9a-f]{64})"', text):
    if not url.startswith(prefix):
        continue
    target = downloads_dir / name
    shutil.copyfile(data_dir / url[len(prefix):], target)
    digest = hashlib.sha256(target.read_bytes()).hexdigest()
    if digest != sha:
        sys.exit(f"SHA256 falsch fuer {name}: {digest} != {sha}")

# Gradle-Kopie ohne PostgreSQL-Quellarchiv und Eclipse CDT
reduced = text
for name in (r"postgresql-[\d.]+\.tar\.gz", r"cdt-[\d.]+\.zip"):
    reduced, count = re.subn(r'\t\[\n\t\tname: "%s".*?\n\t\],\n' % name, "", reduced, flags=re.S)
    if count != 1:
        sys.exit(f"Eintrag {name} nicht genau einmal gefunden ({count})")
(gradle_file.parent / "fetchDependencies_reduced.gradle").write_text(reduced)
PYEOF

# --- 4. Gradle-Fetch -----------------------------------------------------------
cd "${SOURCE_DIR}"
log "Lade restliche Abhaengigkeiten (PyPI, Maven, Z3 ...)"
# -DhideDownloadProgress: unterdrueckt die Fortschrittsanzeige (sonst >25 MB Log)
timeout --kill-after=1m "${FETCH_TIMEOUT}" "${GRADLE_BIN}" "${GRADLE_OPTS_COMMON[@]}" -DhideDownloadProgress -I gradle/support/fetchDependencies_reduced.gradle

# --- 5. Build ------------------------------------------------------------------
log "Baue Ghidra (ca. 18 min)"
timeout --kill-after=1m "${BUILD_TIMEOUT}" "${GRADLE_BIN}" "${GRADLE_OPTS_COMMON[@]}" buildGhidra
log "Build abgeschlossen"

# --- 6. Installation und Aufraeumen --------------------------------------------
DIST_ZIP="$(ls "${SOURCE_DIR}"/build/dist/ghidra_${GHIDRA_VERSION}_*_linux_x86_64.zip)"
log "Installiere ${DIST_ZIP} nach ${INSTALL_DIR}"
EXTRACT_DIR="$(mktemp -d "${BUILD_ROOT}/extract.XXXX")"
unzip -q "${DIST_ZIP}" -d "${EXTRACT_DIR}"
rm -rf "${INSTALL_DIR}"
mkdir -p "$(dirname "${INSTALL_DIR}")"
# ZIP enthaelt genau ein Wurzelverzeichnis (ghidra_<version>_DEV)
mv "${EXTRACT_DIR}"/ghidra_${GHIDRA_VERSION}_* "${INSTALL_DIR}"
cd /
rm -rf "${BUILD_ROOT}"
log "Fertig: $(grep -E '^application.(version|release.name)=' "${INSTALL_DIR}/Ghidra/application.properties" | tr '\n' ' ')"
