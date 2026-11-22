# MamaBot legal webpages

These are the **MamaBot-only** Terms of Use and Privacy Policy webpages.

They are deliberately separate from HelpMum's general website pages:

- `https://helpmum.org/terms`
- `https://helpmum.org/privacy`

Do **not** replace those general pages.

## Live URLs

The pages are hosted on Netlify (public, HTTPS):

```text
https://mamabot-legal.netlify.app/terms.html
https://mamabot-legal.netlify.app/privacy.html
```

Landing page:

```text
https://mamabot-legal.netlify.app/
```

Netlify project: `mamabot-legal` in the Netlify account signed in as `chatbot@helpmum.org`. It is set to **Public** (anyone with the address can open it).

The HTML files still live in this `docs/mamabot-legal/` folder as the source of truth. A GitHub Pages copy also exists, but the user's network refuses connections to `github.io`, so Netlify is the URL used by the app and Play Console.

## Update the documents later

The HTML pages are generated from the app's Markdown files. After editing either legal document, run:

```bash
python3 tools/build_legal_pages.py
```

Then commit and push the generated `docs/mamabot-legal/*.html` files. If the wording shown to users changes, also upload the updated `terms.html`, `privacy.html` and `index.html` to the Netlify project (`mamabot-legal`) so the live pages match.

## Google Play Console

Set the Privacy Policy URL to:

```text
https://mamabot-legal.netlify.app/privacy.html
```

## If you later get a nicer MamaBot domain

Change only `lib/core/config/legal_links.dart` and the last line of `assets/legal/privacy_policy.md`, then rebuild the app. The HTML pages cross-link to each other with relative links, so they keep working.
