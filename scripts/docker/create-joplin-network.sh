#!/usr/bin/env bash
set -euo pipefail

docker network inspect joplin-net >/dev/null 2>&1 || \
docker network create joplin-net
