# ActiveStorage SCAP Content Proof of Concept Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Store `ScapContent` XML through ActiveStorage while preserving the plugin's existing upload, digest, profile discovery, download, API, and bulk-upload behavior.

**Architecture:** `ScapContent` will declare `has_one_attached :scap_file`; the existing `ScapFileContent` concern will become the compatibility boundary for attachment presence, byte reads, and digest calculation. Controllers and bulk upload will attach IOs directly, while downloads and proxy calls will read through the concern. The legacy database column remains untouched and is not used by the POC.

**Tech Stack:** Ruby, Rails ActiveStorage, ActiveRecord, ActiveSupport::Concern, Minitest, Mocha, FactoryBot.

**Spec:** `docs/superpowers/specs/2026-03-06-activestorage-scap-content-design.md`

## Global Constraints

- Cover `ScapContent` only; leave `TailoringFile` unchanged.
- Do not remove the legacy `scap_file` column or migrate existing rows.
- Preserve existing authorized XML endpoint URLs and response filenames.
- Preserve `original_filename` and `digest` as compatibility metadata.
- Do not introduce production ActiveStorage service configuration in the plugin.
- Do not silently fall back to the legacy database blob column.

## Review Focus

- Missing attachment: model validation must fail cleanly rather than raising from `download`; test in `test/unit/scap_content_test.rb`.
- Replaced attachment: SHA-256 must change after the new attachment is persisted; test in `test/unit/scap_content_test.rb`.
- Multipart upload IO: controllers must attach the IO without eagerly reading it into params; test through the existing controller upload tests or focused controller coverage.
- Existing bulk-upload update: same-title content must update its attachment and retain existing result/error behavior; test in `test/lib/foreman_openscap/bulk_upload_test.rb`.
- Existing endpoint/API contract: XML bytes, filename, digest, and serialized content must remain correct; test in the relevant functional/API tests.

---

### Task 1: Convert the SCAP file model concern to ActiveStorage

**Files:**
- Modify: `app/models/foreman_openscap/scap_content.rb`
- Modify: `app/models/concerns/foreman_openscap/scap_file_content.rb`
- Test: `test/unit/scap_content_test.rb`

**Interfaces:**
- Consumes: ActiveStorage's `has_one_attached :scap_file` and attachment methods.
- Produces: `ScapContent#scap_file_contents` returning the attached bytes, `ScapContent#attach_scap_file(io, filename:)` attaching an IO and preserving `original_filename`, and `ScapContent#scap_file_attached?` for callers/tests. Existing `digest` remains the persisted SHA-256 string.

- [ ] **Step 1: Write failing model tests**
  - Add a test that creates a `ScapContent`, attaches the fixture IO with its filename, saves it, and asserts `scap_file.attached?`, `scap_file_contents` equals the fixture bytes, and `original_filename` is preserved.
  - Add a test that creates a record without an attachment and asserts validation fails with the existing `scap_file` presence error.
  - Add a test that replaces the attachment, saves, and asserts the digest changes.

- [ ] **Step 2: Run the focused tests to verify they fail**

  Run: `bundle exec ruby -Itest test/unit/scap_content_test.rb`

  Expected: FAIL because `ScapContent` does not yet declare an ActiveStorage attachment or the new concern API.

- [ ] **Step 3: Implement the attachment boundary**
  - Declare `has_one_attached :scap_file` in `ScapContent`.
  - Replace direct column reads and `scap_file_changed?` callbacks in `ScapFileContent` with attachment-aware presence, byte access, attachment-change detection, and SHA-256 calculation.
  - Implement `attach_scap_file(io, filename:)` using the ActiveStorage attachment API and update `original_filename`.
  - Keep validation and digest behavior synchronous enough that a saved record has the correct digest.
  - Update `ScapContent#as_json` to serialize `scap_file_contents` without depending on the legacy column.

- [ ] **Step 4: Run the focused tests to verify they pass**

  Run: `bundle exec ruby -Itest test/unit/scap_content_test.rb`

  Expected: PASS, subject to the host Foreman test environment providing ActiveStorage test storage.

- [ ] **Step 5: Commit**

  ```bash
  git add app/models/foreman_openscap/scap_content.rb app/models/concerns/foreman_openscap/scap_file_content.rb test/unit/scap_content_test.rb
  git commit -m "Use ActiveStorage for SCAP content attachments"
  ```

### Task 2: Adapt upload and bulk-upload paths

**Files:**
- Modify: `app/controllers/scap_contents_controller.rb`
- Modify: `app/controllers/api/v2/compliance/scap_contents_controller.rb`
- Modify: `app/services/foreman_openscap/bulk_upload.rb`
- Modify: `app/controllers/concerns/foreman/controller/parameters/scap_content.rb` if strong-parameter handling requires it
- Test: `test/lib/foreman_openscap/bulk_upload_test.rb`
- Test: existing functional/API SCAP content controller tests identified by the test suite

**Interfaces:**
- Consumes: `ScapContent#attach_scap_file(io, filename:)` from Task 1.
- Produces: HTML/API create and update actions and bulk upload that attach uploaded/opened IOs without reading them into `params`.

