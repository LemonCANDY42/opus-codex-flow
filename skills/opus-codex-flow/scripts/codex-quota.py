#!/usr/bin/env python3
"""Decide whether Codex quota is clearly ample, using CodexBar (`codexbar usage --provider codex`).

Prints `QUOTA: ample|tight|unknown` plus the facts behind it. Always exits 0 once it has
a verdict; any unreadable or odd data gives `unknown`, never a traceback.

Weekly window (`secondary`), with CodexBar's pace (`pace.secondary.expectedUsedPercent`,
`willLastToReset`) when present and a linear estimate from the window otherwise:
  tight   if the tier is free/go, the short window is at 80%+, usage will not last to the
          reset, or usage runs more than MAX_AHEAD points ahead of pace
  tight   if the remaining share is below the floor
  ample   otherwise
  unknown for an unrecognised tier, missing or stale window data, or no CodexBar

Tier limits (floor = minimum remaining %, MAX_AHEAD = points ahead of pace):
  pro: floor 40, MAX_AHEAD 10     plus/team/business/enterprise/edu/prolite: floor 60, MAX_AHEAD 5
End of window: in the last quarter, headroom that is about to expire counts for more. When
usage is at least 10 points behind pace, the floor drops to 15.
Override the tier's floor and MAX_AHEAD with OPUS_CODEX_FLOW_MIN_REMAINING and
OPUS_CODEX_FLOW_MAX_AHEAD (percent points).
"""
import json
import os
import subprocess
import sys
from datetime import datetime, timezone
from typing import NoReturn

LIMITS = {"pro": (40, 10)}
OTHER_PAID = {"plus", "team", "business", "enterprise", "edu", "education", "prolite"}
OTHER_PAID_LIMITS = (60, 5)
NEVER_AMPLE = {"free", "go"}
END_QUARTER = 25   # percent of the window left
END_RESERVE = 10   # points behind pace that count as expiring headroom
END_FLOOR = 15


def verdict(kind: str, reason: str, facts=()) -> NoReturn:
    print(f"QUOTA: {kind}")
    for line in facts:
        print(line)
    print(f"reason: {reason}")
    sys.exit(0)


def read_entry():
    try:
        out = subprocess.run(
            ["codexbar", "usage", "--provider", "codex", "--format", "json"],
            capture_output=True, text=True, timeout=90, check=False,
        )
    except FileNotFoundError:
        verdict("unknown", "codexbar not found; install CodexBar to enable the quota check")
    except subprocess.TimeoutExpired:
        verdict("unknown", "codexbar timed out")
    try:
        return next(e for e in json.loads(out.stdout) if isinstance(e, dict) and e.get("usage"))
    except (ValueError, StopIteration, TypeError):
        verdict("unknown", "codexbar returned no Codex usage; check that the provider is enabled and logged in")


def assess(entry):
    usage = entry["usage"]
    tier = str(usage.get("loginMethod") or "").strip().lower()
    week = usage.get("secondary") or {}
    used = float(week["usedPercent"])
    window = float(week["windowMinutes"]) * 60
    resets = datetime.fromisoformat(week["resetsAt"].replace("Z", "+00:00"))
    if resets.tzinfo is None:
        resets = resets.replace(tzinfo=timezone.utc)
    left = (resets - datetime.now(timezone.utc)).total_seconds()
    facts_tier = [f"tier: {tier or 'unknown'}"]
    if window <= 0 or left <= 0 or left > window:
        verdict("unknown", "weekly window data looks stale or inconsistent", facts_tier)

    time_left = left / window * 100
    pace = (entry.get("pace") or {}).get("secondary") or {}
    expected = pace.get("expectedUsedPercent")
    if not isinstance(expected, (int, float)):
        expected = min(100.0, max(0.0, 100 - time_left))
    ahead = used - expected
    facts = facts_tier + [
        f"weekly: {used:.0f}% used, {expected:.0f}% expected by now "
        f"({ahead:+.0f} points vs pace), {time_left:.0f}% of the window left, resets {week['resetsAt']}",
    ]

    if tier in NEVER_AMPLE:
        verdict("tight", f"{tier} tier is never treated as ample", facts)
    if tier in LIMITS:
        floor, max_ahead = LIMITS[tier]
    elif tier in OTHER_PAID:
        floor, max_ahead = OTHER_PAID_LIMITS
    else:
        verdict("unknown", "unrecognised subscription tier", facts)
    floor = float(os.environ.get("OPUS_CODEX_FLOW_MIN_REMAINING", str(floor)))
    max_ahead = float(os.environ.get("OPUS_CODEX_FLOW_MAX_AHEAD", str(max_ahead)))

    short = usage.get("primary")
    if short and float(short.get("usedPercent", 0)) >= 80:
        verdict("tight", f"short window {float(short['usedPercent']):.0f}% used", facts)
    if pace.get("willLastToReset") is False:
        verdict("tight", "CodexBar projects usage will not last to the reset", facts)
    if ahead > max_ahead:
        verdict("tight", f"usage runs {ahead:.0f} points ahead of pace (limit {max_ahead:.0f}) for {tier}", facts)

    note = ""
    if time_left <= END_QUARTER and -ahead >= END_RESERVE:
        floor = min(floor, END_FLOOR)
        note = f"; end of window with {-ahead:.0f} points of expiring headroom, floor lowered to {floor:.0f}%"
    if 100 - used < floor:
        verdict("tight", f"remaining {100 - used:.0f}% is below {floor:.0f}% for {tier}", facts)
    verdict("ample", f"remaining {100 - used:.0f}% and {ahead:+.0f} points vs pace are inside the {tier} limits{note}", facts)


def main():
    try:
        assess(read_entry())
    except Exception as e:  # odd data must give a verdict, not a traceback
        verdict("unknown", f"could not interpret codexbar output ({type(e).__name__}: {e})")


if __name__ == "__main__":
    main()
