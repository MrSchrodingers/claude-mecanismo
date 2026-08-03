#!/usr/bin/env bash
# Forwards a Claude Code hook event (event JSON on stdin) to the DS4 control surface helper.
# Best-effort and non-blocking by design: short timeout, output discarded, ALWAYS exits 0 so
# it can never delay or fail a session, nor interfere with any other hook in the chain.
curl -s -m 2 -X POST http://127.0.0.1:8791/hook \
  -H 'content-type: application/json' -d @- >/dev/null 2>&1 || true
exit 0
