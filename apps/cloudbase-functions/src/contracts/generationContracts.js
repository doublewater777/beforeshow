export const GENERATION_TYPES = {
  candidateSongs: "candidateSongs",
  roundTripDraft: "roundTripDraft"
};

const SHOW_TYPES = new Set(["concert", "livehouse", "musicFestival"]);
const DIRECTIONS = new Set(["outbound", "return"]);
const FORBIDDEN_RESPONSE_KEYS = new Set([
  "lyrics",
  "lyric",
  "recommendationReason",
  "reason",
  "score",
  "sourceText",
  "coverUrl",
  "thumbnailUrl",
  "videoUrl",
  "audioUrl",
  "danmaku",
  "comments",
  "pageContent",
  "platformId"
]);

const SONG_TIERS = new Set(["high", "mid", "guest", "encore"]);
const LEGACY_SONG_CONFIDENCE = new Set(["high", "mid"]);

export class ContractError extends Error {
  constructor(code, message, path = "$") {
    super(message);
    this.name = "ContractError";
    this.code = code;
    this.path = path;
  }
}

export function validateGenerationRequest(input) {
  assertPlainObject(input, "$");
  assertAllowedKeys(
    input,
    ["type", "requestId", "locale", "show", "direction", "userPlaces", "constraints", "limits"],
    "$"
  );

  assertNonEmptyString(input.type, "$.type");
  if (!Object.values(GENERATION_TYPES).includes(input.type)) {
    throw new ContractError("UNSUPPORTED_TYPE", "Unsupported generation type.", "$.type");
  }

  assertNonEmptyString(input.requestId, "$.requestId");
  if (input.locale !== undefined) {
    assertNonEmptyString(input.locale, "$.locale");
  }

  switch (input.type) {
  case GENERATION_TYPES.candidateSongs:
    return validateCandidateSongsRequest(input);
  case GENERATION_TYPES.roundTripDraft:
    return validateRoundTripDraftRequest(input);
  default:
    throw new ContractError("UNSUPPORTED_TYPE", "Unsupported generation type.", "$.type");
  }
}

export function validateGenerationResponse(type, input) {
  assertNonEmptyString(type, "type");
  assertPlainObject(input, "$");
  rejectForbiddenKeysDeep(input, "$");

  switch (type) {
  case GENERATION_TYPES.candidateSongs:
    return validateCandidateSongsResponse(input);
  case GENERATION_TYPES.roundTripDraft:
    return validateRoundTripDraftResponse(input);
  default:
    throw new ContractError("UNSUPPORTED_TYPE", "Unsupported generation type.", "type");
  }
}

export function selectValidProviderResponse(type, providerResults) {
  if (!Array.isArray(providerResults) || providerResults.length === 0) {
    throw new ContractError(
      "NO_PROVIDER_RESULTS",
      "Provider fallback requires at least one provider result.",
      "$"
    );
  }

  const errors = [];

  for (const result of providerResults) {
    assertPlainObject(result, "$.providerResults[]");
    assertNonEmptyString(result.provider, "$.provider");

    if (result.response === undefined) {
      errors.push({ provider: result.provider, code: "MISSING_RESPONSE" });
      continue;
    }

    try {
      return {
        provider: result.provider,
        response: validateGenerationResponse(type, result.response),
        usedFallback: result !== providerResults[0]
      };
    } catch (error) {
      errors.push({
        provider: result.provider,
        code: error.code ?? "INVALID_PROVIDER_RESPONSE",
        path: error.path
      });
    }
  }

  throw new ContractError(
    "NO_VALID_PROVIDER_RESPONSE",
    `No provider returned a valid ${type} response.`,
    "$"
  );
}

function validateCandidateSongsRequest(input) {
  assertRequestDoesNotCarryOtherFeatureFields(input, ["direction", "userPlaces", "constraints"]);
  const show = validateShow(input.show);

  if (input.limits !== undefined) {
    assertPlainObject(input.limits, "$.limits");
    assertAllowedKeys(input.limits, ["maxSongs"], "$.limits");
    assertPositiveInteger(input.limits.maxSongs, "$.limits.maxSongs");
  }

  return { ...input, show };
}

