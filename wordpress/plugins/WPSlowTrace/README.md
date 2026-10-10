# WP Slow Trace 1.0.0

Installable WordPress plugin (PHP 7.4+). Defaults: 2000 ms slow PHP threshold, 100 ms SQL threshold, 7 days retention, slow requests only, max 30 slow SQL entries per trace, max 10,000 traces retained. Administrators access **Tools → WP Slow Trace**.

![WP Slow Trace Dashboard](image/dashboard-wp-slow-trace.png)

## Install

1. Upload the `wp-slow-trace` folder as a ZIP through **Plugins → Add New → Upload Plugin**, then activate. Alternatively extract it under `wp-content/plugins/` and activate.
2. For SQL query timing, copy `mu-plugin/wp-slow-trace-bootstrap.php` to `wp-content/mu-plugins/wp-slow-trace-bootstrap.php` (create `mu-plugins` if needed). This must be a direct file, not nested inside a folder.
3. Confirm `SAVEQUERIES` is not set to `false` in `wp-config.php` or elsewhere. For earliest query capture, define `SAVEQUERIES` as true in `wp-config.php` **before** WordPress bootstrap instead of relying on the MU file. Warning: query collection incurs overhead on every request, even fast ones; enable only for bounded diagnostic windows. Remove/disable `SAVEQUERIES` when not troubleshooting.
4. Go to **Tools → WP Slow Trace**. The plugin automatically records requests taking at least 2 seconds and purges entries older than 7 days via WP-Cron. On low-traffic sites, WP-Cron may run late. For strict retention, schedule WP-Cron externally.
5. For server-side PHP-FPM slow stack traces, follow `docs/PHP-FPM.md` and configure the correct PHP-FPM pool separately. No automatic FPM log ingestion is included.

## Security / limitations

- Only `manage_options` users can view/change traces; all actions use nonces. Query SQL string/number literals are masked best-effort. This is **not** a full SQL parser and cannot guarantee removal of all sensitive data (e.g., identifiers, comments, encoded data, unquoted values, caller strings). Treat stored traces as sensitive and restrict database backups/access.
- Query capture is opt-in through `SAVEQUERIES`. Query collection has unavoidable memory/CPU overhead and captures all queries in PHP memory before the slow-only persistence decision. Avoid leaving it enabled indefinitely on high-traffic production sites.
- Records store the path only (no URL query string, POST body, cookies, user identity, or IP). Some paths may still contain sensitive tokens or IDs. The SQL caller string may include filesystem paths.
- Only completed/shutting-down PHP requests can write traces. Fatal errors may still reach shutdown; OOM, hard kill, worker crashes and blocked workers may not. For those, use PHP-FPM slowlogs and OS-level diagnostics.
- `sql_total_ms` reflects queries visible to `$wpdb`, not direct PDO/mysqli calls. DB tracing includes the caller string from WordPress, not a full per-query PHP backtrace. Plugin does not implement continuous function-level PHP profiling; PHP-FPM slowlogs provide sampled PHP stack traces for slow workers.
- Collection of SQL timings is unavailable if `SAVEQUERIES` was not enabled early enough. WordPress core and other plugins can alter query recording.
- This version intentionally enforces **slow-only** mode, with no unrestricted capture-all mode.
- Uninstalling/deactivating does not erase diagnostic records automatically. Use **Delete all traces** before uninstalling if desired.

## Compatibility

WordPress 6.x, PHP 7.4+ (targeted; test in staging with your WordPress and PHP version). MariaDB/MySQL using WordPress `$wpdb`. Multisite creates tables per site on activation for that site; network-wide multisite activation and central reporting are not implemented.
~                                                                                 
