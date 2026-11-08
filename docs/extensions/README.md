# Writing a Gittan extension

An extension is one JavaScript file in Gittan's extensions folder: `~/.config/Gittan/extensions` on macOS and Linux, `%APPDATA%\Gittan\extensions` on Windows (Extensions > Open Extensions Folder opens it). Gittan loads every `.js` file there when it starts, and Extensions > Reload Extensions loads them again after an edit. The Extensions page of the settings lists them, turns one off, and shows the fields an extension declares.

The file starts with a manifest in a comment:

```js
/*
@name Commit Lint
@copyright (c) Your Name
@version 1.0
@description Keeps commit subjects short.
@perms data
*/
```

`@perms` names what the extension needs beyond what every extension may do: `data` to read the repositories (`Gittan.repo`, the files and their content, and the full payload of an event), `net` for `Gittan.net.fetch`, `exec` for `Gittan.git.run` and `Gittan.exec.run`, `forge` for the forge's tool with your account (`Gittan.forge`, `Gittan.forges.gh`), `settings` for `Gittan.app.setting`. Gittan asks you once per file, and again when the file changes or a module in a subfolder does (a module runs with the permissions of the file that imports it). A no is not kept: the file is skipped and asked about again at the next load. Dialogs, cards, commands, timers and the extension's own storage and settings page need no permission.

`@repos` keeps an extension to some repositories; without it, it runs for every one. It takes patterns separated by commas, on one line or several. A pattern that starts with `/`, `~`, a drive or `\\` is the root of a repository (`~/work/*`, `C:\src\app`); any other is compared with the repositories' remotes, written as host and path (`github.com/you/*`, `gitlab.example.org/team/app`; a URL such as `git@github.com:you/app.git` works too). `*` and `?` are wildcards. A repository is in when its root or one of its remotes matches. Out of it, the extension's listeners are not called and its commands are not in its menus or the command palette:

```js
/*
@name Ticket Ids
@perms data
@repos github.com/acme/*, ~/work/legacy-app
*/
```

`@forges` keeps it to the repositories on some forges, by name (`@forges github`): a repository whose remotes are on another forge, or on none, is out of it, and in the GitHub view its tabs and commands show only when the view is GitHub's. An extension that runs `gh` says `@forges github`, so it never runs gh for a repository on GitLab. An unknown name keeps the file from loading.

`@repos` and `@forges` pick where the extension acts; they are not permissions. A timer or a command's own code can still read the repository shown, as far as `@perms` lets it.

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

In the GitHub view's own Extensions menu, `where: "forge"`; such a command gets `{forge, login}`: the forge's name and your login on it.

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

Without `data` a listener gets only `ok`, `kind`, `mode` and `amend`, so a lint that reads the message needs it. The events are `repo.opened`, `repo.changed`, `commit.before`, `commit.after`, `push.before`, `push.after`, `pull.before`, `pull.after` and `unload`. A `before` listener stops the action by returning `false`, a string with the reason, or `{cancel: true, message: "..."}`; Gittan shows the reason in a banner. A listener that throws stops nothing, and a returned promise is not waited for. `unload` comes before a reload and as Gittan quits, when the window is already gone: it may save to `Gittan.storage`, but a dialog or a notice shows nothing then.

## The repository

```js
var s = Gittan.repo.snapshot();     // branch, head, ahead, behind, files, stashes, recent commits, refs
var files = Gittan.repo.files();    // [{path, kind, added, deleted, binary, staged, unstaged}]
var text = Gittan.repo.fileText("README.md", "HEAD");   // the work tree's version without a ref
var diff = Gittan.repo.diff("src/main.pp");
Gittan.repo.recent(5).forEach(function (c) { console.log(c.short, c.subject); });
```

These need `data`. Every call takes the repository shown; pass `{repo: "/path/to/other"}` as the last argument for another tab's.

The calls wait for git, and Gittan's window waits with them. For a file that may be long, `diffAsync`, `blameAsync` and `fileTextAsync` take the same arguments and give a promise, with git run in a thread of its own:

```js
Gittan.repo.blameAsync("src/big.pp").then(function (text) { if (text !== undefined) { /* porcelain blame */ } });
```

## The window

```js
Gittan.ui.notify("Title", "a note for a few seconds");
Gittan.ui.error("Title", "stays until closed");
Gittan.ui.setStatus("in the status bar", 10);
Gittan.ui.openFile("src/main.pp", 120);
Gittan.ui.addCard({path: "src/main.pp", line: 120, title: "Note", text: "Markdown **body**", severity: "note"});
Gittan.ui.clearCards();
```

The dialogs wait for an answer, and the script with them:

```js
Gittan.ui.alert("a message with OK");
if (Gittan.ui.confirm("Yes or no?")) { /* ... */ }
var name = Gittan.ui.prompt("Branch", "Name of the branch:", "feature/");   // "" when cancelled
var pick = Gittan.ui.select("Remote", "Push to:", ["origin", "upstream"]);  // the index, -1 when cancelled
var i = Gittan.ui.message({
  title: "Push to main?",
  text: "main is protected in this repository.",
  kind: "warn",                       // "info" (the default), "warn", "error" or "question"
  buttons: ["Push Anyway", "Open Pull Request", "Cancel"],
  default: 1,                         // Return presses it; the first button when left out
  cancel: 2                           // Escape and the close box press it
});
```

