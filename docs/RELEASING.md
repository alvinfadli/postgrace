# Releasing Postgrace on GitHub

This guide outlines how to build, verify, and publish releases for **Postgrace** on GitHub.

---

## 1. Automated Releases via GitHub Actions (Recommended)

Postgrace includes automated GitHub Actions workflows in `.github/workflows/release.yml`.

### Option A: Tag & Push (Full Automation)

Whenever a tag prefixed with `v` (e.g. `v0.1.1`) is pushed to GitHub, the workflow automatically:
1. Spins up an Apple Silicon `macos-14` runner.
2. Runs the full test suite (`swift test --parallel`).
3. Compiles the release binary (`swift build -c release`).
4. Bundles `Postgrace.app`, codesigns (ad-hoc or Developer ID), and creates:
   - `Postgrace-<version>.dmg`
   - `Postgrace-<version>.zip`
   - `Postgrace.dmg`
   - `SHA256SUMS.txt`
5. Automatically creates the GitHub Release, attaches all 4 artifacts, and generates release notes from commit history.

To release:
```bash
# Ensure main is up to date and clean
git checkout main
git pull origin main

# Create the semantic tag (if not already created)
git tag -a v0.1.1 -m "Postgrace v0.1.1"

# Push the tag to GitHub
git push origin v0.1.1
```

### Option B: Trigger via GitHub Actions UI (`workflow_dispatch`)

1. Go to `https://github.com/alvinfadli/postgrace/actions/workflows/release.yml`.
2. Click **Run workflow**.
3. (Optional) Provide the tag name, e.g. `v0.1.1`.
4. Click **Run workflow**.

---

## 2. Publishing via GitHub CLI (`gh`)

If you build locally or have artifacts in `dist/`, you can publish via the GitHub CLI:

```bash
# 1. Build release artifacts locally
VERSION=0.1.1 ./scripts/build_dmg.sh

# 2. Publish release to GitHub
gh release create v0.1.1 \
  dist/Postgrace-0.1.1.dmg \
  dist/Postgrace-0.1.1.zip \
  dist/Postgrace.dmg \
  dist/SHA256SUMS.txt \
  --title "Postgrace v0.1.1" \
  --generate-notes
```

---

## 3. Manual Web Release via GitHub UI

If uploading manually via the GitHub website:

1. Navigate to: `https://github.com/alvinfadli/postgrace/releases/new`
2. Select tag: **`v0.1.1`** (or click **Create new tag: v0.1.1 on publish**).
3. Set Release title: `Postgrace v0.1.1`
4. Click **Generate release notes** to auto-populate commits.
5. In the **Attach binaries by dropping them here or selecting them** box, upload the files from `dist/`:
   - `Postgrace-0.1.1.dmg`
   - `Postgrace-0.1.1.zip`
   - `Postgrace.dmg`
   - `SHA256SUMS.txt`
6. Click **Publish release**.

---

## 4. Release Checklist & Verification

Before publishing:
- [ ] Check `swift test` passes 100%.
- [ ] Verify `dist/SHA256SUMS.txt` contains matching hashes:
  ```bash
  cd dist && shasum -a 256 -c SHA256SUMS.txt
  ```
- [ ] Verify DMG mounts cleanly:
  ```bash
  hdiutil attach dist/Postgrace-0.1.1.dmg
  hdiutil detach /Volumes/Postgrace
  ```

---

## 5. Gatekeeper Advisory for Community Previews

Because preview builds are ad-hoc signed, macOS Gatekeeper may present an "unidentified developer" prompt. Users can bypass this by:
- Right-clicking `Postgrace.app` in `/Applications` and selecting **Open**.
- Or running:
  ```bash
  xattr -cr /Applications/Postgrace.app
  ```
