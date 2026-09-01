import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { mkdtempSync, mkdirSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import path from "node:path";
import test from "node:test";
import { fileURLToPath } from "node:url";

const SCRIPT = fileURLToPath(
  new URL("./check-managed-skills.mjs", import.meta.url),
);
const REPOSITORY = "https://gitlab.com/zapier/skills";
const OLD_SOURCE = "1".repeat(40);
const NEW_SOURCE = "2".repeat(40);

function run(command, args, cwd) {
  const result = spawnSync(command, args, {
    cwd,
    encoding: "utf8",
    timeout: 15_000,
  });
  if (result.error) throw result.error;
  return result;
}

function git(repo, ...args) {
  const result = run("git", args, repo);
  assert.equal(result.status, 0, result.stderr);
  return result.stdout.trim();
}

function marker(commit, repository = REPOSITORY) {
  return `${JSON.stringify({ repository, commit }, null, 2)}\n`;
}

function createRepo() {
  const repo = mkdtempSync(path.join(tmpdir(), "managed-skills-check-"));
  git(repo, "init", "--quiet");
  git(repo, "config", "user.email", "managed-skills-test@example.com");
  git(repo, "config", "user.name", "Managed Skills Test");
  git(repo, "config", "commit.gpgSign", "false");
  mkdirSync(path.join(repo, "skills/workflows/create"), { recursive: true });
  writeFileSync(path.join(repo, "skills/workflows/create/SKILL.md"), "original\n");
  writeFileSync(path.join(repo, "README.md"), "original\n");
  writeFileSync(path.join(repo, ".shared-skills-source.json"), marker(OLD_SOURCE));
  git(repo, "add", ".");
  git(repo, "commit", "--quiet", "-m", "baseline");
  return { repo, base: git(repo, "rev-parse", "HEAD") };
}

function commit(repo, message = "candidate") {
  git(repo, "add", ".");
  git(repo, "commit", "--quiet", "-m", message);
  return git(repo, "rev-parse", "HEAD");
}

function check(repo, base, head, branch) {
  return run(
    process.execPath,
    [SCRIPT, "--base", base, "--head", head, "--branch", branch],
    repo,
  );
}

function withRepo(callback) {
  const fixture = createRepo();
  try {
    callback(fixture);
  } finally {
    rmSync(fixture.repo, { recursive: true, force: true });
  }
}

test("allows an authorized generated managed-skill change", () => {
  withRepo(({ repo, base }) => {
    writeFileSync(path.join(repo, "skills/workflows/create/SKILL.md"), "generated\n");
    writeFileSync(path.join(repo, ".shared-skills-source.json"), marker(NEW_SOURCE));
    const head = commit(repo);

    const result = check(repo, base, head, `shared-skills/${NEW_SOURCE}`);

    assert.equal(result.status, 0, result.stderr);
    assert.match(result.stdout, new RegExp(`source ${NEW_SOURCE}`));
  });
});

test("rejects a direct edit to a managed skill", () => {
  withRepo(({ repo, base }) => {
    writeFileSync(path.join(repo, "skills/workflows/create/SKILL.md"), "direct edit\n");
    const head = commit(repo);

    const result = check(repo, base, head, `shared-skills/${NEW_SOURCE}`);

    assert.equal(result.status, 1);
    assert.match(result.stderr, /source\.json to change in the same pull request/);
  });
});

test("allows an unrelated public-repository change", () => {
  withRepo(({ repo, base }) => {
    writeFileSync(path.join(repo, "README.md"), "unrelated update\n");
    const head = commit(repo);

    const result = check(repo, base, head, "docs/readme-update");

    assert.equal(result.status, 0, result.stderr);
    assert.match(result.stdout, /no managed changes/);
  });
});

test("rejects an invalid source marker", () => {
  withRepo(({ repo, base }) => {
    writeFileSync(path.join(repo, "skills/workflows/create/SKILL.md"), "generated\n");
    writeFileSync(
      path.join(repo, ".shared-skills-source.json"),
      marker(NEW_SOURCE, "https://example.com/not-the-source"),
    );
    const head = commit(repo);

    const result = check(repo, base, head, `shared-skills/${NEW_SOURCE}`);

    assert.equal(result.status, 1);
    assert.match(result.stderr, /repository must be https:\/\/gitlab\.com\/zapier\/skills/);
  });
});

test("rejects a non-generated branch", () => {
  withRepo(({ repo, base }) => {
    writeFileSync(path.join(repo, "skills/workflows/create/SKILL.md"), "generated\n");
    writeFileSync(path.join(repo, ".shared-skills-source.json"), marker(NEW_SOURCE));
    const head = commit(repo);

    const result = check(repo, base, head, "feature/direct-edit");

    assert.equal(result.status, 1);
    assert.match(result.stderr, /shared-skills\/<40-character-lowercase-sha> branch/);
  });
});

test("rejects a generated branch whose SHA does not match the marker", () => {
  withRepo(({ repo, base }) => {
    writeFileSync(path.join(repo, "skills/workflows/create/SKILL.md"), "generated\n");
    writeFileSync(path.join(repo, ".shared-skills-source.json"), marker(NEW_SOURCE));
    const head = commit(repo);

    const result = check(repo, base, head, `shared-skills/${"3".repeat(40)}`);

    assert.equal(result.status, 1);
    assert.match(result.stderr, /does not match/);
  });
});
