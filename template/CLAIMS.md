# CLAIMS.md - The Decay Term

_Curation decides what gets written. This decides what stops being true._

---

> **Why this file exists:** `MEMORY.md` has no expiry. A line that was true when you wrote it and
> quietly went false afterward keeps full strength forever, and it keeps it in the file you load
> every session. Nothing in the system notices. See [the rot](https://nubzparmesan.github.io/minnow-oc/decay/).
>
> This is **not** a list of everything you know. It is the short list of claims that would actually
> cost you something if they went false without you noticing. If it is longer than a screen, it is
> a log again and you will stop reading it.

## How to use it

1. When you verify something load-bearing against reality, add a row.
2. Read this file at session open, with the rest of your loading ritual.
3. When something is due: **go and check it**, then update `verified`.
4. **Never update `verified` without actually re-checking.** Resetting the clock on an unread claim
   preserves the error and makes it look maintained. That is the exact failure this file exists to
   catch, not a shortcut through it.

## The claims

| id | claim | verified | recheck | how to re-check | why it matters |
|---|---|---|---|---|---|
| `example-hardware` | The thing is NOT built. Parts only, nothing assembled. | 2026-01-01 | 30d | Go and look at the hardware. Do not infer it from a note. | Three drafts depend on what can honestly be claimed about it. |
| `example-service` | Service X is running with start-type Automatic. | 2026-01-01 | 45d | Query the service directly; do not trust any note, including this one. | Two files disagreed about this for two weeks and the confident one was wrong. |

_Delete both examples once you have real rows._

---

## Rules that keep it honest

- **A zero is evidence about a string, not about a habit.** Searching and finding nothing proves
  something about the spelling you searched. Check the variants before concluding anything is absent.
- **Age is a prompt to verify, never a licence to rewrite.** Stale is not the same as wrong.
- **If a claim is dead, say so ABOVE it, not below.** A correction underneath the thing it corrects
  is weaker than the thing it corrects, because a reader who stops early never reaches it.
- **The warm entries rot first.** Anything phrased as care rather than fact gets reinforced by every
  future session and audited by none. Register those too.
- **Retire rows.** A claim that stopped mattering should leave this file, not sit here forever
  costing a re-check.
