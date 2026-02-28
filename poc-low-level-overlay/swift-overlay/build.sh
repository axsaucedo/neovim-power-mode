#!/bin/bash
set -e
cd "$(dirname "$0")"
swiftc -o power-mode-overlay \
  -framework Cocoa \
  -framework QuartzCore \
  main.swift \
  OverlayWindow.swift \
  ParticleView.swift \
  JsonReader.swift
echo "Built: ./power-mode-overlay"
