# WP Slow Trace

**WordPress PHP, SQL, callback, and HTTP performance diagnostics — from the dashboard or WP-CLI.**

Version **1.4.0** · Requires **PHP 7.4+** · No PHP-FPM configuration required

<!-- Add an actual dashboard screenshot at images/dashboard.png, then uncomment:
![WP Slow Trace dashboard](images/dashboard.png)
-->

WP Slow Trace records **completed slow WordPress requests** and helps investigate where time was spent. It can report total request duration, memory usage, SQL query timings, WordPress lifecycle checkpoints, instrumented action/filter callbacks, and outbound requests made through the WordPress HTTP API.

> **Scope:** This is application-level instrumentation, not a system-wide PHP profiler. It cannot inspect currently stuck PHP-FPM workers, reconstruct arbitrary PHP call stacks, or measure exclusive CPU time for every PHP function.

## Features

- **Slow PHP requests:** request path, type, elapsed time, peak memory, and SQL totals.
- **SQL diagnostics:** slow queries and WordPress query callers when `SAVEQUERIES` is enabled early enough.
- **Callback profiling (v1.4):** inclusive wall-clock timing for instrumented WordPress hook callbacks, with callback identity and source location when available.
- **Outbound HTTP timing (v1.4):** WordPress HTTP API calls, remote hostnames, response status, and elapsed time.
- **Lifecycle checkpoints:** cumulative elapsed time at WordPress hooks such as `init`, `wp_loaded`, and `shutdown`.
- **WordPress admin:** **Tools → WP Slow Trace** to configure collection and inspect saved traces.
- **WP-CLI reports:** filter by time window and export tables, JSON, or CSV.
- **Bounded retention:** default seven-day cleanup and a maximum number of saved traces.
- **Plugin-only operation:** no PHP-FPM slowlog, privileged log reader, or server cron required.

## Installation

1. Download the release ZIP (`wp-slow-trace-v1.4.0.zip`).
2. In WordPress, open **Plugins → Add New Plugin → Upload Plugin**, select the ZIP, and activate **WP Slow Trace**.
3. Open **Tools → WP Slow Trace**. The plugin begins collecting eligible completed requests when enabled.
4. **Optional SQL tracing:** copy `mu-plugin/wp-slow-trace-bootstrap.php` from the plugin package to `wp-content/mu-plugins/wp-slow-trace-bootstrap.php` (create the destination directory if needed). For reliable early SQL capture, define `SAVEQUERIES` as `true` in `wp-config.php` before WordPress loads. This adds overhead; use it selectively.
5. Generate some site traffic, then inspect the dashboard or run `wp slow-trace status` from the WordPress installation directory.

**Upgrading:** Replace the installed plugin with the new release ZIP. Existing settings and trace records are intended to be preserved. The optional MU bootstrap from an earlier plugin-only release can remain in place. Take a backup and test on staging first.

## Default configuration

| Setting | Default |
| --- | --- |
| Slow PHP request threshold | **2,000 ms** |
| Slow SQL query threshold | **100 ms** |
| Trace collection mode | **Slow requests only** |
| Trace retention | **7 days** |
| Maximum slow SQL entries per saved trace | **30** |
| Maximum saved traces | **10,000** |
| Callback instrumentation cap | **2,500 wrapped callbacks/request** |
| Callback invocation measurement cap | **1,000/request** |
| Saved callback samples | **50 slowest/request** |
| Saved outbound HTTP calls | **30/request** |

The callback and HTTP caps help bound overhead and storage. Because only slow *requests* are saved in the default mode, an isolated slow SQL query may not be retained if its overall PHP request finishes below 2,000 ms.

## WP-CLI command reference

