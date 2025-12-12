# SolMobile

SolMobile is a native iOS client for SolOS, designed to support deliberate thinking, explicit memory, and calm interaction with AI systems.

It is built around a simple premise:

> Users should always know what is remembered, why it is remembered, and how long it lasts.

---

## Purpose

SolMobile exists to make SolOS usable in daily life without sacrificing user agency or clarity.

This is not a general-purpose assistant app.
It is a **personal cognitive tool** with strict boundaries around persistence, cost, and control.

---

## Core Principles

- **Explicit over implicit**  
  Nothing is saved unless the user chooses to save it.

- **Local-first by default**  
  Conversations live on-device and expire automatically.

- **Inspectable memory**  
  Stored memories are discrete, reviewable objects.

- **Calm systems**  
  The interface avoids urgency, manipulation, or background activity.

- **Cost awareness**  
  Usage is visible and bounded.

---

## What SolMobile Does

- Captures user input (text-first in v0)
- Displays responses from SolOS-backed inference
- Stores conversation threads locally with a time limit
- Allows users to explicitly save memories
- Shows usage and cost information

---

## What SolMobile Does *Not* Do

- No passive listening
- No automatic long-term memory
- No behavioral profiling
- No hidden cloud sync
- No automation or actions in v0
- No persona simulation or roleplay UI

These exclusions are intentional.

---

## Architecture Overview

At a high level:

- **Client (SolMobile)**
  - UI
  - Local thread storage
  - Explicit memory actions
  - Cost display

- **Server (SolServer)**
  - Inference requests
  - Schema validation
  - Explicit memory persistence
  - Usage accounting

The client and server are intentionally decoupled.
There is no shared hidden state.

---

## Versioning

This repository currently targets **SolMobile v0**.

v0 is focused on validating:
- the explicit memory model
- local-first thread lifecycle
- calm interaction patterns

Feature expansion is deferred until these foundations are proven.

---

## Documentation

Additional documentation lives in:
- `/docs` — SolMobile-specific design and scope
- `infra-docs` — Canonical architecture and decisions across systems

---

## Status

SolMobile is under active development.
This README reflects current intent, not a finished product.

© SolLabsHQ
