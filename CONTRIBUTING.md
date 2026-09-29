# Contributing

Thanks for your help. This package is small, so keep changes small and focused.

## Setup

```bash
npm install
npm run lint
npm run typecheck
npm test
npm run build
```

## Rules

- Write the failing test first. Keep coverage at 80% or more.
- `show` and `dismiss` must never throw.
- Native changes need proof: compile both platforms and check the result in `example/`.
- Use [Conventional Commits](https://www.conventionalcommits.org): `feat:`, `fix:`, `docs:`, `test:`, `refactor:`, `chore:`.
- Do not bump `version` by hand. `semantic-release` sets it on `main`.

## Run the example

```bash
cd example
npm install
npx expo prebuild
npx expo run:ios      # or run:android
```

See [AGENTS.md](./AGENTS.md) for the full architecture notes.
