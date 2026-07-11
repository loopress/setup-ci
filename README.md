# loopress/setup-ci

Bootstrap a full WordPress environment in CI with a single step. No configuration required.

Starts MySQL and WordPress via Docker, installs WP-CLI, creates the REST credentials, and installs the Loopress CLI. Your pipeline can run `loopress push` immediately after.

## GitHub Actions

```yaml
steps:
  - uses: actions/checkout@v4
  - uses: loopress/setup-ci@v1
  - run: loopress push
```

### Inputs

| Input | Description | Default |
|---|---|---|
| `wp-version` | WordPress version | `latest` |
| `site-id` | Loopress site ID | `ci` |
| `port` | WordPress port on the runner | `8080` |
| `token` | Loopress cloud token | |

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
    LOOPRESS_SITE: "production"
```

### Variables

| Variable | Description | Default |
|---|---|---|
| `LOOPRESS_WP_VERSION` | WordPress version | `latest` |
| `LOOPRESS_WP_PORT` | WordPress port | `8080` |
| `LOOPRESS_SITE` | Site ID for deploy jobs | `staging` |
| `LOOPRESS_TOKEN` | Loopress cloud token | |

### Available templates

- `.loopress-test`: boots WordPress and runs `loopress push`. Triggers on branches and merge requests.
- `.loopress-deploy`: deploys to a real site with `loopress push` then verifies with `loopress diff`.

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

## CircleCI

```yaml
version: 2.1

orbs:
  loopress: loopress-dev/loopress@1

workflows:
  main:
    jobs:
      - loopress/test
      - loopress/deploy:
          site: production
          requires:
            - loopress/test
```

### `setup` command parameters

| Parameter | Type | Description | Default |
|---|---|---|---|
| `wp-version` | string | WordPress version | `latest` |
| `wp-port` | integer | WordPress port | `8080` |
| `token` | env_var_name | Env var holding the cloud token | `LOOPRESS_TOKEN` |

### `deploy` command parameters

| Parameter | Type | Description | Default |
|---|---|---|---|
| `site` | string | Site ID | `staging` |
| `token` | env_var_name | Env var holding the cloud token | `LOOPRESS_TOKEN` |

### Restoring between groups of tests

A CircleCI job is a single executor, so restoring between groups of tests happens as an extra
step in the same job, after `setup` has already run once (it's what downloads the restore
script and takes the snapshot):

```yaml
- loopress/setup:
    wp-version: "6.5"
- run: npx playwright test tests/e2e/happy-path.spec.ts
- loopress/restore
- run: npx playwright test tests/e2e/conflicts.spec.ts
```

## Token

CI testing is free and unlimited: no token needed to run `loopress push` against a local WordPress instance.

A token is required only when deploying to a real site. Get one at https://console.loopress.dev/tokens.

## How it works

1. Starts MySQL 8 and WordPress via Docker Compose
2. Waits for WordPress to respond (up to 90 seconds)
3. Installs WP-CLI inside the WordPress container
4. Runs `wp core install` and creates an application password
5. Exports a clean database snapshot for `loopress/setup-ci/restore` to reset to later
6. Writes `$XDG_CONFIG_HOME/loopress/config.json` (or `~/.config/loopress/config.json`) with the site credentials
7. Installs `@loopress/cli`
