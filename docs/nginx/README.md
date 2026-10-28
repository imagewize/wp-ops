# Nginx Configuration Tools

Nginx include templates for WordPress sites on [Roots Trellis](https://roots.io/trellis/). Each guide below covers one template, how to wire it into `wordpress_sites.yml`, and how to check it deployed.

| Guide | What it deploys |
|-------|-----------------|
| [browser-caching/](browser-caching/README.md) | Cache headers for static assets (global include) |
| [image-optimization/](image-optimization/README.md) | Automatic WebP/AVIF content negotiation (site include) |
| [redirects/](redirects/README.md) | SEO redirect templates and examples (site include) |

## Deploying an include

1. **Copy the template** into your Trellis project:
   ```bash
   # Site-specific include
   cp docs/nginx/image-optimization/nginx-includes/webp-avf.conf.j2 \
      ~/trellis/nginx-includes/

   # Global include (applies to every site on the server)
   cp docs/nginx/browser-caching/nginx-includes/all/assets-expiry.conf.j2 \
      ~/trellis/nginx-includes/all/
   ```

2. **Reference site-specific includes** in `group_vars/production/wordpress_sites.yml`. Files under `nginx-includes/all/` need no entry:
   ```yaml
   wordpress_sites:
     example.com:
       nginx_includes:
         - nginx-includes/webp-avf.conf.j2
         - nginx-includes/seo-redirects.conf.j2
   ```

3. **Try it in the VM first**, then deploy with the `nginx-includes` tag:
   ```bash
   trellis provision development
   trellis vm shell -- sudo nginx -t

   trellis provision --tags nginx-includes production
   ```

4. **Verify** with `curl -I` against a real URL (each guide lists the expected headers).

## Scopes

| Directory in your Trellis project | Lands on the server at | Use for |
|-----------------------------------|------------------------|---------|
| `nginx-includes/all/` | `/etc/nginx/includes.d/all/` | Caching headers, security headers, rate limits: anything every site wants |
| `nginx-includes/` | `/etc/nginx/includes.d/example.com/` | Image negotiation, per-site redirects, custom rewrites |

All templates use the `.conf.j2` extension, so Trellis variables such as `{{ site_name }}` and Jinja2 conditionals work. Trellis validates the syntax and reloads Nginx after provisioning.

## Troubleshooting

1. **Configuration not applied**: confirm the file sits in the right `nginx-includes/` directory, that `wordpress_sites.yml` names it, and re-provision with `--tags nginx-includes`.
2. **Syntax errors**: run `sudo nginx -t` on the server, check the `.conf.j2` for typos and Jinja2 mistakes, and read `/var/log/nginx/error.log`.
3. **Includes not loaded**: `ssh web@example.com "grep -r 'include.*includes.d' /etc/nginx/sites-enabled/"`.
4. **Redirect loops, WebP not served, headers missing**: see the troubleshooting section of the matching guide.

## Further reading

- [Trellis Nginx configuration](https://roots.io/trellis/docs/nginx/)
- [Nginx documentation](https://nginx.org/en/docs/)
