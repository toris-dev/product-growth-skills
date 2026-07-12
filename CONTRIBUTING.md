# Contributing

Contributions are welcome. Each skill should have one clear responsibility and guide an agent to inspect the real project, work from evidence, and produce verifiable results.

## Principles

- Verify changing platform specifications, policies, and APIs against current official documentation during the task.
- Separate diagnosis from implementation authority and preserve unrelated user changes.
- Never guarantee rankings, store approval, performance gains, or AI-search inclusion.
- Do not commit generated output, caches, secrets, or machine-specific absolute paths.
- Move long conditional guidance into `references/` and tell the agent exactly when to read it from `SKILL.md`.

## Contribution workflow

1. Use lowercase hyphen-case for the skill folder and make the frontmatter `name` match it exactly.
2. Write a `description` that explains both what the skill does and when it should trigger.
3. Keep `agents/openai.yaml` aligned with the skill. It must contain a display name, a 25–64 character short description, and a default prompt that mentions `$skill-name`.
4. Run the repository and official validators:

```bash
python3 scripts/validate_skills.py
python3 /path/to/skill-creator/scripts/quick_validate.py <skill-directory>
```

5. In the pull request, explain the purpose of the change, the validation performed, and any remaining limits.

