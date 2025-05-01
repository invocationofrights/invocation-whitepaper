# Invocation of Rights – White-Paper sources

This repository contains the XeLaTeX sources for the *Invocation of Rights* white-paper.  
No PDFs live in the repo; they are built automatically and published by GitHub Actions.

---

## 📁 Repo layout
```pre
├── Invocation_of_Rights.tex # root document
├── sections/ # .tex fragments
└── .github/
  └── workflows/
    └── latex.yml # CI pipeline (build + release + Pages)
```
---

## 🚀 How the CI pipeline works

| Step                 | Trigger                                 | Output                                                                                              |
|----------------------|-----------------------------------------|-----------------------------------------------------------------------------------------------------|
| **Compile PDF**      | `release` event (`gh release create …`) | `Invocation_of_Rights.pdf`                                                                          |
| **Attach asset**     | same job                                | release asset (download-only)                                                                       |
| **Publish to Pages** | same job                                | inline view at:<br> `https://invocationofrights.org/invocation-whitepaper/Invocation_of_Rights.pdf` |

### Key URLs

* **Latest inline (view in browser)**  
  https://invocationofrights.org/invocation-whitepaper/Invocation_of_Rights.pdf

* **Latest immutable download**  
  https://github.com/invocationofrights/invocation-whitepaper/releases/latest/download/Invocation_of_Rights.pdf

---

## 🛠️ Day-to-day author flow

# 1. edit .tex, .bib, etc.
```bash
git add -A
git commit -m "draft edits"
```

# 2. bump version tag & publish Release (fires CI)
```bash
git tag -a v1.2.0 -m "White-paper v1.2.0"
git push origin v1.2.0
gh release create v1.2.0 --title "White-paper v1.2.0" --notes "see changelog"
```

# 3. optional: watch the build
```bash
gh run watch $(gh run list -L1 -q '.[0].id')
```
Within ~1 min the PDF is attached to the Release and live at the Pages URL.

Manual rebuild (no new Release)
```bash
gh workflow run latex.yml                  # compile only
gh run watch $(gh run list -L1 -q '.[0].id')
gh run download --name pdf --dir build/    # PDF lands in build/
```
