# ActiveStorage SCAP Content Proof of Concept

## Goal

Demonstrate how `ForemanOpenscap::ScapContent` can store its SCAP XML data stream using the ActiveStorage support being added to Foreman, instead of relying on the plugin's `scap_file` database column and controller-specific file handling.

This is a proof of concept, not a production migration. It intentionally covers `ScapContent` only; `TailoringFile` remains unchanged for a later follow-up.

## Scope

The POC covers the existing SCAP content lifecycle:

- model attachment and validation;
- HTML and API upload paths;
- bulk upload from files on disk;
- digest calculation and filename metadata;
- proxy profile discovery, which requires the XML contents;
- HTML and API XML downloads;
- API serialization and focused regression tests.

The existing `original_filename` and `digest` columns remain as compatibility metadata. The legacy `scap_file` column is not removed and no data migration is attempted. Existing records are therefore outside the migration guarantee of this POC unless the ActiveStorage attachment is present.

## Design

`ScapContent` declares a single ActiveStorage attachment named `scap_file`. Callers continue to use the domain-level `scap_file` concept, but file bytes are attached through ActiveStorage rather than assigned to an ActiveRecord binary attribute.

The model concern will provide the compatibility behavior needed by the current plugin:

- validate that the attachment is present;
- expose a byte/string read operation for XML parsing, proxy calls, downloads, and JSON encoding;
- calculate SHA-256 from the attachment contents;
- update `digest` when a new file is attached;
- preserve `original_filename` from the uploaded file.

Upload controllers will attach the uploaded IO directly and will no longer read the entire temporary file into the request parameter hash. The bulk uploader will attach an opened file and retain its existing title, taxonomy, and error handling behavior.

Download actions will use the attachment contents and existing response headers rather than exposing ActiveStorage routes, because these endpoints are already authorized plugin endpoints and must preserve their current URLs and filenames.

## Data flow

1. A multipart upload supplies an IO-like object.
2. `ScapContent` is initialized with regular metadata; the IO is attached through ActiveStorage.
3. Model validation checks attachment presence and SCAP validity.
4. After a successful save, profile discovery reads the attached XML through the attachment API.
5. API and HTML download actions read the attachment and use `original_filename` as before.
6. Bulk upload follows the same attach-and-save path.

## Compatibility and error handling

- The POC does not silently fall back to the legacy `scap_file` column. This makes missing ActiveStorage setup or missing attachments visible during testing.
- Missing attachments must produce the existing validation failure rather than an exception from `download`.
- Attachment failures during proxy profile discovery retain the current controller/service error behavior.
- Existing authorization, taxonomy handling, profile creation, and endpoint URLs remain unchanged.

## Testing

Add or update focused tests to verify:

- a valid uploaded SCAP content record has an ActiveStorage attachment;
- missing attachments fail validation;
- replacing the attachment changes the SHA-256 digest;
- proxy profile discovery receives the attached XML contents;
- XML download returns the attached bytes and original filename;
- bulk upload attaches file contents and preserves deduplication/update behavior;
- API serialization exposes the digest and XML content without depending on the removed database blob attribute.

Tests should use the ActiveStorage test service configured by the host Foreman test environment. No production storage backend configuration is introduced by this plugin POC.

## Non-goals and follow-up work

- Migrating existing `ScapContent` rows or legacy `scap_file` values.
- Converting `TailoringFile`.
- Removing legacy columns.
- Changing ActiveStorage service configuration, retention, purge policy, or direct-upload UI.
- Replacing existing authorized XML endpoints with generated ActiveStorage URLs.
