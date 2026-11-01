# Writing a Gittan extension

An extension is one JavaScript file in Gittan's extensions folder: `~/.config/Gittan/extensions` on macOS and Linux, `%APPDATA%\Gittan\extensions` on Windows (Extensions > Open Extensions Folder opens it). Gittan loads every `.js` file there when it starts, and Extensions > Reload Extensions loads them again after an edit. The Extensions page of the settings lists them, turns one off, and shows the fields an extension declares.

The file starts with a manifest in a comment:

```js
/*
@name Commit Lint
@copyright (c) Your Name
@version 1.0
@description Keeps commit subjects short.
@perms data, net, exec
*/
```

`@perms` names what the extension needs beyond what every extension may do: `data` to read the repositories (`Gittan.repo`, the files and their content, and the full payload of an event), `net` for `Gittan.net.fetch`, `exec` for `Gittan.git.run` and `Gittan.exec.run`, `settings` for `Gittan.app.setting`. Gittan asks you once per file, and again when the file changes. Dialogs, cards, commands, timers and the extension's own storage and settings page need no permission.

The scripts run in quickjs-ng (ES2023, with `fetch`-like networking, timers, `console`, `import` of modules from subfolders of the extensions folder, and top-level `await`). `gittan.d.ts` beside this file describes the `Gittan` object for an editor's completion.

## Commands

```js
Gittan.commands.register({
  id: "shortlog",
  title: "Who Wrote What",
  where: ["menu", "file"],      // the Extensions menu (and the command palette), the file tree's popup, "editor" for the editor's
  run: function (ctx) {         // ctx: {repo, path, line, selection}
    Gittan.git.run(["shortlog", "-sn", "HEAD"]).then(function (r) { Gittan.ui.alert(r.stdout); });
  }
});
```

## Events

```js
Gittan.on("commit.before", function (p) {       // {repo, message, paths, amend}
  var subject = p.message.split("\n")[0];
  if (subject.length > 72) return "The subject is " + subject.length + " characters; keep it under 72.";
});
Gittan.on("push.after", function (p) {          // {repo, ok, error, kind}
  if (p.ok) Gittan.ui.setStatus("Pushed", 5);
});
```

Without `data` a listener gets only `ok`, `kind`, `mode` and `amend`, so a lint that reads the message needs it. The events are `repo.opened`, `repo.changed`, `commit.before`, `commit.after`, `push.before`, `push.after`, `pull.before`, `pull.after` and `unload`. A `before` listener stops the action by returning `false`, a string with the reason, or `{cancel: true, message: "..."}`; Gittan shows the reason in a banner. A listener that throws stops nothing, and a returned promise is not waited for.

## The repository

```js
var s = Gittan.repo.snapshot();     // branch, head, ahead, behind, files, stashes, recent commits, refs
var files = Gittan.repo.files();    // [{path, kind, added, deleted, binary, staged, unstaged}]
var text = Gittan.repo.fileText("README.md", "HEAD");   // the work tree's version without a ref
var diff = Gittan.repo.diff("src/main.pp");
Gittan.repo.recent(5).forEach(function (c) { console.log(c.short, c.subject); });
```

These need `data`. Every call takes the repository shown; pass `{repo: "/path/to/other"}` as the last argument for another tab's.

## The window

```js
Gittan.ui.notify("Title", "a note for a few seconds");
Gittan.ui.error("Title", "stays until closed");
Gittan.ui.setStatus("in the status bar", 10);
Gittan.ui.openFile("src/main.pp", 120);
Gittan.ui.addCard({path: "src/main.pp", line: 120, title: "Note", text: "Markdown **body**", severity: "note"});
Gittan.ui.clearCards();
```

A card sits under the line in the change view, like the AI review's, while the work tree is what is compared.

## Storage and settings

```js
Gittan.settings.define([
  {key: "url", type: "string", label: "Webhook URL", default: "", note: "Posted on every push."},
  {key: "loud", type: "bool", label: "Say it loud", default: "1"},
  {key: "mode", type: "choice", label: "Mode", options: ["quiet", "normal"], default: "normal"},
  {key: "max", type: "number", label: "Max lines", default: "20"}
]);
var url = Gittan.settings.get("url");             // what the settings page holds, else the default
Gittan.storage.setJSON("seen", {hash: s.head});   // the extension's own values in gittan.ini
```

A value may hold anything, line ends included. A key is one line without `=`, not starting with `;` or `[`; `get`, `set` and `define` throw on another.

## Programs and the network

```js
Gittan.git.run(["log", "--oneline", "-n", "5"]).then(function (r) { /* r.ok, r.status, r.stdout, r.stderr */ });
Gittan.exec.run("gh", ["pr", "list"]).then(function (r) { ... });
Gittan.net.fetch("https://example.com/hook", {method: "POST", body: JSON.stringify(p), headers: {"Content-Type": "application/json"}})
  .then(function (res) { return res.text(); });
```

These run off the main thread and come back as promises. A script that runs for 10 seconds without returning is stopped; waiting for a promise does not count.