`message` gives the index of the button pressed, or -1 when the dialog was closed without one (no `cancel`). Without `buttons` it has OK alone, and `Gittan.ui.message("text")` is the same as `{text: "text"}`. It takes up to six buttons, each with a label; a shape it cannot show (an unknown kind, an empty label, an index that is no button's) throws instead of opening the dialog. The dialog's title says which extension it is from, Extension "name", and `title` heads the text. The buttons are placed the way the system places them, so the default one may not be where it is in the list.

A card sits under the line in the change view, like the AI review's, while the work tree is what is compared. It goes to the shown repository; a command that answers later gives `repo: ctx.repo` to `addCard` and `clearCards`, so the card lands in the repository it ran in even after another tab was picked. `clearCards()` without one clears every repository's.

## Storage and settings

```js
Gittan.settings.define([
  {key: "url", type: "string", label: "Webhook URL", default: "", note: "Posted on every push."},
  {key: "loud", type: "bool", label: "Say it loud", default: "1"},
  {key: "mode", type: "choice", label: "Mode", options: ["quiet", "normal"], default: "normal"},
  {key: "max", type: "number", label: "Max lines", default: "20"}
]);
var url = Gittan.settings.get("url");             // what the settings page holds, else the default
Gittan.storage.setJSON("seen", {at: Date.now()}); // the extension's own values, kept in settings.json
```

A value may hold anything, line ends included. A key tells case, as a JavaScript object's does (`Token` and `token` are two keys), and is not empty and has no line end, tab or other control character; `get`, `set` and `define` throw on another.

## Programs and the network

```js
Gittan.git.run(["log", "--oneline", "-n", "5"]).then(function (r) { /* r.ok, r.status (the exit code), r.stdout, r.stderr */ });
Gittan.exec.run("make", ["-n", "all"]).then(function (r) { ... });
Gittan.net.fetch("https://example.com/hook", {method: "POST", body: JSON.stringify(p), headers: {"Content-Type": "application/json"}})
  .then(function (res) { return res.text(); });
```

These run off the main thread and come back as promises. A script that runs for 10 seconds without returning is stopped; waiting for a promise does not count.

## The forge

With `forge`, an extension runs the forge's own tool (gh for GitHub), logged in as you, without `exec`:

```js
Gittan.forge.info();          // {name: "GitHub", cli: "gh", ready, reason, accounts: [{host, login, active}]}, null on no forge
Gittan.forge.cli(["pr", "list", "--json", "number,title"]).then(function (r) { /* as git.run's */ });
Gittan.forges.gh.run(["api", "user"]);      // gh, and only where the forge is GitHub
```

The forge is the one of the repository named (`{repo: ctx.repo}`), else the GitHub view's while it is shown, else the shown repository's; `{forge: "GitHub"}` names one. It is looked up at each call, so code that awaits between calls names its forge or repository (`{forge: ctx.forge}` in a tab, `{repo: ctx.repo}` in an operation) and does not change course when the user closes the view meanwhile. The tool runs in that repository, or your home folder for the view. `Gittan.forge.cli` runs whichever forge's tool that is, so code that reads its output should look at `info().name`; `Gittan.forges.gh.run` refuses (the promise is rejected) where the forge is not GitHub, with the reason, as it does when GitHub is turned off in the settings or gh is not found. The tool can do whatever your account may on the forge, which is why `forge` is asked for, but nothing on your computer: for gh only `api`, `pr`, `issue`, `repo`, `run`, `workflow`, `release`, `search`, `label`, `status` and `cache`, without what works in a local clone or with local files (`pr checkout`, `pr create`, `repo clone`, `repo rename`, `run download`, `release upload`, `pr merge --delete-branch`, `issue develop --checkout`, `--worktree`, `--body-file`, `--attach`, `--input`, `api -F key=@file`...) and without `--web` (`-w`) or `--editor`; the subcommand comes first, after `--repo` alone (`["pr", "--repo", "o/r", "list"]`); anything else (an alias, a gh extension, `config`, `auth`, `gist`) is rejected with the reason. For more, ask for `exec` and run `Gittan.exec.run("gh", ...)`.

## The GitHub view

An extension can add a tab to the GitHub view, after Batch:

```js
Gittan.forgeTabs.register({
  id: "waiting",
  title: "Waiting",
  description: "Your pull requests with no update in two weeks.",
  render: async function (ctx) {               // ctx: {forge, login}; as the tab is shown, on Refresh and for another account
    return {
      text: "",                                // a paragraph over the rows
      rows: [{title: "acme/app#12 Fix", detail: "Updated 2026-09-01", tag: "draft", severity: "warn",
              url: "https://github.com/acme/app/pull/12", actions: [{id: "nudge", title: "Nudge"}]}],
      empty: "Nothing waits."                  // when there are no rows
    };
  },
  action: async function (id, row, ctx) { }   // a row's pill; return a model ({text: ""} clears the tab), or nothing to render again
});
```

A row opens its `url` in the browser (http and https only; another link is dropped), or its `repo` (a root) in Gittan. `severity` is `info`, `ok`, `warn` or `error`. A throw or a rejected promise shows its message on the tab.

And an operation to the Batch tab, which runs once for each repository picked there, in turn:

```js
Gittan.batch.register({
  id: "open",
  title: "Open on GitHub",
  description: "How many pull requests are open in each.",
  run: async function (ctx) {                  // ctx: {repo, name, forge, login}
    var r = await Gittan.forges.gh.run(["pr", "list", "--json", "number"], {repo: ctx.repo});
    if (!r.ok) return {text: r.stderr, severity: "error"};
    var n = JSON.parse(r.stdout).length;
    return n ? n + " open" : null;             // a string, {text, severity, url}, or null (false, 0, "") for nothing to say
  }
});
```

A repository the extension does not run for (`@repos`, `@forges`) is left out and named as such. `samples/forge-overview.js` has a tab, an operation and a command of the view.
