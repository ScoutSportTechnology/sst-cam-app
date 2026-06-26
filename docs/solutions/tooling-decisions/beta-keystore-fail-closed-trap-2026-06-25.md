---
title: "Fail-closed on missing keystore broke the beta lane — signing gate belongs at promotion, not the build"
date: 2026-06-25
category: tooling-decisions
module: ci-cd
problem_type: tooling_decision
component: tooling
severity: medium
applies_when:
  - "Adding a signing/keystore requirement to the alpha/beta build workflows"
  - "Deciding where to enforce release-signing in the alpha → beta → stable ladder"
  - "Editing the 'Materialize Android signing keystore' step in release-*.yml"
tags: [ci-cd, github-actions, apk-signing, keystore, release, flutter, fail-closed]
related_components: [tooling, development_workflow]
---

# Fail-closed on missing keystore broke the beta lane

## Context

A code review of the release-pipeline rework flagged that a **debug-signed**
production APK could reach the stable Release silently: the keystore step warns and
continues when `ANDROID_KEYSTORE_BASE64` is unset, `build.gradle.kts` falls back to
the public debug key, and `release.yml`'s SHA-256 promotion check proves byte-identity
but **not signer identity**. Distribution (Play/MDM) rejects debug-signed APKs.

## Problem

The first fix (PR #21) made the **beta build** fail closed — `exit 1` on missing
`ANDROID_KEYSTORE_BASE64`. But **no keystore secret is configured** in this repo
(verify with `gh secret list`). Every prior beta/stable was already debug-signed.
So the change made `release-beta.yml` fail at the "Materialize Android signing
keystore" step, beta.4 minted **no tag**, and the whole beta lane was dead — while
the team relies on **debug-signed betas for sideload device-testing**.

## Solution

Reverted the beta lane to **warn-and-continue** (debug signing), matching alpha
(PR #22). The distribution concern only bites at **stable promotion**, so the
enforcement belongs there, behind a keystore actually existing. Added to the
`release.yml` promote step:

```
# TODO(signing): once ANDROID_KEYSTORE_BASE64 is configured, assert the promoted
# prod APK is RELEASE-signed (apksigner verify --print-certs; reject the Android
# Debug cert) before publishing stable. SHA-256 proves bytes, not signer. Deferred
# while no keystore exists (betas are debug-signed for sideload testing).
```

## Lesson

Don't hard-gate a precondition (signing) on a **build** stage when that precondition
isn't met yet and the artifact is still useful without it. A fail-closed check is
correct in principle but must be placed where it doesn't trap an upstream lane the
team depends on. Map the guarantee to the rung that actually needs it:
debug-signed is fine for **alpha/beta sideload**; release-signing matters only at
**stable**. Before merging a fail-closed CI change, confirm the resource it requires
(here: the keystore secret) actually exists.
