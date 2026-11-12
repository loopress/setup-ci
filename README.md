# loopress/setup-ci

Bootstrap a full WordPress environment in CI with a single step. No configuration required.

Starts MySQL and WordPress via Docker, installs WP-CLI, creates the REST credentials, and installs the Loopress CLI. Your pipeline can run `lps push` immediately after.

## GitHub Actions

```yaml
steps:
  - uses: actions/checkout@v4
  - uses: loopress/setup-ci@main
  - run: lps push
```

### Inputs

| Input | Description | Default |
|---|---|---|
| `wp-version` | WordPress version | `latest` |
| `site-id` | Loopress site ID | `ci` |
| `port` | WordPress port on the runner | `8080` |
| `install-cli` | Install `@loopress/cli` globally. Set to `false` to skip it (saves about 11 s) when the CLI is already available | `true` |
| `token` | Loopress cloud token, exported as `LOOPRESS_TOKEN` for the following steps | |

### Output

| Output | Description |
|---|---|
| `wp-url` | WordPress URL (`http://localhost:<port>`) |

### Full example

```yaml
- uses: loopress/setup-ci@main
  with:
    wp-version: "6.5"
    port: "9090"
    token: ${{ secrets.LOOPRESS_TOKEN }}
```

### Restoring between groups of tests

`loopress/setup-ci` takes a snapshot of the database as its last setup step. If your e2e suite
runs several independent groups of tests and respawning the whole Docker stack between them is
too slow, call `loopress/setup-ci/restore` to reset WordPress back to that clean snapshot instead.
It's a separate action so it never re-triggers the boot/install steps, it's always something you
call explicitly, in your own workflow:

```yaml
steps:
  - uses: actions/checkout@v4
  - uses: loopress/setup-ci@main

  - name: Happy path tests
    run: npx playwright test tests/e2e/happy-path.spec.ts

  - uses: loopress/setup-ci/restore@main

  - name: Conflict tests
    run: npx playwright test tests/e2e/conflicts.spec.ts
```

The snapshot path defaults to `/tmp/loopress-snapshot-clean.sql` and doesn't need configuring for
most cases. To override it, set `LOOPRESS_SNAPSHOT_PATH` in the job or step `env:` around both the
setup and restore steps, no input is needed since composite action steps inherit env vars set at
the job or workflow level.

## GitLab CI

Reference the template via remote include. Do not copy the file: reference it so you always get the latest version.

```yaml
include:
  - remote: 'https://raw.githubusercontent.com/loopress/setup-ci/v1/gitlab/template.yml'

test:
  extends: .loopress-test

deploy:
  extends: .loopress-deploy
  variables:
    LOOPRESS_ENV: "production"
```

### Variables

| Variable | Description | Default |
|---|---|---|
| `LOOPRESS_WP_VERSION` | WordPress version | `latest` |
| `LOOPRESS_WP_PORT` | WordPress port | `8080` |
| `LOOPRESS_INSTALL_CLI` | Set to `false` to skip `npm install -g @loopress/cli` | `true` |
| `LOOPRESS_ENV` | Environment deploy jobs push to (`--env`) | `staging` |
| `LOOPRESS_CONFIG` | File-type variable holding the export of one environment's config (not your whole `config.json`), required by deploy jobs | |
| `LOOPRESS_TOKEN` | Loopress cloud token | |
| `LOOPRESS_SKIP_DRIFT_GUARD` | Set to `1` to skip the pre-deploy drift guard for one run | |

### Available templates

- `.loopress-test`: boots WordPress and runs `lps push`. Triggers on branches and merge requests.
- `.loopress-deploy`: deploys to a real site: drift guard, `lps push --env $LOOPRESS_ENV --yes`, then `lps diff` to verify. The site's URL and credentials come from `LOOPRESS_CONFIG`: configure the project once on your machine (`lps project config`), then store a copy of your `~/.loopress/config.json` reduced to that one project and that one environment (same shape as [`templates/loopress-config.json`](templates/loopress-config.json): `currentProject`, `projects.<id>.environments.<name>` with its `url` and `token`) as a File-type CI/CD variable. It uses `resource_group: loopress-$LOOPRESS_ENV`, so two pipelines never deploy to the same environment at once.
- `.loopress-preview`: on merge requests, `lps diff --env $LOOPRESS_ENV --json` prints what the change would do to the environment. It never fails and posts no comment; it needs only `LOOPRESS_CONFIG`.

