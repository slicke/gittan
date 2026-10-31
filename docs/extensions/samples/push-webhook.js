/*
@name Push Webhook
@copyright (c) Gittan samples
@version 1.0
@description Posts every push to a webhook, with the branch and the newest commit.
@perms net
*/
Gittan.settings.define([
  {key: "url", type: "string", label: "Webhook URL", default: "", note: "Left empty, nothing is posted."},
  {key: "failures", type: "bool", label: "Post failed pushes too", default: "0"}
]);

Gittan.on("push.after", function (p) {
  var url = Gittan.settings.get("url");
  if (!url) return;
  if (!p.ok && Gittan.settings.get("failures") !== "1") return;
  var snap = Gittan.repo.snapshot({repo: p.repo});
  var body = {
    repo: p.repo, kind: p.kind, ok: p.ok, error: p.error,
    branch: snap && snap.branch, head: snap && snap.head,
    subject: snap && snap.recent.length ? snap.recent[0].subject : ""
  };
  Gittan.net.fetch(url, {method: "POST", headers: {"Content-Type": "application/json"}, body: JSON.stringify(body), timeout: 10000})
    .then(function (res) {
      if (!res.ok) Gittan.ui.error("Push Webhook", "The webhook answered " + res.status);
    }, function (err) {
      Gittan.ui.error("Push Webhook", String(err));
    });
});