- [ ] **Step 1: Add failing bulk-upload coverage**
  - Extend the successful upload tests to assert the resulting `ScapContent#scap_file` is attached and its downloaded bytes equal the source file.
  - Extend the existing same-title update test to assert the attachment bytes are replaced and the digest changes.

- [ ] **Step 2: Run the focused bulk-upload tests to verify the new assertions fail**

  Run: `bundle exec ruby -Itest test/lib/foreman_openscap/bulk_upload_test.rb`

  Expected: FAIL because bulk upload still assigns the legacy `scap_file` attribute.

- [ ] **Step 3: Implement direct IO attachment in bulk upload**
  - Open each source file in binary mode and pass it to `attach_scap_file` with the existing filename.
  - Preserve title lookup, taxonomy assignment, save behavior, and error messages.
  - Ensure the file handle is closed after the record has been saved or the attempt fails.

- [ ] **Step 4: Replace controller parameter mutation with attachment handling**
  - Remove `handle_file_upload` code that reads `tempfile` into `params`.
  - Extract the uploaded IO and filename in create/update, assign regular permitted attributes, and call `attach_scap_file` before saving.
  - Apply the same behavior to the HTML and API controllers while preserving API validation and response behavior.

- [ ] **Step 5: Run bulk and controller tests**

  Run: `bundle exec ruby -Itest test/lib/foreman_openscap/bulk_upload_test.rb` and the existing SCAP content functional/API controller test files.

  Expected: PASS, with attachments used for both new records and same-title updates.

- [ ] **Step 6: Commit**

  ```bash
  git add app/controllers/scap_contents_controller.rb app/controllers/api/v2/compliance/scap_contents_controller.rb app/services/foreman_openscap/bulk_upload.rb app/controllers/concerns/foreman/controller/parameters/scap_content.rb test/lib/foreman_openscap/bulk_upload_test.rb test/functional test/unit
  git commit -m "Attach SCAP uploads through ActiveStorage"
  ```

### Task 3: Adapt reads, downloads, and API behavior

**Files:**
- Modify: `app/controllers/scap_contents_controller.rb`
- Modify: `app/controllers/api/v2/compliance/scap_contents_controller.rb`
- Modify: `app/models/concerns/foreman_openscap/data_stream_content.rb` if profile discovery still reads the old interface
- Modify: API RABL template only if serialization requires an explicit compatibility value
- Test: `test/functional/api/v2/compliance/scap_contents_controller_test.rb` and/or existing SCAP content controller tests
- Test: `test/unit/scap_content_test.rb`

**Interfaces:**
- Consumes: `ScapContent#scap_file_contents` and `ScapContent#original_filename` from Task 1.
- Produces: existing HTML/API XML endpoints and proxy profile discovery operating on ActiveStorage bytes.

- [ ] **Step 1: Write failing read-path tests**
  - Assert `fetch_profiles` receives the attached XML bytes.
  - Assert the HTML/API XML endpoint returns the attached bytes with `application/xml` and the preserved/or fallback filename.
  - Assert API JSON includes the digest and encoded SCAP content without reading the legacy column.

- [ ] **Step 2: Run focused tests to verify failures**

  Run: the focused SCAP content unit and functional/API tests.

  Expected: FAIL where the paths still call the ActiveRecord blob accessor or otherwise do not use the attachment contents.

- [ ] **Step 3: Route all read paths through the attachment boundary**
  - Update proxy/profile discovery and download actions to use `scap_file_contents`.
  - Preserve current filenames, MIME type, authorization, endpoint paths, and fallback naming behavior.
  - Keep API representation compatible with existing clients.

- [ ] **Step 4: Run focused tests to verify they pass**

  Run: the focused SCAP content unit and functional/API tests.

  Expected: PASS.

- [ ] **Step 5: Commit**

  ```bash
  git add app/controllers/scap_contents_controller.rb app/controllers/api/v2/compliance/scap_contents_controller.rb app/models/concerns/foreman_openscap/data_stream_content.rb app/views/api/v2/compliance/scap_contents/base.json.rabl test/unit/scap_content_test.rb test/functional
  git commit -m "Read SCAP content through ActiveStorage"
  ```

### Task 4: Run the complete verification suite and document POC boundaries

**Files:**
- Modify: `README.md` only if the project’s existing documentation convention has a suitable ActiveStorage/POC section
- Test: all affected Ruby tests

- [ ] **Step 1: Run the complete Ruby test suite**

  Run: `bundle exec rake test`

  Expected: PASS.

- [ ] **Step 2: Run lint and diff checks**

  Run: `bundle exec rubocop` and `git diff --check`.

  Expected: no new RuboCop violations and no whitespace errors.

- [ ] **Step 3: Inspect the final diff for non-goals**
  - Confirm `TailoringFile`, legacy columns, storage configuration, and unrelated endpoints are unchanged.
  - Confirm no controller still eagerly reads an uploaded SCAP file into `params`.

- [ ] **Step 4: Commit any required verification-only fixes**

  ```bash
  git add README.md app test
  git commit -m "Verify ActiveStorage SCAP content POC"
  ```