Run commands from your WordPress root (or use WP-CLI's `--path` option):

```bash
# Check configuration and trace collection status
wp slow-trace status

# Summarize recent slow requests and SQL activity
wp slow-trace report --since=24h --top=20

# Show the slowest completed PHP requests
wp slow-trace php --since=24h --top=20

# Show the slowest retained SQL queries
wp slow-trace sql --since=24h --top=30

# Show lifecycle checkpoints (cumulative elapsed times)
wp slow-trace hooks --since=24h --top=20

# NEW in v1.4: slow WordPress callbacks
wp slow-trace callbacks --since=24h --top=30

# NEW in v1.4: outbound WordPress HTTP API requests
wp slow-trace http --since=24h --top=30

# Inspect one stored request by trace ID
wp slow-trace show 146 --format=json

# Apply trace retention immediately
wp slow-trace cleanup
```

### Filters and formats

- `--since=1h`, `--since=24h`, `--since=7d`, or `--since=2w`: look back by hours, days, or weeks; maximum **365 days**.
- `--top=20`: limit list/report output; supported range **1–500**.
- `--format=table|json|csv`: supported for list/report commands, with command-specific differences.
- `wp slow-trace show <id> --format=json|table`: inspect an individual trace.

Examples for automation:

```bash
wp slow-trace report --since=24h --format=json > slow-report.json
wp slow-trace sql --since=1h --top=100 --format=csv > slow-sql.csv
wp slow-trace callbacks --since=24h --top=30 --format=json > slow-callbacks.json
```

Treat exports as sensitive diagnostics: even with best-effort SQL redaction, query metadata and file paths may expose operational details.

## Understanding the reports

### PHP requests

`wp slow-trace php` ranks **completed requests** by overall elapsed time. A slow request can be caused by PHP computation, database waits, filesystem I/O, network calls, or multiple smaller operations.

### SQL queries

`wp slow-trace sql` shows captured slow SQL statements from retained requests. It requires WordPress query collection (`SAVEQUERIES`) to have been enabled sufficiently early. **Missing SQL data does not prove that no SQL ran.** SQL literals are redacted on a best-effort basis, not with a guarantee of removing every secret.

### Hook checkpoints

`wp slow-trace hooks` reports **time elapsed since request start** at each checkpoint, *not* the exclusive execution time of that hook. For example:

```text
init       2587 ms
wp_loaded  2605 ms
shutdown   2662 ms
```

Here, most recorded time elapsed before `init`; the difference between `init` and `wp_loaded` is about **18 ms**. This is useful for narrowing down the request phase but does not identify a particular callback.

### PHP callbacks (v1.4)

`wp slow-trace callbacks` measures individual instrumented WordPress action/filter callback invocations. Timing is **inclusive wall-clock duration**, so it includes waits and can overlap for nested callbacks. It is not a per-function CPU profile. Instrumentation starts at `plugins_loaded` priority 1, and very early bootstrap activity is not individually attributed.

### Outbound HTTP (v1.4)

`wp slow-trace http` reports requests made through the **WordPress HTTP API**. It records remote hostnames rather than complete URLs or request headers. Direct cURL, sockets, and other HTTP clients that bypass the WordPress HTTP API are not covered.

## Troubleshooting a slow request

1. Find the slowest recent requests: `wp slow-trace php --since=1h --top=20`.
2. Inspect a request: `wp slow-trace show <trace-id> --format=json`.
3. Compare total request duration with SQL time: `wp slow-trace sql --since=1h --top=30`.
4. Check slow callback invocations: `wp slow-trace callbacks --since=1h --top=30`.
5. Check external waits: `wp slow-trace http --since=1h --top=30`.
6. Use `wp slow-trace hooks --since=1h --top=30` to determine which WordPress lifecycle phase was slow.

If the request duration is high but SQL, callback, and HTTP reports explain little of it, investigate uncaptured early bootstrap work, direct network clients, filesystem latency, and code that executes outside instrumented callbacks.

## Security and production considerations

- The dashboard requires WordPress administrator-level `manage_options` access.
- Saved request paths exclude query strings; outbound HTTP records use hostnames rather than full URLs.
- SQL text is redacted on a **best-effort** basis and may still contain sensitive information. Protect database access, exports, and backups.
- Instrumentation has overhead. Callback wrapping may also interact with plugins that inspect callback identity; test on staging before deploying broadly.
- Captured requests must **finish** before a trace can be stored. An indefinitely blocked or terminated worker may leave no record.
- WordPress scheduled cleanup runs when WP-Cron executes; it is not guaranteed to run at an exact time on low-traffic sites. Manual cleanup is available via WP-CLI.
- No server-level PHP-FPM configuration is required, but the plugin does not provide native PHP-FPM process stack traces.

## Project structure

```text
wp-slow-trace/
├── wp-slow-trace.php
├── includes/
│   ├── class-wst.php
│   ├── class-wst-cli.php
│   └── class-wst-profiler.php
├── mu-plugin/
│   └── wp-slow-trace-bootstrap.php
└── README.md
```

## Screenshots on GitHub

To display an actual screenshot, add `images/dashboard.png` to the repository and replace the commented image block near the top of this README with:

```markdown
![WP Slow Trace Dashboard](image/dashboard-wp-slow-trace.png)
```

Commit both files. GitHub will display the screenshot automatically. Avoid publishing screenshots that expose private URLs, SQL data, or server paths.

## Limitations

WP Slow Trace is intended for **WordPress application-level troubleshooting**. It is not a substitute for an operating-system process monitor, database server slow-query log, Xdebug/Blackfire/Tideways-style function profiler, or PHP-FPM slowlog. Historical records created before v1.4.0 do not contain the new callback or HTTP timing fields.

## License

No license is declared in the v1.4.0 package. Add an appropriate `LICENSE` file before publishing if you intend others to reuse or redistribute the code.

