# Theory

This document describes the design philosophy behind the jupyter-workbench system — why it works, what it is, and where it's going.

## What This Is

An agentic development system that turns one person's knowledge into parallel, autonomous production. The human provides intent and domain expertise. The system provides execution, parallelism, and self-improvement.

The architecture has two mechanisms:

- **Worktrees** are the self-improvement mechanism. They modify the workbench itself — recipes, skills, templates, documentation. Every worktree makes future work faster and more reliable.
- **Workspaces** are the production mechanism. They execute real development tasks — features, bug fixes, refactors — in isolated environments with full autonomy.

## The Loop

```
Human Knowledge → Codified Procedures → Parallel Execution → Better Procedures
      ↑                                                              |
      └──────────────────────────────────────────────────────────────┘
```

1. A human understands how something works.
2. That understanding is distilled into natural language artifacts: skills, plans, recipes.
3. Agents execute those artifacts autonomously and in parallel.
4. The results reveal what's missing or broken in the procedures.
5. The human refines, and the cycle repeats.

The system compounds. Each iteration makes the next one cheaper.

## Why It Works

**Knowledge is written once, executed indefinitely.** A skill that describes "how to open a chat panel in JupyterLab" is written in 20 minutes and used by every future agent session that needs it. The cost of codifying knowledge amortizes to zero over time.

**Parallelism is nearly free.** Spawning a new agent on a new task costs minutes of human time — just enough to describe the intent. The marginal cost of work approaches the cost of describing it.

**The bottleneck is taste, not labor.** The human's job is deciding what should exist, how it should behave, and what quality bar it should meet. The system handles the rest. This is the correct division of labor: humans for judgment, machines for execution.

**Self-improvement is structural, not magical.** Worktrees modify the infrastructure that workspaces depend on. Today's improvement to a recipe makes tomorrow's workspace agent more capable. This is recursive self-improvement in the practical sense — the factory retooling itself.

## The Inputs

The system requires exactly one input: **human knowledge**, expressed as:

- **Skills** — reusable procedures for specific capabilities (browser automation, server management, PR workflows)
- **Plans** — one-shot intent documents that describe what an agent should accomplish
- **Recipes** — composable shell commands that encode operational knowledge
- **Documentation** — context that agents read to understand the system they're operating in

These are all natural language artifacts. No special tooling, no DSLs, no training. Just text files that describe how things work and what should happen.

## The Limits

**Ambiguity degrades quality.** Agents perform well on well-specified tasks and poorly on vague ones. The clearer the plan, the better the output. Novel or underspecified work still requires human intervention.

**Scaling is sublinear.** Two parallel agents are easy. Twenty parallel agents introduce coordination overhead, merge conflicts, and review bottlenecks. Isolation is solved; integration is not.

**No autonomous learning.** The system does not learn from failure on its own. When an agent gets stuck, a human diagnoses the problem and improves the skill or plan. The feedback loop runs through a person. This is a factory you retool, not an organism that adapts.

**Quality review remains manual.** Agents produce work that must be reviewed before merging. The system accelerates production but does not eliminate the need for judgment.

## Beyond Jupyter

The pattern is domain-agnostic:

1. Isolated environments for parallel work (workspaces)
2. Self-modifying infrastructure (worktrees)
3. Reusable procedural knowledge (skills)
4. Intent documents that drive autonomous execution (plans)
5. A human in the loop for judgment, taste, and refinement

This could be pointed at any complex software project. The architecture is the contribution — not the specific application to Jupyter.

## The Claim

One person, equipped with this system, produces output that resembles a team's. Not because the agents are brilliant, but because the human's knowledge is leveraged across parallel execution streams that never sleep, never forget a procedure, and improve their own tooling as they go.

This is significant. Not because it's conscious or alive, but because it changes the economics of software development in a way that compounds over time.

## Comparison to OpenAI Symphony

