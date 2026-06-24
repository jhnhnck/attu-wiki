# Pre-mortem — acme-sh-migration

**Bottom line: proceed with revisions** (all folded into plan.md)

### Risks

- [high] scope — `--install-cert` loop over all three domains was wrong: acme.sh can
  only install-cert for a domain issued as primary; `dev.attuproject.org` and
  `links.attuproject.org` would fail. Fixed: issue one multi-SAN cert, install once
  to `attuproject.org/` directory. · probe: Phase 0 staging run confirms single-cert
  layout before Phase 1 switches to production CA.

- [high] operational — Caddy must be reconfigured to read from the new cert path
  before certbot mounts are removed; without this, Phase 2 cleanup is a deploy
  blocker. Fixed: explicit coordination dependency section added; Phase 2 prerequisite
  stated. · probe: confirm Caddy config before merging Phase 2 branch.

- [medium] dependency — acme.sh installed via unpinned `curl | sh` is a supply-chain
  and offline-build risk. Fixed: install from pinned GitHub release URL + sha256sum
  check, same pattern as `discord.sh`. · probe: verify checksum matches expected hash
  in the Dockerfile PR.

- [medium] premise — Phase 0 skeleton didn't originally test state persistence across
  container restart. Fixed: Phase 0 DoD explicitly requires restart + re-run proving
  exit 2.

- [medium] scope — `migration/override.prod.yml` and `migrate.zsh` also hold certbot
  references; plan originally missed them. Fixed: added to Phase 2 file list.

- [low] scope — `--register-account` called on every renewal run is unnecessary;
  `--issue` auto-registers on first run. Fixed: removed from final script.
