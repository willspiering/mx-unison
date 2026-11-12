# Development workflow

This workflow works for a solo maintainer and can grow into a public collaboration process. Keep source changes in your checkout, run checks, commit them, then deploy. Editing the installed copy directly will leave changes outside version control.

## Git setup

The repository preserves its inherited MX Control history. `upstream` points to the original project for reference. Its local push URL is disabled; the optional pre-push hook also rejects pushes to that remote. `main` intentionally does not track upstream: pulling upstream into it without review could overwrite assumptions specific to this fork. The inherited checkout is shallow; fetch more history if you need it:

```sh
git fetch --unshallow upstream  # only while git rev-parse --is-shallow-repository says true
```

The public repository is `https://github.com/willspiering/mx-unison` and is configured as `origin`. Contributors should fork it and open pull requests against `main`. Before committing, check that your commit author email is one you are happy to publish; GitHub's `users.noreply.github.com` address is a good default. Preserved upstream commits retain their original authorship.

Useful inspection commands:

```sh
git status
git remote -v
git log --oneline --decorate -10
```

Local configuration uses fast-forward-only pulls and `push.default = simple`. Pushing `main` explicitly targets `origin`; until that remote exists a plain push should fail. This avoids accidentally pushing the fork to the original repository. Local hooks live in `.githooks/` and are enabled in the current checkout. Hooks and local Git configuration do not automatically propagate to fresh clones; opt in there with:

```sh
git config --local core.hooksPath .githooks
git config --local pull.ff only
git config --local push.default simple
git config --local branch.main.pushRemote origin
```

The pre-commit hook checks whitespace and common accidentally staged local artifacts. It is not a secret scanner. The pre-push hook blocks `upstream` and runs automated checks. Hooks can be bypassed and are not security boundaries; CI is the shared verification mechanism.

## Everyday changes

```sh
git switch main
git switch -c feat/describe-the-change
# Edit source, docs and relevant tests.
./scripts/check.sh
git diff --check
git diff
git add PATHS_YOU_REVIEWED
git diff --cached
git commit -m "Describe the resulting behavior"
python3 scripts/deploy.py --dry-run
python3 scripts/deploy.py --enable
```

After `origin` is configured, push the branch and use a pull request, or merge locally for small solo changes:

```sh
git switch main
git merge --ff-only feat/describe-the-change
git push origin main
```

If `main` advanced, rebase or merge the feature branch deliberately before attempting a fast-forward merge. Do not force-push `main`. Tag a release only after appropriate hardware verification; a software test pass alone is not evidence that switching works on a specific model or transport.

To inspect upstream changes, use `git fetch upstream` and compare before selectively cherry-picking or merging. Preserve attribution and license notices. Fetching does not update local files.

## Checks and hardware validation

`./scripts/check.sh` runs the Python unit suite, both JavaScript model checks, and whitespace validation. Python tests use synthetic data and mocked device APIs. They require Unix sockets; a restricted sandbox may block socket tests. The GitHub Actions workflow runs the Python/JavaScript tests for pushes to `main` and pull requests.

Hardware testing is separate and should record model family, firmware, transport, dependency versions, steps and observed results, without serial numbers or host names. Cover:

- Discovery, supported settings, wake/reconnect and permission failures.
- Remap and shortcut restoration after normal shutdown and interrupted operation.
- Scroll/acceleration application, compositor reload and orderly restoration.
- Different channel mappings, unavailable group members and unpaired destinations.
- Real group switching in both directions, including partial failures.
- CHANGE_HOST v2 notification behavior before claiming physical Easy-Switch compatibility.

Do not trigger a live host switch as an automated test. It can disconnect the inputs needed to recover the session.

## Deployment and rollback

`python3 scripts/deploy.py --dry-run` validates the manifest and lists the files that would be copied. Without `--dry-run`, it copies only the explicit runtime allowlist and the translation catalogs. Tests, Git history, screenshots, preferences and runtime snapshots are excluded.

Existing installations are backed up under `$XDG_STATE_HOME/mx-unison/backups/` (default `~/.local/state/mx-unison/backups/`). The source checkout and deployed plugin are separate directories. `--enable` rescans the shell and enables the bar widget; it does not install Solaar, configure devices or edit Hyprland bindings. An IPC failure may leave files installed but not enabled; the script reports failure so you can resolve the shell connection and retry.

Shell file watching may reload plugins while files are copied. Deploy when not using device software actions. QML components can remain cached even after a rescan; if behavior is stale, run `omarchy restart shell` at a convenient time. Avoid deploying directly from an unreviewed branch.

To roll back, disable the plugin, move the current installed directory aside, copy the desired backup back to `~/.config/omarchy/plugins/local.mx-unison/`, rescan with `omarchy-shell shell rescanPlugins`, and enable it again. Restart the shell if needed. Do not overwrite local preferences as part of code rollback; review schema compatibility first.

## Source conventions

Use plain-text QML sinks for device and other dynamic text. Escape dynamic text before passing it to shared tooltip components that do not expose text-format controls. Keep hardware writes on the helper’s command thread, network access explicit, and group switching opt-in. Use Omarchy theme/motion primitives and add new UI strings to `i18n/en.json`. Document behavioral limitations alongside features, and add regression tests for meaningful backend changes.
