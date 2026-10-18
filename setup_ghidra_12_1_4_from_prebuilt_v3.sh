#!/usr/bin/env bash
# =============================================================================
# setup_ghidra_12_1_4_from_prebuilt_v3.sh
# -----------------------------------------------------------------------------
# Zweck:
#   Installiert das vorgebaute Ghidra 12.1.4 aus dem oeffentlichen Repo
#   absret111/ghidra-12.1.4-build nach GHIDRA_INSTALL_DIR
#   (Standard: /root/.local/opt/ghidra_12.1.4_PUBLIC).
#
# Hintergrund:
#   Setup-Scripts der Cloud-Umgebung muessen in ca. 5 Minuten fertig sein,
#   sonst haengt der Session-Start bzw. die Umgebung wird nicht gecacht.
#   Der Bau aus dem Quellcode (v1/v2) dauert ca. 18 Minuten und ist daher
#   ungeeignet. Das Repo enthaelt das fertige Build als gesplittetes tar.gz
#   (6 Teile < 100 MB, Pruefsummen in SHA256SUMS). Klonen + Entpacken: ca. 1-2 min.
#   Der Neubau aus dem Quellcode ist nur noch bei einem Versionswechsel noetig
#   (setup_ghidra_12_1_4_from_source_v2.sh, ausserhalb des Setup-Scripts).
#
# Idempotenz:
#   Ist Ghidra 12.1.4 bereits installiert, endet das Script sofort.
#
# Versionshistorie:
#   v1 (2026-10-17)  Bau aus Quellcode (Datei setup_ghidra_..._from_source_v1)
#   v2 (2026-10-17)  Bau aus Quellcode mit --no-daemon und Zeitlimits
#   v3 (2026-10-18)  Installation aus vorgebautem Archiv im eigenen Repo
#
# Gliederung:
#   0. Parameter
#   1. Vorabpruefung (bereits installiert?)
#   2. Archiv-Repo klonen und Pruefsummen pruefen
#   3. Entpacken, umbenennen, aufraeumen
# =============================================================================

set -euo pipefail

# --- 0. Parameter -------------------------------------------------------------
GHIDRA_VERSION="12.1.4"                                            # Ziel-Version
PREBUILT_REPO_URL="https://github.com/absret111/ghidra-12.1.4-build" # Archiv-Repo (oeffentlich)
INSTALL_DIR="${GHIDRA_INSTALL_DIR:-/root/.local/opt/ghidra_${GHIDRA_VERSION}_PUBLIC}"  # Zielpfad
WORK_DIR="$(mktemp -d /tmp/ghidra_prebuilt.XXXX)"                   # temporaerer Klon
ARCHIVE_ROOT_NAME="ghidra_${GHIDRA_VERSION}_PUBLIC"                 # Wurzelordner im Archiv
CLONE_TIMEOUT="4m"                                                 # Zeitlimit fuer den Klon

log() { echo "[setup_ghidra $(date +%H:%M:%S)] $*"; }
trap 'rm -rf "${WORK_DIR}"' EXIT                                   # Klon immer entfernen

# --- 1. Vorabpruefung ---------------------------------------------------------
if grep -qs "^application.version=${GHIDRA_VERSION}$" "${INSTALL_DIR}/Ghidra/application.properties"; then
    log "Ghidra ${GHIDRA_VERSION} bereits in ${INSTALL_DIR} installiert - nichts zu tun."
    exit 0
fi

# --- 2. Archiv-Repo klonen und pruefen ------------------------------------------
log "Klone ${PREBUILT_REPO_URL}"
timeout "${CLONE_TIMEOUT}" git -c advice.detachedHead=false clone -q --depth 1 \
    "${PREBUILT_REPO_URL}" "${WORK_DIR}/repo"
(cd "${WORK_DIR}/repo" && sha256sum --quiet -c SHA256SUMS)          # bricht bei Abweichung ab
log "Pruefsummen ok"

# --- 3. Entpacken ----------------------------------------------------------------
mkdir -p "${WORK_DIR}/extract" "$(dirname "${INSTALL_DIR}")"
cat "${WORK_DIR}"/repo/ghidra_${GHIDRA_VERSION}_linux_x86_64.tar.gz.part_* \
    | tar -xzf - -C "${WORK_DIR}/extract"
rm -rf "${INSTALL_DIR}"
mv "${WORK_DIR}/extract/${ARCHIVE_ROOT_NAME}" "${INSTALL_DIR}"
log "Fertig: $(grep -E '^application.(version|release.name)=' "${INSTALL_DIR}/Ghidra/application.properties" | tr '\n' ' ')"
