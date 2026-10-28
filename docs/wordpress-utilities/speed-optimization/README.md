# WordPress Speed Optimization Tools

Measuring TTFB with `curl` and `wget`, the 0.8 s / 1.8 s thresholds, and why to test as a crawler too: [Measuring WordPress TTFB From the Command Line](https://wpvilla.in/measure-wordpress-ttfb-curl-wget-user-agents/).

## Running the Bundled Scripts

Two runnable scripts back the manual `curl`/`wget` checks above with repeatable,
averaged measurements. They live in
[`scripts/monitoring/`](../../../scripts/monitoring/), not this folder — everything
under `wordpress-utilities/` is treated by the `wp-ops` CLI as a copy-paste
reference snippet (printed or clipboard-copied, never executed), which doesn't
fit an actual runnable tool. This README stays the docs home; `@doc` on both
scripts points back here.

- [`../../scripts/monitoring/ttfb-test.sh`](../../../scripts/monitoring/ttfb-test.sh) —
  runs `curl` against a URL 5 times from your machine, averages
  TTFB/DNS/connect/SSL timings, rates the result against the benchmarks above,
  and writes a detailed report with optimization recommendations to `audits/`.
  ```bash
  wp-ops ttfb-test https://example.com
  ```
- [`../../scripts/monitoring/remote-ttfb-ua.sh`](../../../scripts/monitoring/remote-ttfb-ua.sh) —
  runs `curl` on the server itself over SSH (so your own network distance
  doesn't skew the result), once per URL for each of: default, Googlebot,
  AhrefsBot, and Screaming Frog user agents — useful when a WAF or cache
  treats bots differently from regular visitors.
  ```bash
  wp-ops remote-ttfb-ua web@example.com https://example.com/ https://example.com/blog/
  ```