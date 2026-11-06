# Security policy

## Supported versions

Only the [latest release](https://github.com/Wirtexxx/plugin-sorter/releases/latest) gets security fixes.

## Reporting a vulnerability

Please report privately through
[Report a vulnerability](https://github.com/Wirtexxx/plugin-sorter/security/advisories/new)
on the Security tab, and don't open a public issue.

Plugin Sorter is maintained by one person, so a reply can take up to 7 days.

## Known limitations

- **The app is not notarized.** It is ad-hoc signed, so macOS warns on first launch and can't
  vouch for who built it. Build from source if you want to check what you run.
- **Administrator actions rely on a script your user account can change.** Actions that ask for your
  password run `sort-plugins.sh` from inside the app with administrator rights, and an app in `/Applications`
  is usually writable by its owner. The risk is local: it needs a program already running under
  your account, and you still have to enter your password. Fixing this takes a Developer ID and
  a privileged helper, which the project doesn't have yet.

Reports about these two points are welcome only if they show something new.

## Scope

In scope: the app, its helper, `sort-plugins.sh` and the website in this repository.

Out of scope: third-party plugins, even when Plugin Sorter loads them to check them. Please
report those to their developers.