function validateRoundTripDraftRequest(input) {
  assertRequestDoesNotCarryOtherFeatureFields(input, ["limits"]);
  const show = validateShow(input.show);
  assertNonEmptyString(input.direction, "$.direction");

  if (!DIRECTIONS.has(input.direction)) {
    throw new ContractError("INVALID_DIRECTION", "Round-trip direction is invalid.", "$.direction");
  }

  assertPlainObject(input.userPlaces, "$.userPlaces");
  assertAllowedKeys(
    input.userPlaces,
    ["origin", "destination", "hotel", "meetingPoint"],
    "$.userPlaces"
  );
  assertAtLeastOneString(input.userPlaces, "$.userPlaces");

  if (input.constraints !== undefined) {
    assertPlainObject(input.constraints, "$.constraints");
    assertAllowedKeys(input.constraints, ["arrivalBy", "departAfter", "notes"], "$.constraints");
  }

  return { ...input, show };
}

function validateCandidateSongsResponse(input) {
  assertAllowedKeys(input, ["type", "items"], "$");
  assertResponseType(input, GENERATION_TYPES.candidateSongs);
  assertArray(input.items, "$.items", { min: 1 });

  return {
    type: GENERATION_TYPES.candidateSongs,
    items: input.items.map((item, index) => {
      const path = `$.items[${index}]`;
      assertPlainObject(item, path);
      assertAllowedKeys(item, ["songName", "artist", "tier", "hint", "confidence"], path);
      assertNonEmptyString(item.songName, `${path}.songName`);
      assertNonEmptyString(item.artist, `${path}.artist`);

      let tier = "mid";
      if (item.tier !== undefined) {
        if (typeof item.tier !== "string" || !SONG_TIERS.has(item.tier)) {
          throw new ContractError(
            "INVALID_SONG_TIER",
            "Song tier must be \"high\", \"mid\", \"guest\", or \"encore\".",
            `${path}.tier`
          );
        }
        tier = item.tier;
      }

      if (item.confidence !== undefined) {
        if (typeof item.confidence !== "string" || !LEGACY_SONG_CONFIDENCE.has(item.confidence)) {
          throw new ContractError(
            "INVALID_SONG_CONFIDENCE",
            "Song confidence must be \"high\" or \"mid\".",
            `${path}.confidence`
          );
        }
        if (item.tier === undefined) {
          tier = item.confidence;
        }
      }

      const normalized = {
        songName: item.songName.trim(),
        artist: item.artist.trim(),
        tier
      };
      if (item.hint !== undefined) {
        assertNonEmptyString(item.hint, `${path}.hint`);
        normalized.hint = item.hint.trim();
      }
      return normalized;
    })
  };
}

function validateRoundTripDraftResponse(input) {
  assertAllowedKeys(input, ["type", "direction", "summary", "steps", "evidence"], "$");
  assertResponseType(input, GENERATION_TYPES.roundTripDraft);
  assertNonEmptyString(input.direction, "$.direction");

  if (!DIRECTIONS.has(input.direction)) {
    throw new ContractError("INVALID_DIRECTION", "Round-trip direction is invalid.", "$.direction");
  }

  assertNonEmptyString(input.summary, "$.summary");
  assertArray(input.steps, "$.steps", { min: 1 });
  const steps = input.steps.map((step, index) => {
    const path = `$.steps[${index}]`;
    assertPlainObject(step, path);
    assertAllowedKeys(step, ["title", "detail"], path);
    assertNonEmptyString(step.title, `${path}.title`);
    assertNonEmptyString(step.detail, `${path}.detail`);
    return {
      title: step.title.trim(),
      detail: step.detail.trim()
    };
  });

  assertArray(input.evidence, "$.evidence", { min: 1 });
  const evidence = input.evidence.map((item, index) => {
    const path = `$.evidence[${index}]`;
    assertPlainObject(item, path);
    assertAllowedKeys(item, ["title", "url"], path);
    assertNonEmptyString(item.title, `${path}.title`);
    if (item.url !== undefined) {
      assertNonEmptyString(item.url, `${path}.url`);
    }
    return {
      title: item.title.trim(),
      ...(item.url === undefined ? {} : { url: item.url.trim() })
    };
  });

  return {
    type: GENERATION_TYPES.roundTripDraft,
    direction: input.direction,
    summary: input.summary.trim(),
    steps,
    evidence
  };
}

