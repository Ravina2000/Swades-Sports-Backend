#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
dart pub get
dart run bin/server.dart "$@"
