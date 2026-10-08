# loopress/setup-ci

Bootstrap a full WordPress environment in CI with a single step. No configuration required.

Starts MySQL and WordPress via Docker, installs WP-CLI, creates the REST credentials, and installs the Loopress CLI. Your pipeline can run `lps push` immediately after.

## GitHub Actions

```yaml
steps:
  - uses: actions/checkout@v4
  - uses: loopress/setup-ci@v1
  - run: lps push
```

### Inputs

| Input | Description | Default |
|---|---|---|
| `wp-version` | WordPress version | `latest` |
| `site-id` | Loopress site ID | `ci` |
| `port` | WordPress port on the runner | `8080` |
| `token` | Loopress cloud token, exported as `LOOPRESS_TOKEN` for the following steps | |

### Output

| Output | Description |
|---|---|
| `wp-url` | WordPress URL (`http://localhost:<port>`) |

### Full example

```yaml
- uses: loopress/setup-ci@v1
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
  - uses: loopress/setup-ci@v1

  - name: Happy path tests
    run: npx playwright test tests/e2e/happy-path.spec.ts

  - uses: loopress/setup-ci/restore@v1

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
| `LOOPRESS_ENV` | Environment deploy jobs push to (`--env`) | `staging` |
| `LOOPRESS_CONFIG` | File-type variable holding your `config.json`, required by deploy jobs | |
| `LOOPRESS_TOKEN` | Loopress cloud token | |

### Available templates

- `.loopress-test`: boots WordPress and runs `lps push`. Triggers on branches and merge requests.
- `.loopress-deploy`: deploys to a real site with `lps push --env $LOOPRESS_ENV --yes` then verifies with `lps diff`. The site's URL and credentials come from `LOOPRESS_CONFIG`: configure the project once on your machine (`lps project config`), then store that `config.json` as a File-type CI/CD variable.

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

## Plugins

Only Loopress Full is preinstalled. Declare the other plugins your project needs (WPCode, ACF, WPForms, an SEO plugin...) in `loopress.json`: `lps push` installs them before pushing anything else, so the CI site matches your real one.

## Token

CI testing is free and unlimited: no token needed to run `lps push` against a local WordPress instance.

A token is required only when deploying to a real site. Get one at https://console.loopress.dev/tokens.

## How it works

1. Starts MySQL 8 and WordPress via Docker Compose, waiting until both are healthy
2. Installs WP-CLI inside the WordPress container
3. Runs `wp core install`, installs the latest Loopress Full release, and creates an application password
4. Dumps a clean database snapshot (from the MySQL container) for `loopress/setup-ci/restore` to reset to later
5. Writes `$XDG_CONFIG_HOME/loopress/config.json` (or `~/.config/loopress/config.json`) with the site credentials
6. Installs `@loopress/cli`
