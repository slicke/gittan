/*
@name Commit Lint
@copyright (c) Gittan samples
@version 1.0
@description Stops a commit whose subject is too long or lacks a ticket id.
@perms data
*/
Gittan.settings.define([
  {key: "max", type: "number", label: "Longest subject", default: "72"},
  {key: "ticket", type: "string", label: "Ticket pattern (a regular expression, empty for none)", default: "",
    note: "For example ^[A-Z]+-[0-9]+: for JIRA-123: style subjects."}
]);

Gittan.on("commit.before", function (p) {
  var subject = p.message.split("\n")[0].trim();
  var max = Number(Gittan.settings.get("max")) || 72;
  if (subject.length > max)
    return "The subject is " + subject.length + " characters; keep it under " + max + ".";
  var pattern = Gittan.settings.get("ticket");
  if (!pattern)
    return;
  var re;
  try {
    re = new RegExp(pattern);
  } catch (e) {
    // A listener that throws stops nothing, so a broken pattern stops the commit here.
    return "The ticket pattern " + pattern + " is not a regular expression.";
  }
  if (!re.test(subject))
    return "The subject does not match " + pattern + ".";
});
