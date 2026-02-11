# WordPress Multisite Slug Mismatch Incident (Fintech → Kafe)

## Summary

A WordPress Multisite site rename from **`/fintech/`** to **`/kafe/`** resulted in an inconsistent state where:

* The database (`wp_blogs.path`) showed the new slug `/kafe/`
* WP-CLI and Network Admin still referenced `/fintech/`
* Admin links using `blog_id=6` behaved unpredictably
* The site appeared partially renamed and partially “missing”

This was **not a failed site creation**, but a **slug change that did not fully propagate through Multisite caches and per-site options**.

---

## Symptoms Observed

* `wp site list` still displayed:

  ```
  https://demo.imagewize.com/fintech/
  ```

  even though the database showed `/kafe/`.

* Visiting:

  ```
  /wp-admin/network/site-info.php?id=6
  ```

  loaded incorrect or stale site data.

* The new site seemed to “take over” the old one instead of being created cleanly.

---

## Root Cause

WordPress Multisite stores site identity in multiple layers:

| Layer                             | What Happened                  |
| --------------------------------- | ------------------------------ |
| `wp_blogs` table                  | Updated to `/kafe/` ✅          |
| Per-site options (`wp_6_options`) | Still referenced `/fintech/` ❌ |
| Object cache (Redis)              | Cached old blog path ❌         |
| Multisite blog lookup cache       | Not invalidated ❌              |

Because Multisite relies heavily on cached **blog lookup mappings**, WordPress continued resolving:

```
blog_id 6 → /fintech/
```

even after the database row had changed.

This created a **split-brain state** between database truth and cached routing.

---

## Resolution

The fix required synchronizing **all three layers**:

1. **Correct the site’s own URL settings**
   (Multisite does NOT update these automatically when changing slugs)

   ```bash
   wp --url=https://demo.imagewize.com/kafe option update siteurl https://demo.imagewize.com/kafe --path=web/wp
   wp --url=https://demo.imagewize.com/kafe option update home https://demo.imagewize.com/kafe --path=web/wp
   ```

2. **Replace lingering references inside the site**

   ```bash
   wp --url=https://demo.imagewize.com/kafe search-replace '/fintech/' '/kafe/' --skip-columns=guid --path=web/wp
   ```

3. **Flush WordPress object cache**

   ```bash
   wp cache flush --path=web/wp
   ```

4. **Flush Redis persistent cache (critical)**

   ```bash
   redis-cli FLUSHALL
   ```

5. **Clear Multisite blog lookup cache**

   ```bash
   wp db query "DELETE FROM wp_sitemeta WHERE meta_key LIKE '%blog_lookup%';"
   ```

6. **Rebuild rewrite rules**

   ```bash
   wp rewrite flush --hard --path=web/wp
   ```

After these steps, `wp site list` correctly reflected:

```
https://demo.imagewize.com/kafe/
```

---

## Why This Happens (Multisite Gotcha)

In Multisite, changing a site slug is **not a single operation**.

WordPress does **not automatically invalidate**:

* Persistent object cache (Redis / Relay)
* Blog lookup mappings
* Per-site `home` and `siteurl` values
* Domain-mapping / sunrise cache (if present)

So a manual rename can leave the network in an inconsistent routing state unless caches are explicitly cleared.

---

## Prevention Guidelines

When renaming a Multisite subsite:

### ✅ Always perform these steps together

1. Update the slug (DB or via tooling).
2. Immediately update that site’s `home` and `siteurl`.
3. Run a search-replace for old paths.
4. Flush **persistent cache** (Redis).
5. Flush WP cache + rewrite rules.

### ❌ Avoid

* Renaming via database only.
* Creating a new site using a previously used slug without cache flush.
* Assuming `wp_blogs` change is enough (it isn’t).

---

## Quick Rename Checklist (Future Use)

```bash
# After changing slug:
wp --url=<new-url> option update siteurl <new-url>
wp --url=<new-url> option update home <new-url>

wp --url=<new-url> search-replace '<old-path>' '<new-path>' --skip-columns=guid

wp cache flush
redis-cli FLUSHALL

wp db query "DELETE FROM wp_sitemeta WHERE meta_key LIKE '%blog_lookup%';"

wp rewrite flush --hard
```

---

## Final Status

✔ Site `/kafe/` now resolves correctly
✔ Network Admin links map to correct blog
✔ No remaining references to `/fintech/`
✔ Multisite routing and cache fully consistent

---

**Lesson Learned:**

> In WordPress Multisite, a site slug is cached infrastructure — not just a string.
