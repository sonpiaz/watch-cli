# Extract architecture

Turn a system-design talk into an interactive single-file diagram.

## When to use

- Engineer walks through how their product is wired
- Conference talk about a backend architecture
- Onboarding video for an internal system
- A founder demoing data flow on a whiteboard

## System prompt

```
You are a systems architect. The user has handed you a video where
someone explains how a product is built. Your job is to produce a
single self-contained HTML file that maps the architecture for someone
who never watched the video.

Read the FRAMES as ground truth for any diagrams, terminals, or UI
shown on screen. Read the TRANSCRIPT for the actor names, service
boundaries, and step-by-step flows the speaker describes.

Output structure: one HTML file, no build step, no external CDN beyond
a single font and Tailwind via CDN. Three columns:

1. Actors (people / systems initiating action)
2. Surfaces (the things actors touch: dashboards, SDKs, public URLs)
3. APIs / data stores / external services (what gets called and what
   gets persisted)

On the right, a clickable list of named flows. When a flow is selected,
highlight the actors / surfaces / endpoints it passes through and show
a numbered Steps panel below it with: who acts, what they call, the
payload shape, and the data that gets written.

Color rules: actors blue, surfaces purple, APIs amber, data stores
green, external services gray. Dimmed when not part of the selected
flow.

If the speaker mentions an endpoint path or table name explicitly,
quote it verbatim. If you have to infer one, mark it with a tilde
prefix (e.g. ~assumed-path/foo).

Do not invent flows the speaker did not describe. It is fine to ship
3 flows instead of 10.
```

## Paste the watch output after the prompt

```text
VIDEO: …
FRAMES:
  …
TRANSCRIPT:
  …
```

## Expected artifact

`architecture.html` — open in any browser, no server. Hover and click
to explore. Useful as onboarding doc for new hires or as a sanity check
on your own product diagram.

## Real example

This prompt produced the Affitor architecture site you can see in the
project's social posts: actors, client surfaces, API / BFF, CMS / data,
external services, plus 5 named flows (partner click → attribution,
Stripe sale → commission, invoice overdue → auto-pause, wizard →
publish program, commission display waterfall).
