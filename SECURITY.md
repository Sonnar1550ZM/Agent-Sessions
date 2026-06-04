# Security Policy

## Supported Versions

Agent Sessions is pre-1.0. Security fixes are handled on the `main` branch until formal releases are published.

## Reporting a Vulnerability

Please do not report vulnerabilities in public issues.

Use GitHub's private vulnerability reporting if it is enabled, or contact the maintainer through the repository owner profile. Include:

- A short description of the issue.
- Steps to reproduce.
- Impact and affected surfaces.
- Any relevant logs or hook payloads with secrets and private paths removed.

## Security Model

Agent Sessions is local-first:

- The event receiver binds to loopback by default.
- Hook scripts post local status events and fail open if the app is unavailable.
- State is stored under the current user's Application Support directory.
- The app does not require OpenAI, Anthropic, or other provider API keys.

Areas that deserve extra care include hook payload parsing, local HTTP handling, path display, transcript-derived text, state persistence, and shell script changes.
