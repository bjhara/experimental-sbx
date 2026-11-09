#!/usr/bin/env bash
# Runs inside the sandbox (Debian 13, user "agent" with sudo) before Claude starts.
# Installs the project's toolchain. Edit this for other stacks (Python, Node.js, ...).
set -euo pipefail

if ! command -v java >/dev/null || ! command -v mvn >/dev/null; then
  echo "Installing JDK 25 and Maven..."
  sudo apt-get update -qq
  sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq openjdk-25-jdk-headless maven >/dev/null
fi

java -version 2>&1 | grep -v JAVA_TOOL_OPTIONS | head -1
mvn -v 2>/dev/null | head -1
