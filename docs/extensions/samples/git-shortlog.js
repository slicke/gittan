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
    Gittan.git.run(["log", "-n", "1", "--format=%h %an, %as: %s", "--", ctx.path]).then(function (r) {
      var line = ctx.line > 0 ? ctx.line : 1;
      Gittan.ui.clearCards();
      Gittan.ui.addCard({path: ctx.path, line: line, title: "Last changed", text: r.stdout.trim() || "No commit has this file.", severity: "note"});
    });
  }
});
