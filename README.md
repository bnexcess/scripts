# Scripts that can be useful under the right usage 

# Scripts

A curated collection of scripts for server administration, troubleshooting, and automation.

This repository is organized by topic so scripts are easier to find, maintain, and reuse.

## Table of contents

- [Overview](#overview)
- [Structure](#structure)
- [Usage](#usage)
- [Contributing](#contributing)
- [Conventions](#conventions)
- [License](#license)

## Overview

This repo contains practical scripts used for common operational tasks, including:

- server management.
- log analysis.
- performance tuning.
- automation.
- quick troubleshooting.
- infrastructure maintenance.

## Structure

Scripts are grouped by topic:

- `cloudflare/` — Cloudflare-related scripts and automation.
- `php-fpm/` — PHP-FPM management, tuning, and debugging.
- `apache/` — Apache-related scripts.
- `haproxy/` — HAProxy-related scripts.
- `nginx/` — Nginx-related scripts.
- `mysql/` — Database-related scripts.
- `misc/` — General-purpose or one-off scripts.

## Usage

Each script should include a short header comment describing:

- what it does.
- required inputs or arguments.
- dependencies.
- example usage.

Example:

```bash
./cloudflare/cf-phpfpm-attack-toggle.sh
```

If a script is not executable, you can make it so:

```bash
chmod +x cloudflare/cf-phpfpm-attack-toggle.sh
```

## Contributing

Contributions are welcome.

When adding a new script:

1. Put it in the most relevant topic directory.
2. Use a clear, descriptive filename.
3. Test it before committing.
4. Document usage or assumptions.
5. Keep scripts focused on a single task.

## Conventions

- Use lowercase filenames with hyphens, such as `restart-php-fpm.sh`.
- Prefer Bash or POSIX shell when appropriate.
- Avoid hardcoding environment-specific values unless necessary.
- Clearly document any destructive or irreversible behavior.
- Keep scripts small and easy to review.

## License

Free Use - Most scripts here are used in a RedHat/CentOS/Rocky Enviorment

---

Contact briansnelson@gmail.com / https://www.briansnelson.com  / 
