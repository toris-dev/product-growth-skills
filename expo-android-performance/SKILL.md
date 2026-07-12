---
name: expo-android-performance
description: Diagnose, measure, and optimize Android performance in Expo and React Native applications across startup, JavaScript and UI responsiveness, rendering, lists, memory, network, images and fonts, bundle size, native modules, and package artifacts. Use when an Expo Android app feels slow, drops frames, starts slowly, uses excessive memory or network, has an oversized build, regresses, or needs an Expo-aware performance audit and implementation.
---

# Expo Android Performance

Measure the real bottleneck across JavaScript, UI, and native boundaries before changing code. Preserve Expo workflow ownership and prove results in a production-like Android build on representative hardware.

## Operating rules

- Default to read-only diagnosis when implementation permission is unclear.
- Detect the actual Expo/React Native workflow and architecture; do not assume managed, prebuild, bare, old, or new architecture.
- Do not manually edit generated native files when config, a config plugin, or another source of truth will overwrite them.
- Development-server and debug behavior cannot prove production performance.
- Preserve correctness, accessibility, navigation, lifecycle behavior, over-the-air update policy, analytics, and unrelated changes.
- Use current official Expo, React Native, Android, and package documentation for version-dependent behavior.
- Read [evidence and verification](../shared-references/evidence-and-verification.md) before reporting gains.

## Workflow

### 1. Define the scenario

Turn the symptom into a numbered sequence with install/update state, launch type, account/data, route, navigation or gesture, network, duration, and expected behavior. Record target device classes and supported Android versions.

### 2. Detect ownership and runtime

Inspect:

- Expo SDK, React Native and React versions, package manager/lockfile, app config, and build profiles;
- managed, continuous-native-generation/prebuild, or bare workflow;
- whether `android/` is generated, ignored, committed, or intentionally maintained;
- JavaScript engine, React Native architecture, native modules/config plugins, development client, and update/runtime-version policy;
- router/navigation, state/data stack, list/image/font/animation libraries, and modules active in the scenario;
- build variant, ABI, minification/shrinking, source maps/symbols, and artifact type;
- physical device, Android version, memory/chipset, refresh rate, thermal/power state, and connection.

Determine the durable source of truth before proposing an edit.

### 3. Capture a production-like baseline

Read [measurement playbook](references/measurement-playbook.md). Select metrics tied to the symptom: cold/warm startup, time to usable UI, JS and UI thread stalls, frame timing/jank, interaction latency, render/commit behavior, list throughput, CPU, allocations/retained memory, GC, network waterfalls/payload, image decode/cache, font loading, bundle/module weight, native initialization, package/download/install size, energy, or thermal effects.

Use repeated controlled trials and retain raw evidence. Keep development tooling overhead out of conclusions about production builds.

### 4. Attribute the bottleneck

- **JavaScript/React:** synchronous work, render cascades, unstable props/selectors, context fan-out, serialization, timers, effects, large module evaluation, data transforms, and JS-driven animation.
- **UI/rendering:** view hierarchy, layout, overdraw, shadows/clipping, images, list virtualization, gesture contention, animation work, and native view cost.
- **Data/network:** waterfalls, retries, payloads, caching, persistence, offline hydration, and request lifecycle.
- **Native/startup:** module initialization, splash/font/assets, config plugins, services, engine/architecture boundaries, and platform lifecycle.
- **Artifact/update:** bundle composition, dependencies, assets, ABIs, native libraries, source maps/symbols, minification/shrinking, and duplicated resources.

For each hypothesis record supporting evidence, a falsifying experiment, likely user impact, confidence, risk, and effort.

### 5. Implement safely

When authorized, change the durable layer: JavaScript/TypeScript source, app configuration, build profile, or config plugin as appropriate. Work on one causal area at a time where practical.

Possible evidence-backed actions include deferring noncritical startup, narrowing renders/subscriptions, moving animation work off the JS thread using already-supported architecture, correcting list virtualization, sizing/caching images, batching data or native crossings, removing a request waterfall, lazy-loading real boundaries, or correcting artifact configuration.

Do not add memoization everywhere, indiscriminately change architecture/engine, eject/prebuild, install a package, or replace navigation/rendering infrastructure without evidence and explicit scope.

### 6. Re-measure and validate

Repeat the same scenario with matching device class, build profile, architecture/engine, data, cache/launch state, network, and measurement method. Compare raw samples, median/range, user-visible behavior, JS/UI attribution, crash/error logs, memory peaks, energy/thermal effects, and artifact changes.

Validate deep links, back/navigation, gestures, lists, loading/error/empty/offline states, background/foreground, updates, accessibility, text scaling, reduced motion, and targeted web/iOS surfaces where the project supports them.

If evidence is noisy or negative, report it; do not cherry-pick.

## Deliverable

Provide scenario/environment, ownership/source-of-truth map, baseline, ranked hypotheses, changes or recommendations, comparable before/after results, correctness gates, unverified areas, and a repeatable regression protocol. Do not report a performance win without comparable evidence.

