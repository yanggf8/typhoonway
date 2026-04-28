# tool.md Contract

`tool.md` is the LLM-facing descriptor for an installed Typhoon tool.

Every forged or promoted CLI has executable code, operator-reviewed requirements, and one `tool.md`. The executable is what runs. The requirements and tests are what the operator reviews. `tool.md` is what the channel LLM sees when deciding whether and how to call the tool.

`tool.md` is not a skill file, not a hidden prompt, and not a behavioral proof. It is a compact contract that turns a CLI into a usable tool surface for an LLM.

## Required Shape

Each `tool.md` must be Markdown with these headings, in this order:

````markdown
# <tool-name>

## Summary
One or two sentences describing what the tool does.

## When to Use
- Situations where the LLM should call this tool.

## When Not to Use
- Situations where the LLM should not call this tool.

## Command
`<tool-name> [args...]`

## Inputs
- Arguments, flags, stdin, environment variables, and required files.

## Outputs
- stdout, stderr, exit codes, generated files, and machine-readable formats.

## Side Effects
- Filesystem, network, subprocess, deployment, account, or other mutations.

## Examples
```bash
<tool-name> ...
```

## Failure Modes
- Common failures and what their exit codes or stderr look like.

## Dependencies
- External binaries, credentials, network access, services, or runtime versions.
````

## Runtime Use

Core builds the LLM tool manifest from approved registry rows and their `tool.md` descriptors. In a channel turn, the LLM chooses tool calls from that manifest. Core mediates execution of the selected call and records the result; core does not choose the tool for the LLM.

Scheduled use entries are different: a cron entry may target a specific tool or subcommand directly. Even then, `tool.md` remains the operator-facing and LLM-facing description of what the tool is expected to do.

## Submission Rule

`typhoon tool propose submit` requires a `tool.md` file for every forged CLI delivery. The tool manager stores it with the proposal, includes it in operator review, and installs it into the active tool registry only on approval.

`typhoon tool promote` also requires or generates a reviewed `tool.md` before the promoted script becomes active.

## Constraints

- Keep it concise enough to fit in a bounded tool manifest.
- Describe the public interface, not implementation internals.
- State side effects explicitly.
- Do not include secrets, local absolute paths, machine-specific usernames, or transient temp paths.
- Keep examples realistic and copy-pastable.
- Update it whenever a replacement changes the tool interface or behavior.
