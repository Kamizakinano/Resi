#!/bin/bash
# Avvia l'app nel simulatore con dati demo e salva uno screenshot per ogni schermata.
set -u
UDID="$1"
APP=$(find build/sim/Build/Products -name "ReturnMate.app" -path "*iphonesimulator*" | head -1)
mkdir -p out/screens
xcrun simctl boot "$UDID" 2>/dev/null || true
xcrun simctl bootstatus "$UDID" -b
xcrun simctl status_bar "$UDID" override --time "9:41" --batteryState charged --batteryLevel 100 || true
xcrun simctl install "$UDID" "$APP"
for SCREEN in home detail add confirm calendar search stats settings premium returnflow; do
  xcrun simctl terminate "$UDID" com.returnmate.app 2>/dev/null || true
  xcrun simctl launch "$UDID" com.returnmate.app -demoData YES -screen "$SCREEN"
  sleep 6
  xcrun simctl io "$UDID" screenshot "out/screens/$SCREEN.png"
done