```yaml
preview:
  extends: .loopress-preview
  variables:
    LOOPRESS_ENV: "production"
```

### Drift guard

Before pushing, `scripts/drift-guard.sh` fails the deploy when it would overwrite an edit made on the site outside the repo. A CI push has no previous snapshot, so the guard compares the site with the previous commit (`$CI_COMMIT_BEFORE_SHA`, checked out in a temporary `git worktree`) and with the commit being deployed, and blocks only on ids that differ from both. The message names them: `lps pull` them into the repo first.

- No previous commit (first push, new branch) or one that cannot be fetched: the guard is skipped with a warning.
- A comparison that is inconclusive only warns.
- It assumes the previous commit was deployed: after a failed or skipped deploy it can raise a false alarm. Set the CI variable `LOOPRESS_SKIP_DRIFT_GUARD=1` to skip it for one run.

### Restoring between groups of tests

A GitLab job is a single isolated container, so restoring between groups of tests happens as an
extra step in the same job's `script:`, not a separate job. `.loopress-bootstrap` already
downloads `/tmp/loopress-restore.sh` alongside the other scripts, call it directly between groups:

```yaml
test:
  extends: .loopress-bootstrap
  script:
    - npx playwright test tests/e2e/happy-path.spec.ts
    - /tmp/loopress-restore.sh
    - npx playwright test tests/e2e/conflicts.spec.ts
```

## GitHub Actions deploy

Same order as the GitLab template: guard, push, verify. `fetch-depth: 0` gives the guard the previous commit (`github.event.before`), and `concurrency` keeps two runs from deploying to the same environment at once.

```yaml
name: Deploy

on:
  push:
    branches: [main]

concurrency:
  group: loopress-production
  cancel-in-progress: false

jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0
      - uses: actions/setup-node@v4
        with:
          node-version: 24
      - run: npm install -g @loopress/cli
      - name: Restore site credentials
        env:
          LOOPRESS_CONFIG: ${{ secrets.LOOPRESS_CONFIG }}
        run: |
          mkdir -p ~/.config/loopress
          printf '%s' "$LOOPRESS_CONFIG" > ~/.config/loopress/config.json
      - name: Drift guard
        env:
          LOOPRESS_SKIP_DRIFT_GUARD: ${{ vars.LOOPRESS_SKIP_DRIFT_GUARD }}
        run: |
          curl -fsSL https://raw.githubusercontent.com/loopress/setup-ci/v1/scripts/drift-guard.sh -o /tmp/drift-guard.sh
          bash /tmp/drift-guard.sh production "${{ github.event.before }}"
      - run: lps push --env production --yes
      - run: lps diff --env production
```

A merge request or pull request preview is one step: `lps diff --env production --json || true`.

## Plugins

Only Loopress Full is preinstalled. Declare the other plugins your project needs (WPCode, ACF, WPForms, an SEO plugin...) in `loopress.json`: `lps push` installs them before pushing anything else, so the CI site matches your real one.

## Token

No token is required to push, in CI or to real sites. `LOOPRESS_TOKEN` is read only by best-effort cloud features (deployment record, publish). Get one at https://console.loopress.dev/tokens.

## How it works

1. Starts MySQL 8 and WordPress via Docker Compose, waiting until both are healthy
2. Installs WP-CLI inside the WordPress container
3. Runs `wp core install`, installs the latest Loopress Full release, and creates an application password
4. Dumps a clean database snapshot (from the MySQL container) for `loopress/setup-ci/restore` to reset to later
5. Writes `$XDG_CONFIG_HOME/loopress/config.json` (or `~/.config/loopress/config.json`) with the site credentials
6. Installs `@loopress/cli` (skipped when `install-cli` is `false`)
