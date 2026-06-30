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

## Token

CI testing is free and unlimited: no token needed to run `loopress push` against a local WordPress instance.

A token is required only when deploying to a real site. Get one at https://console.loopress.dev/tokens.

## How it works

1. Starts MySQL 8 and WordPress via Docker Compose
2. Waits for WordPress to respond (up to 90 seconds)
3. Installs WP-CLI inside the WordPress container
4. Runs `wp core install` and creates an application password
5. Writes `~/.loopress/sites.json` with the site credentials
6. Installs `@loopress/cli`
