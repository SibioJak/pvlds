# WoVP test fixtures — provenance

**Model-derived, not captured.** The scores spike
(`~/workspace/pvlds-scores-spike/FINDINGS.md`) found no literal
sample response anywhere in VPin Studio's published source, so
these payloads were constructed field-by-field from Studio's own
DTO definitions, mirrored in the spike workspace at
`src/vpin-connector-wovp/.../models/`:

- `validate_apikey.json` — `ApiKeyValidationResponse`
  (`success`, `userId`, `firstName`, `lastName`).
- `challenges_search.json` — `Challenges { items: [Challenge] }`
  with `Challenge`, `PinballTable`, `PinballTableVersion`,
  `ScoreBoard { items: [ScoreBoardItem { position, values }] }`,
  and `ScoreBoardItemPositionValues` with its exact
  `@JsonProperty` spellings (PascalCase throughout, except
  `approvalNote`, which is camelCase in the DTO).

What is real here:

- The VPS ids are real: the four owned tables' game ids
  (`aT_GONvw`, `-5yMpqSy`, `WMwkA7_p`, `LJRH3fKk`) and table-file
  ids come from the real VPS database records the letter-jump
  fixtures already carry; the not-owned challenge uses AC/DC
  (LUCI Premium)'s real game id `kGBkVb-v` and table-file id
  `butCgIcLzI`.
- The challenge type codes are the `ChallengeTypeCode` enum's
  exact values: `season`, `extra`, `tournament`,
  `monthly_contracts`.

What is invented, and marked as such:

- Player names, scores, divisions, countries, challenge ids and
  names — plausible board content, nothing more. "His" rows
  belong to `fixture-user-1` ("S. Kubrick", the player's real
  league handle; `validate_apikey.json` resolves the key to
  "Fixture Player" so tests prove the plumbing, not a person).
- `approvalStatus` values are arbitrary — the field is opaque
  by design (no source anywhere states its meanings).
- `scriptMatchKeywords` are empty lists: the field's shape is
  DTO-real, its values are table-specific and unknowable from
  the spike. (The core test exercises a non-empty list by
  mutation.)
- `PinballTable.tableType` and `backglassImage` are omitted:
  their vocabularies/shapes are not established by the spike.
- The dates are placeholders. The harness stub rewrites each
  challenge's `endDateUTC` relative to serve time so deadline
  legs never rot; the parser and clock tests use their own
  fixed instants.

One row (`approvalNote: null`, Twilight Zone position 5)
exercises the parser's null tolerance, which the DTO's
nullable String permits.
