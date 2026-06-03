# Walkthrough 06 — Knowledge-Grounded Answers (3 min)

> **Audience**: technical evaluators or new platform team members
> **Goal**: upload an architecture / runbook doc, ask a question that requires it, watch the agent cite the doc.

## Prerequisites

Have these tabs ready:
1. Agent at https://sre.azure.com → **Builder → Knowledge settings**
2. A fresh chat thread
3. The doc(s) you'll upload — usually one of:
   - `DEMO-RUNBOOK.md` (operator playbook) — *recommended for VM demos*
   - An architecture overview md
   - A high-cardinality runbook the customer recognises

## The narrative — 3 minutes

### Minute 0 — The pain (15 s)

> *"Out of the box, the agent knows Azure. It doesn't know your runbooks, your naming conventions, or the unwritten rules your team carries in someone's head. Today we make that explicit."*

### Minute 1 — Upload (45 s)

Either via the portal (drag-and-drop into Knowledge settings → Add file), or via the bundled script:

```bash
./scripts/upload-knowledge.sh \
  --subscription <your-subscription-id> \
  --resource-group <your-agent-rg> \
  --agent <your-agent-name> \
  --docs DEMO-RUNBOOK.md
```

Watch the status flip from **Pending** to **✓ Indexed** in ~30 seconds. The portal shows the file name, type (`.md`), and last-modified.

> *"Supported formats: .md, .txt, .pdf, .docx, .csv, .json, images. We're using the runbook here, but the same flow works for an architecture diagram PDF or a CSV of service ownerships."*

### Minute 2 — Ask a grounded question (1 min)

In the fresh chat:

```
I need to walk through the disk-iops scenario in 30 minutes. Walk me
through the pre-flight checklist.
```

Without knowledge, the agent would either guess or ask for more context. With the runbook indexed, it produces a step-by-step answer **and the answer includes clickable citation markers** like `[1]` pointing back to the exact section of DEMO-RUNBOOK.md.

Click one citation. The Knowledge panel opens, scrolled to the exact paragraph the answer drew from.

> *"That's the citation chain. The agent can't make stuff up about your environment any more — every claim is anchored to a document you uploaded."*

### Minute 3 — One more ask, this time pattern-matching (1 min)

```
Our new on-caller is at a different office and can't SSH from their laptop.
Based on our runbook, what's the right alternative?
```

Watch the agent search the knowledge, find the Bastion-only access section, and produce a precise answer — *"Per your runbook, Bastion-only is the default access model. Use Azure Portal → Bastion → vm-sre-demo-cpu with the password file at..."*

> *"The agent isn't repeating verbatim. It read the section, understood it, and applied it to the new on-caller's situation. The runbook is the source, but the answer is contextualised."*

---

## Why this matters

| Without knowledge docs | With knowledge docs |
|---|---|
| Agent guesses or asks for missing context | Agent answers with citations |
| Each engineer reads runbooks differently | Single source of truth, automatically applied |
| Documentation rots in a wiki nobody reads | Documentation is queried every time, surfacing stale sections |
| "Tribal knowledge" stays tribal | Tribal knowledge becomes queryable |

## Memory + knowledge synergy

After running this demo, mention the **memory** layer (Concepts → Memory):

> *"Now imagine doing this once for runbooks, and the agent also learns from every investigation it runs — patterns it's seen, fixes that worked, dead ends. After a month, your agent has two layers: the knowledge you uploaded and the memory it built. New team members ramp into both."*

This is a natural lead-in to Walkthrough 08 (memory and learning) if you have time.

## What to upload, when

| Audience | Best doc to upload |
|---|---|
| Live operators | DEMO-RUNBOOK.md — they recognise the format |
| Architects | Architecture overview md or PDF |
| Compliance | Hooks/governance reference + runbook |
| New hires | Onboarding doc + naming conventions |

## Cleanup

**Builder → Knowledge settings → select files → Delete**. Indexed content disappears within seconds; agent stops citing them in the next turn.
