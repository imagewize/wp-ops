# WordPress Speed Optimization Tools

## Chapter Purpose

This chapter focuses on measuring TTFB and using command-line checks to spot performance regressions.

## Understanding TTFB Performance

According to Google's web.dev documentation at https://web.dev/articles/ttfb:

> Because TTFB precedes user-centric metrics such as First Contentful Paint (FCP) and Largest Contentful Paint (LCP), it's recommended that your server responds to navigation requests quickly enough so that the 75th percentile of users experience an FCP within the "good" threshold. As a rough guide, most sites should strive to have a TTFB of 0.8 seconds or less.

**Performance Guidelines:**
- **Good**: TTFB ≤ 0.8 seconds
- **Needs Improvement**: 0.8 - 1.8 seconds  
- **Poor**: > 1.8 seconds

## Checking Site Speed with Command Line Tools

### Using curl

Check TTFB (Time To First Byte) and response headers:

```bash
curl -w "\nTTFB: %{time_starttransfer}s\n" -o /dev/null -s -D - https://domain.nl
```

Example output:
```
HTTP/2 200 
x-powered-by: PHP/8.0.30
content-type: text/html; charset=UTF-8
link: <https://domain.nl/wp-json/>; rel="https://api.w.org/"
link: <https://domain.nl/wp-json/wp/v2/pages/5292>; rel="alternate"; title="JSON"; type="application/json"
link: <https://domain.nl/>; rel=shortlink
etag: "130-1748673482;;;"
x-litespeed-cache: hit
content-length: 189768
date: Sat, 31 May 2025 06:40:05 GMT
server: LiteSpeed
x-powered-by: PleskLin
alt-svc: h3=":443"; ma=2592000, h3-29=":443"; ma=2592000, h3-Q050=":443"; ma=2592000, h3-Q046=":443"; ma=2592000, h3-Q043=":443"; ma=2592000, quic=":443"; ma=2592000; v="43,46"

TTFB: 0.762227s
```

### Using wget

Check response time and save timing information:

```bash
wget --server-response --spider --timeout=30 https://domain.nl 2>&1 | grep -E "(HTTP|Length|time)"
```

For more detailed timing:
```bash
time wget --spider --quiet https://domain.nl
```
