# Postgrace

A native macOS PostgreSQL client.

![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)

## Requirements

- macOS 14+
- Xcode 15+

## Build Instructions

You can build the project in two ways:
1. Open `Package.swift` in Xcode and press `Cmd+R` to build and run.
2. From the command line, run:
   ```bash
   swift build
   ```

## Packaging & Releases

To package a standalone `.app` bundle and installer `.dmg`:
```bash
VERSION=0.1.1 ./scripts/build_dmg.sh
```

All build artifacts (`Postgrace.dmg`, `Postgrace-<version>.dmg`, `Postgrace-<version>.zip`, and `SHA256SUMS.txt`) will be generated inside the `dist/` directory.

For instructions on releasing to GitHub, see [docs/RELEASING.md](docs/RELEASING.md).

