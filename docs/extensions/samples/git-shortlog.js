/*
@name Git Shortlog
@copyright (c) Gittan samples
@version 1.0
@description Who wrote what, from the Extensions menu, and a file's last commit as a card from the file tree's menu.
@perms exec
*/
Gittan.commands.register({
  id: "shortlog",
  title: "Who Wrote What",
  run: function () {
    Gittan.git.run(["shortlog", "-sn", "--no-merges", "HEAD"]).then(function (r) {
      Gittan.ui.alert(r.ok ? r.stdout : r.stderr);
    });
  }
});

Gittan.commands.register({
  id: "last",
  title: "Mark Last Commit of File",
  where: ["file", "editor"],
  run: function (ctx) {
    if (!ctx.path) return;
    Gittan.git.run(["log", "-n", "1", "--format=%h %an, %as: %s", "--", ctx.path], {repo: ctx.repo}).then(function (r) {
      if (!r.ok) {
        Gittan.ui.error("git log failed", r.stderr);
        return;
      }
      var line = ctx.line > 0 ? ctx.line : 1;
      // ctx.repo: the repository the command was run in, though another may be shown by now.
      Gittan.ui.clearCards({repo: ctx.repo});
      Gittan.ui.addCard({repo: ctx.repo, path: ctx.path, line: line, title: "Last changed", text: r.stdout.trim() || "No commit has this file.", severity: "note"});
    });
  }
});