*Note: I developed this system before reading the [Symphony blog post](https://openai.com/index/open-source-codex-orchestration-symphony/) (April 2026) to ensure a fresh perspective. The convergence is validating — it suggests the pattern is correct rather than idiosyncratic.*

[Symphony](https://github.com/openai/symphony) is an open-source agent orchestrator from OpenAI that turns a project management board (Linear) into a control plane for Codex agents. Every open ticket gets an agent in an isolated workspace. Agents run continuously. Humans review results. It produced a 500% increase in landed PRs on some teams.

The architectures are nearly identical:

| | Symphony | jupyter-workbench |
|---|---|---|
| Core idea | Every task gets an isolated agent workspace | Every task gets an isolated workspace |
| Orchestration | Polls Linear for tickets, auto-dispatches | Human dispatches via plans and recipes |
| Workspace isolation | Per-issue directory, sandboxed | Per-task directory, git-isolated |
| Agent knowledge | `WORKFLOW.md` — documented process agents follow | `AGENTS.md` + skills — documented process agents follow |
| Human role | File tickets, review PRs | Write plans, review PRs |
| Harness engineering | Skills, repo structure, tests as guardrails | Skills, recipes, browser-eval framework |
| Quality enforcement | CI/e2e tests + human PR review | CI/tests + human PR review |
| Proof of work | Agents attach video walkthroughs to PRs | Browser screenshots/recordings (planned) |

### What differs

**Dispatch model.** Symphony is fully autonomous — a daemon polls Linear every 30 seconds and dispatches agents without human involvement. This system requires human intent (a plan or command) to start work. Symphony optimizes for throughput; this system optimizes for correctness.

**Self-improvement as a structural concept.** This system makes the worktree/workspace distinction explicit: worktrees improve the system, workspaces use the system to produce. Symphony likely does this too (agents filing follow-up tickets to improve the harness), but it's not a named first-class concept in their architecture.

**Scale and polish.** Symphony has a team of engineers, Codex app-server mode (headless JSON-RPC), and a 2000-line formal spec. This system has one person, Kiro CLI, and shell scripts. Same architecture, different maturity.

**Domain specificity.** Symphony is general-purpose (any repo, any ticket). This system is adapted to JupyterLab extension development with domain-specific recipes (browser automation, server lifecycle, chat interaction).

### What they haven't solved either

Quality at scale. Their spec is almost entirely about orchestration mechanics — polling, retries, concurrency, workspace isolation. Quality enforcement is punted to the harness (tests, CI) and human PR review. There's no automated review agent, no quality metrics dashboard, no mechanism for catching subtle architectural drift. Their answer is the same as ours: make changes cheap enough that reverting bad ones is painless, and iteratively improve the harness when failures slip through.

## Related Work

### Taxonomy of Agent Paradigms

The Gödel Agent paper (Yin et al., 2024) proposes a useful three-level taxonomy of agent systems based on their degree of freedom. We extend it here with a fourth category that describes this system.

```
Degree of Freedom
        │
        │   ┌─────────────────────────────────────────────────────────────────┐
   4    │   │  Human-Guided Self-Referential  (this system)                   │
        │   │  Updates: policy π, improvement algorithm I, AND the            │
        │   │  infrastructure that future agents run on.                      │
        │   │  Feedback: human judgment (PR review, plan refinement)          │
        │   │  Validator: human taste + domain expertise                      │
        │   └─────────────────────────────────────────────────────────────────┘
        │
        │   ┌─────────────────────────────────────────────────────────────────┐
   3    │   │  Self-Referential Agent  (Gödel Agent, Darwin Gödel Machine)    │
        │   │  Updates: policy π AND improvement algorithm I                  │
        │   │  Feedback: automated utility function U(ε, π)                   │
        │   │  Validator: benchmark score                                     │
        │   └─────────────────────────────────────────────────────────────────┘
        │
        │   ┌─────────────────────────────────────────────────────────────────┐
   2    │   │  Meta-Learning Optimized  (DSPy, Meta Agent Search)             │
        │   │  Updates: policy π via fixed algorithm I                        │
        │   │  Feedback: environment reward                                   │
        │   │  Validator: automated metric                                    │
        │   └─────────────────────────────────────────────────────────────────┘
        │
        │   ┌─────────────────────────────────────────────────────────────────┐
   1    │   │  Hand-Designed  (CoT, ReAct, Reflexion)                         │
        │   │  Updates: nothing — fixed pipeline                              │
        │   │  Feedback: none (or used only within a single run)              │
        │   │  Validator: human designs it once, deploys it                   │
        │   └─────────────────────────────────────────────────────────────────┘
        │
        └─────────────────────────────────────────────────────────────────────────
```

The key distinction between levels 3 and 4: at level 3, the system validates against automated benchmarks and runs autonomously. At level 4, the human remains structurally in the loop — not as a safety bolt-on, but as the source of the utility function itself. The tradeoff is speed (level 3 runs 30 iterations in minutes; level 4 runs on human-time) in exchange for reliability (level 3 fails 14% of the time; level 4 fails only when the human's judgment is wrong).

### Formal Comparison with Gödel Agent

The Gödel Agent framework (Yin et al., 2024) formalizes recursive self-improvement as:

```
π_{t+1}, I_{t+1} = I_t(π_t, r_t)       where r_t = U(ε, π_t)
```

The agent updates both its policy π (what it does) and its improvement algorithm I (how it decides what to change), guided by a utility function U that scores performance against an environment ε.

Mapping this to the jupyter-workbench system:

| Formal concept | Gödel Agent | This system |
|---|---|---|
| Policy π | Runtime code (monkey-patched) | Skills, recipes, plans (text files) |
| Improvement algorithm I | The SELF_IMPROVE function | Worktree mechanism + human steering |
| Utility function U | Benchmark score | Human judgment (PR review) |
| Environment ε | Task dataset | Real software project |
| Self-modification | Monkey patching at runtime | Git commits to infrastructure |
| Feedback loop speed | Seconds (automated) | Hours (human-mediated) |
| Failure rate | 14% of trials degrade | Near-zero (human validates) |
| Parallelism | Single agent, sequential | Multiple agents, parallel |
| Persistence | Within one optimization run | Permanent (committed to repo) |

**What Gödel Agent has that this system doesn't:**
- Autonomous discovery of novel strategies (e.g., spontaneously switching from LLM prompting to search algorithms for Game of 24)
- Speed — 30 improvement iterations for ~$15 in API cost
- No human bottleneck

**What this system has that Gödel Agent doesn't:**
- Reliability — changes are validated by a human before merging, so the system never regresses
- Persistence — improvements are committed to version control, not lost when a session ends
- Production output — the system does real work (ships features) while simultaneously improving itself
- Parallelism — multiple improvement and production streams run concurrently
- Composability — improvements are modular (a skill, a recipe) rather than monolithic code rewrites

**The convergence hypothesis:** As LLMs improve, the gap between levels 3 and 4 narrows. The human's role shifts from "steering every improvement" to "approving improvements the system proposes autonomously." The architecture of this system (worktrees for self-improvement, workspaces for production, PR review as the gate) is designed to accommodate that transition without structural changes.

### [Darwin Gödel Machine: Open-Ended Evolution of Self-Improving Agents](https://arxiv.org/abs/2505.22954)

- Extends the Gödel Agent concept to open-ended evolution: the system iteratively modifies its own code, improving its ability to self-modify, validated against coding benchmarks.
- Similar: The core loop is identical — the system improves the system that improves the system. Worktrees are this project's equivalent of self-modification.
- Differs: Fully autonomous with no human in the loop. Validates against benchmarks rather than human judgment. No separation between "production work" and "self-improvement work."

### [Gödel Agent: A Self-Referential Agent Framework for Recursive Self-Improvement](https://arxiv.org/abs/2410.04444)

- Peking University / UCSB, 2024. The first fully self-referential LLM agent. Uses monkey patching to modify its own runtime code, including the code responsible for deciding what to modify. Outperforms hand-designed agents (CoT, Self-Refine) and meta-learning agents (Meta Agent Search) on DROP, MGSM, MMLU, and GPQA benchmarks.
- Similar: The recursive self-improvement loop is the same in structure. Both systems update not just "what the agent does" but "how the agent improves." In this system, a worktree can modify the recipe that future worktrees use — that's the equivalent of Gödel Agent modifying its own SELF_IMPROVE function.
- Differs: Gödel Agent is fully autonomous and single-purpose (optimize benchmark performance). It has no concept of parallel production work. It operates within a single session and improvements are not persisted. It fails 14% of the time because there's no human gate. This system trades speed for reliability and adds a production dimension.

### [HULA: Human-In-the-Loop Software Development Agents](https://arxiv.org/abs/2411.12924)

- Atlassian, ICSE 2025. A framework where software engineers refine and guide LLMs when generating plans and code.
- Similar: Human provides judgment and steering; agent provides execution. The human-agent collaboration model matches closely.
- Differs: Single-agent, single-task. No self-improvement of the system's own infrastructure. No parallelism. The human is in the loop for *each task*, not for *improving the system that does tasks*.

### [Self-Organizing Multi-Agent Systems for Continuous Software Development](https://arxiv.org/html/2603.25928v1)

- Multi-agent system for persistent, continuous software development beyond one-shot tasks.
- Similar: Parallel agents working on a shared codebase continuously, not just completing isolated tasks.
- Differs: Agents self-organize without explicit human orchestration. No distinction between infrastructure improvement and feature work.

### [AgentOrchestra: Orchestrating Multi-Agent Intelligence with the TEA Protocol](https://www.arxiv.org/abs/2506.12508)

- Hierarchical framework where a central planner orchestrates specialized sub-agents and dynamically instantiates/refines tools during execution.
- Similar: Orchestrator pattern with specialized workers. Tools are refined online — analogous to skills being improved via worktrees.
- Differs: Single-session runtime optimization rather than persistent cross-session knowledge accumulation. No human-authored procedures as the knowledge substrate.

### [Cybernetics and the "human-on-the-loop" in agentic coding](https://www.thoughtworks.com/en-us/insights/blog/generative-ai/cybernetics-and-human-on-the-loop-in-agentic-coding)

- ThoughtWorks essay framing agentic coding as a cybernetic feedback control system with humans providing course correction.
- Similar: Philosophically aligned — the human is a governor in a feedback loop, not a laborer. Non-determinism is managed through structure, not eliminated.
- Differs: Conceptual framing only, not a concrete system. No self-improvement mechanism or parallel execution model.

### [Self-Optimizing Multi-Agent Systems for Deep Research](https://arxiv.org/html/2604.02988v1)

- Orchestrator-worker architecture where agents self-play and explore prompt combinations to outperform hand-engineered systems.
- Similar: The system optimizes its own prompts/procedures through iteration, replacing hand-engineering with discovered improvements.
- Differs: Optimization is automated via self-play rather than human-guided. Domain is research synthesis, not software development.

## Aside: Cybernetics

*Disclaimer: I'm skeptical of the practical value of cybernetics as a field — it often feels like giving fancy names to things practitioners already do intuitively. But the conceptual vocabulary is useful for explaining why this system works, and where it doesn't yet.*

Cybernetics is the study of communication and control in complex systems. Three concepts from it map cleanly onto this project:

**Ashby's Law of Requisite Variety** — "Only variety can absorb variety." A controller must have at least as much complexity as the system it controls. If agents produce code at machine speed, a human reviewing every line can't match that variety. They become a bottleneck or a rubber stamp. The solution: step to the meta level. Don't control the output — control the system that produces the output.

**The Conant-Ashby Theorem** — "Every good regulator of a system must be a model of that system." You can only steer what you understand. The human must maintain an accurate mental model of how the agentic system works. In this project, the model IS the documentation: AGENTS.md, CONTRIBUTING.md, skills, recipes.

**Homeostasis via Attenuation/Amplification** — Balance between human and system is achieved by:
- *Attenuating* variety from the system (filtering output to what matters — `cmux notify` for done/stuck, PR diffs rather than raw logs)
- *Amplifying* variety from the human (encoding decisions into reusable artifacts — skills, plans, recipes that propagate across all agents)

### How this system applies cybernetics

| Concept | Mechanism |
|---|---|
| Amplification | Skills, plans, recipes — human knowledge propagated across parallel agents |
| Attenuation | Notifications on done/stuck — human doesn't watch agents work |
| Meta-level steering | PROMPT.md describes intent, not implementation |
| Model of system | AGENTS.md, CONTRIBUTING.md, THEORY.md |
| "Go See" (Gemba) | PR review — descend into code to verify steering worked |
| Homeostasis | Worktrees adjust the system when it drifts; workspaces produce |

### Gaps (through a cybernetics lens)

**Weak sensors.** The only signal between "started" and "done/stuck" is silence. No intermediate progress, no drift detection, no quality metrics reported automatically. A richer feedback channel would let the human intervene earlier when an agent goes off-track.

**No automated "Go See."** PR review is manual and ad-hoc. A review agent that runs after the worker finishes — before the human sees the PR — would catch obvious issues without human time.

**Model drift.** As worktree agents modify the system, the human's mental model can lag. If a worktree adds a recipe and the human doesn't notice, their steering becomes misaligned. Automated changelog generation or documentation-vs-reality diffing would help.

**No double-loop learning.** When a PR needs revision, the human fixes the plan or skill. But there's no systematic mechanism to ask "why did the system produce this?" and trace it to a root cause. A retro log or pattern detection across failures would close this loop.

**Quality amplification is thin.** Plans describe *what* to do but not *how well*. There's no codified quality bar (code style, test expectations, commit format) that agents consult when making judgment calls.
