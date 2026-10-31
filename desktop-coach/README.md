# Desktop coach (Mac accessibility spike)

A small macOS menu bar app that watches which field you're typing in and, when a
rule from the team's rule set isn't met, shows a friendly tip. Rules so far:

| Rule | Field in Jira | Tip when |
|---|---|---|
| **TEAM-02** | Summary, Description | the text isn't written as "As a … I want to … so that …" |
| **SG-200** | Story point estimate | the estimate is above the team's average velocity (set it in the menu, default 10) |
| **SG-150** | Start Sprint dialog | the Sprint goal field is empty |
| **TEAM-03** | Start Sprint dialog | the Sprint's total estimate (read from its backlog header, "Schatting: 10 van 10") is above the average velocity |

For now the average velocity is the coach's own setting. Reading Jira's velocity (and the
Sprint total) straight from Jira with a read-only API token is planned for later.

This is a spike: it answers "can a local coach see the field we're in (Jira in
Safari) without screenshots?" It is not part of the scrum-app web app.

## What it does and doesn't do

- Uses the macOS Accessibility API to read the focused field's type, label, text
  and, in Safari, the page address. No screenshots, no screen recording, nothing
  saved to disk, nothing sent anywhere.
- Never reads password or search fields.
- Coaches only the fields above on Jira pages (`*.atlassian.net` or a host with
  "jira" in it), unless you switch on test mode.
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
3. **Story points**: choose **Average velocity** in the coach menu and check the
   number (10 by default). Give a story an estimate of 13 and click elsewhere.
4. **Sprint Goal**: in the backlog, click **Start sprint** (Sprint starten), leave
   the Sprint goal empty and press Tab to move through the fields. If you click
   Start straight away the dialog closes before the coach can look; then try
   Control-Option-C while you're in the dialog.
5. **If nothing happens**: click in the field and choose **Show what the coach
   sees** from the menu. It shows the app, page, field type, label, text and the
   other fields of the dialog the coach read. A screenshot of that window tells us what Jira exposes, which is
   exactly what this spike is meant to find out.

## Log what the screen reports (CoachProbe)

The coach depends on what macOS and the app report: which element has the focus,
when a value changes, when a dialog opens. Safari doesn't always report this the
way we expect, so there's a separate small logger to see it for ourselves.

1. In Terminal, in the `desktop-coach` folder, start it:

   ```sh
   swift run CoachProbe
   ```

   It uses the same Accessibility permission as the coach (granted to Terminal).
   You can run it alongside the coach or on its own.
2. Switch to Safari. The probe doesn't watch the Terminal window it writes to
   (that would log its own lines in a loop), so nothing new appears until you
   use another app. Use Jira as usual: click, tab, type, open the Start Sprint dialog, click Start.
   Press **Control-Option-M** just before a step you want to look at; it writes
   "marker 1", "marker 2" … into the log so we can find that moment.
3. Press **Control-C** in Terminal to stop. The log is in the folder
   `coach-probe-logs` in your home folder (Finder: Go > Home). Send me that file.

Each line has the time (to the millisecond), a tag and the details:

| Tag | What it means |
|---|---|
| `app` | another app came to the front |
| `focus` | the app reported a new focused element (and, if different, what it says when asked) |
| `value` | the app reported that an element's value changed |
| `poll` | the probe looked itself (4 times a second) and found a focus or value change the app **didn't** report |
| `gone` | the focused element was removed, for example an inline editor that closed |
| `window` | a window, sheet or menu opened, closed or got the focus |
| `click` | a mouse click, with the element under the pointer and the button it is in |
| `key` | a key by its kind: Tab, Shift-Tab, Return, Escape, arrows or just "character" |
| `mark` | your Control-Option-M marker |

Privacy: it logs which kind of key you press, never which letter or digit. Field
values are logged as a short preview (60 characters) so we can see for example an
estimate change; start it with `swift run CoachProbe --no-text` to log only their
length. Password and search fields are never read. The log stays on your Mac.

## Architecture

The coach has three layers. Each one only talks to the one below it through a
small, plain data type, so a layer can be replaced without touching the others.

1. **Field sources** (`Sources/DesktopCoach`) turn what is on screen into
   `FieldSnapshot`s: which app, which field (type and label), the text, and where
   it is. A source implements the `FieldSource` protocol
   (`FieldSource.swift`). Today there is one source, `FocusWatcher.swift`, which
   follows the keyboard focus with the macOS Accessibility API (`AX.swift`).
2. **Coaching** (`AppDelegate.swift`, `HintPanel.swift`, `HotKey.swift`) decides
   *when* to help (after leaving a changed field, or when asked with
   Control-Option-C) and shows the tip without taking the keyboard focus.
3. **Rules and wording** (`Sources/CoachCore`) are pure functions with unit tests
   (`swift test`): which fields are in scope, which rule applies, and the friendly
   What / Why / How text. No AppKit and no Accessibility API here.

### Planned: legacy apps in terminal emulators

Older back-office applications often run in a terminal emulator (IBM 3270 or
5250, frequently inside a browser). The Accessibility API then sees the whole
terminal screen as **one** field, so field recognition doesn't work there.

This is meant to be added later as a separate, switchable field source, without
changing coaching or the rules:

- A **terminal-screen source** reads the full screen text (24×80 or similar) and
  the cursor position, and cuts it into *virtual fields* using a **screen map**
  per application: "screen ORD01, row 6, columns 20–60 is the Order description".
- It produces the same `FieldSnapshot`s as today (label from the screen map, text
  from those columns, "field left" when the cursor moves out or Enter is pressed),
  so every existing rule works on terminal screens unchanged.
- It is off by default and switched on per application, next to the
  Accessibility source; screen maps are configuration, not code.

Nothing of this is built yet; the `FieldSource` protocol is the place it plugs in.

CI builds and tests it on a macOS runner (`.github/workflows/desktop-coach.yml`).

Scrum Guide text © 2020 Ken Schwaber and Jeff Sutherland, licensed CC BY-SA 4.0 (scrumguides.org).
