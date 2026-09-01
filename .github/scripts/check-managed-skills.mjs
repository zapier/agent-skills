#!/usr/bin/env node

import { spawnSync } from "node:child_process";
import { pathToFileURL } from "node:url";
import path from "node:path";

export const SOURCE_REPOSITORY = "https://gitlab.com/zapier/skills";
export const SOURCE_MARKER = ".shared-skills-source.json";
export const MANAGED_SKILLS = Object.freeze([
  "create",
  "modify",
  "history",
  "list",
  "install",
  "doctor",
]);

const SHA_PATTERN = /^[0-9a-f]{40}$/;
const GENERATED_BRANCH_PATTERN = /^shared-skills\/([0-9a-f]{40})$/;
const REF_PATTERN = /^[A-Za-z0-9][A-Za-z0-9._/-]*$/;

function fail(message) {
  throw new Error(message);
}

function validateRef(value, flag) {
  if (!value || !REF_PATTERN.test(value) || value.includes("..")) {
    fail(`${flag} must be a safe, non-empty Git revision`);
  }
  return value;
}

function runGit(args, cwd, encoding = "utf8") {
  const result = spawnSync("git", args, {
    cwd,
    encoding,
    timeout: 15_000,
    maxBuffer: 10 * 1024 * 1024,
  });

  if (result.error) {
    fail(`git ${args[0]} failed: ${result.error.message}`);
  }
  if (result.status !== 0) {
    const stderr = Buffer.isBuffer(result.stderr)
      ? result.stderr.toString("utf8")
      : result.stderr;
    fail(`git ${args[0]} failed: ${stderr.trim() || `exit ${result.status}`}`);
  }
  return result.stdout;
}

export function isManagedPath(filePath) {
  return MANAGED_SKILLS.some(
    (skill) =>
      filePath === `skills/workflows/${skill}` ||
      filePath.startsWith(`skills/workflows/${skill}/`),
  );
}

export function validateSourceMarker(contents) {
  let marker;
  try {
    marker = JSON.parse(contents);
  } catch (error) {
    fail(`${SOURCE_MARKER} must contain valid JSON: ${error.message}`);
  }

  if (!marker || Array.isArray(marker) || typeof marker !== "object") {
    fail(`${SOURCE_MARKER} must contain a JSON object`);
  }

  const keys = Object.keys(marker).sort();
  if (keys.length !== 2 || keys[0] !== "commit" || keys[1] !== "repository") {
    fail(`${SOURCE_MARKER} must contain exactly "repository" and "commit"`);
  }
  if (marker.repository !== SOURCE_REPOSITORY) {
    fail(`${SOURCE_MARKER} repository must be ${SOURCE_REPOSITORY}`);
  }
  if (!SHA_PATTERN.test(marker.commit)) {
    fail(`${SOURCE_MARKER} commit must be a 40-character lowercase Git SHA`);
  }

  return marker;
}

function changedPaths(base, head, cwd) {
  const output = runGit(
    [
      "diff",
      "--name-only",
      "--no-renames",
      "--diff-filter=ACDMRTUXB",
      "-z",
      `${base}...${head}`,
      "--",
    ],
    cwd,
    null,
  );

  return output
    .toString("utf8")
    .split("\0")
    .filter(Boolean);
}

export function checkManagedSkills({ base, head, branch, cwd = process.cwd() }) {
  validateRef(base, "--base");
  validateRef(head, "--head");

  const paths = changedPaths(base, head, cwd);
  const managedChanges = paths.filter(isManagedPath);
  const markerChanged = paths.includes(SOURCE_MARKER);

  if (managedChanges.length === 0 && !markerChanged) {
    return { managedChanges, markerChanged, sourceCommit: null };
  }

  if (!markerChanged) {
    fail(
      `managed skill changes require ${SOURCE_MARKER} to change in the same pull request`,
    );
  }

  const branchMatch = GENERATED_BRANCH_PATTERN.exec(branch ?? "");
  if (!branchMatch) {
    fail(
      "managed skill and source-marker changes require a shared-skills/<40-character-lowercase-sha> branch",
    );
  }

  const markerContents = runGit(
    ["show", `${head}:${SOURCE_MARKER}`],
    cwd,
  );
  const marker = validateSourceMarker(markerContents);

  if (branchMatch[1] !== marker.commit) {
    fail(
      `generated branch SHA ${branchMatch[1]} does not match ${SOURCE_MARKER} commit ${marker.commit}`,
    );
  }

  return {
    managedChanges,
    markerChanged,
    sourceCommit: marker.commit,
  };
}

function parseArgs(argv) {
  const values = new Map();
  for (let index = 0; index < argv.length; index += 2) {
    const flag = argv[index];
    const value = argv[index + 1];
    if (!["--base", "--head", "--branch"].includes(flag) || value === undefined) {
      fail(
        "usage: check-managed-skills.mjs --base <ref> --head <ref> --branch <branch>",
      );
    }
    if (values.has(flag)) {
      fail(`${flag} may only be provided once`);
    }
    values.set(flag, value);
  }

  for (const flag of ["--base", "--head", "--branch"]) {
    if (!values.has(flag)) {
      fail(`missing required argument ${flag}`);
    }
  }

  return {
    base: values.get("--base"),
    head: values.get("--head"),
    branch: values.get("--branch"),
  };
}

function main() {
  try {
    const result = checkManagedSkills(parseArgs(process.argv.slice(2)));
    if (result.sourceCommit) {
      console.log(
        `managed skills check: PASS (${result.managedChanges.length} managed path(s), source ${result.sourceCommit})`,
      );
    } else {
      console.log("managed skills check: PASS (no managed changes)");
    }
  } catch (error) {
    console.error(`managed skills check: FAIL\n${error.message}`);
    process.exitCode = 1;
  }
}

const invokedPath = process.argv[1]
  ? pathToFileURL(path.resolve(process.argv[1])).href
  : null;
if (invokedPath === import.meta.url) {
  main();
}
