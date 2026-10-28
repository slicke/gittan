# Adding a forge

Read this before adding a service that hosts repositories (GitLab, Bitbucket, Gitea, Forgejo) beside GitHub. github.md describes how GitHub is done, and what the pull request features do with a forge; this file is the contract a new one fills in.

## What a forge is to Gittan

- A forge is a unit of its own in `src/core/` (`gittan.gitlab.pp`, say), with no LCL, beside `gittan.github.pp`. It inherits `TGittanForge` (`gittan.forge.pp`), makes its own kinds of the three jobs, and turns the service's words into `gittan.forge`'s kinds (`TGittanPullState`, `TGittanReviewDecision`, `TGittanReviewVerdict`, `TGittanChecksState`) before they leave the unit. Nothing outside the unit names its class or runs its tool.
- It reaches the service through the service's command line tool (`glab`, say), run with `RunCli` in `gittan.git` (GitHub's `RunGh` is the model: its prompts and update notice off). The tool keeps the user's login; Gittan stores no token.
- Its unit registers it as it loads, and `Gittan.lpr` lists the unit so it is linked:

  ```pascal
  initialization
    RegisterForge(TGittanGitLabForge);
  ```

  From then on everything else follows: a repository whose remote is on the forge gets it (`ForgeClassFor` asks `HostsRemote`), the settings keep its tool's path in a section named after it, the settings dialog's Hosting page has a block for it (its name and its tool's field, under the one switch for every forge), and About lists its tool's version. No unit in `src/ui` needs to change.

## The class

Every method below is abstract in `TGittanForge`; each comment in `gittan.forge.pp` is the authority.

1. `class function Name: string` – how the interface names it ("GitLab"): menus, links, the sidebar, the settings section and the Hosting page's block. Keep it short and stable, since it is the ini section name.
2. `class function CliName: string` – the tool as found on the search path ("glab"). `FindTool` looks for it, and an old `[Tools]` key of that name is read once.
3. `class function HostsRemote(const AHost: string): boolean` – whether a remote on `AHost` (lower case, no user, no port, from `RemoteHost`) is on this forge: its public host (gitlab.com), and the self-hosted ones its tool is logged in to, read from the tool's own config file the way GitHub's reads gh's `hosts.yml` (`GhHosts`, `GhConfigDir`; read again only when the file changed, `GhLoggedHosts`, since `ForgeClassFor` asks for every remote of every repository). It is called from the snapshot's consumer whenever the remotes change, so it should read a file at most, never run the tool or touch the network.
4. `function Version(out AVersion: string): boolean` – the tool's own `--version`, as "glab 1.45.0".
5. `function PullJob(const ARoot, ABranch, ALogin: string): TGittanPullRequestJob` – the open repository's pull requests (merge requests, on GitLab), see below. Not started.
6. `function ReviewJob(const ARoot, ARepo: string; ANumber: integer): TGittanReviewJob` – one pull request's review threads and conversation. Not started.
7. `function AccountJob(const ARoot: string): TGittanForgeJob` – the user's pull requests across every repository, for the forge view. Not started.
8. `function WebUrl(const ARoot: string; const ATarget: TGittanWebTarget; out AUrl, AError: string): boolean` – the web address of a file at a line in a commit or on a branch, a commit, an issue, or the page that opens a new pull request from a branch (`wtNewPull`: `Branch` as named on its remote, `HeadRepo` the path of the repository it is pushed to, a fork when it is not the forge's own), for the repository at `ARoot`; false with the reason when its remote is not on the forge.
9. `function FileOfWebUrl(const AUrl: string; out ARepo, APath: string; out ALine: integer): boolean` – the reverse, for links in comments: the repository, file and line of an address of a file on the forge; false for any other address.
10. `function PullRef(ANumber: integer): string` – the ref a remote serves the pull request's head at, which `git fetch` fetches to compare with it ("refs/merge-requests/12/head" on GitLab).

Three more have an answer in the base, for a forge whose tool keeps no list of accounts (none, no note, no switch), and a forge overrides them when its tool can be logged in to several:

- `class function Accounts: TGittanForgeAccounts` – the accounts the tool is logged in to, a host and a login each, the active one per host marked, read from the tool's own files without running it, since the window asks on every activation and every minute (`CheckAccounts`). GitHub reads gh's `hosts.yml` (`GhAccounts`), again only when the file changed. Keep it cheap and main-thread.
- `class function AccountsNote: string` – why the tool would not use the account picked, when something outside its login decides (gh with `GH_TOKEN` in the environment); empty otherwise. The Hosting page shows it in place of its own note.
- `function SwitchAccount(const AHost, ALogin: string; out AError: string): boolean` – makes ALogin the tool's active account on AHost, for the tool everywhere (`gh auth switch --hostname --user`). It runs the tool and waits.

Two more are for acting on a pull request, which the base cannot (no menu items then), and a forge overrides them when its tool can:

- `class function HasPullActions: boolean` – whether `ActionJob` gives a job; the menus offer the actions only then.
- `function ActionJob(const ARoot, ARepo: string; ANumber: integer; AAction: TGittanPullAction; const AText: string): TGittanPullActionJob` – a job that does one `TGittanPullAction` (approve, request changes, comment, merge with a merge commit, squash, rebase, mark ready for review) to pull request ANumber of ARepo ("owner/name"), with AText as a review's words; fill in `Ask` (false with the tool's words in AError). GitHub's is `gh pr review` with `--approve`, `--request-changes` or `--comment` and `--body`, `gh pr merge` with `--merge`, `--squash` or `--rebase`, and `gh pr ready`, always with `--repo` (`GitHubPullActionArgs`, tested). `PullActionDone`, `PullActionIsReview` and `PullActionMerges` describe an action for the views.

A job takes what it needs from the forge (the tool's path, the name) when it is made, never the forge itself: the settings may change, and the forge be freed, while it runs.

## The jobs

Each is a thread (`TGittanJob`); the base class runs the steps, filters and reports, and the forge fills in only what talks to the service. Read the base's comments before writing one.

- `TGittanPullRequestJob` – fill in `AskBranchPull` (the pull request of the checked-out branch; false for none, which is no failure), `AskOpenPulls` (the repository's open ones; false with the message, such as not logged in), `AskReviewPulls` (the open ones whose review is asked of the user or a team of theirs) and `AskLogin`. The base filters out what the user has reviewed (`WithoutReviewed`) and finds the branches gone from the remote.
- `TGittanReviewJob` (`gittan.reviews`) – fill in `Ask`: the threads (`TGittanReviewThreads`, with their file, line, side, resolved and outdated), the conversation (`TGittanPullNotes`) and the head commit. A forge without threads on lines gives the comments as notes.
- `TGittanForgeJob` – fill in `Ask`: the login (and `AvatarUrl`, the address of the user's picture when the forge gives one, which the base fetches over HTTP without the tool's token; a forge whose pictures need it leaves it empty and the view shows the initial), the user's open pull requests and the ones asked of them, as `TGittanForgePull`s, each with its `Repo` (the forge's path of it, "group/sub/project" on GitLab; `RemoteUrlsHold` matches it against a clone's remotes), the review decision, the checks as one word, the user's latest review, whether they are asked in person (`Requested`) and whether someone else has answered (`Feedback`). The base filters what the user has reviewed (`StillToReview`) and finds local clones.

Fields a service does not have stay at their defaults (`rdNone`, `chkNone`, `False`); the views leave out what is not there.

## Tests

Write the parsing as plain functions of the tool's output (JSON, mostly) and test them in `tests/test<forge>.pp`, as `tests/testgithub.pp` does with canned answers: the pull requests, the review threads, the account query, errors, `HostsRemote` and the parsing of the tool's hosts file, `WebUrl`'s arguments and `FileOfWebUrl`. Add the unit to `tests/gittantests.lpr`. No test runs the tool or goes to the network. `tests/testforge.pp` registers a stand-in forge on example.org to test how a repository's remotes pick a forge; a test that needs another forge can do the same.

## Still to do when a second forge arrives

- The forge view shows one forge, the first registered that is on and whose tool is found, with its filters' settings in `[GitHub]`. With two forges on, it needs a way to show the other's pull requests, a switch in its head or tabs of its own, and the filters a section per forge.
- `ForgeClassFor` takes the first forge that hosts one of the remotes, the remotes in git's order. A repository with remotes on two forges gets the first; a setting per repository may be wanted then.
- The texts of the pull request features name the forge through `Name`; check that none of them says something only true of GitHub ("gh", "GitHub Actions") for the new one.
