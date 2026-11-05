/*
@name Forge Overview
@copyright (c) Gittan samples
@version 1.0
@description A tab of your pull requests that have waited, the open pull requests and issues of each repository on the Batch tab, and who you are logged in as.
@perms forge
@forges github
*/

// gh is GitHub's tool, so the extension runs for GitHub alone (@forges):
// its tab and command show in GitHub's view only, and its Batch operation
// leaves out the repositories on no forge or on another.

var DAYS = 14;

Gittan.forgeTabs.register({
  id: "waiting",
  title: "Waiting",
  description: "Your open pull requests with no update in " + DAYS + " days.",
  // { forge: ctx.forge } keeps the calls to the view's forge, even when
  // the view is closed before the answer comes.
  render: async function (ctx) {
    var r = await Gittan.forges.gh.run(["search", "prs", "--author=@me", "--state=open",
      "--json", "number,title,url,updatedAt,repository,isDraft", "--limit", "100"], { forge: ctx.forge });
    if (!r.ok)
      throw new Error(r.stderr.trim() || "gh failed");
    var cutoff = Date.now() - DAYS * 24 * 3600 * 1000;
    var rows = JSON.parse(r.stdout)
      .filter(function (p) { return Date.parse(p.updatedAt) < cutoff; })
      .sort(function (a, b) { return Date.parse(a.updatedAt) - Date.parse(b.updatedAt); })
      .map(function (p) {
        return {
          title: p.repository.nameWithOwner + "#" + p.number + " " + p.title,
          detail: "Last updated " + p.updatedAt.slice(0, 10),
          tag: p.isDraft ? "draft" : "",
          severity: p.isDraft ? "info" : "warn",
          url: p.url,
          actions: [{ id: "nudge", title: "Comment “Still on it”" }]
        };
      });
    return { rows: rows, empty: "Nothing has waited more than " + DAYS + " days." };
  },
  // Nothing returned: the tab renders again.
  action: async function (id, row, ctx) {
    if (id !== "nudge" || !Gittan.ui.confirm("Comment “Still on it” on " + row.title + "?"))
      return;
    var r = await Gittan.forges.gh.run(["pr", "comment", row.url, "--body", "Still on it."],
      { forge: ctx.forge });
    if (!r.ok)
      throw new Error(r.stderr.trim());
  }
});

Gittan.batch.register({
  id: "open",
  title: "Open on GitHub",
  description: "How many pull requests and issues are open in each repository, read with gh. Nothing changes.",
  run: async function (ctx) {
    var o = { repo: ctx.repo };
    var prs = await Gittan.forges.gh.run(["pr", "list", "--state", "open", "--json", "number", "--limit", "200"], o);
    if (!prs.ok)
      return { text: prs.stderr.trim(), severity: "error" };
    var issues = await Gittan.forges.gh.run(["issue", "list", "--state", "open", "--json", "number", "--limit", "200"], o);
    var p = JSON.parse(prs.stdout).length;
    var i = issues.ok ? JSON.parse(issues.stdout).length : 0;
    if (p === 0 && i === 0)
      return null;
    var view = await Gittan.forges.gh.run(["repo", "view", "--json", "url"], o);
    return {
      text: p + " open pull request" + (p === 1 ? "" : "s") + ", " + i + " open issue" + (i === 1 ? "" : "s"),
      url: view.ok ? JSON.parse(view.stdout).url : ""
    };
  }
});

Gittan.commands.register({
  id: "whoami",
  title: "Who Am I on the Forge",
  where: "forge",
  run: function (ctx) {
    var f = Gittan.forge.info({ forge: ctx.forge });
    if (!f)
      return;
    Gittan.ui.alert(f.name + " through " + f.cli + ":\n" + f.accounts.map(function (a) {
      return a.login + " on " + a.host + (a.active ? " (active)" : "");
    }).join("\n"));
  }
});
