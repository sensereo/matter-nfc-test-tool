# Repository instructions

## Language

Use English for all repository content: documentation, code identifiers,
comments, UI strings, examples, configuration comments, issue templates, commit
messages, and pull request descriptions. Conversation with a contributor may
follow their preferred language.

## Scope and accuracy

- Keep changes focused on the requested task.
- Distinguish planned functionality from implemented and verified behavior.
- Date descriptions of current capabilities and name the verification evidence.
- Do not import private project files, logs, credentials, or unpublished material.
- Check redistribution rights and preserve licenses before importing source,
  frameworks, assets, or third-party dependencies.
- Do not commit, push, publish, or create a release unless requested.
- Do not add AI attribution or generated-by footers to commits or pull requests.

## Documentation and files

- Keep the project introduction in `README.md` and the documentation index in
  `docs/README.md`.
- Maintain architecture and scope in `docs/overview.md`.
- Add `docs/reference/`, `docs/guides/`, and `docs/decisions/` only when needed.
- Use lowercase kebab-case documentation names, except conventional entry files.
- Use repository-relative links; do not depend on private workspace paths.
- Put local experiments in `.scratch/`, which must remain ignored by Git.
- Keep secrets, signing material, local network datasets, and device identities
  out of tracked files. Use clearly synthetic examples.

## Validation

Run checks appropriate to the change and report their actual results. Once
application code is introduced, document reproducible build and test commands.
Do not invent passing tests, compatibility claims, or hardware validation.
