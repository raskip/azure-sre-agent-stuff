# Walkthrough 08 — Memory & Learning (3 min, two-day arc)

> **Audience**: technical evaluators or new platform team members
> **Goal**: prove the agent remembers — without us building anything —
> by running the same scenario twice and watching the second run cite
> the first.

## What you're demoing

Every SRE Agent thread that completes triggers a **synthesis step** ~30
minutes after the thread goes quiet. The agent extracts:

- Symptoms observed
- Steps that resolved it
- Root cause
- Pitfalls to avoid

…and saves them into a per-resource memory plus a global
`memories/synthesizedKnowledge/overview.md` that's preloaded into the
agent's system prompt for every future conversation. New threads
investigating the same resource get **same-resource priority** — the
agent checks "have I seen this before on *this* VM?" first.

This is the demo that proves it.

## Shape of the demo

Unusually for our catalogue, this is a **two-day demo**. You run Day 1
during your normal demo flow (e.g., right after the high-cpu wow), then
come back 30+ minutes later for Day 2 — which can be the next morning,
the next session, or just "after coffee".

```
Day 1 (T+0)                Day 2 (T+30 min … T+24 h)
───────────                ────────────────────────────
Fire stress-ng on cpu VM   New chat thread
Open chat:                 Open chat:
"Investigate high CPU on   "Investigate high CPU on
 vm-<name>."                vm-<name> again."

Agent investigates,        Agent investigates
identifies stress-ng,      AND
proposes kill, you         cites the Day 1 thread:
approve, fixed.            "We saw this 28 minutes
                            ago. Same root cause
Thread closes.              (stress-ng). Last fix
                            worked. Apply it again?"
30 min synthesis runs
in background.
```

The "we saw this before" line is the demo. Everything else is set dressing.

## Prerequisites

Day 1 requirements:
1. An SRE Agent with VM skills available (marketplace-imported or manual)
2. A demo VM tagged `workload=sre-demo` running and reachable for fault injection
3. The agent has Reader on the demo RG
4. You'll need to spend ~5 min on Day 1, then ~3 min on Day 2

Day 2 requirements:
1. At least 30 minutes elapsed since the Day 1 thread closed
2. The same SRE Agent
3. (Optional) The demo VM in a fresh "broken" state — re-fire `stress-ng`
   if you want the symptom to be live during Day 2

## Day 1 — 5 minutes (~normal high-cpu flow)

This is just the high-cpu demo. If you've already done [Demo 01 — Quick
Wow](../examples/01-quick-wow-high-cpu.md), Day 1 is done — skip to Day 2.

The only thing to be careful about: let the agent **actually resolve**
the issue and let the thread go quiet. Don't leave the thread mid-
investigation; synthesis runs on completed threads.

Set a calendar reminder for 30-60 min from now.

## Day 2 — 3 minutes (the actual memory demo)

### Minute 0 — Set the stage (30 s)

> *"Earlier today / yesterday, this agent helped me diagnose a CPU spike
> on this exact VM. What we couldn't do at the time is show what happens
> next. Now we can."*

Quick refresher: show the Day 1 thread briefly in the sidebar. Mention
the timestamp.

### Minute 1 — Open a fresh thread, ask the same question (1 min)

In a brand new chat:

```
The VM <vm-name> in <resource-group> is hot again. Investigate.
```

Watch the planning step. It should include something like:

> *"Searching memory for prior issues on this resource…"*

> *"Found a relevant prior investigation: 'High CPU on `<vm-name>`'
> (28 minutes ago). Root cause was stress-ng PID 1234 launched manually.
> Resolution: `pkill -9 stress-ng`. Verifying whether the same pattern
> applies now…"*

If the agent doesn't cite memory in its first attempt, gently nudge:

```
Have you seen this before on this VM?
```

The agent will then explicitly query memory and pull up Day 1.

### Minute 2 — Inspect the citation chain (1 min)

Click on the citation marker. The Day 1 thread opens in a side drawer.
Scroll to the exact passage. Walk the audience through:

- The agent didn't *quote* Day 1 — it *summarised* what mattered
- The agent applied the Day 1 fix to today's situation (not blindly —
  it confirmed the symptom matches first)
- This synthesis happened automatically, no manual configuration

### Minute 3 — Show the persistent knowledge (1 min)

Open another chat:

```
What do you know about <vm-name>?
```

The agent responds with a synthesised summary — a few sentences that
draw on Day 1 (and any other Day 0 threads). Mention:

> *"This summary lives in the agent's `synthesizedKnowledge/overview.md`.
> Every conversation starts with that file already loaded. New team
> members onboarding to this on-call rotation see what the agent knows
> before they ask a single question."*

Optional power move: ask the agent to save something explicit:

```
Save this to your knowledge: <vm-name> is our demo VM for high-CPU
walkthroughs. Treat any CPU spike here as expected during business hours.
```

The agent writes that into a knowledge file. Future on-call rotations
won't get paged for the demo VM during work hours.

## Discussion points

- **"It's not training, it's notes."** The agent isn't fine-tuning a
  model. It's writing notes to itself in markdown files. We can read
  them. We can edit them. We can `git diff` them if we mount the
  knowledge directory.
- **"Same-resource priority is the killer feature."** Generic memory
  is useful. Memory that prioritises *this exact VM I'm investigating*
  is incidents-prevented-at-3-AM useful.
- **"30-minute lag is intentional."** If you summarise too eagerly,
  you summarise mid-incident and the wrong lessons stick. The 30-min
  quiet window means only completed-and-stable investigations enter
  long-term memory.

## What this isn't

- We don't claim the agent is "learning" in the ML sense. It's
  extracting, summarising, indexing.
- We don't show **manual knowledge upload** here — that's covered in
  [Walkthrough 06 — Knowledge-Grounded Answers](walkthrough-06-knowledge-grounded-answers.md).
  Memory and Knowledge are complementary: memory comes from
  investigations, knowledge comes from documents you upload.

## Cleanup

There's nothing to clean up. Memory accumulates by design. If you must
purge it (e.g., privacy / compliance):

- **Builder → Knowledge settings** lists synthesised entries — delete
  individual files
- For tenant-wide reset, contact Support; there's no self-service
  "forget everything" button by design

## Variant: doing it in one session

If you can't reliably wait 30 minutes between Day 1 and Day 2 in a
demo, do this instead:

- **During Day 1**, ask the agent: *"Save the root cause and fix to
  your knowledge files for future reference."* The agent writes
  immediately — no synthesis lag.
- **Then immediately**, in a new thread, ask the Day 2 question. The
  agent will cite the just-saved knowledge file.

This is a slightly weaker story (knowledge instead of synthesised
memory) but works inside a single 30-minute demo slot.
