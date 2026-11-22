#!/usr/bin/env python3
"""Build the MamaBot-only legal HTML pages from the app's Markdown assets."""

from pathlib import Path
import html
import re

ROOT = Path(__file__).resolve().parents[1]
LEGAL = ROOT / "assets" / "legal"
OUT_DIR = ROOT / "docs" / "mamabot-legal"

CSS = """
:root { color-scheme: light; }
* { box-sizing: border-box; }
body {
  margin: 0;
  background: #f5f8f7;
  color: #17332d;
  font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif;
  line-height: 1.65;
}
.topbar { background: #ffffff; border-bottom: 1px solid #dce8e4; }
.wrap { width: min(860px, calc(100% - 32px)); margin: 0 auto; }
.nav { display: flex; align-items: center; justify-content: space-between; gap: 16px; padding: 18px 0; flex-wrap: wrap; }
.brand { color: #0f6b58; font-weight: 800; font-size: 18px; text-decoration: none; letter-spacing: -0.2px; }
nav { display: flex; gap: 18px; flex-wrap: wrap; }
nav a { color: #31574e; font-size: 14px; font-weight: 700; text-decoration: none; padding-bottom: 3px; border-bottom: 2px solid transparent; }
nav a:hover, nav a.active { color: #0f6b58; border-bottom-color: #0f6b58; }
.card {
  background: #ffffff;
  margin: 28px 0;
  padding: 38px 42px;
  border: 1px solid #dce8e4;
  border-radius: 18px;
  box-shadow: 0 10px 30px rgba(18, 73, 61, 0.06);
}
h1 { font-size: 27px; line-height: 1.25; margin: 0 0 6px; color: #0d3f35; letter-spacing: -0.4px; }
h2 { font-size: 18px; line-height: 1.35; margin: 30px 0 10px; color: #0f6b58; letter-spacing: -0.1px; }
p { margin: 0 0 14px; font-size: 15px; }
ul { margin: 0 0 14px; padding-left: 22px; font-size: 15px; }
li { margin-bottom: 7px; }
a { color: #0f6b58; text-decoration-thickness: 1px; text-underline-offset: 2px; }
footer { text-align: center; color: #6a7f79; font-size: 13px; padding: 0 16px 36px; }
@media (max-width: 600px) {
  .card { padding: 26px 20px; border-radius: 14px; margin: 18px 0; }
  h1 { font-size: 23px; }
  nav { gap: 12px; }
}
"""


def inline(text: str) -> str:
    out = html.escape(text)
    out = out.replace("\t", "&nbsp;&nbsp;&nbsp;&nbsp;")
    out = re.sub(r"(https?://[^\s<]+)", r'<a href="\1" target="_blank" rel="noopener">\1</a>', out)
    out = re.sub(
        r"([A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,})",
        r'<a href="mailto:\1">\1</a>',
        out,
    )
    return out


def render(md_path: Path, active: str) -> str:
    lines = md_path.read_text(encoding="utf-8").splitlines()
    body = []
    i = 0
    while i < len(lines):
        stripped = lines[i].strip()
        if not stripped:
            i += 1
            continue
        if stripped.startswith("## "):
            body.append("<h2>" + inline(stripped[3:]) + "</h2>")
            i += 1
        elif stripped.startswith("# "):
            body.append("<h1>" + inline(stripped[2:]) + "</h1>")
            i += 1
        elif stripped.startswith("- "):
            items = []
            while i < len(lines) and lines[i].strip().startswith("- "):
                items.append("<li>" + inline(lines[i].strip()[2:]) + "</li>")
                i += 1
            body.append("<ul>" + "".join(items) + "</ul>")
        else:
            body.append("<p>" + inline(stripped) + "</p>")
            i += 1

    terms_active = ' class="active"' if active == "terms" else ""
    privacy_active = ' class="active"' if active == "privacy" else ""
    title = "MamaBot AI Terms of Use" if active == "terms" else "MamaBot AI Privacy Policy"
    return (
        "<!doctype html>\n"
        '<html lang="en">\n'
        "<head>\n"
        '  <meta charset="utf-8">\n'
        '  <meta name="viewport" content="width=device-width, initial-scale=1">\n'
        f"  <title>{html.escape(title)}</title>\n"
        f'  <meta name="description" content="{html.escape(title)} for the MamaBot AI mobile application.">\n'
        f"  <style>{CSS}</style>\n"
        "</head>\n"
        "<body>\n"
        '  <header class="topbar">\n'
        '    <div class="wrap nav">\n'
        '      <a class="brand" href="privacy.html">MamaBot AI</a>\n'
        '      <nav aria-label="Legal documents">\n'
        f'        <a{terms_active} href="terms.html">Terms of Use</a>\n'
        f'        <a{privacy_active} href="privacy.html">Privacy Policy</a>\n'
        "      </nav>\n"
        "    </div>\n"
        "  </header>\n"
        '  <main class="wrap card">\n' + "\n".join(body) + "\n  </main>\n"
        "  <footer>HelpMum Africa Foundation &middot; MamaBot AI &middot; Version 1.0</footer>\n"
        "</body>\n"
        "</html>\n"
    )


def main() -> None:
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    (OUT_DIR / "terms.html").write_text(render(LEGAL / "terms_of_use.md", "terms"), encoding="utf-8")
    (OUT_DIR / "privacy.html").write_text(render(LEGAL / "privacy_policy.md", "privacy"), encoding="utf-8")
    print(f"Wrote {OUT_DIR / 'terms.html'}")
    print(f"Wrote {OUT_DIR / 'privacy.html'}")


if __name__ == "__main__":
    main()