function validateShow(show) {
  assertPlainObject(show, "$.show");
  assertAllowedKeys(show, ["name", "date", "city", "venueName", "type", "artists"], "$.show");
  assertNonEmptyString(show.name, "$.show.name");
  assertNonEmptyString(show.date, "$.show.date");
  assertNonEmptyString(show.type, "$.show.type");

  if (!SHOW_TYPES.has(show.type)) {
    throw new ContractError("INVALID_SHOW_TYPE", "Unsupported show type.", "$.show.type");
  }

  if (show.city !== undefined) {
    assertNonEmptyString(show.city, "$.show.city");
  }

  if (show.venueName !== undefined) {
    assertNonEmptyString(show.venueName, "$.show.venueName");
  }

  if (show.artists !== undefined) {
    assertArray(show.artists, "$.show.artists", { min: 1 });
    show.artists.forEach((artist, index) => {
      assertNonEmptyString(artist, `$.show.artists[${index}]`);
    });
  }

  return show;
}

function assertResponseType(input, expectedType) {
  assertNonEmptyString(input.type, "$.type");
  if (input.type !== expectedType) {
    throw new ContractError("RESPONSE_TYPE_MISMATCH", "Response type does not match.", "$.type");
  }
}

function assertRequestDoesNotCarryOtherFeatureFields(input, forbiddenFields) {
  for (const key of forbiddenFields) {
    if (input[key] !== undefined) {
      throw new ContractError(
        "UNSUPPORTED_FIELD",
        `Field ${key} is not supported for ${input.type}.`,
        `$.${key}`
      );
    }
  }
}

function rejectForbiddenKeysDeep(value, path) {
  if (Array.isArray(value)) {
    value.forEach((item, index) => {
      rejectForbiddenKeysDeep(item, `${path}[${index}]`);
    });
    return;
  }

  if (!value || typeof value !== "object") {
    return;
  }

  for (const [key, child] of Object.entries(value)) {
    const childPath = path === "$" ? `$.${key}` : `${path}.${key}`;
    if (FORBIDDEN_RESPONSE_KEYS.has(key)) {
      throw new ContractError(
        "UNSUPPORTED_RESPONSE_FIELD",
        `Response field ${key} is not supported.`,
        childPath
      );
    }
    rejectForbiddenKeysDeep(child, childPath);
  }
}

function assertPlainObject(value, path) {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    throw new ContractError("EXPECTED_OBJECT", "Expected an object.", path);
  }
}

function assertAllowedKeys(value, allowedKeys, path) {
  const allowed = new Set(allowedKeys);
  for (const key of Object.keys(value)) {
    if (!allowed.has(key)) {
      throw new ContractError(
        "UNSUPPORTED_FIELD",
        `Field ${key} is not supported.`,
        path === "$" ? `$.${key}` : `${path}.${key}`
      );
    }
  }
}

function assertArray(value, path, options = {}) {
  if (!Array.isArray(value)) {
    throw new ContractError("EXPECTED_ARRAY", "Expected an array.", path);
  }

  if (options.min !== undefined && value.length < options.min) {
    throw new ContractError("ARRAY_TOO_SHORT", "Array is too short.", path);
  }
}

function assertNonEmptyString(value, path) {
  if (typeof value !== "string" || value.trim().length === 0) {
    throw new ContractError("EXPECTED_STRING", "Expected a non-empty string.", path);
  }
}

function assertPositiveInteger(value, path) {
  if (!Number.isInteger(value) || value <= 0) {
    throw new ContractError("EXPECTED_POSITIVE_INTEGER", "Expected a positive integer.", path);
  }
}

function assertAtLeastOneString(value, path) {
  if (!Object.values(value).some((item) => typeof item === "string" && item.trim().length > 0)) {
    throw new ContractError("EXPECTED_ONE_PLACE", "At least one place is required.", path);
  }
}
