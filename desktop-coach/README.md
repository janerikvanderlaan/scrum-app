# Desktop coach (Mac accessibility spike)

A small macOS menu bar app that watches which field you're typing in and, when a
rule from the team's rule set isn't met, shows a friendly tip. First rule:
**TEAM-02**, a backlog item is written as "As a … I want to … so that …".

This is a spike: it answers "can a local coach see the field we're in (Jira in
Safari) without screenshots?" It is not part of the scrum-app web app.

## What it does and doesn't do

- Uses the macOS Accessibility API to read the focused field's type, label, text
  and, in Safari, the page address. No screenshots, no screen recording, nothing
  saved to disk, nothing sent anywhere.
- Never reads password or search fields.
- Coaches only story fields (Summary, Description, Title) on Jira pages
  (`*.atlassian.net` or a host with "jira" in it), unless you switch on test mode.
- Explains afterwards: the tip appears when you leave the field, never while typing.
  A tip you've closed isn't shown again for the same text.
- Helps when asked: press **Control-Option-C** in any field, or use the menu.
- Only advises. It never types, clicks or changes anything in Jira.

## Run it on your Mac

You need macOS 13 or later and Apple's command line tools. Each step below is a
command you type in the **Terminal** app (find it with Spotlight, ⌘-Space, "Terminal").

1. **Install Apple's developer tools** (once). Skip this if you already have Xcode.

   ```sh
   xcode-select --install
   ```

   This opens a macOS dialog that installs the Swift compiler and git. Click Install and wait.

2. **Get the code** (once). This copies the repository from GitHub into a folder
   called `scrum-app` in your home folder:

   ```sh
   cd ~
   git clone https://github.com/janerikvanderlaan/scrum-app.git
   cd scrum-app/desktop-coach
   ```

   `cd` means "change directory": go into that folder. Later, to fetch the newest
   version, run `git pull` inside the `scrum-app` folder.

3. **Build and start the coach**:

   ```sh
   swift run DesktopCoach
   ```

   The first build takes a minute. A graduation cap (or a speech bubble with an
   exclamation mark) appears in the menu bar at the top right of the screen.
   Leave the Terminal window open; the coach runs as long as it's open.

4. **Allow Accessibility access** (once). macOS asks for this the first time.
   Open **System Settings > Privacy & Security > Accessibility** and switch on
   **Terminal** (when you start the coach from Terminal, macOS gives the
   permission to Terminal). The menu bar icon turns into a graduation cap within
   a few seconds. If it doesn't, stop the coach and start it again.

5. **Stop the coach**: choose **Quit Coach** from its menu, or press Control-C in
   the Terminal window.

## Try it

1. **Without Jira**: in the coach menu switch on **Coach in every app (test
   mode)**. Open a new TextEdit document, type "Fix login bug", then click on
   another app (for example Finder): a tip appears. Go back, replace the text with
   "As a user I want to log in so that I see my work" and press
   Control-Option-C: it says the story looks good.
2. **In Jira in Safari**: switch test mode off. Create an issue and type a summary
   that isn't a user story, then move to the next field.
3. **If nothing happens**: click in the field and choose **Show what the coach
   sees** from the menu. It shows the app, page, field type, label and text the
   coach read. A screenshot of that window tells us what Jira exposes, which is
   exactly what this spike is meant to find out.

## Code

- `Sources/CoachCore`: the rules and all wording, as pure functions with unit tests
  (`swift test`). No AppKit here.
- `Sources/DesktopCoach`: the menu bar app. `AX.swift` reads fields,
  `FocusWatcher.swift` follows the focus with an AXObserver, `HintPanel.swift`
  shows the tip without taking the keyboard focus, `HotKey.swift` is Control-Option-C.

CI builds and tests it on a macOS runner (`.github/workflows/desktop-coach.yml`).

Scrum Guide text © 2020 Ken Schwaber and Jeff Sutherland, licensed CC BY-SA 4.0 (scrumguides.org).
