#!/usr/bin/env python3
"""Keep the opus-codex-flow block in the global CLAUDE.md (<CLAUDE_CONFIG_DIR or ~/.claude>/CLAUDE.md).

sync    (default; the SessionStart hook runs it) refresh the block if it is there; add it once
        on first run; never re-add it after it was removed.
add     add or refresh the block now, even after a removal.
remove  delete the block and keep it from coming back.
OPUS_CODEX_FLOW_NO_CLAUDE_MD=1 stops sync from touching the file.

The block sits between a begin line and an end line. If those lines are missing, duplicated or
out of order the file is left alone. Hook stdout reaches the session, so sync prints one JSON
`systemMessage` (shown to the user, not to Claude) when it writes, and never fails the session.
"""
import json
import os
import re
import shutil
import sys
import tempfile

BEGIN = "<!-- opus-codex-flow:begin (managed by the opus-codex-flow plugin; /opus-codex-flow uninstall removes it) -->"
END = "<!-- opus-codex-flow:end -->"
BEGIN_RE = re.compile(r"^<!-- opus-codex-flow:begin\b.*-->[ \t\r]*$", re.M)
END_RE = re.compile(r"^<!-- opus-codex-flow:end -->[ \t\r]*$", re.M)


def say(message, as_json):
    print(json.dumps({"systemMessage": message}, ensure_ascii=False) if as_json else message)


def region(text):
    """Return (start, end) of the block, None when absent; raise ValueError when malformed."""
    begins, ends = list(BEGIN_RE.finditer(text)), list(END_RE.finditer(text))
    if not begins and not ends:
        return None
    if len(begins) != 1 or len(ends) != 1 or begins[0].start() > ends[0].start():
        raise ValueError("opus-codex-flow markers in CLAUDE.md are missing, duplicated or out of order")
    end = ends[0].end()
    if text.startswith("\r\n", end):
        end += 2
    elif text.startswith("\n", end):
        end += 1
    return begins[0].start(), end


def main():
    action = sys.argv[1] if len(sys.argv) > 1 else "sync"
    if action not in ("sync", "add", "remove"):
        sys.exit("usage: sync-claude-md.py [sync|add|remove]")
    if action == "sync" and os.environ.get("OPUS_CODEX_FLOW_NO_CLAUDE_MD") == "1":
        return
    hook = action == "sync"
    config = os.path.expanduser(os.environ.get("CLAUDE_CONFIG_DIR") or "~/.claude")
    target = os.path.realpath(os.path.join(config, "CLAUDE.md"))
    state = os.path.join(config, "opus-codex-flow", ".claude-md-offered")
    if not os.path.isdir(os.path.dirname(target)):
        return

    text = ""
    if os.path.exists(target):
        with open(target, encoding="utf-8", newline="") as f:
            text = f.read()
    nl = "\r\n" if "\r\n" in text else "\n"
    with open(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "claude-md-block.md"), encoding="utf-8") as f:
        body = f.read().strip().replace("\r\n", "\n").replace("\n", nl)
    block = f"{BEGIN}{nl}{body}{nl}{END}{nl}"

    found = region(text)
    if action == "remove":
        new = text[: found[0]] + text[found[1]:] if found else text
        new = new.rstrip("\r\n") + nl if new.strip() else ""
    elif found:
        new = text[: found[0]] + block + text[found[1]:]
    elif action == "sync" and os.path.exists(state):
        return  # offered before and since removed: respect that
    else:
        new = text + (nl if text and not text.endswith(nl + nl) else "") + block

    if new != text:
        if text:
            backup = target + ".opus-codex-flow.bak"
            if not os.path.exists(backup):
                shutil.copy2(target, backup)
        fd, tmp = tempfile.mkstemp(dir=os.path.dirname(target), prefix=".CLAUDE.md.")
        with os.fdopen(fd, "w", encoding="utf-8", newline="") as f:
            f.write(new)
        if os.path.exists(target):
            shutil.copymode(target, tmp)
        os.replace(tmp, target)
        verb = "removed the delegation block from" if action == "remove" else ("updated" if found else "added") + " the delegation block in"
        say(f"opus-codex-flow {verb} {target}. Text between its markers is managed by the plugin; "
            "/opus-codex-flow uninstall removes it; OPUS_CODEX_FLOW_NO_CLAUDE_MD=1 stops updates.", hook)
    os.makedirs(os.path.dirname(state), exist_ok=True)
    open(state, "a").close()


if __name__ == "__main__":
    try:
        main()
    except Exception as e:  # a hook must never break the session
        say(f"opus-codex-flow: CLAUDE.md sync skipped: {e}", True)
