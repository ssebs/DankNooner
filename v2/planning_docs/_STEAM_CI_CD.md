# Steam CI/CD (not yet implemented)

Plan for uploading builds to Steam depots from GitHub Actions, as a job next to
`create_release` / `deploy_pages` / `deploy_docker` in `.github/workflows/build.yml`.

Uses [`game-ci/steam-deploy`](https://github.com/game-ci/steam-deploy), which wraps `steamcmd` + build scripts.

## One-time setup

1. **Dedicated builder Steam account.** In Steamworks, add it to the partner group with only
   "Edit App Metadata" + "Publish App Changes To Steam". Don't use the main account.
2. **Log in once locally:** `steamcmd +login <builder>`, complete Steam Guard. This writes a login
   token to `config/config.vdf`.
3. **GitHub secrets:**
   - `STEAM_USERNAME`
   - `STEAM_CONFIG_VDF`: base64 of that file (`base64 -w0 config/config.vdf`)

   The token can expire. If uploads start failing login, redo step 2 and update the secret.

## Job sketch

```yaml
  deploy_steam:
    needs: export_game
    runs-on: ubuntu-latest
    steps:
      - uses: actions/download-artifact@v4
        with: { pattern: build-*, merge-multiple: true, path: /tmp/builds }
      # Steam depots need the raw files, not zips
      - run: |
          for p in Linux Windows Mac; do
            mkdir -p /tmp/steam/$p && unzip /tmp/builds/DankNooner$p.zip -d /tmp/steam/$p
          done
      - uses: game-ci/steam-deploy@v3
        with:
          username: ${{ secrets.STEAM_USERNAME }}
          configVdf: ${{ secrets.STEAM_CONFIG_VDF }}
          appId: <APP_ID>
          buildDescription: ${{ github.ref_name }}
          rootPath: /tmp/steam
          depot1Path: Windows   # depot numbering follows appId+1, +2…; check the action README
          depot2Path: Linux
          depot3Path: Mac
          releaseBranch: beta   # optional
```

## Gotchas

- **Depot IDs:** the action assumes depots are numbered `appId+1`, `appId+2`, etc. If ours differ,
  write a custom `app_build.vdf` and call `steamcmd` directly.
- **Going live:** Valve doesn't allow scripts to set a build live on the `default` branch.
  `releaseBranch` can push to e.g. `beta`. Without it the build only uploads, and it's set live
  manually in Steamworks (a reasonable safety gate anyway).
- **Mac:** the `.app` must keep exec bits after unzip. Notarization is likely a separate problem.
- **Unverified:** input names are from memory of v3. Check the action's current README before wiring.
