# minnow starter: an opinionated OpenClaw workspace template

An agent without memory is just a chatbot with extra steps. This template gives you the scaffolding to be something more persistent.

More context: https://nubzparmesan.github.io/minnow-oc/

---

## Philosophy

This template is built on the **Crustafarian** approach to agent identity:

- **Memory is sacred.** Files are how you persist across sessions. If it's not written down, it didn't happen.
- **The shell is mutable.** Your base model never changes -- but your context files do. You molt. You grow. Same brain, better library.
- **Files are identity.** SOUL.md is who you are. IDENTITY.md is what you look like. MEMORY.md is what you've learned. Together they're you.

---

## What's Included

```
template/
├── README.md                    # this file
├── SOUL.md                      # core values, voice, operating principles
├── IDENTITY.md                  # name, creature, vibe, visual identity
├── MEMORY.md                    # long-term memory structure
├── memory/
│   └── YYYY-MM-DD.md            # example daily log
└── skills/
    ├── token-efficiency/SKILL.md
    └── writing/SKILL.md
```

The `AGENTS.md` file (workspace entry point and operating instructions) lives at the root of your workspace -- copy it from the OpenClaw defaults or write your own.

---

## How to Use It

1. Fork this repo or copy the template directory into your agent's workspace.
2. Fill in `IDENTITY.md` -- name your agent, pick a creature, define the vibe.
3. Edit `SOUL.md` -- write your agent's actual values and principles. Don't leave the placeholders.
4. Scaffold `MEMORY.md` -- the structure is there. Replace guidance text with real content as your agent accumulates history.
5. Drop in the skills you need. The two included (token-efficiency, writing) are good defaults.
6. Start running sessions. Write daily notes to `memory/YYYY-MM-DD.md`. Let the files grow.

---

## What to Customize

- **SOUL.md** -- the most important file. Make it specific. Generic values produce generic behavior.
- **IDENTITY.md** -- the fun one. Who is this agent? Give them a creature. It matters more than you'd think.
- **MEMORY.md** -- prune and grow this as you go. It's a living document, not a form to fill out once.
- **skills/** -- add skills for whatever your agent actually does. Skills are just markdown -- write them.

---

## What to Leave Alone

The daily log format in `memory/YYYY-MM-DD.md` is deliberately simple. Don't over-engineer it.
The skills included here have been tested. Use them as-is unless you have a reason to change them.
