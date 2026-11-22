# MamaBot legal webpages

These are the **MamaBot-only** Terms of Use and Privacy Policy webpages.

They are deliberately separate from HelpMum's general website pages:

- `https://helpmum.org/terms`
- `https://helpmum.org/privacy`

Do **not** replace those general pages.

## Live GitHub Pages URLs

After GitHub Pages is enabled for this repository, the pages will be:

```text
https://helpmumchatbot359.github.io/Offline-first-on-device-AI-chatbot/docs/mamabot-legal/terms.html
https://helpmumchatbot359.github.io/Offline-first-on-device-AI-chatbot/docs/mamabot-legal/privacy.html
```

## Enable GitHub Pages

1. Go to the repository on GitHub:

   ```text
   https://github.com/helpmumchatbot359/Offline-first-on-device-AI-chatbot
   ```

2. Open **Settings**.
3. Open **Pages** (under *Code and automation*).
4. Under **Build and deployment**:
   - **Source:** `Deploy from a branch`
   - **Branch:** `main`
   - **Folder:** `/docs`
5. Click **Save**.
6. Wait 1–2 minutes, then open the two URLs above.

The MamaBot legal pages are in `docs/mamabot-legal/`, so they will be served automatically from the `/docs` folder.

## Update the documents later

The HTML pages are generated from the app's Markdown files. After editing either legal document, run:

```bash
python3 tools/build_legal_pages.py
```

Then commit and push the generated `docs/mamabot-legal/*.html` files.

## Google Play Console

Set the Privacy Policy URL to:

```text
https://helpmumchatbot359.github.io/Offline-first-on-device-AI-chatbot/docs/mamabot-legal/privacy.html
```

## If you later get a nicer MamaBot domain

Change only `lib/core/config/legal_links.dart` and the last line of `assets/legal/privacy_policy.md`, then rebuild the app. The HTML pages cross-link to each other with relative links, so they keep working.
