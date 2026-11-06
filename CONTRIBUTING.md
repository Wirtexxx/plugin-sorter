# Contributing

Thanks for helping. Bug reports from musicians are as useful as code.

## Where things live

- `app/`: the macOS app, its helper, `scripts/sort-plugins.sh` and the Swift tests
- `web/`: the landing page
- `docs/`: screenshots and the icon

## Branches

Open pull requests against `develop`. A release is a pull request from `develop` to `main`, plus a tag.

## Before you open a pull request

```bash
# app/
swift test

# web/
npm ci
npx playwright install chromium firefox webkit   # once, for test:browser
npm test
npm run test:browser
```

Run the part you changed. The app needs only the Command Line Tools, the site needs Node 22.

Tests must never touch `/Library/Audio/Plug-Ins` or FL Studio's database. Run the script against
a temporary tree through `PLUGIN_SORT_ROOT`, as the existing tests do.

## A good first contribution

Add a developer to the display names in [`app/scripts/sort-plugins.sh`](app/scripts/sort-plugins.sh),
so their plugins land in a properly named folder.

## Security

Please don't report vulnerabilities in public issues. See [SECURITY.md](SECURITY.md).
