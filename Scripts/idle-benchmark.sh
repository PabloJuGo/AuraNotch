#!/bin/bash
# Consumo en reposo de Aura Notch con herramientas CLI (ps/top). NO sustituye a Instruments
# (Time Profiler, Allocations, Core Animation).
#
# Uso: Scripts/idle-benchmark.sh [ruta/al/binario] [segundos_de_medida=20]
# Sin ruta usa .build/release/AuraNotch si existe, si no .build/debug/AuraNotch.
# Arranca la app sin argumentos, espera 5 s de asentamiento, mide y la mata siempre (trap EXIT).
set -u

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BIN="${1:-}"
SECS="${2:-20}"

if [ -z "$BIN" ]; then
    for candidate in "$ROOT/.build/release/AuraNotch" "$ROOT/.build/debug/AuraNotch"; do
        if [ -x "$candidate" ]; then BIN="$candidate"; break; fi
    done
fi
if [ -z "$BIN" ] || [ ! -x "$BIN" ]; then
    echo "No hay binario AuraNotch. Compila con: swift build --product AuraNotch [--scratch-path .build-qa]" >&2
    exit 2
fi

case "$BIN" in
    */release/*) BUILD="release" ;;
    */debug/*) BUILD="debug (sin optimizar: los valores son mayores que en release)" ;;
    *) BUILD="desconocido" ;;
esac

# Segundos de CPU acumulados del proceso (ps -o time= da M:SS.ss o H:MM:SS).
cpu_seconds() {
    ps -o time= -p "$1" | awk -F'[:]' '{ s = 0; for (i = 1; i <= NF; i++) s = s * 60 + $i; printf "%.3f\n", s }'
}

"$BIN" >/dev/null 2>&1 &
PID=$!
trap 'kill "$PID" 2>/dev/null; sleep 1; kill -9 "$PID" 2>/dev/null; wait "$PID" 2>/dev/null' EXIT INT TERM

sleep 5
if ! kill -0 "$PID" 2>/dev/null; then
    echo "La app terminó antes de la medida (código de salida no capturado)." >&2
    exit 1
fi

T0=$(date +%s.%N)
CPU0=$(cpu_seconds "$PID")
RSS_MIN=""; RSS_MAX=""; RSS_LAST=""
for _ in $(seq "$SECS"); do
    sleep 1
    kill -0 "$PID" 2>/dev/null || { echo "La app murió durante la medida." >&2; exit 1; }
    RSS_LAST=$(ps -o rss= -p "$PID" | tr -d ' ')
    [ -z "$RSS_MIN" ] || [ "$RSS_LAST" -lt "$RSS_MIN" ] && RSS_MIN=$RSS_LAST
    [ -z "$RSS_MAX" ] || [ "$RSS_LAST" -gt "$RSS_MAX" ] && RSS_MAX=$RSS_LAST
done
T1=$(date +%s.%N)
CPU1=$(cpu_seconds "$PID")
THREADS=$(ps -M -p "$PID" | tail -n +2 | wc -l | tr -d ' ')

WALL=$(awk -v a="$T0" -v b="$T1" 'BEGIN { printf "%.2f", b - a }')
CPU_PCT=$(awk -v c0="$CPU0" -v c1="$CPU1" -v w="$WALL" 'BEGIN { printf "%.3f", (c1 - c0) / w * 100 }')
# Segunda lectura independiente con top (muestra 2 de 2 s = uso en ese intervalo).
TOP_LINE=$(top -l 2 -s 2 -pid "$PID" -stats pid,cpu,mem,th 2>/dev/null | awk -v p="$PID" '$1 == p { line = $0 } END { print line }')

echo "=== Aura Notch: benchmark de reposo (CLI) ==="
echo "Fecha:            $(date '+%Y-%m-%d %H:%M:%S')"
echo "macOS:            $(sw_vers -productVersion) ($(sw_vers -buildVersion)) · $(sysctl -n hw.model)"
echo "Binario:          $BIN"
echo "Build:            $BUILD"
echo "Reposo:           sin argumentos, sin interacción, asentamiento 5 s, medida ${SECS} s"
echo "CPU (ps, media):  ${CPU_PCT} % de un núcleo (CPU ${CPU0} s -> ${CPU1} s en ${WALL} s)"
echo "CPU/mem (top):    ${TOP_LINE:-no disponible}"
echo "RSS (KB):         min ${RSS_MIN} · max ${RSS_MAX} · final ${RSS_LAST}"
echo "Hilos:            ${THREADS}"
