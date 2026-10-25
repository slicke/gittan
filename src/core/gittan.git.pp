unit gittan.git;

{** Git access for Gittan.

  Runs the git command line tool against a repository and returns its output.
  Nothing is parsed here beyond trimming; the caller decides how to show it. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, gittan.graph, gittan.rebase;

const
  {** Bits added to the kind in the Objects of ChangedPaths: the index
    holds a change, the work tree differs from the index. }
  flagStaged = 16;
  flagUnstaged = 32;

type
  {** A piece of what a git process wrote, on stdout or stderr, as it
    is read, for a caller that shows the progress of a long command (a
    pre-push hook's output, say). Called in the thread the command runs
    in. }
  TGittanOutputEvent = procedure(const AText: string) of object;
  {** Asked while a tool runs, in the thread it runs in: True ends the
    tool (a job that was told to stop). }
  TGittanCancelEvent = function: boolean of object;
type
  {** What happened to a changed file, condensed from the two status columns
    of `git status --porcelain`. }
  TGittanChangeKind = (ckModified, ckAdded, ckDeleted, ckRenamed, ckUntracked,
    ckConflict);

  {** One changed file with its line counts. A binary file has no counts.
    Staged is set when the index holds a change to the file, Unstaged when
    the work tree differs from the index; an untracked file has neither.
    Both are false while a Base other than HEAD is compared against. }
  TGittanFileStat = record
    Path: string;
    Kind: TGittanChangeKind;
    Added, Deleted: integer;
    Binary: boolean;
    Staged, Unstaged: boolean;
  end;
  TGittanFileStats = array of TGittanFileStat;

  {** A commit as SyncCommits and RecentCommits list it: its id, the
    short id git abbreviates it to, and the first line of its message.
    RecentCommits also gives the author, the commit time (UTC, 0 when
    unknown) and whether the commit is on HEAD but not on its upstream
    (not pushed yet). }
  TGittanCommitLine = record
    Hash, Short, Subject, Author: string;
    Date: TDateTime;
    Unpushed: boolean;
  end;
  TGittanCommitLines = array of TGittanCommitLine;

  {** Everything the views read about a repository at one moment, gathered
    in one pass so it can be computed off the main thread and handed over
    whole. Ok is false when git failed, with the message in Error. }
  {** A stash: the commit it is (Id), its place in the list (Index, the
    n of the stash@ n git names it by, which shifts as stashes come and
    go, so the id names it here), the branch
    it was made on, its message (the user's, or for one made without
    the short id and subject of the commit it was made on), when it was
    made in Unix seconds, and whether it holds untracked files. }
  TGittanStash = record
    Id: string;
    Index: integer;
    Branch, Message: string;
    Time: int64;
    Untracked: boolean;
  end;
  TGittanStashes = array of TGittanStash;

  {** A tag: its name (without refs/tags/), the commit it points at,
    whether it is annotated (a tag object, with a message and a tagger),
    when it was made in Unix seconds (the tagger's date of an annotated
    tag, the commit's of a lightweight one) and the subject of its
    message, or of the commit's for a lightweight one. }
  TGittanTag = record
    Name, Commit: string;
    Annotated: boolean;
    Time: int64;
    Subject: string;
  end;
  TGittanTags = array of TGittanTag;

  {** A line of HEAD's reflog: the commit HEAD was on after the move,
    when HEAD moved there in Unix seconds, what git wrote of the move
    ("commit: subject", "reset: moving to HEAD~1", "checkout: moving
    from main to topic") and whether the commit is reachable from no
    ref, so that only the reflog keeps it. }
  TGittanReflogEntry = record
    Commit: string;
    Time: int64;
    Subject: string;
    Lost: boolean;
  end;
  TGittanReflog = array of TGittanReflogEntry;

  {** Where a bisect stands, from the refs git keeps under refs/bisect:
    the commit marked bad, those marked good and those skipped. Once a
    bad and a good commit are known, Left is how many commits are left
    to test (those the bad one has and no good one has, less the bad one
    and the skipped ones), else -1. When none is left, Found is the
    first bad commit with its Subject, or, when skipped commits stand in
    the way, Suspects are the commits it could be, the bad one among
    them. }
  TGittanBisect = record
    Bad, Found, Subject: string;
    Good, Skipped, Suspects: TStringArray;
    Left: integer;
  end;

  {** What a commit is marked as in a bisect: good (from before the
    bug), bad (with it), or skipped (it cannot be tested). }
  TGittanBisectMark = (bmGood, bmBad, bmSkip);

  TGittanRepoSnapshot = record
    Ok: boolean;
    Error: string;
    Stats: TGittanFileStats;
    Branch, DefaultBranch, MergeBase, Operation, RebaseBranch: string;
    {** HEAD is on no branch: Branch is then the short commit id. }
    Detached: boolean;
    HasUpstream: boolean;
    Ahead, Behind: integer;
    {** How many commits of DefaultBranch the branch lacks, from
      BehindDefault; 0 on a detached HEAD. }
    BehindDefault: integer;
    {** For a branch without an upstream in a repository with a remote,
      how many of its commits no remote-tracking branch has, from
      NotOnRemotes (0 when all are there); -1 with an upstream, without
      a remote or on a detached HEAD. }
    NotOnRemote: integer;
    {** The branch and its upstream have both moved on, and the
      upstream's tip is one the branch had (UpstreamInReflog): the
      branch was rewritten since it was pushed, by a rebase or an amend,
      and a force push, not a pull, is the next step. }
    Rewritten: boolean;
    {** The stashes, newest first, from Stashes. }
    Stashes: TGittanStashes;
    {** The newest commits of HEAD, from RecentCommits; read only when
      the work tree is clean, since only the summary of a clean tree
      shows them. }
    Recent: TGittanCommitLines;
    {** Where the bisect stands, from BisectState, read only while
      Operation is "bisecting". }
    Bisect: TGittanBisect;
  end;
  PGittanRepoSnapshot = ^TGittanRepoSnapshot;

  {** How Pull joins the upstream's commits to the branch: pmAuto as the
    user's config says (pull.rebase, pull.ff, branch.<name>.rebase), or,
    when it says nothing, only by a fast-forward, so a branch that has
    diverged is not merged or rebased without asking; pmMerge with a
    merge commit, pmRebase by rebasing the branch's own commits on top. }
  TGittanPullMode = (pmAuto, pmMerge, pmRebase);

  {** A side of a conflict: the user's own work, or what came in. In a
    merge, a cherry-pick, a revert or a stash git calls them ours and
    theirs; a rebase replays the user's commits onto the upstream, so
    there mine is git's theirs. }
  TGittanConflictSide = (csMine, csTheirs);

  {** What Reset keeps: the index and the work tree (rmSoft, the reset
    commits' changes staged), the work tree (rmMixed, unstaged), or
    nothing (rmHard, every change in tracked files lost). }
  TGittanResetMode = (rmSoft, rmMixed, rmHard);

  {** What Clean removes: the files git neither tracks nor ignores
    (cnUntracked, `git clean`), the ignored ones alone (cnIgnored, `-X`)
    or both (cnAll, `-x`). }
  TGittanCleanKind = (cnUntracked, cnIgnored, cnAll);

  {** What an entry of a commit's tree is: a folder, a file, a symbolic
    link (its blob holds the target) or a submodule (its commit). }
  TGittanTreeKind = (tkFolder, tkFile, tkLink, tkSubmodule);

  {** An entry of a folder of a commit's tree (TGittanRepo.TreeEntries):
    its name in the folder, its path from the root, what it is, its
    object id, its size in bytes (-1 for a folder or a submodule) and
    whether it is executable. }
  TGittanTreeEntry = record
    Name: string;
    Path: string;
    Kind: TGittanTreeKind;
    Id: string;
    Size: int64;
    Executable: boolean;
  end;
  TGittanTreeEntries = array of TGittanTreeEntry;

  {** A commit a patch series takes (TGittanRepo.PatchCommits): its id,
    its short id and its subject. }
  TGittanPatchCommit = record
    Hash: string;
    Short: string;
    Subject: string;
  end;
  TGittanPatchCommits = array of TGittanPatchCommit;

  {** A file committed with other content than the work tree's: Text is
    what goes in for Path, the work tree's with some of its changes left
    out (see gittan.leaveout and TGittanRepo.Commit). }
  TGittanCommitPart = record
    Path: string;
    Text: RawByteString;
  end;
  TGittanCommitParts = array of TGittanCommitPart;

  {** One opened repository. Open finds the work tree root for a folder, and
    the other calls run inside that root. }
  TGittanRepo = class
  private
    FRoot: string;
    { The git directory, found by Open with the root. }
    FGitDir: string;
    FError: string;
    FBase: string;
    FWholeTree: boolean;
    FTempIndex: string;
    { Inside a ChangeStats (FIndexPass > 0) the temporary index is
      brought up to date once (FIndexAdded), not by every diff of it. }
    FIndexPass: integer;
    FIndexAdded: boolean;
    FIgnoreWhitespace: boolean;
    FOnOutput: TGittanOutputEvent;
    function RunGit(const ADir: string; const AArgs: array of string;
      out AOutput: string; const AIndexFile: string = ''): boolean;
    function RunRemote(const AArgs: array of string): boolean;
    function IndexPath: string;
    function CopyIndex(const ATarget: string): boolean;
    function CommitTree(const ATree, AParent, AMessage: string; out AId: string): boolean;
    function WholeTreeActive: boolean;
    function RebaseFilesFolder: string;
    procedure CleanRebaseFiles;
    function PatchRange(const AOlder, ANewer: string; out ARevs: TStringArray;
      out ARoot: boolean): boolean;
    function CompareIndex: string;
    procedure DropTempIndex;
    procedure SetWholeTree(AValue: boolean);
    function DiffBase: string;
    function EmptyTree: string;
    procedure SplitRange(out ALeft, ARight: string);
    function RunDiff(const AArgs: array of string; out AOutput: string): boolean;
    function FullPath(const APath: string): string;
    function RefGroup(const AGroup: string; AList: TStrings): boolean;
  public
    {** Opens the repository that contains ADir. Returns false, with the git
      message in Error, when ADir is not inside a work tree. }
    destructor Destroy; override;
    function Open(const ADir: string): boolean;
    {** Forgets the repository. }
    procedure Close;
    {** Unified diff of the work tree against Base (HEAD by default), or
      against the empty tree in a repository without commits, where every
      staged file is new. Empty when there are no changes. }
    function Diff: string;
    {** The branches and tags of the repository, local branches first,
      each most recently committed first: what Base can be set to. }
    function Refs(AList: TStrings): boolean;
    {** The branches of the repository, each group most recently
      committed first: the local ones in ALocal, the remote-tracking ones
      (origin/main) in ARemote, the symbolic origin/HEAD left out. }
    function Branches(ALocal, ARemote: TStrings): boolean;
    {** The local branches whose upstream is gone (`[gone]` in
      `git branch -vv`): the branch it tracks was deleted on the remote
      and a fetch with --prune, or the push that deleted it, removed the
      remote-tracking ref. }
    function GoneBranches(AList: TStrings): boolean;
    {** Switches the work tree to the branch ABranch (`git switch`): a
      local branch, or the name of a remote-tracking one without the
      remote, which makes a local branch tracking it. False, with git's
      reason in Error, when git refuses: a change in the work tree the
      switch would overwrite, an operation in progress, or a name it
      does not know. With AMerge the local changes come along even to
      files the branch changes, merged into its version (`--merge`);
      where they clash the files are left in conflict. With ADetach
      ABranch may be any commit, a tag say, and HEAD is left on it
      without a branch (`--detach`). }
    function Switch(const ABranch: string; AMerge: boolean = False;
      ADetach: boolean = False): boolean;
    {** Puts the files APaths (relative to Root) back as HEAD has them,
      in the index and the work tree (`git restore --source=HEAD
      --staged --worktree`); one HEAD lacks, added or untracked, is taken
      out of the index and deleted, and a rename goes back along with
      its old path. Before anything changes, the content of every file
      on disk is written into the repository as a blob (`git
      hash-object -w`), so RestoreReverted can put it back: ASaved gets
      one line per file, the path, a NUL and the blob's id, which is
      empty for a file that was not there. A submodule is left alone. }
    function RevertFiles(APaths, ASaved: TStrings): boolean;
    {** Writes back what RevertFiles saved in ASaved: each file as it
      was on disk, and a file that was not there is deleted again. What
      the index held is not brought back. }
    function RestoreReverted(ASaved: TStrings): boolean;
    {** Whether the index holds APath (relative to Root) as a file
      (`git ls-files`), so git mv and git rm take it. }
    function IsTracked(const APath: string): boolean;
    {** Renames or moves the tracked file AOld to ANew, both relative to
      Root (`git mv`), making ANew's folder first, since git mv makes
      none. The rename is staged, so git shows it as one. git refuses an
      untracked file or a target that exists. }
    function MovePath(const AOld, ANew: string): boolean;
    {** Takes the tracked files APaths (relative to Root) out of the
      repository (`git rm`): with AKeep only out of the index
      (`--cached`), the files staying on disk as untracked ones, else
      deleted too. Either is staged, to go in with the next commit. git
      refuses to delete a file with changes not committed. }
    function RemovePaths(APaths: TStrings; AKeep: boolean): boolean;
    {** Stashes the local changes, untracked files included, with the
      message AMessage (`git stash push -u`; without one git names the
      stash after HEAD), leaving the work tree as HEAD has them: every
      change, or with APaths only the files named (relative to Root),
      the others left as they are. True with nothing to stash too, when
      git makes no stash. }
    function Stash(const AMessage: string; APaths: TStrings = nil): boolean;
    {** The stashes, newest first (`git stash list`), each with its
      place in the list. Returns false when git failed. }
    function Stashes(out AList: TGittanStashes): boolean;
    {** The place of the stash AId (its commit) in the list now, the n
      git names it stash@ n by; -1 when it is gone. }
    function StashIndex(const AId: string): integer;
    {** Puts the changes of the stash AId back into the work tree (`git
      stash apply`), and with APop drops it once that went through
      (`git stash pop`). False, with git's reason, when it did not:
      AConflicts is then set when the changes clashed with the work tree
      and the files are left in conflict, to resolve as after a merge;
      the stash is kept then. }
    function StashApply(const AId: string; APop: boolean; out AConflicts: boolean): boolean;
    {** Drops the stash AId (`git stash drop`). }
    function StashDrop(const AId: string): boolean;
    {** Makes the branch AName at the commit the stash AId was made on,
      switches to it, puts the stash's changes back and drops it (`git
      stash branch`): what to do with a stash the branch has since moved
      past. False, with git's reason, when the name is taken or wrong or
      local changes stand in the way; the stash is kept then. }
    function StashBranch(const AName, AId: string): boolean;
    {** A Base that shows what the stash AId holds, in ARange: the range
      from the commit it was made on to the stash. The untracked files
      a stash holds are in a commit of their own, its third parent: for
      a stash with any, a commit no branch points at is made whose tree
      is the stash's with them added (through a temporary index, as a
      snapshot is), and the range runs to that one, so the view shows
      the whole stash. False when the stash is unknown; ARange then
      still names the plain range. }
    function StashRange(const AId: string; out ARange: string): boolean;
    {** Commits the files APaths (relative to Root, as ChangedPaths gives
      them) as they are in the work tree, with the message AMessage as it
      is, whatever the index holds for them: the other changed files stay
      out of the commit, and their staged changes stay staged. An
      untracked file among APaths is added first, and taken out of the
      index again when the commit fails; the old path of a rename is
      committed with its new one. With AAmend HEAD is replaced instead,
      and with no paths only its message changes. During a merge, a
      cherry-pick or a revert git allows no commit of some files only:
      APaths are then added to the index and the whole index committed.
      git runs the repository's hooks and signs as configured. False,
      with the reason in Error (a hook's output, say), when nothing was
      committed: also while any file is in conflict, or with no paths and
      no AAmend outside those operations. AId is the new commit.
      AParts are files among APaths that go in with the text they give
      in place of the work tree's (with the work tree's mode, through
      git's filters as git add would): the commit is then made from a
      temporary index, HEAD's tree with APaths added and AParts written
      over them, and the real index takes the committed paths as the new
      HEAD has them, so what was left out shows as not staged; during a
      merge, a cherry-pick or a revert AParts go into the real index. }
    function Commit(const AMessage: string; APaths: TStrings; AAmend: boolean;
      out AId: string; const AParts: TGittanCommitParts = nil): boolean;
    {** The whole message of HEAD, without its trailing line ends; false
      before the first commit. }
    function HeadMessage(out AMessage: string): boolean;
    {** Whether ARef names a commit in the repository. }
    function HasCommit(const ARef: string): boolean;
    {** The full id of the commit ARef names, empty when it names none. }
    function CommitId(const ARef: string): string;
    {** How many commits AFrom..ATo holds (those ATo reaches and AFrom
      does not), -1 when git cannot tell. }
    function CountCommits(const AFrom, ATo: string): integer;
    {** The name the repository commits under (`git config user.name`,
      the repository's own setting before the global one), empty when
      none is set. }
    function UserName: string;
    {** Fetches every remote, dropping the remote-tracking branches
      whose branch is gone from it (`git fetch --all --prune`). }
    function Fetch: boolean;
    {** Pulls the branch's upstream into it, the way AMode says. False,
      with git's reason in Error, when nothing was pulled; ADiverged is
      then set when the branch and its upstream both have commits the
      other lacks, so a fast-forward alone could not do it and the user
      must choose pmMerge or pmRebase. A merge takes git's message as it
      is, without an editor; a rebase stashes the local changes for the
      time it runs (--autostash). A conflict leaves git merging or
      rebasing, as on the command line. }
    function Pull(AMode: TGittanPullMode; out ADiverged: boolean): boolean;
    {** Pushes the branch to its upstream (`git push <remote>
      HEAD:<branch>`, whatever push.default says), or, without one, to a
      branch of the same name on the remote RemoteFor gives, which then
      becomes its upstream (-u). False, with git's reason in Error, when
      nothing was pushed: ARejected is then set when the remote has
      commits the branch lacks, which a pull would bring first. }
    function Push(out ARejected: boolean): boolean;
    {** Pushes the branch over its upstream even when that loses the
      upstream's commits the branch lacks, as after a rebase of pushed
      commits, but only while the upstream is where the last fetch saw
      it (`--force-with-lease`), so commits someone pushed since are not
      lost unseen, and only while the branch once held the upstream's
      tip (`--force-if-includes`), so commits a fetch brought in but
      nothing took in are not lost either. False without an upstream,
      and when git refused: AStale is then set when the remote has moved
      since the last fetch, AUnseen when the upstream has commits that
      were fetched but never in the branch. }
    function ForcePush(out AStale, AUnseen: boolean): boolean;
    {** Pushes the local branch ABranch to a branch of the same name on
      ARemote and makes that its upstream (`git push -u`). }
    function PushBranch(const ABranch, ARemote: string): boolean;
    {** Makes the remote-tracking branch AUpstream (origin/main, say)
      the upstream of the local branch ABranch, without pushing (`git
      branch --set-upstream-to`); with AUpstream empty the branch tracks
      nothing any more (`--unset-upstream`). }
    function SetUpstream(const ABranch, AUpstream: string): boolean;
    {** The remotes of the repository (`git remote`), sorted as git
      lists them. }
    function Remotes(AList: TStrings): boolean;
    {** Adds the remote AName with the URL AUrl (`git remote add`),
      fetching nothing. False, with git's reason, when the name is taken
      or no remote's name. }
    function AddRemote(const AName, AUrl: string): boolean;
    {** Renames the remote AOld to ANew (`git remote rename`), its
      remote-tracking branches and the upstreams that name them going
      with it. }
    function RenameRemote(const AOld, ANew: string): boolean;
    {** Removes the remote AName (`git remote remove`), its
      remote-tracking branches with it; the branches that tracked them
      track nothing then. The remote itself is not touched. }
    function RemoveRemote(const AName: string): boolean;
    {** Sets the URL the remote AName fetches from to AUrl and the one it
      pushes to to APushUrl (`git remote set-url`, with --push); with
      APushUrl empty or AUrl it pushes to AUrl, any push URL unset. }
    function SetRemoteUrls(const AName, AUrl, APushUrl: string): boolean;
    {** The remote a push goes to: that of the current branch's upstream,
      else the one RemoteFor gives; empty when there is none. }
    function PushRemote: string;
    {** Whether the repository has the hook AName (pre-push, say): a file
      of that name in its hooks folder, `core.hooksPath` (husky's
      .husky/_) or .git/hooks. }
    function HasHook(const AName: string): boolean;
    {** The variables a fetch, pull or push runs with besides Gittan's
      own: ssh in batch mode (`ssh -o BatchMode=yes`), so a key that
      needs its passphrase, or a host not yet known, fails at once with
      ssh's reason instead of waiting for an answer at a terminal nobody
      sees; none when the user runs ssh their own way (GIT_SSH_COMMAND,
      GIT_SSH or core.sshCommand). A key in the agent still works. }
    function RemoteEnvironment: TStringArray;
    {** Whether AName may name a branch (`git check-ref-format --branch`). }
    function IsBranchName(const AName: string): boolean;
    {** Makes the branch AName at the commit AAt, and switches to it with
      ASwitch (`git switch -c`). False, with git's reason, when the name
      is taken or wrong, or the switch would overwrite local changes;
      the branch is then not made either. }
    function CreateBranch(const AName, AAt: string; ASwitch: boolean): boolean;
    {** Renames the local branch AOld to ANew (`git branch -m`), its
      upstream and reflog going with it. }
    function RenameBranch(const AOld, ANew: string): boolean;
    {** Deletes the local branch AName (`git branch -d`), or with AForce
      even when its commits are in no other branch or its upstream
      (`-D`). False, with git's reason, when nothing was deleted;
      ANotMerged is then set when only that stood in the way. }
    function DeleteBranch(const AName: string; AForce: boolean;
      out ANotMerged: boolean): boolean;
    {** The remote-tracking branch the local branch AName tracks, such as
      origin/main; empty when it tracks none. }
    function Upstream(const AName: string): string;
    {** Splits a remote-tracking branch such as origin/feature/x into the
      remote (origin) and the branch on it (feature/x), by the remotes
      the repository has, so a remote whose name has a slash is found
      too; false when no remote matches. }
    function SplitRemoteRef(const ARef: string; out ARemote, ABranch: string): boolean;
    {** Deletes the branch the remote-tracking branch ARef stands for on
      its remote (`git push <remote> --delete <branch>`), and so the
      remote-tracking branch. Goes to the network. }
    function DeleteRemoteBranch(const ARef: string): boolean;
    {** Tags the commit AAt as AName: an annotated tag with the message
      AMessage, or a lightweight one when it is empty. }
    function CreateTag(const AName, AAt, AMessage: string): boolean;
    {** The tags, newest first (`git for-each-ref refs/tags`, by
      creatordate, those of one second by version, the highest first),
      read by ParseTags. }
    function Tags(out AList: TGittanTags): boolean;
    {** Deletes the tag AName here (`git tag -d`); the remotes keep it. }
    function DeleteTag(const AName: string): boolean;
    {** Pushes the tag AName to ARemote, or every tag with AName empty
      (`git push --tags`). Goes to the network. }
    function PushTag(const ARemote, AName: string): boolean;
    {** Deletes the tag AName on ARemote (`git push <remote> --delete
      refs/tags/<name>`), leaving the local one. Goes to the network. }
    function DeleteRemoteTag(const ARemote, AName: string): boolean;
    {** Initializes and checks out the submodules at the commits the
      repository records, theirs too (`git submodule update --init
      --recursive`), or the one at APath alone; what a submodule lacks
      is fetched. Goes to the network. }
    function UpdateSubmodules(const APath: string): boolean;
    {** Copies the URLs .gitmodules gives into the config and into the
      submodules' own remotes (`git submodule sync --recursive`), for
      every submodule or the one at APath alone. }
    function SyncSubmodules(const APath: string): boolean;
    {** Clones AUrl into APath (relative to the root, "/" separators) as
      a new submodule following the branch ABranch (the remote's
      default with ABranch empty), and stages it with .gitmodules (`git
      submodule add`). False, with git's reason, when the path is taken
      or the clone failed; git then leaves nothing behind. Goes to the
      network. }
    function AddSubmodule(const AUrl, APath, ABranch: string): boolean;
    {** The newest ALimit lines of HEAD's reflog, newest first (`git log
      -g`, read by ParseReflog), those whose commit no ref and not HEAD
      reaches marked Lost (`git rev-list <commits> --not --all`). An
      unborn HEAD has none. }
    function Reflog(out AList: TGittanReflog; ALimit: integer = 1000): boolean;
    {** Where the bisect in progress stands: the marks from `git
      for-each-ref refs/bisect` (read by ParseBisectRefs), the commits
      left from `git rev-list <bad> --not <good>...`. False when git
      failed. }
    function BisectState(out AState: TGittanBisect): boolean;
    {** Starts a bisect (`git bisect start`), with ABad marked bad and
      AGood good when they are given; with both git checks out the
      first commit to test. }
    function BisectStart(const ABad, AGood: string): boolean;
    {** Marks the commit ACommit (HEAD, the one checked out to test, or
      another) as AMark (`git bisect good|bad|skip`); git then checks
      out the next commit to test, or names the first bad one. The mark
      counts as made when only skipped commits are left to test, which
      git ends with 2. }
    function BisectMark(const ACommit: string; AMark: TGittanBisectMark): boolean;
    {** Ends the bisect (`git bisect reset`): HEAD goes back to the
      branch or commit it was on when the bisect started. }
    function BisectEnd: boolean;
    {** Whether the commit AAncestor is in the history of ADescendant. }
    function IsAncestor(const AAncestor, ADescendant: string): boolean;
    {** Merges ARef (a branch, tag or commit) into the branch HEAD is on,
      with git's message (`git merge --no-edit`). False when nothing was
      merged; AConflicts is then set when git stopped merging with
      conflicts to resolve, which the Commit section carries on. }
    function MergeRef(const ARef: string; out AConflicts: boolean): boolean;
    {** Replays the commits the branch HEAD is on made since it left AOnto
      (a branch, tag or commit) on top of AOnto (`git rebase --autostash`,
      so local changes are stashed and put back). False when git refused;
      AConflicts is then set when the rebase stopped with conflicts to
      resolve, which the Commit section carries on. }
    function RebaseOnto(const AOnto: string; out AConflicts: boolean): boolean;
    {** The commits a rebase onto AOnto would replay, oldest first as
      git applies them, as steps for RebaseInteractive, each a pick with
      its own message, Pushed set for those on the branch's upstream.
      AMerges is set when one of them is a merge commit, which a rebase
      of this kind flattens. False when AOnto is unknown. }
    function RebaseSteps(const AOnto: string; out ASteps: TGittanRebaseSteps;
      out AMerges: boolean): boolean;
    {** Replays ASteps onto AOnto as `git rebase -i` does, the todo list
      BuildRebaseTodo makes handed over through GIT_SEQUENCE_EDITOR (a
      cp of a file in RebaseFilesFolder, inside the git directory), with
      the message files beside it, local changes stashed and put back
      (--autostash) and a commit that comes out empty kept (--empty=keep),
      so an exec line amends the commit it was written for. True when
      the rebase went through. False when it stopped: AConflicts with
      conflicts to resolve, AStopped at an edit, or at an exec line
      that failed, with git's words in Error and the commit in
      RebaseStoppedAt; the Commit section carries both on. False with
      neither when git refused. }
    function RebaseInteractive(const AOnto: string; const ASteps: TGittanRebaseSteps;
      out AConflicts, AStopped: boolean): boolean;
    {** The id of the commit an interactive rebase stopped at to edit,
      empty when it stopped for another reason (conflicts, a failed
      exec line) or there is no rebase. }
    function RebaseStoppedAt: string;
    {** What a rebase onto AOnto would replay: ACount commits, of which
      APushed are already on the branch's upstream, so the next push
      after rewriting them must be forced. False when AOnto is unknown. }
    function CommitsToRebase(const AOnto: string; out ACount, APushed: integer): boolean;
    {** Applies the changes of the commit AHash on top of HEAD as a new
      commit (`git cherry-pick`); AConflicts as for MergeRef. }
    function CherryPick(const AHash: string; out AConflicts: boolean): boolean;
    {** Makes a commit that undoes AHash (`git revert --no-edit`);
      AConflicts as for MergeRef. }
    function RevertCommit(const AHash: string; out AConflicts: boolean): boolean;
    {** Moves the branch HEAD is on (or HEAD itself when detached) to the
      commit AHash, keeping what AMode says (`git reset`). }
    function Reset(const AHash: string; AMode: TGittanResetMode): boolean;
    {** What Clean with AKind would remove, as `git clean -n -d` lists it
      (read by ParseCleanPreview): paths from the root, a folder whose
      every file goes as one path ending in a slash. A repository nested
      in the work tree is never listed. }
    function CleanPreview(AKind: TGittanCleanKind; APaths: TStrings): boolean;
    {** Deletes APaths, a choice from CleanPreview with the same AKind,
      from disk (`git clean -f -d`, folders with what they hold). Only
      what that preview would list goes, so a file that became tracked
      meanwhile stays. Nothing is kept to bring them back. }
    function Clean(AKind: TGittanCleanKind; APaths: TStrings): boolean;
    {** What the folder AFolder (a path from the root, '' for the root)
      holds in the commit ACommit (`git ls-tree -l -z`, read by
      ParseTreeEntries): folders first, then the rest, each by name. }
    function TreeEntries(const ACommit, AFolder: string;
      out AList: TGittanTreeEntries): boolean;
    {** The commits a patch series from AOlder to ANewer takes, oldest
      first (`git log --no-merges --reverse`): ANewer alone when AOlder
      is empty, else every commit from AOlder, which must be in ANewer's
      history, to ANewer, both included. git leaves merge commits out of
      a series, so they are not listed. }
    function PatchCommits(const AOlder, ANewer: string;
      out ACommits: TGittanPatchCommits): boolean;
    {** Writes the series PatchCommits lists into the folder AFolder, a
      file per commit numbered from 0001 (`git format-patch`), a file of
      the same name there overwritten; with ACoverLetter first a
      0000-cover-letter.patch to fill in. AFiles gets the files written,
      with their full paths, in order. }
    function FormatPatches(const AOlder, ANewer, AFolder: string; ACoverLetter: boolean;
      AFiles: TStrings): boolean;
    {** Applies the patch files AFiles in their order. With ACommit each
      becomes a commit with the author, date and message it carries (`git
      am --3way`, so every file must be a mail as format-patch writes
      them): one that does not apply stops the am, which the Commit
      section then carries on (Operation 'applying patches'), with
      AConflicts set when it stopped with conflicts. Without, the changes
      go into the work tree alone (`git apply`, a file at a time, each
      whole or not at all), with a three-way merge that leaves conflicts
      (AConflicts) when one does not apply as it is; the first that fails
      stops the rest. AApplied counts the patches that went in. }
    function ApplyPatches(AFiles: TStrings; ACommit: boolean; out AConflicts: boolean;
      out AApplied: integer): boolean;
    {** Resolves the conflict in APath by taking one side whole, as
      `git checkout --ours` or `--theirs` and `git add` do; when that
      side deleted the file it goes (`git rm`). }
    function ResolveConflict(const APath: string; ASide: TGittanConflictSide): boolean;
    {** Marks APath resolved as it is in the work tree (`git add`), or
      deleted when it is gone from there (`git rm`). }
    function MarkResolved(const APath: string): boolean;
    {** Puts APath back in conflict after MarkResolved or `git add`: the
      base, ours and theirs return to the index from what git kept of
      them when it was resolved (`git update-index --unresolve`), the
      work tree as it is. False when git kept nothing to bring back. }
    function Unresolve(const APath: string): boolean;
    {** Goes on with what git is in the middle of (Operation), once the
      conflicts are resolved: the tracked files' changes are staged
      first (`git add -u`), since they are what the stopped commit
      takes, then `git <merge|rebase|cherry-pick|revert|am> --continue`
      runs without an editor, keeping git's message. Refused while a
      file is still in conflict. A rebase may stop
      again at a later commit, which leaves it rebasing with new
      conflicts and is no failure. }
    function ContinueOperation: boolean;
    {** The tracked files changed in the work tree besides the conflicts
      resolved at this stop (the paths git keeps resolve-undo stages
      for), which ContinueOperation's `add -u` would take into the
      commit too, sorted. None at a stop without conflicts, such as an
      edit stop of an interactive rebase, where the changes are what
      the commit is stopped for. }
    function ContinueExtras: TStringArray;
    {** Leaves out the commit a rebase, cherry-pick, revert or am
      stopped at (`--skip`) and goes on with the rest. }
    function SkipOperation: boolean;
    {** Gives up what git is in the middle of (`--abort`): the branch and
      the work tree go back to how they were before it started. }
    function AbortOperation: boolean;
    {** Forgets what git is in the middle of (`--quit`): HEAD, the index
      and the work tree stay as they are, git just stops rebasing (or
      cherry-picking, reverting, applying patches). For a rebase left
      behind by a checkout to another branch, where --abort would check
      the rebased branch out again. Not for a merge. }
    function QuitOperation: boolean;
    {** The message git prepared for the merge, cherry-pick or revert in
      progress (MERGE_MSG in the git directory), its comment lines left
      out; empty when there is none. }
    function MergeMessage: string;
    {** The e-mail the repository commits under (`git config
      user.email`), empty when none is set. }
    function UserEmail: string;
    {** Sets the name and e-mail commits are made under: in the user's
      global git config with AGlobal, else in the repository's own. With
      AGlobal the repository's own are unset, since they would go
      before the global ones. }
    function SetIdentity(const AName, AEmail: string; AGlobal: boolean): boolean;
    {** Whether the repository sets a name or an e-mail of its own
      (`git config --local`), which go before the global ones. }
    function HasLocalIdentity: boolean;
    {** The remote whose URL holds ARepoPath ("owner/repo", compared
      without regard to case), else origin, else the first remote, else
      empty. }
    function RemoteFor(const ARepoPath: string): string;
    {** Fetches pull request ANumber of ARemote (a GitHub remote, which
      serves it as refs/pull/N/head) into refs/gittan/pr/N, the name given
      in AHeadRef, and ABaseRef along with it, so the remote-tracking
      branch of the base is current too. Nothing in the work tree or the
      branches changes. }
    function FetchPullRequest(const ARemote: string; ANumber: integer;
      const ABaseRef: string; out AHeadRef: string): boolean;
    {** Records the work tree as it is now, untracked files included, in
      a commit of its own (parent HEAD when there is one, no branch points
      at it), and returns its id: a Base to compare against later, with
      WholeTree set, to see what changed since. The repository's own
      index is left alone: the tree is built through a temporary copy.
      The commit is reachable from nothing, so git prunes it with the
      other loose objects two weeks or more after it was made. }
    function TakeSnapshot(out AId: string): boolean;
    {** Changed files as "XY path" entries in the shape of `git status
      --porcelain`, untracked files included, one per file: a rename is
      listed under its new path alone. Paths are plain UTF-8 with "/"
      separators, never quoted. Returns false when git failed. }
    function ChangedFiles(AList: TStrings): boolean;
    {** Paths of the changed files from ChangedFiles, relative to Root.
      Each Objects entry holds the file's TGittanChangeKind as
      TObject(PtrUInt(Ord(Kind))), with flagStaged and flagUnstaged added
      from the two status columns. Returns false when git failed. }
    function ChangedPaths(AList: TStrings): boolean;
    {** The changed files of ChangedPaths with their added and deleted line
      counts from `git diff --numstat`. A file git does not know yet has
      every line counted as added. Returns false when git failed. }
    function ChangeStats(out AStats: TGittanFileStats): boolean;
    {** Everything the views read about the repository, gathered in one
      pass: the changed files, the branch, the default branch, the merge
      base with it, the ahead/behind counts, and the operation in progress
      with the branch a rebase rebases. Runs only git, no LCL, so it can
      be called from a watcher thread and the result handed to the main
      thread. ASnap.Ok is false, with ASnap.Error set, when the changed
      files could not be read; the rest is filled in as far as git
      answered. Returns ASnap.Ok. }
    function Snapshot(out ASnap: TGittanRepoSnapshot): boolean;
    {** The current branch, the short commit id when HEAD is detached, or
      empty when nothing is open. }
    function Branch: string;
    {** The same, with ADetached true when HEAD is on no branch. }
    function Branch(out ADetached: boolean): string;
    {** The remote-tracking branch the repository was cloned from, such as
      origin/main: what the remote's HEAD points at, else main or master
      on the remote RemoteFor gives, else empty. }
    function DefaultBranch: string;
    {** How many commits of ADefault (DefaultBranch, as of the last
      fetch) HEAD lacks, for the branch ABranch HEAD is on: what a
      rebase onto it or a merge of it would bring in. 0 when ADefault
      is ABranch's upstream or ABranch's own name on the remote (the
      sync line counts that, and a pull brings it in), or when git
      cannot tell. }
    function BehindDefault(const ABranch, ADefault: string): integer;
    {** Whether the tip of the local branch ABranch's upstream is reached
      from one of the branch's newest reflog entries, as push
      --force-if-includes asks: the upstream holds nothing the branch
      never had, so a branch that has moved away from it was rewritten
      here, and no one else pushed to it since the last fetch. False
      without an upstream or a reflog. }
    function UpstreamInReflog(const ABranch: string): boolean;
    {** How many commits HEAD reaches that no remote-tracking branch
      does (as of the last fetch): what a push of a branch new on the
      remote would bring there. -1 when git cannot tell. }
    function NotOnRemotes: integer;
    {** The merge base of ARef and HEAD, the commit the branch left ARef
      at; false when either is unknown or they share no history. }
    function MergeBase(const ARef: string; out AHash: string): boolean;
    {** How many commits the branch is ahead of and behind its upstream;
      false when it has none. }
    function AheadBehind(out AAhead, ABehind: integer): boolean;
    {** The commits the branch is ahead of its upstream (not pushed yet)
      with AAhead, else those it is behind (not pulled yet), newest
      first, at most AMax of them; false when it has no upstream. }
    function SyncCommits(AAhead: boolean; out ACommits: TGittanCommitLines;
      AMax: integer = 100): boolean;
    {** The newest AMax commits of HEAD, newest first, those not pushed
      to the upstream marked; false before the first commit. }
    function RecentCommits(out ACommits: TGittanCommitLines;
      AMax: integer = 10): boolean;
    {** The newest AMax commits of every local and remote branch, every
      tag and HEAD, in topological order, newest first, with their
      parents and refs, those not pushed and not pulled marked, laid out
      with LayoutGraph; false before the first commit. }
    function GraphCommits(out ACommits: TGittanGraphCommits;
      AMax: integer = 500): boolean;
    {** The ids of the commits of every local and remote branch, every
      tag and HEAD that touched APath, a file or a folder relative to
      Root, newest first, at most AMax; a file is followed through its
      renames. False when git failed, as before the first commit. }
    function PathCommits(const APath: string; AHashes: TStrings;
      AMax: integer = 50000): boolean;
    {** The git directory of the work tree (a linked work tree has one of
      its own), empty when nothing is open. }
    function GitDir: string;
    {** What git is in the middle of: "merging", "rebasing",
      "cherry-picking", "reverting" or "bisecting", from the files it
      leaves in the git directory meanwhile; empty when nothing. }
    function Operation: string;
    {** The branch a rebase in progress is rebasing, which HEAD, detached
      meanwhile, no longer names; empty when there is no rebase. }
    function RebaseBranch: string;
    {** How far a rebase in progress has come: APos of ATotal commits
      replayed so far, from the counters git keeps beside its todo list
      (msgnum and end for rebase-merge, next and last for rebase-apply).
      False, with both 0, when there is no rebase or git has not
      written them yet. }
    function OperationProgress(out APos, ATotal: integer): boolean;
    {** Whether Base is a range "A..B" or "A...B": the right side of
      every diff is then the commit B instead of the work tree. }
    function IsRange: boolean;
    {** Every file of the work tree git knows or would add: the tracked
      files and the untracked ones that are not ignored, as paths
      relative to Root with "/" separators. Returns false when git
      failed. }
    function Files(AList: TStrings): boolean;
    {** Runs `git grep` for the words AWords, whole words only, over the
      files Files lists (the untracked ones too), binary files left out,
      ignoring case when AIgnoreCase. AOutput is what `-z -n` prints: the
      path, the row and the text of every matching row, NUL separated,
      one row per line (see ParseGrep in gittan.callers). No match is not
      a failure: the output is empty then. Returns false when git
      failed. }
    function Grep(AWords: TStrings; AIgnoreCase: boolean; out AOutput: string): boolean;
    {** The change kind of a "XY" status from `git status --porcelain`. }
    class function ChangeKind(const AStatus: string): TGittanChangeKind;
    {** flagStaged and flagUnstaged for a "XY" status: X is the index
      column, Y the work tree column; an untracked or ignored file has
      neither flag, and neither has an unmerged one, whose columns name
      the two sides of the conflict, not the index and the work tree. }
    class function StageFlags(const AStatus: string): integer;
    {** One changed file as the lines of a unified diff against HEAD with the
      whole file as context: every line starts with ' ', '+' or '-'. A file
      git does not know yet is returned as all added lines; a binary file
      gives no lines. Returns false when git failed. }
    function FileChanges(const APath: string; ALines: TStrings): boolean;
    {** The two commits a diff of a file is between: ALeft is Base (HEAD
      by default), ARight the right commit of a range, or empty for the
      work tree. For a three-dot range A...B ALeft is the merge base of
      A and B, which is what git diffs B against (A itself when git
      finds none). }
    procedure DiffSides(out ALeft, ARight: string);
    {** The bytes of APath as it is in the commit ARef (`git cat-file
      blob`, no filter applied), or in the work tree when ARef is empty.
      Returns false when the version has no such file. }
    function FileBlob(const APath, ARef: string; out AData: RawByteString): boolean;
    {** The size in bytes of APath in the commit ARef (`git cat-file -s`),
      or in the work tree when ARef is empty, without reading it. Returns
      false when the version has no such file. }
    function FileSize(const APath, ARef: string; out ASize: int64): boolean;
    {** The output of `git blame --porcelain` for APath as it is in the
      commit ARef, or in the work tree when ARef is empty, with
      IgnoreWhitespace passed on as -w. Returns false when git failed: a
      file it does not know, or one ARef lacks. }
    function Blame(const APath, ARef: string; out AOutput: string): boolean;
    {** The output of `git log` for the commits that changed the lines
      AFrom..ATo of APath, as they are in the commit ARef (HEAD when
      empty), newest first and at most AMax of them, each with its diff
      of those lines (`git log -L`). With AFrom 0 the whole file is
      followed instead (`git log -p`). Every commit starts with a line
      of #1, the hash, the author, the author time and the summary
      separated by #31 (see TGittanHistory.Parse). IgnoreWhitespace is
      passed on as -w. Returns false when git failed: a file it does not
      know, or a range past the end of the file in ARef. }
    function LineHistory(const APath, ARef: string; AFrom, ATo, AMax: integer;
      out AOutput: string): boolean;
    {** A Base that shows what the commit AHash changed: the range from
      its parent, or from the empty tree for a commit without one. }
    function CommitRange(const AHash: string): string;
    {** The commit AHash as a line (its id, short id, author, commit time
      and subject; Unpushed is not set) and ABody, the rest of its
      message without the blank line after the subject, trimmed; false
      when git does not know it. }
    function CommitDetails(const AHash: string; out ACommit: TGittanCommitLine;
      out ABody: string): boolean;
    {** A text that changes whenever the branch, the set of changed files
      or the content of a changed file changes: the branch, the commit ids
      of HEAD and Base, the status of every changed file, and the size,
      modification time and content hash of every changed file on disk.
      Empty when nothing is open or git failed. Meant for polling: two
      equal fingerprints mean there is nothing new to show. }
    function Fingerprint: string;
    {** Work tree root, empty when nothing is open. }
    property Root: string read FRoot;
    {** Message from the last git call that failed. A call that succeeds
      leaves it as it was (a call may fail on the way to its answer and
      still give one), so it says why only right after a call that
      returned false. }
    property Error: string read FError;
    {** The commit the work tree is compared against: a branch, tag or
      commit id, or empty for HEAD. A range "A..B" compares the commits A
      and B instead, "A...B" the commit B against its merge base with A
      (the changes of a branch since it left A), as git diff reads them;
      an end left out is HEAD. }
    property Base: string read FBase write FBase;
    {** Compare every file of the work tree against Base, the untracked
      ones too: a diff only lists the files of the index, so one is run
      through a temporary index with every file added. An untracked file
      Base holds unchanged is then not a change, one it lacks is added,
      not untracked; the stage flags are off as against any base. Made
      for a snapshot from TakeSnapshot, which holds the untracked files;
      no effect against HEAD or in a range. }
    property WholeTree: boolean read FWholeTree write SetWholeTree;
    {** Leave out changes in whitespace: every diff is run with -w, so a
      line that only changed its spacing counts as unchanged, and a file
      with no other change has no changes. }
    property IgnoreWhitespace: boolean read FIgnoreWhitespace write FIgnoreWhitespace;
    {** Gets what a fetch, pull or push writes as it runs: git's progress
      and the output of the hooks it runs. Called in the caller's
      thread. }
    property OnOutput: TGittanOutputEvent read FOnOutput write FOnOutput;
  end;

{** The PATH Gittan looks for its tools on and runs git and gh with,
  so the hooks git runs get it too: Gittan's own PATH, then the folders
  of it that are missing where package managers and version managers
  put commands (Homebrew, /usr/local/bin, ~/.local/bin, Cargo, Volta,
  asdf, mise, Nix, Linuxbrew, snap), those that exist. An app started
  from the macOS Finder gets a PATH of /usr/bin:/bin:/usr/sbin:/sbin
  alone, without which neither gh nor the node of a hook would be
  found. Windows keeps its PATH as it is. }
function ToolSearchPath: string;

{** The value of the environment variable AName as UTF-8, empty when it
  is not set. SysUtils.GetEnvironmentVariable is wrong on Windows (FPC
  3.2.4): it reads the ANSI environment and labels the bytes as the OEM
  code page, so "C:\Users\Björn" (ö is F6 in Windows-1252) comes out as
  "C:\Users\Bj÷rn" (F6 in code page 850); this reads the Unicode
  environment instead. Every unit asks the environment through this. }
function EnvironmentVariable(const AName: string): string;

{** Every variable of Gittan's environment as "NAME=value" in UTF-8;
  SysUtils.GetEnvironmentString has the fault EnvironmentVariable
  describes, and a git given a USERPROFILE of Bj÷rn could not write
  ~/.gitconfig. }
function EnvironmentStrings: TStringArray;

{** Full path of the command AName (without .exe; Windows adds it) on
  ToolSearchPath, or empty when it is not installed. node is found this
  way too, wherever nvm, fnm, Volta or Homebrew put it. }
function FindTool(const AName: string): string;

{** Makes git run by the path APath, or, with APath empty, by the one
  FindTool gives (plain git when it finds none, so the error names it).
  Called at start with the setting and again when the setting changes:
  a git started after that runs by the new path. }
procedure SetGitExe(const APath: string);

{** The path git runs by. }
function GitExe: string;

const
  {** The oldest git Gittan supports: 2.30, the first with
    `push --force-if-includes`. }
  MinGitMajor = 2;
  MinGitMinor = 30;

{** Reads what `git --version` prints ("git version 2.39.5 (Apple
  Git-154)", "git version 2.30.1.windows.1") into AVersion (2.39.5),
  AMajor and AMinor; false when it names no version. }
function ParseGitVersion(const AText: string; out AVersion: string;
  out AMajor, AMinor: integer): boolean;

{** The version of the git GitExe runs, as ParseGitVersion reads it;
  false when git cannot be run or names no version. }
function GitVersion(out AVersion: string; out AMajor, AMinor: integer): boolean;

{** Whether git AMajor.AMinor is MinGitMajor.MinGitMinor or later. }
function GitVersionSupported(AMajor, AMinor: integer): boolean;

{** What a git call answers when git could not be started: that none
  was found, when AExe is the plain "git" SetGitExe falls back to, else
  that the one at AExe could not be run; both say where to set another. }
function GitNotRunMessage(const AExe: string): string;

{** Whether AError, what a failed git wrote, is macOS saying the
  developer tools are not installed: /usr/bin/git only stands in for the
  git of the Command Line Tools, and says so (and asks to install them)
  when they are missing or the path xcode-select has is gone. }
function IsMissingDeveloperTools(const AError: string): boolean;

const
  {** What a git call answers in place of that. }
  MissingDeveloperToolsMessage = 'git on macOS comes with the Command Line Tools, which ' +
    'are not installed. Install them (run xcode-select --install in Terminal, or accept ' +
    'the dialog macOS shows), or set the path of another git under Tools in the settings.';

{** The bin folder of the node that nvm in ANvmDir (~/.nvm, or NVM_DIR)
  runs by default: the version its alias "default" names, followed
  through the alias files (default → lts/* → lts/krypton → v24.21.0), a
  bare number ("20", "20.11") taken as the newest version that starts
  with it, else (no alias, or one naming a version not installed) the
  newest version installed. Empty when none is. }
function NvmNodeBin(const ANvmDir: string): string;

{** The bin folder of the node that fnm in AFnmDir (FNM_DIR, or its
  default folder) runs by default: its alias "default", else the newest
  version installed. Empty when none is. }
function FnmNodeBin(const AFnmDir: string): string;

{** Runs gh (AExe, from FindTool('gh')) in ADir and answers whether it
  succeeded, with its standard output in AOutput and, on failure, its
  message in AError. gh runs with its prompts and its update notice off,
  since nobody could answer the one and the other would land in stderr. }
function RunGitHubCli(const AExe, ADir: string; const AArgs: array of string;
  out AOutput, AError: string): boolean;

{** Runs an AI agent's command line tool (AExe: claude, copilot) in ADir
  with AArgs and AInput on its standard input, and answers whether it
  exited with 0, with its standard output in AOutput, kept on failure
  too (claude -p --output-format json says why there), and its standard
  error in AError. ACancel is asked as it runs; when it
  answers True claude is ended and the result is False. }
function RunAgentCli(const AExe, ADir: string; const AArgs: array of string;
  const AInput: string; ACancel: TGittanCancelEvent; out AOutput, AError: string): boolean;

{** The files a refused switch or checkout names in AError, git's
  message, as those it "would overwrite" (local changes, or untracked
  files the branch has), each on a line of its own after a tab; false
  when the message names none, a refusal for another reason. }
function SwitchBlockedFiles(const AError: string; AFiles: TStrings): boolean;

{** The branch and the message of a stash from its reflog subject, as
  `git stash list` prints it: "On main: message" for one made with a
  message, "WIP on main: 1234abc subject" for one made without (the
  message is then the short id and subject of the commit it was made
  on), and "(no branch)" for a detached HEAD, which gives no branch. }
procedure ParseStashSubject(const ASubject: string; out ABranch, AMessage: string);

{** The tags in AOutput, what `git for-each-ref` prints with TagFormat:
  per tag a line of the name, the object, the commit an annotated tag
  peels to (empty for a lightweight one), the date in Unix seconds and
  the subject, separated by #31. Lines that do not hold five fields are
  skipped. }
function ParseTags(const AOutput: string): TGittanTags;

{** The lines of HEAD's reflog in AOutput, what `git log -g --date=unix`
  prints with ReflogFormat: per line the commit, the selector with the
  time (HEAD@ and the unix time in braces) and the subject, separated by
  #31. Lines
  that do not hold three fields are skipped. }
function ParseReflog(const AOutput: string): TGittanReflog;

{** The marks of a bisect in AOutput, what `git for-each-ref` prints
  with BisectFormat: per line the commit and the ref, refs/bisect/bad
  or refs/bisect/good-<id> or refs/bisect/skip-<id>, separated by a
  space; into ABad, AGood and ASkipped. Other lines are skipped. }
procedure ParseBisectRefs(const AOutput: string; out ABad: string;
  out AGood, ASkipped: TStringArray);

const
  BisectFormat = '%(objectname) %(refname)';
  ReflogFormat = '%H%x1f%gd%x1f%gs';
  TagFormat = '%(refname:strip=2)%1f%(objectname)%1f%(*objectname)%1f' +
    '%(creatordate:unix)%1f%(contents:subject)';

{** The paths in what `git clean -n` prints, a line "Would remove
  <path>" each, a path quoted C-style unquoted (UnquoteCPath); other
  lines ("Would skip repository <path>") are left out. }
procedure ParseCleanPreview(const AOutput: string; APaths: TStrings);

{** The entries in what `git ls-tree -l -z` prints for the folder
  AFolder ('' for the root), each "<mode> <type> <id> <size>\t<name>"
  ended by a NUL, the size padded and "-" for a folder or a submodule;
  folders first, then the rest, each by name as git sorts them (bytes).
  Entries of another shape are skipped. }
function ParseTreeEntries(const AOutput, AFolder: string): TGittanTreeEntries;

{** Whether AText, the start of a patch file, is a mail that `git am`
  takes: an mbox "From " line first (what format-patch writes), or a
  header with From: and Subject: before the first empty line. A plain
  diff is not. Empty lines before it are skipped. }
function IsMailPatch(const AText: string): boolean;

{** IsMailPatch for the first 8 KB of the file AFileName; False for a
  file that cannot be read. }
function IsMailPatchFile(const AFileName: string): boolean;

{** APath as git meant it: when it is in double quotes, the quotes
  dropped and the escapes (\", \\, \t, \n, three octal digits for a
  byte...) turned back into what they stand for; else as it is. }
function UnquoteCPath(const APath: string): string;

{** Whether the file AFileName is binary by git's own rule: a NUL byte
  in its first 8000 bytes. False for a file that cannot be read. }
function IsBinaryFile(const AFileName: string): boolean;

{** FindFirst for the file AFileName itself, which FindFirst reads as a
  pattern: on Unix a *, ? or [...] in a name also matches its
  neighbours, and FindFirst gives whichever it finds first (a deleted
  a*b.txt gave aXb.txt's size and time). Only the file of that very name
  counts; AInfo is closed when there is none, else the caller closes
  it. }
function StatExact(const AFileName: string; out AInfo: TSearchRec): boolean;

{** Runs git in ADir as TGittanRepo does (see Running git) and answers
  whether it succeeded, with its standard output in AOutput and, on
  failure, its message in AError: what it wrote on stdout, then on
  stderr, since a pre-push hook's output goes to the one and git's own
  reason to the other. For work outside an open repository's
  root, such as a submodule, and for threads, which keep no repository. }
function RunGitIn(const ADir: string; const AArgs: array of string;
  out AOutput, AError: string; const AIndexFile: string = ''): boolean;

{** RunGitIn with the variables AEnv ("NAME=value") set besides those
  Gittan always sets, and AOnOutput told of each piece git writes as it
  runs, on either stream. }
function RunGitEnv(const ADir: string; const AArgs, AEnv: array of string;
  out AOutput, AError: string; const AIndexFile: string = '';
  AOnOutput: TGittanOutputEvent = nil): boolean;

{** The variables a command that goes to the network runs with in ADir
  besides Gittan's own: ssh in batch mode (see
  TGittanRepo.RemoteEnvironment), unless the environment or the config
  read in ADir (the repository's, else the user's) says how to run ssh. }
function RemoteEnvironmentIn(const ADir: string): TStringArray;

{** Clones the repository at AUrl into the folder ATarget (`git clone
  --progress`, with --recurse-submodules when ASubmodules is set), which
  must not exist or be empty; ATarget's parent must exist. Goes to the
  network: AOnOutput is told of what git writes as it runs. False, with
  git's reason in AError, when git failed; git then removes what it
  made of ATarget. }
function CloneRepository(const AUrl, ATarget: string; ASubmodules: boolean;
  out AError: string; AOnOutput: TGittanOutputEvent = nil): boolean;

{** Makes the existing folder ADir a new repository (`git init`), the
  first branch named as the config says (init.defaultBranch). }
function InitRepository(const ADir: string; out AError: string): boolean;

{** The folder git clone would make for AUrl: the last part of the URL
  or path, without a trailing slash, ".git" or "/.git" (a host alone
  stands for itself, without its port or user); '' when nothing is left. }
function CloneFolderName(const AUrl: string): string;

{** Whether AText looks like a URL to clone from: https, http, ssh, git
  or file URL, or the scp-like user@host:path, on one line without
  spaces. For prefilling a field from the clipboard. }
function LooksLikeCloneUrl(const AText: string): boolean;

{** AText with the carriage returns of a terminal's progress lines
  ("Writing objects:  33%" written over and over) resolved: of what a
  line held before each return only the part after the last one stays,
  so the text reads as the terminal last showed it. }
function ResolveReturns(const AText: string): string;

{** Puts in AList the local branches of the repository in ADir that track
  a branch no longer on its remote: git ls-remote asks each remote once,
  since the remote-tracking ref stays until a fetch with --prune. A
  remote that cannot be reached counts none of its branches as gone.
  For threads: it goes to the network. }
procedure GoneUpstreamsIn(const ADir: string; AList: TStrings);

{** S quoted as the C runtime of Windows splits a command line: in double
  quotes, with a quote inside escaped and the backslashes before it or
  before the closing quote doubled; S as it is when it holds no space, tab
  or quote and is not empty. }
function WindowsArg(const S: string): string;

{** S as an item of TProcess.Parameters. On Windows TProcess joins them
  into one command line and quotes an item only when it holds a space and
  no quote, so an item with a quote (a commit message, a pull request's
  title) or an empty one would not come through; there it is WindowsArg,
  which TProcess passes as it is. Elsewhere S. }
function ProcessArg(const S: string): string;

implementation

uses
  {$ifdef unix}BaseUnix,{$endif}
  Process, Pipes, md5, StrUtils, DateUtils, gittan.textfile;

{ ---------------------------------------------------------------------------
  The environment
  --------------------------------------------------------------------------- }

{$ifdef windows}
{ Declared here rather than taken from the Windows unit, whose DeleteFile,
  Sleep and GetEnvironmentVariable would shadow those of SysUtils. }
function GetEnvironmentStringsW: PWideChar; stdcall;
  external 'kernel32' name 'GetEnvironmentStringsW';
function FreeEnvironmentStringsW(ABlock: PWideChar): LongBool; stdcall;
  external 'kernel32' name 'FreeEnvironmentStringsW';
{$endif}

function EnvironmentVariable(const AName: string): string;
begin
  {$ifdef windows}
  Result := UTF8Encode(SysUtils.GetEnvironmentVariable(UnicodeString(AName)));
  {$else}
  Result := SysUtils.GetEnvironmentVariable(AName);
  {$endif}
end;

function EnvironmentStrings: TStringArray;
{$ifdef windows}
var
  Block, P: PWideChar;
  Entry: UnicodeString;
begin
  Result := nil;
  Block := GetEnvironmentStringsW;
  if Block = nil then
    Exit;
  try
    P := Block;
    while P^ <> #0 do
    begin
      Entry := P;
      Inc(P, Length(Entry) + 1);
      SetLength(Result, Length(Result) + 1);
      Result[High(Result)] := UTF8Encode(Entry);
    end;
  finally
    FreeEnvironmentStringsW(Block);
  end;
end;
{$else}
var
  i: integer;
begin
  { envp itself, not GetEnvironmentString: GetEnvironmentVariableCount
    counts once and keeps the number, so a variable set since is missed. }
  Result := nil;
  i := 0;
  while envp[i] <> nil do
  begin
    SetLength(Result, i + 1);
    Result[i] := envp[i];
    Inc(i);
  end;
end;
{$endif}

var
  GToolPath: string;
  GGitExe: string;
  { The paths git ran by before, once each: kept, so that a thread
    starting git while the main thread changes the path copies a string
    that is not freed. }
  GOldGitExes: TStringList;

function ToolSearchPath: string;
begin
  Result := GToolPath;
end;

function ParseGitVersion(const AText: string; out AVersion: string;
  out AMajor, AMinor: integer): boolean;
const
  Prefix = 'git version ';
var
  Text: string;
  Parts: TStringArray;
  i: integer;
begin
  AVersion := '';
  AMajor := 0;
  AMinor := 0;
  Text := Trim(AText);
  if Pos(Prefix, Text) <> 1 then
    Exit(False);
  Text := Copy(Text, Length(Prefix) + 1, MaxInt);
  i := 1;
  while (i <= Length(Text)) and (Text[i] in ['0'..'9', '.']) do
    Inc(i);
  AVersion := Copy(Text, 1, i - 1);
  { 2.30.1.windows.1 stops at the dot before windows. }
  while (AVersion <> '') and (AVersion[Length(AVersion)] = '.') do
    SetLength(AVersion, Length(AVersion) - 1);
  Parts := AVersion.Split(['.']);
  Result := (Length(Parts) >= 2) and TryStrToInt(Parts[0], AMajor) and
    TryStrToInt(Parts[1], AMinor);
end;

function GitVersion(out AVersion: string; out AMajor, AMinor: integer): boolean;
var
  Output, Err: string;
begin
  AVersion := '';
  AMajor := 0;
  AMinor := 0;
  Result := RunGitIn(GetTempDir, ['--version'], Output, Err) and
    ParseGitVersion(Output, AVersion, AMajor, AMinor);
end;

function GitVersionSupported(AMajor, AMinor: integer): boolean;
begin
  Result := (AMajor > MinGitMajor) or ((AMajor = MinGitMajor) and (AMinor >= MinGitMinor));
end;

function GitNotRunMessage(const AExe: string): string;
begin
  if (AExe = '') or (AExe = 'git') then
    Result := 'git was not found. Install git, or set the path of one under Tools in ' +
      'the settings.'
  else
    Result := Format('Could not run git at %s. Install git, or set the path of one under ' +
      'Tools in the settings.', [AExe]);
end;

{ "No developer tools were found" with none installed, "invalid active
  developer path" when xcode-select points at a folder that is gone. }
function IsMissingDeveloperTools(const AError: string): boolean;
begin
  Result := (Pos('No developer tools were found', AError) > 0) or
    (Pos('invalid active developer path', AError) > 0);
end;

procedure SetGitExe(const APath: string);
var
  Exe: string;
  i: integer;
begin
  Exe := APath;
  if Exe = '' then
    Exe := FindTool('git');
  if Exe = '' then
    Exe := 'git';
  if Exe = GGitExe then
    Exit;
  { One string per path git ran by, not one per call: the settings set
    it again on every save. A path set again is the kept string itself,
    so the one in use is always kept or new, never a copy freed later. }
  if (GGitExe <> '') and (GOldGitExes.IndexOf(GGitExe) < 0) then
    GOldGitExes.Add(GGitExe);
  i := GOldGitExes.IndexOf(Exe);
  if i >= 0 then
    GGitExe := GOldGitExes[i]
  else
    GGitExe := Exe;
end;

function GitExe: string;
begin
  Result := GGitExe;
end;

{ Whether the folder name A ("v24.21.0") is a newer node version than
  B, by number; a name that is no version counts as the oldest. }
function NodeVersionNewer(const A, B: string): boolean;

  function Parts(const S: string; out N: array of integer): boolean;
  var
    Fields: TStringArray;
    i: integer;
  begin
    for i := 0 to High(N) do
      N[i] := -1;
    Fields := S.TrimLeft(['v']).Split(['.']);
    Result := (Length(Fields) > 0) and (Length(Fields) <= Length(N));
    for i := 0 to High(Fields) do
      if not (Result and TryStrToInt(Fields[i], N[i])) then
        Exit(False);
  end;

var
  NA, NB: array[0..2] of integer;
  i: integer;
begin
  if not Parts(A, NA) then
    Exit(False);
  if not Parts(B, NB) then
    Exit(True);
  for i := 0 to 2 do
    if NA[i] <> NB[i] then
      Exit(NA[i] > NB[i]);
  Result := False;
end;

{ The newest version folder under AVersionsDir whose name starts with
  APrefix (every one when it is empty), or empty. }
function NewestNodeVersion(const AVersionsDir, APrefix: string): string;
var
  Info: TSearchRec;
begin
  Result := '';
  if FindFirst(IncludeTrailingPathDelimiter(AVersionsDir) + '*', faDirectory, Info) = 0 then
  begin
    repeat
      if ((Info.Attr and faDirectory) <> 0) and (Info.Name <> '.') and (Info.Name <> '..') and
        ((APrefix = '') or (Pos(APrefix, Info.Name) = 1)) and
        ((Result = '') or NodeVersionNewer(Info.Name, Result)) then
        Result := Info.Name;
    until FindNext(Info) <> 0;
    FindClose(Info);
  end;
end;

function NvmNodeBin(const ANvmDir: string): string;
var
  Versions, Name, Line: string;
  Hops: integer;
  Lines: TStringList;
begin
  Result := '';
  Versions := IncludeTrailingPathDelimiter(ANvmDir) + 'versions' + PathDelim + 'node';
  if not DirectoryExists(Versions) then
    Exit;
  Name := 'default';
  Hops := 0;
  Lines := TStringList.Create;
  try
    { An alias file holds a version or another alias (lts/* → lts/krypton). }
    while (Hops < 8) and FileExists(IncludeTrailingPathDelimiter(ANvmDir) + 'alias' +
        PathDelim + Name) do
    begin
      Lines.LoadFromFile(IncludeTrailingPathDelimiter(ANvmDir) + 'alias' + PathDelim + Name);
      Line := '';
      if Lines.Count > 0 then
        Line := Trim(Lines[0]);
      if Line = '' then
        Break;
      Name := Line;
      Inc(Hops);
    end;
  finally
    Lines.Free;
  end;
  if (Name <> '') and (Name[1] in ['0'..'9']) then
    Name := 'v' + Name;
  if (Name <> '') and (Name[1] = 'v') then
  begin
    if DirectoryExists(IncludeTrailingPathDelimiter(Versions) + Name) then
      Result := Name
    else
      Result := NewestNodeVersion(Versions, Name + '.');
  end;
  if Result = '' then
    Result := NewestNodeVersion(Versions, '');
  if Result <> '' then
    Result := IncludeTrailingPathDelimiter(Versions) + Result + PathDelim + 'bin';
end;

function FnmNodeBin(const AFnmDir: string): string;
var
  Versions: string;
begin
  Result := IncludeTrailingPathDelimiter(AFnmDir) + 'aliases' + PathDelim + 'default' +
    PathDelim + 'bin';
  if DirectoryExists(Result) then
    Exit;
  Result := '';
  Versions := IncludeTrailingPathDelimiter(AFnmDir) + 'node-versions';
  if NewestNodeVersion(Versions, '') <> '' then
    Result := IncludeTrailingPathDelimiter(Versions) + NewestNodeVersion(Versions, '') +
      PathDelim + 'installation' + PathDelim + 'bin';
end;

{ Gittan's PATH with the folders of Extra that exist and are not in it
  yet, after it, so a tool the user put first on PATH still comes
  first. The node of nvm and fnm lives in a folder named after its
  version, found through their default alias; pnpm's home is PNPM_HOME
  or its platform's default. }
function MakeToolPath: string;
{$ifndef windows}
const
  Extra: array[0..19] of string = ('/opt/homebrew/bin', '/opt/homebrew/sbin',
    '/usr/local/bin', '/usr/bin', '/bin', '~/.local/bin', '~/bin', '~/.cargo/bin',
    '~/.volta/bin', '~/.asdf/shims', '~/.local/share/mise/shims',
    '~/.nix-profile/bin', '/nix/var/nix/profiles/default/bin',
    '/home/linuxbrew/.linuxbrew/bin', '/snap/bin',
    '~/.bun/bin', '~/.deno/bin', '~/.yarn/bin', '~/.npm-global/bin',
    '~/.config/yarn/global/node_modules/.bin');
var
  Dirs: TStringList;
  Home, Dir, Full, NvmDir, FnmDir, Pnpm: string;
  More: TStringArray;

  procedure AddDir(const AFull: string);
  begin
    if (AFull = '') or (Dirs.IndexOf(AFull) >= 0) or not DirectoryExists(AFull) then
      Exit;
    if Result <> '' then
      Result := Result + PathSeparator;
    Result := Result + AFull;
    Dirs.Add(AFull);
  end;

{$endif}
begin
  Result := EnvironmentVariable('PATH');
  {$ifndef windows}
  Home := ExcludeTrailingPathDelimiter(GetUserDir);
  Dirs := TStringList.Create;
  try
    for Dir in Result.Split([PathSeparator]) do
      if Dir <> '' then
        Dirs.Add(Dir);
    for Dir in Extra do
    begin
      if (Dir[1] = '~') and (Home = '') then
        Continue;
      AddDir(StringReplace(Dir, '~', Home, []));
    end;
    NvmDir := EnvironmentVariable('NVM_DIR');
    if (NvmDir = '') and (Home <> '') then
      NvmDir := Home + '/.nvm';
    FnmDir := EnvironmentVariable('FNM_DIR');
    Pnpm := EnvironmentVariable('PNPM_HOME');
    if Home <> '' then
    begin
      if FnmDir = '' then
      begin
        {$ifdef darwin}
        More := [Home + '/Library/Application Support/fnm', Home + '/.fnm'];
        {$else}
        More := [EnvironmentVariable('XDG_DATA_HOME') + '/fnm',
          Home + '/.local/share/fnm', Home + '/.fnm'];
        {$endif}
        for Full in More do
          if (FnmDir = '') and (Full[1] = '/') and DirectoryExists(Full) then
            FnmDir := Full;
      end;
      if Pnpm = '' then
        {$ifdef darwin}
        Pnpm := Home + '/Library/pnpm';
        {$else}
        Pnpm := Home + '/.local/share/pnpm';
        {$endif}
    end;
    if NvmDir <> '' then
      AddDir(NvmNodeBin(NvmDir));
    if FnmDir <> '' then
      AddDir(FnmNodeBin(FnmDir));
    AddDir(Pnpm);
  finally
    Dirs.Free;
  end;
  {$endif}
end;

function FindTool(const AName: string): string;
begin
  {$ifdef windows}
  Result := ExeSearch(AName + '.exe', GToolPath);
  {$else}
  Result := ExeSearch(AName, GToolPath);
  {$endif}
end;

{ Gives P the environment of Gittan (EnvironmentStrings, in UTF-8, which
  TProcess turns into the Unicode environment the process gets) without
  the variables whose names (with the equals sign) are in ASkip, so the
  caller can set those, and with ToolSearchPath as its PATH outside
  Windows (whose variable is "Path", and whose PATH is kept as it is). }
procedure CopyEnvironment(P: TProcess; const ASkip: array of string);
var
  Env, Prefix: string;
  Keep: boolean;
begin
  for Env in EnvironmentStrings do
  begin
    Keep := True;
    for Prefix in ASkip do
      if Pos(Prefix, Env) = 1 then
        Keep := False;
    {$ifndef windows}
    if Pos('PATH=', Env) = 1 then
      Keep := False;
    {$endif}
    if Keep then
      P.Environment.Add(Env);
  end;
  {$ifndef windows}
  P.Environment.Add('PATH=' + GToolPath);
  {$endif}
end;

function WindowsArg(const S: string): string;
var
  i, Slashes: integer;
begin
  if (S <> '') and (LastDelimiter(' '#9'"', S) = 0) then
    Exit(S);
  Result := '"';
  Slashes := 0;
  for i := 1 to Length(S) do
  begin
    if S[i] = '\' then
      Inc(Slashes)
    else
    begin
      if S[i] = '"' then
        Result := Result + StringOfChar('\', Slashes + 1);
      Slashes := 0;
    end;
    Result := Result + S[i];
  end;
  Result := Result + StringOfChar('\', Slashes) + '"';
end;

function ProcessArg(const S: string): string;
begin
  {$ifdef MSWINDOWS}
  Result := WindowsArg(S);
  {$else}
  Result := S;
  {$endif}
end;

{ ---------------------------------------------------------------------------
  Running git
  ---------------------------------------------------------------------------
  git is found on PATH. stderr is read apart from stdout: git warns there
  about things that are not failures (with core.autocrlf on, every diff
  of a file with LF line endings says they will be replaced), and a
  warning must not be taken for output. On failure the error message is
  kept in FError: what came on stderr, or on stdout when stderr had
  nothing. git gets
  the environment of Gittan with LC_ALL set to C, so its messages come in
  English whatever the user's locale and the few that are matched on can
  be relied upon, and with prompts turned off, since nobody could answer
  one. Path names come back as plain UTF-8 instead of octal escapes. }
function RunGitIn(const ADir: string; const AArgs: array of string;
  out AOutput, AError: string; const AIndexFile: string): boolean;
begin
  Result := RunGitEnv(ADir, AArgs, [], AOutput, AError, AIndexFile);
end;

function ResolveReturns(const AText: string): string;
var
  Lines: TStringArray;
  i, p: integer;
begin
  if Pos(#13, AText) = 0 then
    Exit(AText);
  Lines := AText.Split([#10]);
  for i := 0 to High(Lines) do
  begin
    { A return at the end of a line (before its newline) is no overwrite. }
    while (Lines[i] <> '') and (Lines[i][Length(Lines[i])] = #13) do
      SetLength(Lines[i], Length(Lines[i]) - 1);
    p := LastDelimiter(#13, Lines[i]);
    if p > 0 then
      Lines[i] := Copy(Lines[i], p + 1, MaxInt);
  end;
  Result := string.Join(#10, Lines);
end;

{ Reads what the pipe holds, into ADest and to AOnOutput; false when it
  held nothing. }
function ReadPipe(APipe: TInputPipeStream; var ADest: string;
  AOnOutput: TGittanOutputEvent): boolean;
var
  Chunk: string;
  N: longint;
begin
  N := APipe.NumBytesAvailable;
  Result := N > 0;
  if not Result then
    Exit;
  SetLength(Chunk, N);
  N := APipe.Read(Chunk[1], N);
  if N < 0 then
    N := 0;
  SetLength(Chunk, N);
  if Chunk = '' then
    Exit(False);
  ADest := ADest + Chunk;
  if Assigned(AOnOutput) then
    AOnOutput(Chunk);
end;

{ Waits until git writes or ends, so RunGitEnv does not sleep past the
  end of a git call that takes a few milliseconds. On Unix git's pipes
  are watched, for a tenth of a second at most: its exit closes them,
  which wakes the wait too. A pipe at its end stays readable with nothing
  to read, so it is left out from then on (AOutOpen, AErrOpen); with
  both ended only git's exit is left to wait for. On Windows a pipe
  cannot be waited on, the process is: the wait ends when git does, and
  what git writes meanwhile waits in the pipe, so the wait is as short
  as the sleep it replaces, or git would stand still on a full pipe. }
{$ifdef windows}
{ Declared here rather than taken from the Windows unit, whose DeleteFile
  and others would hide SysUtils' own. }
function WaitForSingleObject(AHandle: THandle; AMilliseconds: DWord): DWord;
  stdcall; external 'kernel32' name 'WaitForSingleObject';
{$endif}

procedure WaitForGit(P: TProcess; var AOutOpen, AErrOpen: boolean);
{$ifdef unix}
const
  Timeout = 100;
var
  Fds: TFDSet;
  Tv: TTimeVal;
  Top: cint;
begin
  if not AOutOpen and not AErrOpen then
  begin
    P.WaitOnExit;
    Exit;
  end;
  fpFD_ZERO(Fds);
  Top := 0;
  if AOutOpen then
  begin
    fpFD_SET(P.Output.Handle, Fds);
    Top := P.Output.Handle;
  end;
  if AErrOpen then
  begin
    fpFD_SET(P.Stderr.Handle, Fds);
    if P.Stderr.Handle > Top then
      Top := P.Stderr.Handle;
  end;
  Tv.tv_sec := 0;
  Tv.tv_usec := Timeout * 1000;
  if fpSelect(Top + 1, @Fds, nil, nil, @Tv) <= 0 then
    Exit;
  { Readable with nothing in it: the end of the pipe. }
  if AOutOpen and (fpFD_ISSET(P.Output.Handle, Fds) = 1) and
    (P.Output.NumBytesAvailable = 0) then
    AOutOpen := False;
  if AErrOpen and (fpFD_ISSET(P.Stderr.Handle, Fds) = 1) and
    (P.Stderr.NumBytesAvailable = 0) then
    AErrOpen := False;
end;
{$else}
const
  Timeout = 10;
begin
  WaitForSingleObject(P.ProcessHandle, Timeout);
end;
{$endif}

{ Runs AExe in ADir with AArgs, in the environment with ASkip (prefixes
  like "NAME=") and the names of AEnv left out and AEnv added; false,
  with nothing read, when AExe cannot be started. Both pipes are read
  as the tool writes, so a long command's progress can be shown and
  neither pipe fills up and blocks it; what is left once it has ended
  is read after it. AStatus is its exit code. AInput is written to the
  tool's input before its input is closed: a tool that reads all of it
  before it writes (claude -p) takes any length, one that writes first
  could block on a full pipe while it is written. ACancel, when given,
  is asked on every pass of the reading loop, and True ends the tool. }
function RunTool(const AExe, ADir: string; const AArgs, ASkip, AEnv: array of string;
  out AOutput, AError: string; out AStatus: integer;
  AOnOutput: TGittanOutputEvent; const AInput: string = '';
  ACancel: TGittanCancelEvent = nil): boolean;
var
  P: TProcess;
  Skip: array of string;
  i: integer;
  Got, OutOpen, ErrOpen: boolean;
begin
  AOutput := '';
  AError := '';
  AStatus := -1;
  P := TProcess.Create(nil);
  try
    P.Executable := AExe;
    P.CurrentDirectory := ADir;
    for i := 0 to High(AArgs) do
      P.Parameters.Add(ProcessArg(AArgs[i]));
    SetLength(Skip, Length(ASkip) + Length(AEnv));
    for i := 0 to High(ASkip) do
      Skip[i] := ASkip[i];
    for i := 0 to High(AEnv) do
      Skip[Length(ASkip) + i] := Copy(AEnv[i], 1, Pos('=', AEnv[i]));
    CopyEnvironment(P, Skip);
    for i := 0 to High(AEnv) do
      P.Environment.Add(AEnv[i]);
    P.Options := [poNoConsole, poUsePipes];
    try
      P.Execute;
    except
      Exit(False);
    end;
    { The input ends once AInput is written (at once without one): a
      hook or an alias that reads it would otherwise wait for ever, and
      the app with it. A tool that ended before reading it all breaks the
      pipe, which is no failure of the run. }
    if AInput <> '' then
      try
        P.Input.WriteBuffer(AInput[1], Length(AInput));
      except
      end;
    P.CloseInput;
    OutOpen := True;
    ErrOpen := True;
    repeat
      if Assigned(ACancel) and ACancel() then
      begin
        P.Terminate(1);
        AStatus := -1;
        Exit(False);
      end;
      Got := ReadPipe(P.Output, AOutput, AOnOutput);
      if ReadPipe(P.Stderr, AError, AOnOutput) then
        Got := True;
      if not Got then
        if P.Running then
          WaitForGit(P, OutOpen, ErrOpen)
        else
          Break;
    until False;
    while ReadPipe(P.Output, AOutput, AOnOutput) do;
    while ReadPipe(P.Stderr, AError, AOnOutput) do;
    AStatus := P.ExitStatus;
    Result := True;
  finally
    P.Free;
  end;
end;

{ A failed tool's reason is what it wrote, on both streams in their
  order: a pre-push hook's output (husky's "pre-push script failed", the
  tests it ran) is on stdout, git's own "failed to push some refs" on
  stderr, and either alone says little. Progress is read as the terminal
  last showed it. Blank space is trimmed but not an escape sequence (a
  hook's color) at the start, which Trim would cut the ESC of. AOutput
  is emptied. }
procedure JoinFailure(var AOutput, AError: string);
const
  Blank: array[0..3] of char = (' ', #9, #10, #13);
begin
  AError := ResolveReturns(AError).Trim(Blank);
  AOutput := ResolveReturns(AOutput).Trim(Blank);
  if AOutput <> '' then
    if AError = '' then
      AError := AOutput
    else
      AError := AOutput + LineEnding + AError;
  AOutput := '';
end;

function RunGitEnv(const ADir: string; const AArgs, AEnv: array of string;
  out AOutput, AError: string; const AIndexFile: string;
  AOnOutput: TGittanOutputEvent): boolean;
var
  Args, Env: array of string;
  Status, i: integer;
begin
  SetLength(Args, 4 + Length(AArgs));
  Args[0] := '-c';
  Args[1] := 'core.quotepath=false';
  { With it git writes a blank context line as an empty line, not a
    space, and the readers of a hunk would lose the line. }
  Args[2] := '-c';
  Args[3] := 'diff.suppressBlankEmpty=false';
  for i := 0 to High(AArgs) do
    Args[4 + i] := AArgs[i];
  SetLength(Env, Length(AEnv) + 4);
  for i := 0 to High(AEnv) do
    Env[i] := AEnv[i];
  i := Length(AEnv);
  Env[i] := 'LC_ALL=C';
  Env[i + 1] := 'GIT_TERMINAL_PROMPT=0';
  { git status refreshes the index when it may, under index.lock; the
    watcher's poll would then make a commit started meanwhile fail. }
  Env[i + 2] := 'GIT_OPTIONAL_LOCKS=0';
  if AIndexFile <> '' then
    Env[i + 3] := 'GIT_INDEX_FILE=' + AIndexFile
  else
    SetLength(Env, i + 3);
  { The user's own GIT_INDEX_FILE goes even when none is given. }
  if not RunTool(GGitExe, ADir, Args, ['GIT_INDEX_FILE='], Env, AOutput, AError,
    Status, AOnOutput) then
  begin
    AError := GitNotRunMessage(GGitExe);
    Exit(False);
  end;
  Result := Status = 0;
  if not Result then
  begin
    JoinFailure(AOutput, AError);
    if IsMissingDeveloperTools(AError) then
      AError := MissingDeveloperToolsMessage;
  end;
end;

{ Each line of for-each-ref is "branch<TAB>remote<TAB>refs/heads/x",
  the last two empty without an upstream; each of ls-remote's is
  "<id><TAB>refs/heads/x". }
procedure GoneUpstreamsIn(const ADir: string; AList: TStrings);
var
  Output, Err, Line, Remote: string;
  Tracks, Fields, Heads, Asked: TStringList;
  i: integer;
begin
  AList.Clear;
  if not RunGitIn(ADir, ['for-each-ref',
    '--format=%(refname:short)%09%(upstream:remotename)%09%(upstream:remoteref)',
    'refs/heads'], Output, Err) then
    Exit;
  Tracks := TStringList.Create;
  Fields := TStringList.Create;
  Heads := TStringList.Create;
  Asked := TStringList.Create;
  try
    Tracks.Text := Output;
    Fields.Delimiter := #9;
    Fields.StrictDelimiter := True;
    Heads.Sorted := True;
    for i := 0 to Tracks.Count - 1 do
    begin
      Fields.DelimitedText := Tracks[i];
      if (Fields.Count < 3) or (Fields[1] = '') or (Fields[2] = '') then
        Continue;
      Remote := Fields[1];
      if Asked.IndexOf(Remote) < 0 then
      begin
        Asked.Add(Remote);
        if RunGitIn(ADir, ['ls-remote', '--heads', Remote], Output, Err) then
        begin
          for Line in Output.Split([#10]) do
            if Pos(#9, Line) > 0 then
              Heads.Add(Remote + #9 + Copy(Line, Pos(#9, Line) + 1, MaxInt));
        end
        else
          { Not reached: one ref stands for it, which no branch matches. }
          Heads.Add(Remote + #9#9);
      end;
      if (Heads.IndexOf(Remote + #9#9) < 0) and
        (Heads.IndexOf(Remote + #9 + Fields[2]) < 0) then
        AList.Add(Fields[0]);
    end;
  finally
    Tracks.Free;
    Fields.Free;
    Heads.Free;
    Asked.Free;
  end;
end;

function TGittanRepo.RunGit(const ADir: string; const AArgs: array of string;
  out AOutput: string; const AIndexFile: string): boolean;
var
  Err: string;
begin
  Result := RunGitIn(ADir, AArgs, AOutput, Err, AIndexFile);
  if not Result then
    FError := Err;
end;

function RunGitHubCli(const AExe, ADir: string; const AArgs: array of string;
  out AOutput, AError: string): boolean;
var
  Status: integer;
begin
  if not RunTool(AExe, ADir, AArgs, [], ['GH_PROMPT_DISABLED=1',
    'GH_NO_UPDATE_NOTIFIER=1'], AOutput, AError, Status, nil) then
  begin
    AError := 'Could not run ' + AExe;
    Exit(False);
  end;
  Result := Status = 0;
  if not Result then
    JoinFailure(AOutput, AError);
end;

function RunAgentCli(const AExe, ADir: string; const AArgs: array of string;
  const AInput: string; ACancel: TGittanCancelEvent; out AOutput, AError: string): boolean;
var
  Status: integer;
begin
  if not RunTool(AExe, ADir, AArgs, [], [], AOutput, AError, Status, nil, AInput,
    ACancel) then
  begin
    if (AError = '') and not (Assigned(ACancel) and ACancel()) then
      AError := 'Could not run ' + AExe;
    Exit(False);
  end;
  Result := Status = 0;
  AError := Trim(ResolveReturns(AError));
end;

{ The NUL-separated fields of the output of a git command run with -z; a
  trailing NUL ends the last field and adds none. }
procedure SplitNul(const AOutput: string; AFields: TStrings);
var
  Start, i: integer;
begin
  AFields.Clear;
  Start := 1;
  for i := 1 to Length(AOutput) do
    if AOutput[i] = #0 then
    begin
      AFields.Add(Copy(AOutput, Start, i - Start));
      Start := i + 1;
    end;
  if Start <= Length(AOutput) then
    AFields.Add(Copy(AOutput, Start, MaxInt));
end;

{ Writes AText to AFileName byte for byte. }
{ AList as git reads a --pathspec-from-file with --pathspec-file-nul:
  each entry ended by a NUL. }
function NulList(AList: TStrings): string;
var
  i: integer;
begin
  Result := '';
  for i := 0 to AList.Count - 1 do
    Result := Result + AList[i] + #0;
end;

procedure AddArg(var AArgs: TStringArray; const S: string);
begin
  SetLength(AArgs, Length(AArgs) + 1);
  AArgs[High(AArgs)] := S;
end;

procedure WriteBytes(const AFileName, AText: string);
var
  Stream: TFileStream;
begin
  Stream := TFileStream.Create(AFileName, fmCreate);
  try
    if AText <> '' then
      Stream.WriteBuffer(AText[1], Length(AText));
  finally
    Stream.Free;
  end;
end;

{ TGittanRepo }

destructor TGittanRepo.Destroy;
begin
  DropTempIndex;
  inherited Destroy;
end;

function TGittanRepo.Open(const ADir: string): boolean;
var
  Top: string;
  Lines: TStringArray;
begin
  Close;
  if not DirectoryExists(ADir) then
  begin
    FError := Format('Folder not found: %s', [ADir]);
    Exit(False);
  end;
  Result := RunGit(ADir, ['rev-parse', '--show-toplevel', '--absolute-git-dir'], Top);
  if Result then
  begin
    Lines := Trim(Top).Split([#10]);
    FRoot := Trim(Lines[0]);
    if Length(Lines) > 1 then
      FGitDir := Trim(Lines[1]);
  end
  { git's message is in English (RunGit sets LC_ALL=C), so the common
    case gets a shorter one; any other failure keeps git's own. }
  else if Pos('not a git repository', FError) > 0 then
    FError := Format('Not a git repository: %s', [ADir]);
end;

procedure TGittanRepo.Close;
begin
  DropTempIndex;
  FRoot := '';
  FGitDir := '';
  FError := '';
  FBase := '';
  FWholeTree := False;
end;

function TGittanRepo.DiffBase: string;
begin
  if FBase = '' then
    Result := 'HEAD'
  else
    Result := FBase;
end;

function TGittanRepo.IsRange: boolean;
begin
  Result := Pos('..', FBase) > 0;
end;

{ The two ends of a range Base, HEAD for one left out. }
procedure TGittanRepo.SplitRange(out ALeft, ARight: string);
var
  p: integer;
begin
  p := Pos('..', FBase);
  ALeft := Copy(FBase, 1, p - 1);
  ARight := Copy(FBase, p + 2, MaxInt);
  if Copy(ARight, 1, 1) = '.' then
    Delete(ARight, 1, 1);
  if ALeft = '' then
    ALeft := 'HEAD';
  if ARight = '' then
    ARight := 'HEAD';
end;

function TGittanRepo.FullPath(const APath: string): string;
begin
  Result := IncludeTrailingPathDelimiter(FRoot) + SetDirSeparators(APath);
end;

{ The id of the empty tree, which depends on the repository's hash
  function: the base of a diff before the first commit. }
function TGittanRepo.EmptyTree: string;
var
  Format: string;
begin
  if RunGit(FRoot, ['rev-parse', '--show-object-format'], Format) and
    (Trim(Format) = 'sha256') then
    Result := '6ef19b41225c5369f1c104d45d8d85efa9b057b53b14b4b9b939dd74decc5321'
  else
    Result := '4b825dc642cb6eb9a060e54bf8d69288fbee4904';
end;

{ ---------------------------------------------------------------------------
  The whole tree through a temporary index
  ---------------------------------------------------------------------------
  `git diff <commit>` compares the commit with the work tree, but only for
  the paths the index knows: an untracked file is never in it, and a path
  the commit has but the index lacks reads as deleted. So a snapshot that
  holds the untracked files is compared through an index of its own: a
  copy of the repository's, with every file of the work tree added in
  intent (-N: the entry without its content, so no object is written) and
  the deleted ones dropped (-A) before each diff. The copy is made once
  per TGittanRepo and refreshed, since git then re-stats only what moved;
  the repository's own index is never written. The snapshot is built the
  same way, with the contents added (write-tree needs them). }

{ The repository's index file: in the git dir of the work tree (a linked
  work tree has one of its own). }
function TGittanRepo.IndexPath: string;
var
  Dir: string;
begin
  Result := '';
  Dir := GitDir;
  if Dir <> '' then
    Result := IncludeTrailingPathDelimiter(Dir) + 'index';
end;

function TGittanRepo.GitDir: string;
begin
  Result := FGitDir;
end;

{ A rebase keeps its state in rebase-merge (the default backend) or
  rebase-apply, which git am also uses (with an "applying" file). A
  cherry-pick or revert of several commits also leaves a sequencer
  directory, but its _HEAD file is there while it stops. }
function TGittanRepo.Operation: string;
var
  Dir: string;
begin
  Result := '';
  Dir := GitDir;
  if Dir = '' then
    Exit;
  Dir := IncludeTrailingPathDelimiter(Dir);
  if DirectoryExists(Dir + 'rebase-merge') or
    (DirectoryExists(Dir + 'rebase-apply') and not FileExists(Dir + 'rebase-apply' +
    PathDelim + 'applying')) then
    Result := 'rebasing'
  else if DirectoryExists(Dir + 'rebase-apply') then
    Result := 'applying patches'
  else if FileExists(Dir + 'MERGE_HEAD') then
    Result := 'merging'
  else if FileExists(Dir + 'CHERRY_PICK_HEAD') then
    Result := 'cherry-picking'
  else if FileExists(Dir + 'REVERT_HEAD') then
    Result := 'reverting'
  else if FileExists(Dir + 'BISECT_LOG') then
    Result := 'bisecting';
end;

function TGittanRepo.RebaseBranch: string;
var
  Dir, Sub: string;
  Lines: TStringList;
begin
  Result := '';
  Dir := GitDir;
  if Dir = '' then
    Exit;
  for Sub in ['rebase-merge', 'rebase-apply'] do
    if FileExists(IncludeTrailingPathDelimiter(Dir) + Sub + PathDelim + 'head-name') then
    begin
      Lines := TStringList.Create;
      try
        Lines.LoadFromFile(IncludeTrailingPathDelimiter(Dir) + Sub + PathDelim + 'head-name');
        if Lines.Count > 0 then
          Result := Trim(Lines[0]);
      finally
        Lines.Free;
      end;
      if Pos('refs/heads/', Result) = 1 then
        Delete(Result, 1, Length('refs/heads/'));
      { A rebase of a detached HEAD writes "detached HEAD". }
      if Pos(' ', Result) > 0 then
        Result := '';
      Exit;
    end;
end;

function TGittanRepo.OperationProgress(out APos, ATotal: integer): boolean;

  function Counter(const AFile: string): integer;
  var
    Lines: TStringList;
  begin
    Result := 0;
    if not FileExists(AFile) then
      Exit;
    Lines := TStringList.Create;
    try
      Lines.LoadFromFile(AFile);
      if Lines.Count > 0 then
        Result := StrToIntDef(Trim(Lines[0]), 0);
    finally
      Lines.Free;
    end;
  end;

var
  Dir: string;
begin
  APos := 0;
  ATotal := 0;
  Result := False;
  Dir := GitDir;
  if Dir = '' then
    Exit;
  Dir := IncludeTrailingPathDelimiter(Dir);
  if DirectoryExists(Dir + 'rebase-merge') then
  begin
    APos := Counter(Dir + 'rebase-merge' + PathDelim + 'msgnum');
    ATotal := Counter(Dir + 'rebase-merge' + PathDelim + 'end');
  end
  else if DirectoryExists(Dir + 'rebase-apply') then
  begin
    APos := Counter(Dir + 'rebase-apply' + PathDelim + 'next');
    ATotal := Counter(Dir + 'rebase-apply' + PathDelim + 'last');
  end;
  Result := ATotal > 0;
  if not Result then
    APos := 0;
end;

{ Copies the repository's index to ATarget; no index (nothing staged
  since init) leaves ATarget absent, which git takes as empty. On
  Windows GetTempFileName has made the file already, and git refuses
  an empty one ("index file smaller than expected"), so it is
  deleted. }
function TGittanRepo.CopyIndex(const ATarget: string): boolean;
var
  Source: string;
  Stream: TMemoryStream;
begin
  Result := True;
  Source := IndexPath;
  if (Source = '') or not FileExists(Source) then
  begin
    if FileExists(ATarget) then
      Result := DeleteFile(ATarget);
    Exit;
  end;
  Stream := TMemoryStream.Create;
  try
    try
      Stream.LoadFromFile(Source);
      Stream.SaveToFile(ATarget);
    except
      Result := False;
    end;
  finally
    Stream.Free;
  end;
end;

{ A commit Gittan makes for itself (a snapshot, a stash with its
  untracked files), reachable from nothing and never shared: it gets an
  identity of its own, since commit-tree refuses to run without a name
  and an e-mail, which a fresh machine (or a CI runner) does not have.
  commit-tree signs only with -S, whatever commit.gpgSign says. AParent
  may be empty. }
function TGittanRepo.CommitTree(const ATree, AParent, AMessage: string;
  out AId: string): boolean;
var
  Args: array of string;
begin
  Args := ['-c', 'user.name=Gittan', '-c', 'user.email=gittan@localhost', 'commit-tree',
    ATree, '-m', AMessage];
  if AParent <> '' then
    Args := Concat(Args, ['-p', AParent]);
  Result := RunGit(FRoot, Args, AId);
  AId := Trim(AId);
end;

function TGittanRepo.WholeTreeActive: boolean;
begin
  Result := FWholeTree and (FBase <> '') and not IsRange;
end;

{ The temporary index for the whole tree comparison, brought up to date
  with the work tree; empty when the comparison does not apply, or the
  index could not be made (the diff then runs with the repository's). }
function TGittanRepo.CompareIndex: string;
var
  Output: string;
begin
  Result := '';
  if not WholeTreeActive then
    Exit;
  if FTempIndex = '' then
  begin
    FTempIndex := GetTempFileName(GetTempDir, 'gittan-index-');
    if not CopyIndex(FTempIndex) then
    begin
      DropTempIndex;
      Exit;
    end;
  end;
  if (FIndexPass = 0) or not FIndexAdded then
  begin
    RunGit(FRoot, ['add', '-A', '-N'], Output, FTempIndex);
    FIndexAdded := FIndexPass > 0;
  end;
  Result := FTempIndex;
end;

procedure TGittanRepo.SetWholeTree(AValue: boolean);
begin
  FWholeTree := AValue;
  if not AValue then
    DropTempIndex;
end;

procedure TGittanRepo.DropTempIndex;
begin
  if FTempIndex <> '' then
  begin
    DeleteFile(FTempIndex);
    DeleteFile(FTempIndex + '.lock');
    FTempIndex := '';
  end;
end;

function TGittanRepo.HasCommit(const ARef: string): boolean;
var
  Id: string;
begin
  Result := (FRoot <> '') and (ARef <> '') and
    RunGit(FRoot, ['rev-parse', '--verify', '-q', ARef + '^{commit}'], Id);
end;

function TGittanRepo.CommitId(const ARef: string): string;
begin
  if (FRoot = '') or (ARef = '') or
    not RunGit(FRoot, ['rev-parse', '--verify', '-q', ARef + '^{commit}'], Result) then
    Exit('');
  Result := Trim(Result);
end;

function TGittanRepo.CountCommits(const AFrom, ATo: string): integer;
var
  Output: string;
begin
  if (FRoot = '') or (AFrom = '') or (ATo = '') or
    not RunGit(FRoot, ['rev-list', '--count', AFrom + '..' + ATo], Output) or
    not TryStrToInt(Trim(Output), Result) then
    Result := -1;
end;

function TGittanRepo.UserName: string;
begin
  if (FRoot = '') or not RunGit(FRoot, ['config', 'user.name'], Result) then
    Exit('');
  Result := Trim(Result);
end;

function TGittanRepo.UserEmail: string;
begin
  if (FRoot = '') or not RunGit(FRoot, ['config', 'user.email'], Result) then
    Exit('');
  Result := Trim(Result);
end;

function TGittanRepo.SetIdentity(const AName, AEmail: string; AGlobal: boolean): boolean;
var
  Output, Scope: string;
begin
  if AGlobal then
    Scope := '--global'
  else
    Scope := '--local';
  Result := (FRoot <> '') and RunGit(FRoot, ['config', Scope, 'user.name', AName], Output) and
    RunGit(FRoot, ['config', Scope, 'user.email', AEmail], Output);
  { git exits with 5 when there is nothing to unset. }
  if Result and AGlobal then
  begin
    RunGit(FRoot, ['config', '--local', '--unset', 'user.name'], Output);
    RunGit(FRoot, ['config', '--local', '--unset', 'user.email'], Output);
  end;
end;

function TGittanRepo.HasLocalIdentity: boolean;
var
  Output: string;
begin
  Result := (FRoot <> '') and (RunGit(FRoot, ['config', '--local', 'user.name'], Output) or
    RunGit(FRoot, ['config', '--local', 'user.email'], Output));
end;

function TGittanRepo.RemoteFor(const ARepoPath: string): string;
var
  Output, Line, Name: string;
  Raw: TStringList;
  p: integer;
  HasOrigin: boolean;
begin
  Result := '';
  HasOrigin := False;
  if (FRoot = '') or not RunGit(FRoot, ['config', '--get-regexp', '^remote\..*\.url$'],
    Output) then
    Exit;
  Raw := TStringList.Create;
  try
    Raw.Text := Output;
    for Line in Raw do
    begin
      { remote.<name>.url <url> }
      p := Pos(' ', Line);
      if (p = 0) or (Pos('remote.', Line) <> 1) then
        Continue;
      Name := Copy(Line, 8, p - 8);
      if Copy(Name, Length(Name) - 3, 4) <> '.url' then
        Continue;
      Name := Copy(Name, 1, Length(Name) - 4);
      if Result = '' then
        Result := Name;
      HasOrigin := HasOrigin or (Name = 'origin');
      if (ARepoPath <> '') and (Pos(LowerCase(ARepoPath), LowerCase(Line)) > p) then
        Exit(Name);
    end;
  finally
    Raw.Free;
  end;
  if HasOrigin then
    Result := 'origin';
end;

function TGittanRepo.FetchPullRequest(const ARemote: string; ANumber: integer;
  const ABaseRef: string; out AHeadRef: string): boolean;
var
  Output: string;
begin
  AHeadRef := 'refs/gittan/pr/' + IntToStr(ANumber);
  Result := (FRoot <> '') and (ARemote <> '') and RunGit(FRoot, ['fetch', '--no-tags',
    '-q', ARemote, ABaseRef, '+refs/pull/' + IntToStr(ANumber) + '/head:' + AHeadRef],
    Output);
end;

function TGittanRepo.TakeSnapshot(out AId: string): boolean;
var
  Index, Tree, Head: string;
begin
  AId := '';
  if FRoot = '' then
    Exit(False);
  Index := GetTempFileName(GetTempDir, 'gittan-snapshot-');
  try
    Result := CopyIndex(Index) and
      RunGit(FRoot, ['add', '-A'], Tree, Index) and
      RunGit(FRoot, ['write-tree'], Tree, Index);
    if not Result then
      Exit;
    if not RunGit(FRoot, ['rev-parse', '--verify', '-q', 'HEAD'], Head) then
      Head := '';
    Result := CommitTree(Trim(Tree), Trim(Head), 'Gittan snapshot', AId);
  finally
    DeleteFile(Index);
    DeleteFile(Index + '.lock');
  end;
end;

{ Runs `git diff AArgs <base>`, with the base before the "--" of a path
  list when AArgs has one. HEAD does not exist before the first commit;
  the empty tree stands in then, so everything staged shows as added.
  Another base that does not resolve is an error. }
function TGittanRepo.RunDiff(const AArgs: array of string; out AOutput: string): boolean;
var
  Args: array of string;
  FirstError: string;
  Sep, i: integer;

  { "diff", -w when whitespace is ignored, then AArgs with ABase put
    before its "--" (or last, without one). }
  procedure Build(const ABase: string);
  var
    i, n: integer;
  begin
    SetLength(Args, Length(AArgs) + 3);
    n := 0;
    Args[n] := 'diff';
    Inc(n);
    if FIgnoreWhitespace then
    begin
      Args[n] := '-w';
      Inc(n);
    end;
    for i := 0 to High(AArgs) do
    begin
      if i = Sep then
      begin
        Args[n] := ABase;
        Inc(n);
      end;
      Args[n] := AArgs[i];
      Inc(n);
    end;
    if Sep = Length(AArgs) then
    begin
      Args[n] := ABase;
      Inc(n);
    end;
    SetLength(Args, n);
  end;

begin
  Sep := Length(AArgs);
  for i := 0 to High(AArgs) do
    if AArgs[i] = '--' then
    begin
      Sep := i;
      Break;
    end;
  Build(DiffBase);
  Result := RunGit(FRoot, Args, AOutput, CompareIndex);
  if not Result and (FBase = '') then
  begin
    { Without HEAD: the same call against the empty tree. When that fails
      too, HEAD was not the problem and the first message is the one to
      show. }
    FirstError := FError;
    Build(EmptyTree);
    Result := RunGit(FRoot, Args, AOutput);
    if not Result then
      FError := FirstError;
  end;
end;

function TGittanRepo.Diff: string;
begin
  Result := '';
  if FRoot = '' then
    Exit;
  RunDiff(['--no-color', '--no-ext-diff'], Result);
end;

{ Appends the refs under AGroup (refs/heads, refs/remotes or refs/tags),
  newest first, to AList: by creatordate, the commit's date for a branch
  or a lightweight tag and the tagger's for an annotated one, which has
  no committerdate and sorted last. A symbolic ref such as
  origin/HEAD (short name "origin") is skipped: it only points at
  another one in the list. }
function TGittanRepo.RefGroup(const AGroup: string; AList: TStrings): boolean;
var
  Output, Line, Name: string;
  Raw: TStringList;
  Tab: integer;
begin
  Result := RunGit(FRoot, ['for-each-ref', '--format=%(refname:short)%09%(symref)',
    '--sort=-creatordate', AGroup], Output);
  if not Result then
    Exit;
  Raw := TStringList.Create;
  try
    Raw.Text := Output;
    for Line in Raw do
    begin
      Tab := Pos(#9, Line);
      if (Tab = 0) or (Tab < Length(Line)) then
        Continue;
      Name := Copy(Line, 1, Tab - 1);
      if (Name <> '') and (AList.IndexOf(Name) < 0) then
        AList.Add(Name);
    end;
  finally
    Raw.Free;
  end;
end;

{ for-each-ref sorts within each group, so the groups are asked for one
  by one: local branches, remote branches, tags. }
function TGittanRepo.Refs(AList: TStrings): boolean;
begin
  AList.Clear;
  if FRoot = '' then
    Exit(False);
  Result := RefGroup('refs/heads', AList) and RefGroup('refs/remotes', AList) and
    RefGroup('refs/tags', AList);
end;

function TGittanRepo.Branches(ALocal, ARemote: TStrings): boolean;
begin
  ALocal.Clear;
  ARemote.Clear;
  if FRoot = '' then
    Exit(False);
  Result := RefGroup('refs/heads', ALocal) and RefGroup('refs/remotes', ARemote);
end;

function TGittanRepo.GoneBranches(AList: TStrings): boolean;
var
  Output, Line: string;
  Raw: TStringList;
  Tab: integer;
begin
  AList.Clear;
  if FRoot = '' then
    Exit(False);
  Result := RunGit(FRoot, ['for-each-ref', '--format=%(refname:short)%09%(upstream:track)',
    'refs/heads'], Output);
  if not Result then
    Exit;
  Raw := TStringList.Create;
  try
    Raw.Text := Output;
    for Line in Raw do
    begin
      Tab := Pos(#9, Line);
      if (Tab > 1) and (Copy(Line, Tab + 1, MaxInt) = '[gone]') then
        AList.Add(Copy(Line, 1, Tab - 1));
    end;
  finally
    Raw.Free;
  end;
end;

function TGittanRepo.Switch(const ABranch: string; AMerge, ADetach: boolean): boolean;
var
  Output: string;
  Args: array of string;
begin
  if (FRoot = '') or (ABranch = '') then
    Exit(False);
  Args := ['switch'];
  if AMerge then
    Args := Concat(Args, ['--merge']);
  if ADetach then
    Args := Concat(Args, ['--detach']);
  Result := RunGit(FRoot, Concat(Args, [ABranch]), Output);
end;

function TGittanRepo.RevertFiles(APaths, ASaved: TStrings): boolean;
var
  Output, Entry, Path, Id, ListFile: string;
  Fields, Chosen, Paths, InHead, Restore, Remove: TStringList;
  i: integer;

begin
  ASaved.Clear;
  if (FRoot = '') or (APaths.Count = 0) then
    Exit(False);
  if not RunGit(FRoot, ['status', '--porcelain', '-z', '--untracked-files=all'], Output) then
    Exit(False);
  Fields := TStringList.Create;
  Chosen := TStringList.Create;
  Paths := TStringList.Create;
  InHead := TStringList.Create;
  Restore := TStringList.Create;
  Remove := TStringList.Create;
  ListFile := GetTempFileName(GetTempDir, 'gittan-revert-');
  try
    Chosen.CaseSensitive := True;
    Chosen.Sorted := True;
    Chosen.Duplicates := dupIgnore;
    Chosen.AddStrings(APaths);
    Paths.CaseSensitive := True;
    Paths.Sorted := True;
    Paths.Duplicates := dupIgnore;
    for Path in APaths do
      if not DirectoryExists(FullPath(Path)) then
        Paths.Add(Path);
    { A rename's old path comes with its new one. }
    SplitNul(Output, Fields);
    i := 0;
    while i < Fields.Count do
    begin
      Entry := Fields[i];
      Inc(i);
      if Length(Entry) < 4 then
        Continue;
      if (Entry[1] in ['R', 'C']) or (Entry[2] in ['R', 'C']) then
      begin
        if (i < Fields.Count) and (Pos('R', Copy(Entry, 1, 2)) > 0) and
          (Chosen.IndexOf(Copy(Entry, 4, MaxInt)) >= 0) then
          Paths.Add(Fields[i]);
        Inc(i);
      end;
    end;
    InHead.CaseSensitive := True;
    InHead.Sorted := True;
    if RunGit(FRoot, ['rev-parse', '--verify', '-q', 'HEAD'], Output) then
    begin
      if not RunGit(FRoot, ['ls-tree', '-r', '-z', '--name-only', 'HEAD'], Output) then
        Exit(False);
      SplitNul(Output, InHead);
    end;
    { Every file on disk is saved before anything changes. }
    for Path in Paths do
    begin
      Id := '';
      if FileExists(FullPath(Path)) then
      begin
        if not RunGit(FRoot, ['hash-object', '-w', '--no-filters', '--', Path], Id) then
          Exit(False);
        Id := Trim(Id);
      end;
      ASaved.Add(Path + #0 + Id);
      if InHead.IndexOf(Path) >= 0 then
        Restore.Add(Path)
      else
        Remove.Add(Path);
    end;
    Result := True;
    if Restore.Count > 0 then
    begin
      WriteBytes(ListFile, NulList(Restore));
      Result := RunGit(FRoot, ['--literal-pathspecs', 'restore', '--source=HEAD', '--staged',
        '--worktree', '--pathspec-from-file=' + ListFile, '--pathspec-file-nul'], Output);
    end;
    if Result and (Remove.Count > 0) then
    begin
      WriteBytes(ListFile, NulList(Remove));
      Result := RunGit(FRoot, ['--literal-pathspecs', 'rm', '--cached', '-q',
        '--ignore-unmatch', '--pathspec-from-file=' + ListFile, '--pathspec-file-nul'], Output);
      for Path in Remove do
        if FileExists(FullPath(Path)) then
          DeleteFile(FullPath(Path));
    end;
  finally
    Fields.Free;
    Chosen.Free;
    Paths.Free;
    InHead.Free;
    Restore.Free;
    Remove.Free;
    DeleteFile(ListFile);
  end;
end;

function TGittanRepo.RestoreReverted(ASaved: TStrings): boolean;
var
  i: integer;
  Path, Id, Data: string;
begin
  Result := FRoot <> '';
  for i := 0 to ASaved.Count - 1 do
  begin
    if Pos(#0, ASaved[i]) < 2 then
      Continue;
    Path := Copy(ASaved[i], 1, Pos(#0, ASaved[i]) - 1);
    Id := Copy(ASaved[i], Pos(#0, ASaved[i]) + 1, MaxInt);
    if Id = '' then
    begin
      if FileExists(FullPath(Path)) then
        DeleteFile(FullPath(Path));
      Continue;
    end;
    if not RunGit(FRoot, ['cat-file', 'blob', Id], Data) then
    begin
      Result := False;
      Continue;
    end;
    try
      ForceDirectories(ExtractFileDir(FullPath(Path)));
      WriteBytes(FullPath(Path), Data);
    except
      on E: Exception do
      begin
        FError := E.Message;
        Result := False;
      end;
    end;
  end;
end;

function TGittanRepo.IsTracked(const APath: string): boolean;
var
  Output: string;
begin
  Result := (FRoot <> '') and (APath <> '') and RunGit(FRoot, ['--literal-pathspecs',
    'ls-files', '-z', '--', APath], Output) and (Output = APath + #0);
end;

function TGittanRepo.MovePath(const AOld, ANew: string): boolean;
var
  Output: string;
begin
  if (FRoot = '') or (AOld = '') or (ANew = '') then
    Exit(False);
  if ExtractFileDir(ANew) <> '' then
    ForceDirectories(FullPath(ExtractFileDir(ANew)));
  Result := RunGit(FRoot, ['mv', '--', AOld, ANew], Output);
end;

function TGittanRepo.RemovePaths(APaths: TStrings; AKeep: boolean): boolean;
var
  Output: string;
  Args: array of string;
begin
  if (FRoot = '') or (APaths.Count = 0) then
    Exit(False);
  Args := ['--literal-pathspecs', 'rm', '-q'];
  if AKeep then
    Args := Concat(Args, ['--cached']);
  Result := RunGit(FRoot, Concat(Args, ['--'], APaths.ToStringArray), Output);
end;

{ The paths go in a file, as a commit's do (see Commit), and are read
  literally only then: --literal-pathspecs without paths keeps the
  untracked files out of the stash, since git gathers them with a
  pathspec of its own that needs its magic. }
function TGittanRepo.Stash(const AMessage: string; APaths: TStrings): boolean;
var
  Output, SpecFile, Nul: string;
  Args: TStringArray;
  i: integer;

begin
  if FRoot = '' then
    Exit(False);
  Args := nil;
  if (APaths <> nil) and (APaths.Count > 0) then
    AddArg(Args, '--literal-pathspecs');
  AddArg(Args, 'stash');
  AddArg(Args, 'push');
  AddArg(Args, '-u');
  if AMessage <> '' then
  begin
    AddArg(Args, '-m');
    AddArg(Args, AMessage);
  end;
  SpecFile := '';
  try
    if (APaths <> nil) and (APaths.Count > 0) then
    begin
      Nul := '';
      for i := 0 to APaths.Count - 1 do
        Nul := Nul + APaths[i] + #0;
      SpecFile := GetTempFileName(GetTempDir, 'gittan-stash-');
      WriteBytes(SpecFile, Nul);
      AddArg(Args, '--pathspec-from-file=' + SpecFile);
      AddArg(Args, '--pathspec-file-nul');
    end;
    Result := RunGit(FRoot, Args, Output);
  finally
    if SpecFile <> '' then
      DeleteFile(SpecFile);
  end;
end;

{ The reflog subject of a stash is "On <branch>: <message>" for one made
  with a message and "WIP on <branch>: <short id> <subject>" for one
  made without; a stash made with HEAD detached says "(no branch)". }
procedure ParseStashSubject(const ASubject: string; out ABranch, AMessage: string);
var
  Rest: string;
  Colon: integer;
begin
  ABranch := '';
  AMessage := ASubject;
  if Pos('WIP on ', ASubject) = 1 then
    Rest := Copy(ASubject, Length('WIP on ') + 1, MaxInt)
  else if Pos('On ', ASubject) = 1 then
    Rest := Copy(ASubject, Length('On ') + 1, MaxInt)
  else
    Exit;
  Colon := Pos(': ', Rest);
  if Colon = 0 then
    Exit;
  ABranch := Copy(Rest, 1, Colon - 1);
  AMessage := Copy(Rest, Colon + 2, MaxInt);
  if ABranch = '(no branch)' then
    ABranch := '';
end;

{ One line per stash: the id, the parents, the time and the reflog
  subject. A stash made with -u has a third parent, the commit of the
  untracked files, also when there were none: its tree is the empty
  tree then, so the trees of those commits are read in one more call
  (git log --no-walk, one line per commit) and compared with it. }
function TGittanRepo.Stashes(out AList: TGittanStashes): boolean;
var
  Output, Line, Empty: string;
  Lines, Trees: TStringList;
  Args: array of string;
  Fields: array[0..3] of string;
  i, n, j, Sep: integer;
begin
  AList := nil;
  if FRoot = '' then
    Exit(False);
  Result := RunGit(FRoot, ['stash', 'list', '--format=%H%x1f%P%x1f%at%x1f%gs'], Output);
  if not Result then
    Exit;
  Lines := TStringList.Create;
  Trees := TStringList.Create;
  try
    Lines.Text := Output;
    n := 0;
    SetLength(AList, Lines.Count);
    Args := nil;
    for i := 0 to Lines.Count - 1 do
    begin
      Line := Lines[i];
      for j := 0 to 2 do
      begin
        Sep := Pos(#31, Line);
        if Sep = 0 then
          Break;
        Fields[j] := Copy(Line, 1, Sep - 1);
        Delete(Line, 1, Sep);
      end;
      if Sep = 0 then
        Continue;
      Fields[3] := Line;
      AList[n].Id := Fields[0];
      AList[n].Index := n;
      AList[n].Time := StrToInt64Def(Fields[2], 0);
      ParseStashSubject(Fields[3], AList[n].Branch, AList[n].Message);
      if WordCount(Fields[1], [' ']) >= 3 then
      begin
        { The third parent, looked up below. }
        Trees.AddObject(ExtractWord(3, Fields[1], [' ']), TObject(PtrUInt(n)));
        SetLength(Args, Length(Args) + 1);
        Args[High(Args)] := Trees[Trees.Count - 1];
      end;
      Inc(n);
    end;
    SetLength(AList, n);
    if Trees.Count > 0 then
    begin
      Empty := EmptyTree;
      if RunGit(FRoot, Concat(['log', '--no-walk=unsorted', '--format=%H %T'], Args),
        Output) then
      begin
        Lines.Text := Output;
        for i := 0 to Lines.Count - 1 do
        begin
          Line := Lines[i];
          Sep := Pos(' ', Line);
          j := Trees.IndexOf(Copy(Line, 1, Sep - 1));
          if (Sep > 0) and (j >= 0) then
            AList[PtrUInt(Trees.Objects[j])].Untracked :=
              Trim(Copy(Line, Sep + 1, MaxInt)) <> Empty;
        end;
      end;
    end;
  finally
    Lines.Free;
    Trees.Free;
  end;
end;

function TGittanRepo.StashIndex(const AId: string): integer;
var
  Output: string;
  Lines: TStringList;
begin
  Result := -1;
  if (FRoot = '') or (AId = '') or
    not RunGit(FRoot, ['stash', 'list', '--format=%H'], Output) then
    Exit;
  Lines := TStringList.Create;
  try
    Lines.Text := Output;
    Result := Lines.IndexOf(AId);
  finally
    Lines.Free;
  end;
end;

{ git names a stash to drop or pop by its place in the list only, so
  the id is looked up first; apply takes a commit, but goes the same way
  so a stash that is gone is refused alike. git keeps a stash whose
  changes clashed, and leaves the clashing files in conflict (ls-files
  -u lists them), with no operation in progress. }
function TGittanRepo.StashApply(const AId: string; APop: boolean;
  out AConflicts: boolean): boolean;
var
  Output, Ignored, Ref: string;
  Index: integer;
begin
  AConflicts := False;
  Index := StashIndex(AId);
  if Index < 0 then
  begin
    FError := 'The stash is gone.';
    Exit(False);
  end;
  Ref := 'stash@{' + IntToStr(Index) + '}';
  if APop then
    Result := RunGit(FRoot, ['stash', 'pop', Ref], Output)
  else
    Result := RunGit(FRoot, ['stash', 'apply', Ref], Output);
  if not Result then
    AConflicts := RunGitIn(FRoot, ['ls-files', '-u'], Output, Ignored) and
      (Trim(Output) <> '');
end;

function TGittanRepo.StashDrop(const AId: string): boolean;
var
  Output: string;
  Index: integer;
begin
  Index := StashIndex(AId);
  if Index < 0 then
  begin
    FError := 'The stash is gone.';
    Exit(False);
  end;
  Result := RunGit(FRoot, ['stash', 'drop', 'stash@{' + IntToStr(Index) + '}'], Output);
end;

function TGittanRepo.StashBranch(const AName, AId: string): boolean;
var
  Output: string;
  Index: integer;
begin
  if not IsBranchName(AName) then
  begin
    FError := Format('"%s" is not a valid branch name.', [AName]);
    Exit(False);
  end;
  Index := StashIndex(AId);
  if Index < 0 then
  begin
    FError := 'The stash is gone.';
    Exit(False);
  end;
  Result := RunGit(FRoot, ['stash', 'branch', AName, 'stash@{' + IntToStr(Index) + '}'],
    Output);
end;

{ The two trees never overlap (an untracked file is one the stash's
  tree lacks), so a three-way read-tree from the empty tree takes both
  without a conflict; -i leaves the work tree out of it. The commit is
  reachable from nothing, so git prunes it as it does a snapshot. }
function TGittanRepo.StashRange(const AId: string; out ARange: string): boolean;
var
  Output, Tree, Third, Empty, Index: string;
begin
  ARange := AId + '^..' + AId;
  Result := (FRoot <> '') and (AId <> '') and HasCommit(AId);
  if not Result then
    Exit;
  if not RunGit(FRoot, ['rev-parse', '--verify', '-q', AId + '^3^{tree}'], Third) then
    Exit;
  Empty := EmptyTree;
  if Trim(Third) = Empty then
    Exit;
  Index := GetTempFileName(GetTempDir, 'gittan-stash-index-');
  try
    DeleteFile(Index);
    if RunGit(FRoot, ['read-tree', '-i', '-m', Empty, AId, AId + '^3'], Output, Index) and
      RunGit(FRoot, ['write-tree'], Tree, Index) and
      CommitTree(Trim(Tree), AId + '^', 'Gittan: the stash ' + AId +
      ' with its untracked files', Output) then
      ARange := AId + '^..' + Output;
  finally
    DeleteFile(Index);
  end;
end;

function SwitchBlockedFiles(const AError: string; AFiles: TStrings): boolean;
var
  Line: string;
  Listing: boolean;
begin
  AFiles.Clear;
  Listing := False;
  for Line in AError.Split([#10]) do
    if Pos('would be overwritten by', Line) > 0 then
      Listing := True
    else if Listing and (Line <> '') and (Line[1] = #9) then
      AFiles.Add(Trim(Line))
    else if Listing then
      Listing := False;
  Result := AFiles.Count > 0;
end;

{ The paths go to git in files (--pathspec-from-file, NUL separated), so
  no command line grows with them, and are read literally: a name with
  a "*" or a ":" is that name, not a pattern. git commit --only commits
  the work tree's version of the paths through an index of its own and
  leaves the real index as it was for the others; it knows only tracked
  paths, so the untracked ones are added before. A path whose deletion
  is staged is in neither the index nor the work tree, and git add
  would not match it: during an operation, where the chosen paths are
  added, such a path is left to the index, which already says it is
  gone. }
function TGittanRepo.Commit(const AMessage: string; APaths: TStrings;
  AAmend: boolean; out AId: string; const AParts: TGittanCommitParts): boolean;
var
  Output, Entry, Path, XY, Op, Err, SpecFile, AddFile, MsgFile, PartFile, Index: string;
  Fields, Chosen, Spec, Added, Untrack: TStringList;
  Args: TStringArray;
  Whole: boolean;
  i: integer;

  { Writes AParts over their paths in the index AIndex ('' for the
    repository's): each text goes in as a blob, through the filters of
    its path, with the mode the index has for the path, which git add
    gave it from the work tree. }
  function WriteParts(const AIndex: string): boolean;
  var
    j: integer;
    Blob, Mode: string;
  begin
    Result := True;
    for j := 0 to High(AParts) do
    begin
      WriteBytes(PartFile, AParts[j].Text);
      if not RunGit(FRoot, ['hash-object', '-w', '--path=' + AParts[j].Path, PartFile],
        Blob, AIndex) or not RunGit(FRoot, ['--literal-pathspecs', 'ls-files', '-s',
        '--', AParts[j].Path], Mode, AIndex) then
        Exit(False);
      Blob := Trim(Blob);
      Mode := Copy(Mode, 1, Pos(' ', Mode) - 1);
      if Mode = '' then
        Mode := '100644';
      if not RunGit(FRoot, ['update-index', '--add', '--cacheinfo',
        Mode + ',' + Blob + ',' + AParts[j].Path], Output, AIndex) then
        Exit(False);
    end;
  end;

  { The commit of AParts with the rest of APaths: from a temporary index
    of HEAD's tree with the paths added and the parts written over them,
    so the hooks and signing run as for any commit and nothing else the
    real index holds goes in; a file git rm --cached took out of the
    index (Untrack) is taken out of this one too, since git commit
    --only would commit it as the work tree has it. The real index then
    takes the committed paths as the new HEAD has them, as git commit
    --only leaves them. }
  function CommitThroughIndex: boolean;
  begin
    Result := False;
    Index := GetTempFileName(GetTempDir, 'gittan-commit-index-');
    DeleteFile(Index);
    if HasCommit('HEAD') then
      Result := RunGit(FRoot, ['read-tree', 'HEAD'], Output, Index)
    else
      Result := RunGit(FRoot, ['read-tree', '--empty'], Output, Index);
    if not Result then
      Exit;
    WriteBytes(SpecFile, NulList(Spec));
    Result := RunGit(FRoot, ['--literal-pathspecs', 'add', '-A',
      '--pathspec-from-file=' + SpecFile, '--pathspec-file-nul'], Output, Index) and
      WriteParts(Index);
    if Result and (Untrack.Count > 0) then
    begin
      WriteBytes(AddFile, NulList(Untrack));
      Result := RunGit(FRoot, ['--literal-pathspecs', 'rm', '--cached', '-q',
        '--pathspec-from-file=' + AddFile, '--pathspec-file-nul'], Output, Index);
    end;
    if not Result then
      Exit;
    WriteBytes(MsgFile, AMessage);
    Args := nil;
    AddArg(Args, 'commit');
    AddArg(Args, '-q');
    AddArg(Args, '-F');
    AddArg(Args, MsgFile);
    if AAmend then
      AddArg(Args, '--amend');
    Result := RunGit(FRoot, Args, Output, Index);
    if not Result then
      Exit;
    Err := FError;
    RunGit(FRoot, ['--literal-pathspecs', 'reset', '-q', '--pathspec-from-file=' +
      SpecFile, '--pathspec-file-nul'], Output);
    FError := Err;
    if RunGit(FRoot, ['rev-parse', 'HEAD'], Output) then
      AId := Trim(Output);
  end;

begin
  AId := '';
  if FRoot = '' then
    Exit(False);
  Op := Operation;
  Whole := (Op = 'merging') or (Op = 'cherry-picking') or (Op = 'reverting');
  if (APaths.Count = 0) and not AAmend and not Whole then
  begin
    FError := 'No files chosen to commit.';
    Exit(False);
  end;
  if not RunGit(FRoot, ['status', '--porcelain', '-z', '--untracked-files=all'], Output) then
    Exit(False);
  Fields := TStringList.Create;
  Chosen := TStringList.Create;
  Spec := TStringList.Create;
  Added := TStringList.Create;
  Untrack := TStringList.Create;
  SpecFile := GetTempFileName(GetTempDir, 'gittan-paths-');
  AddFile := GetTempFileName(GetTempDir, 'gittan-add-');
  MsgFile := GetTempFileName(GetTempDir, 'gittan-message-');
  PartFile := GetTempFileName(GetTempDir, 'gittan-part-');
  Index := '';
  try
    Chosen.CaseSensitive := True;
    Chosen.Sorted := True;
    Chosen.Duplicates := dupIgnore;
    Chosen.AddStrings(APaths);
    Spec.AddStrings(APaths);
    SplitNul(Output, Fields);
    i := 0;
    while i < Fields.Count do
    begin
      Entry := Fields[i];
      Inc(i);
      if Length(Entry) < 4 then
        Continue;
      XY := Copy(Entry, 1, 2);
      Path := Copy(Entry, 4, MaxInt);
      if (XY = 'DD') or (XY = 'AA') or (Pos('U', XY) > 0) then
      begin
        FError := 'Resolve the conflict in ' + Path + ' first.';
        Exit(False);
      end;
      if (Entry[1] in ['R', 'C']) or (Entry[2] in ['R', 'C']) then
      begin
        if (i < Fields.Count) and (Pos('R', XY) > 0) and (Chosen.IndexOf(Path) >= 0) then
          Spec.Add(Fields[i]);
        Inc(i);
      end;
      if Chosen.IndexOf(Path) < 0 then
        Continue;
      if XY = '??' then
        Added.Add(Path)
      else if Whole and (XY[1] <> 'D') then
        Added.Add(Path)
      else if (XY[1] = 'D') and FileExists(FullPath(Path)) then
        Untrack.Add(Path);
    end;
    { A file taken out of the index but kept (git rm --cached) is
      untracked too, and is not to go back in. }
    Added.CaseSensitive := True;
    for Path in Untrack do
      if Added.IndexOf(Path) >= 0 then
        Added.Delete(Added.IndexOf(Path));

    if ((Length(AParts) > 0) or (Untrack.Count > 0)) and not Whole then
      Exit(CommitThroughIndex);
    if Added.Count > 0 then
    begin
      WriteBytes(AddFile, NulList(Added));
      if not RunGit(FRoot, ['--literal-pathspecs', 'add', '-A',
        '--pathspec-from-file=' + AddFile, '--pathspec-file-nul'], Output) then
        Exit(False);
    end;
    if Whole and not WriteParts('') then
      Exit(False);
    WriteBytes(MsgFile, AMessage);
    Args := nil;
    AddArg(Args, '--literal-pathspecs');
    AddArg(Args, 'commit');
    AddArg(Args, '-q');
    AddArg(Args, '-F');
    AddArg(Args, MsgFile);
    if AAmend then
      AddArg(Args, '--amend');
    if not Whole then
    begin
      AddArg(Args, '--only');
      if Spec.Count > 0 then
      begin
        WriteBytes(SpecFile, NulList(Spec));
        AddArg(Args, '--pathspec-from-file=' + SpecFile);
        AddArg(Args, '--pathspec-file-nul');
      end;
    end;
    Result := RunGit(FRoot, Args, Output);
    if not Result then
    begin
      { Put the untracked files back as they were; what git said about
        the commit is the error to show. }
      if not Whole and (Added.Count > 0) then
      begin
        Err := FError;
        RunGit(FRoot, ['--literal-pathspecs', 'rm', '--cached', '-q',
          '--pathspec-from-file=' + AddFile, '--pathspec-file-nul'], Output);
        FError := Err;
      end;
      Exit;
    end;
    if RunGit(FRoot, ['rev-parse', 'HEAD'], Output) then
      AId := Trim(Output);
  finally
    Fields.Free;
    Chosen.Free;
    Spec.Free;
    Added.Free;
    Untrack.Free;
    DeleteFile(SpecFile);
    DeleteFile(AddFile);
    DeleteFile(MsgFile);
    DeleteFile(PartFile);
    if Index <> '' then
    begin
      DeleteFile(Index);
      DeleteFile(Index + '.lock');
    end;
  end;
end;

{ ---------------------------------------------------------------------------
  Remotes
  ---------------------------------------------------------------------------
  Fetch, pull and push go to the network: they run with
  RemoteEnvironment, and their output on stderr (progress, "To ...") is
  no failure. }
function RemoteEnvironmentIn(const ADir: string): TStringArray;
var
  Output, Err: string;
begin
  Result := nil;
  if (EnvironmentVariable('GIT_SSH_COMMAND') <> '') or
    (EnvironmentVariable('GIT_SSH') <> '') then
    Exit;
  if (ADir <> '') and RunGitIn(ADir, ['config', 'core.sshCommand'], Output, Err) and
    (Trim(Output) <> '') then
    Exit;
  SetLength(Result, 1);
  Result[0] := 'GIT_SSH_COMMAND=ssh -o BatchMode=yes';
end;

function TGittanRepo.RemoteEnvironment: TStringArray;
begin
  Result := RemoteEnvironmentIn(FRoot);
end;

{ git clone runs in the parent, so a relative URL means what it says
  there, and the config read for ssh is the user's. }
function CloneRepository(const AUrl, ATarget: string; ASubmodules: boolean;
  out AError: string; AOnOutput: TGittanOutputEvent): boolean;
var
  Parent, Output: string;
begin
  Parent := ExtractFileDir(ExcludeTrailingPathDelimiter(ATarget));
  if (AUrl = '') or (Parent = '') or not DirectoryExists(Parent) then
  begin
    AError := Format('The folder %s does not exist.', [Parent]);
    Exit(False);
  end;
  if ASubmodules then
    Result := RunGitEnv(Parent, ['clone', '--progress', '--recurse-submodules', '--', AUrl,
      ATarget], RemoteEnvironmentIn(Parent), Output, AError, '', AOnOutput)
  else
    Result := RunGitEnv(Parent, ['clone', '--progress', '--', AUrl, ATarget],
      RemoteEnvironmentIn(Parent), Output, AError, '', AOnOutput);
end;

function InitRepository(const ADir: string; out AError: string): boolean;
var
  Output: string;
begin
  if not DirectoryExists(ADir) then
  begin
    AError := Format('The folder %s does not exist.', [ADir]);
    Exit(False);
  end;
  Result := RunGitIn(ADir, ['init'], Output, AError);
end;

{ As git's guess_dir_name: the end of the URL, a ".git" bundle or bare
  suffix dropped, and of a URL with nothing after the host, the host. }
function CloneFolderName(const AUrl: string): string;
var
  S: string;
  i, Cut: integer;
begin
  S := Trim(AUrl);
  while (S <> '') and (S[Length(S)] in ['/', '\']) do
    SetLength(S, Length(S) - 1);
  if LowerCase(Copy(S, Length(S) - 4, 5)) = '/.git' then
    SetLength(S, Length(S) - 5)
  else if LowerCase(Copy(S, Length(S) - 3, 4)) = '.git' then
    SetLength(S, Length(S) - 4);
  if LowerCase(Copy(S, Length(S) - 6, 7)) = '.bundle' then
    SetLength(S, Length(S) - 7);
  while (S <> '') and (S[Length(S)] in ['/', '\']) do
    SetLength(S, Length(S) - 1);
  Cut := 0;
  for i := Length(S) downto 1 do
    if S[i] in ['/', '\', ':'] then
    begin
      Cut := i;
      Break;
    end;
  { https://host:8080 or user@host:22: the part after the colon is a
    port, and the host is the name. }
  if (Cut > 0) and (S[Cut] = ':') and (StrToIntDef(Copy(S, Cut + 1, MaxInt), -1) >= 0) then
  begin
    SetLength(S, Cut - 1);
    Cut := 0;
    for i := Length(S) downto 1 do
      if S[i] in ['/', '\', ':'] then
      begin
        Cut := i;
        Break;
      end;
  end;
  Result := Copy(S, Cut + 1, MaxInt);
  i := Pos('@', Result);
  if i > 0 then
    Result := Copy(Result, i + 1, MaxInt);
end;

function LooksLikeCloneUrl(const AText: string): boolean;
const
  Schemes: array[0..5] of string = ('https://', 'http://', 'ssh://', 'git://', 'file://',
    'git+ssh://');
var
  S, Scheme: string;
  At, Colon: integer;
begin
  S := Trim(AText);
  if (S = '') or (Pos(' ', S) > 0) or (Pos(#10, S) > 0) or (Pos(#9, S) > 0) then
    Exit(False);
  for Scheme in Schemes do
    if (Pos(Scheme, LowerCase(S)) = 1) and (Length(S) > Length(Scheme)) then
      Exit(True);
  { user@host:path, the user and the host without a slash. }
  At := Pos('@', S);
  Colon := Pos(':', S);
  Result := (At > 1) and (Colon > At + 1) and (Colon < Length(S)) and
    (Pos('/', Copy(S, 1, Colon)) = 0);
end;

function TGittanRepo.RunRemote(const AArgs: array of string): boolean;
var
  Output, Err: string;
begin
  Result := (FRoot <> '') and RunGitEnv(FRoot, AArgs, RemoteEnvironment, Output, Err, '',
    FOnOutput);
  if not Result then
    FError := Err;
end;

{ --progress: git reports its progress ("Writing objects: 33%") only at
  a terminal unless asked, and OnOutput shows it. }
function TGittanRepo.Fetch: boolean;
begin
  Result := RunRemote(['fetch', '--all', '--prune', '--progress']);
end;

{ Whether the config says how to pull: then pmAuto leaves it to git. }
function PullConfigured(const ARoot, ABranch: string): boolean;
var
  Output, Err: string;
begin
  Result := RunGitIn(ARoot, ['config', 'pull.rebase'], Output, Err) or
    RunGitIn(ARoot, ['config', 'pull.ff'], Output, Err) or
    ((ABranch <> '') and RunGitIn(ARoot, ['config', 'branch.' + ABranch + '.rebase'],
    Output, Err));
end;

{ git says "Not possible to fast-forward" for --ff-only and pull.ff=only,
  and "divergent branches" when it is told nothing. }
function TGittanRepo.Pull(AMode: TGittanPullMode; out ADiverged: boolean): boolean;
begin
  ADiverged := False;
  case AMode of
    pmMerge:
      Result := RunRemote(['pull', '--progress', '--no-rebase', '--ff', '--no-edit']);
    pmRebase:
      Result := RunRemote(['pull', '--progress', '--rebase', '--autostash']);
    else
      if PullConfigured(FRoot, Branch) then
        Result := RunRemote(['pull', '--progress', '--no-edit'])
      else
        Result := RunRemote(['pull', '--progress', '--ff-only']);
  end;
  if not Result then
    ADiverged := (Pos('Not possible to fast-forward', FError) > 0) or
      (Pos('divergent branches', FError) > 0);
end;

function TGittanRepo.Push(out ARejected: boolean): boolean;
var
  Name, Remote, Merge: string;
begin
  ARejected := False;
  Result := False;
  if FRoot = '' then
    Exit;
  if not RunGit(FRoot, ['symbolic-ref', '--short', '-q', 'HEAD'], Name) or (Trim(Name) = '') then
  begin
    FError := 'HEAD is not on a branch.';
    Exit;
  end;
  Name := Trim(Name);
  if RunGit(FRoot, ['config', 'branch.' + Name + '.remote'], Remote) and
    RunGit(FRoot, ['config', 'branch.' + Name + '.merge'], Merge) and
    (Trim(Remote) <> '') and (Trim(Merge) <> '') then
    Result := RunRemote(['push', '--progress', Trim(Remote), 'HEAD:' + Trim(Merge)])
  else
  begin
    Remote := RemoteFor('');
    if Remote = '' then
    begin
      FError := 'The repository has no remote to push to.';
      Exit;
    end;
    Result := RunRemote(['push', '--progress', '-u', Remote, 'HEAD']);
  end;
  if not Result then
    ARejected := (Pos('[rejected]', FError) > 0) or (Pos('fetch first', FError) > 0) or
      (Pos('non-fast-forward', FError) > 0);
end;

{ The lease is the remote-tracking branch of the upstream: git refuses
  with "stale info" when the remote's branch is not there. }
function TGittanRepo.ForcePush(out AStale, AUnseen: boolean): boolean;
var
  Name, Remote, Merge: string;
begin
  AStale := False;
  AUnseen := False;
  Result := False;
  if FRoot = '' then
    Exit;
  if not RunGit(FRoot, ['symbolic-ref', '--short', '-q', 'HEAD'], Name) or (Trim(Name) = '') then
  begin
    FError := 'HEAD is not on a branch.';
    Exit;
  end;
  Name := Trim(Name);
  if not (RunGit(FRoot, ['config', 'branch.' + Name + '.remote'], Remote) and
    RunGit(FRoot, ['config', 'branch.' + Name + '.merge'], Merge) and
    (Trim(Remote) <> '') and (Trim(Merge) <> '')) then
  begin
    FError := Format('%s has no upstream to push over.', [Name]);
    Exit;
  end;
  Result := RunRemote(['push', '--progress', '--force-with-lease', '--force-if-includes',
    Trim(Remote), 'HEAD:' + Trim(Merge)]);
  if not Result then
  begin
    AStale := Pos('stale info', FError) > 0;
    AUnseen := Pos('remote ref updated since checkout', FError) > 0;
  end;
end;

function TGittanRepo.PushBranch(const ABranch, ARemote: string): boolean;
begin
  if (FRoot = '') or (ABranch = '') or (ARemote = '') then
    Exit(False);
  Result := RunRemote(['push', '--progress', '-u', ARemote, 'refs/heads/' + ABranch +
    ':refs/heads/' + ABranch]);
end;

function TGittanRepo.SetUpstream(const ABranch, AUpstream: string): boolean;
var
  Output: string;
begin
  if (FRoot = '') or (ABranch = '') then
    Exit(False);
  if AUpstream = '' then
    Result := RunGit(FRoot, ['branch', '--unset-upstream', ABranch], Output)
  else
    Result := RunGit(FRoot, ['branch', '--set-upstream-to=' + AUpstream, ABranch], Output);
end;

function TGittanRepo.Remotes(AList: TStrings): boolean;
var
  Output, Line: string;
begin
  AList.Clear;
  Result := (FRoot <> '') and RunGit(FRoot, ['remote'], Output);
  if Result then
    for Line in Output.Split([#10]) do
      if Trim(Line) <> '' then
        AList.Add(Trim(Line));
end;

{ `--` keeps a name or a URL that starts with a dash from being read as
  an option. }
function TGittanRepo.AddRemote(const AName, AUrl: string): boolean;
var
  Output: string;
begin
  Result := (FRoot <> '') and RunGit(FRoot, ['remote', 'add', '--', AName, AUrl], Output);
end;

{ No "--": before git parsed options for remote rename and remove, it
  counted the arguments and took "--" for a name, and the supported git
  goes back to 2.30. }
function TGittanRepo.RenameRemote(const AOld, ANew: string): boolean;
var
  Output: string;
begin
  Result := (FRoot <> '') and RunGit(FRoot, ['remote', 'rename', AOld, ANew], Output);
end;

function TGittanRepo.RemoveRemote(const AName: string): boolean;
var
  Output: string;
begin
  Result := (FRoot <> '') and RunGit(FRoot, ['remote', 'remove', AName], Output);
end;

{ git config exits with 5 when there is no push URL to unset. }
function TGittanRepo.SetRemoteUrls(const AName, AUrl, APushUrl: string): boolean;
var
  Output, Err: string;
begin
  Result := (FRoot <> '') and RunGit(FRoot, ['remote', 'set-url', '--', AName, AUrl], Output);
  if not Result then
    Exit;
  if RunGitIn(FRoot, ['config', '--get-all', 'remote.' + AName + '.pushurl'], Output, Err) then
    Result := RunGit(FRoot, ['config', '--unset-all', 'remote.' + AName + '.pushurl'], Output);
  if Result and (APushUrl <> '') and (APushUrl <> AUrl) then
    Result := RunGit(FRoot, ['remote', 'set-url', '--push', '--', AName, APushUrl], Output);
end;

function TGittanRepo.PushRemote: string;
var
  Name: string;
begin
  Result := '';
  if FRoot = '' then
    Exit;
  if RunGit(FRoot, ['symbolic-ref', '--short', '-q', 'HEAD'], Name) and (Trim(Name) <> '') and
    RunGit(FRoot, ['config', 'branch.' + Trim(Name) + '.remote'], Result) then
    Result := Trim(Result);
  { "." is the repository itself, for a branch tracking a local one. }
  if (Result = '') or (Result = '.') then
    Result := RemoteFor('');
end;

{ rev-parse --git-path gives the hooks folder with core.hooksPath
  honoured, relative to the root when it is inside the work tree. }
function TGittanRepo.HasHook(const AName: string): boolean;
var
  Dir: string;
begin
  Result := False;
  if (FRoot = '') or (AName = '') or not RunGit(FRoot, ['rev-parse', '--git-path', 'hooks'], Dir) then
    Exit;
  Dir := Trim(Dir);
  if Dir = '' then
    Exit;
  if not ((Dir[1] in ['/', '\']) or ((Length(Dir) > 1) and (Dir[2] = ':'))) then
    Dir := IncludeTrailingPathDelimiter(FRoot) + Dir;
  Result := FileExists(IncludeTrailingPathDelimiter(SetDirSeparators(Dir)) + AName);
end;

{ ---------------------------------------------------------------------------
  Commit actions
  ---------------------------------------------------------------------------
  What the commit graph's menu does to a commit. Merge, cherry-pick and
  revert make commits: they run with GIT_EDITOR=: so no editor waits,
  and when they stop with conflicts git is left in the middle of them,
  which is no state to report as a plain failure. }
function TGittanRepo.IsBranchName(const AName: string): boolean;
var
  Output: string;
begin
  Result := (FRoot <> '') and (AName <> '') and
    RunGit(FRoot, ['check-ref-format', '--branch', AName], Output);
end;

function TGittanRepo.CreateBranch(const AName, AAt: string; ASwitch: boolean): boolean;
var
  Output: string;
begin
  if not IsBranchName(AName) then
  begin
    FError := Format('"%s" is not a valid branch name.', [AName]);
    Exit(False);
  end;
  if ASwitch then
    Result := RunGit(FRoot, ['switch', '-c', AName, AAt], Output)
  else
    Result := RunGit(FRoot, ['branch', AName, AAt], Output);
end;

function TGittanRepo.RenameBranch(const AOld, ANew: string): boolean;
var
  Output: string;
begin
  if not IsBranchName(ANew) then
  begin
    FError := Format('"%s" is not a valid branch name.', [ANew]);
    Exit(False);
  end;
  Result := RunGit(FRoot, ['branch', '-m', AOld, ANew], Output);
end;

{ git -d says the branch "is not fully merged" when that is all that
  keeps it. }
function TGittanRepo.DeleteBranch(const AName: string; AForce: boolean;
  out ANotMerged: boolean): boolean;
var
  Output: string;
begin
  ANotMerged := False;
  if (FRoot = '') or (AName = '') then
    Exit(False);
  if AForce then
    Result := RunGit(FRoot, ['branch', '-D', AName], Output)
  else
    Result := RunGit(FRoot, ['branch', '-d', AName], Output);
  if not Result then
    ANotMerged := Pos('not fully merged', FError) > 0;
end;

function TGittanRepo.Upstream(const AName: string): string;
begin
  if (FRoot = '') or (AName = '') or not RunGit(FRoot, ['for-each-ref',
    '--format=%(upstream:short)', 'refs/heads/' + AName], Result) then
    Exit('');
  Result := Trim(Result);
end;

function TGittanRepo.SplitRemoteRef(const ARef: string; out ARemote, ABranch: string): boolean;
var
  Output, Remote: string;
begin
  ARemote := '';
  ABranch := '';
  if (FRoot = '') or not RunGit(FRoot, ['remote'], Output) then
    Exit(False);
  { The longest remote that is a prefix, for remotes "a" and "a/b". }
  for Remote in Output.Split([#10]) do
    if (Trim(Remote) <> '') and (Pos(Trim(Remote) + '/', ARef) = 1) and
      (Length(Trim(Remote)) > Length(ARemote)) then
      ARemote := Trim(Remote);
  Result := ARemote <> '';
  if Result then
    ABranch := Copy(ARef, Length(ARemote) + 2, MaxInt);
end;

function TGittanRepo.DeleteRemoteBranch(const ARef: string): boolean;
var
  Remote, OnRemote: string;
begin
  if not SplitRemoteRef(ARef, Remote, OnRemote) or (OnRemote = '') then
  begin
    FError := Format('%s is not a branch of a remote.', [ARef]);
    Exit(False);
  end;
  { Qualified, as DeleteRemoteTag's is: a tag of the same name on the
    remote makes the bare name ambiguous, and git refuses it. }
  Result := RunRemote(['push', Remote, '--delete', 'refs/heads/' + OnRemote]);
end;

function TGittanRepo.CreateTag(const AName, AAt, AMessage: string): boolean;
var
  Output: string;
begin
  if (FRoot = '') or (AName = '') then
    Exit(False);
  if AMessage <> '' then
    Result := RunGit(FRoot, ['tag', '-a', '-m', AMessage, AName, AAt], Output)
  else
    Result := RunGit(FRoot, ['tag', AName, AAt], Output);
end;

function ParseTags(const AOutput: string): TGittanTags;
var
  Lines: TStringList;
  Fields: TStringArray;
  i, n: integer;
begin
  Result := nil;
  Lines := TStringList.Create;
  try
    Lines.Text := AOutput;
    SetLength(Result, Lines.Count);
    n := 0;
    for i := 0 to Lines.Count - 1 do
    begin
      Fields := Lines[i].Split([#31], 5);
      if (Length(Fields) < 5) or (Fields[0] = '') then
        Continue;
      Result[n].Name := Fields[0];
      Result[n].Annotated := Fields[2] <> '';
      if Result[n].Annotated then
        Result[n].Commit := Fields[2]
      else
        Result[n].Commit := Fields[1];
      Result[n].Time := StrToInt64Def(Fields[3], 0);
      Result[n].Subject := Fields[4];
      Inc(n);
    end;
    SetLength(Result, n);
  finally
    Lines.Free;
  end;
end;

function TGittanRepo.Tags(out AList: TGittanTags): boolean;
var
  Output: string;
begin
  AList := nil;
  { The last --sort is the first key. }
  Result := (FRoot <> '') and RunGit(FRoot, ['for-each-ref', '--sort=-v:refname',
    '--sort=-creatordate', '--format=' + TagFormat, 'refs/tags'], Output);
  if Result then
    AList := ParseTags(Output);
end;

function ParseReflog(const AOutput: string): TGittanReflog;
var
  Lines: TStringList;
  Fields: TStringArray;
  i, n, Open: integer;
begin
  Result := nil;
  Lines := TStringList.Create;
  try
    Lines.Text := AOutput;
    SetLength(Result, Lines.Count);
    n := 0;
    for i := 0 to Lines.Count - 1 do
    begin
      Fields := Lines[i].Split([#31], 3);
      if (Length(Fields) < 3) or (Fields[0] = '') then
        Continue;
      Result[n].Commit := Fields[0];
      Open := Pos('@{', Fields[1]);
      if Open > 0 then
        Result[n].Time := StrToInt64Def(Copy(Fields[1], Open + 2,
          Length(Fields[1]) - Open - 2), 0)
      else
        Result[n].Time := 0;
      Result[n].Subject := Fields[2];
      Result[n].Lost := False;
      Inc(n);
    end;
    SetLength(Result, n);
  finally
    Lines.Free;
  end;
end;

{ The commits go to rev-list a hundred at a time: the newest thousand
  ids on one command line passed the length Windows allows, the call
  failed and none was marked. What a batch reaches is reached, so the
  batches together give what all of them at once would. }
function TGittanRepo.Reflog(out AList: TGittanReflog; ALimit: integer): boolean;
const
  Batch = 100;
var
  Output: string;
  Args: array of string;
  Ids, Lost: TStringList;
  i, j, n: integer;
begin
  AList := nil;
  if FRoot = '' then
    Exit(False);
  if CommitId('HEAD') = '' then
    Exit(True);
  Result := RunGit(FRoot, ['log', '-g', '--date=unix', '--format=' + ReflogFormat,
    '-n', IntToStr(ALimit), 'HEAD'], Output);
  if not Result then
    Exit;
  AList := ParseReflog(Output);
  if Length(AList) = 0 then
    Exit;
  { What the commits reach and no ref does; a commit of the reflog in it
    is kept by the reflog alone. A failure only leaves none marked. }
  Ids := TStringList.Create;
  Lost := TStringList.Create;
  try
    Ids.Sorted := True;
    Ids.Duplicates := dupIgnore;
    for i := 0 to High(AList) do
      Ids.Add(AList[i].Commit);
    Lost.Sorted := True;
    Lost.Duplicates := dupIgnore;
    i := 0;
    while i < Ids.Count do
    begin
      n := Ids.Count - i;
      if n > Batch then
        n := Batch;
      SetLength(Args, n + 3);
      Args[0] := 'rev-list';
      for j := 0 to n - 1 do
        Args[1 + j] := Ids[i + j];
      Args[n + 1] := '--not';
      Args[n + 2] := '--all';
      if RunGit(FRoot, Args, Output) then
        Lost.AddText(Output);
      Inc(i, n);
    end;
    for i := 0 to High(AList) do
      AList[i].Lost := Lost.IndexOf(AList[i].Commit) >= 0;
  finally
    Ids.Free;
    Lost.Free;
  end;
end;

procedure ParseBisectRefs(const AOutput: string; out ABad: string;
  out AGood, ASkipped: TStringArray);
var
  Lines: TStringList;
  Line, Id, Ref: string;
  Space: integer;
begin
  ABad := '';
  AGood := nil;
  ASkipped := nil;
  Lines := TStringList.Create;
  try
    Lines.Text := AOutput;
    for Line in Lines do
    begin
      Space := Pos(' ', Line);
      if Space = 0 then
        Continue;
      Id := Copy(Line, 1, Space - 1);
      Ref := Trim(Copy(Line, Space + 1, MaxInt));
      if Ref = 'refs/bisect/bad' then
        ABad := Id
      else if AnsiStartsStr('refs/bisect/good-', Ref) then
      begin
        SetLength(AGood, Length(AGood) + 1);
        AGood[High(AGood)] := Id;
      end
      else if AnsiStartsStr('refs/bisect/skip-', Ref) then
      begin
        SetLength(ASkipped, Length(ASkipped) + 1);
        ASkipped[High(ASkipped)] := Id;
      end;
    end;
  finally
    Lines.Free;
  end;
end;

function TGittanRepo.BisectState(out AState: TGittanBisect): boolean;
var
  Output, Id: string;
  Args: array of string;
  Commits: TStringList;
  i: integer;
begin
  AState := Default(TGittanBisect);
  AState.Left := -1;
  Result := (FRoot <> '') and RunGit(FRoot, ['for-each-ref', '--format=' + BisectFormat,
    'refs/bisect'], Output);
  if not Result then
    Exit;
  ParseBisectRefs(Output, AState.Bad, AState.Good, AState.Skipped);
  if (AState.Bad = '') or (Length(AState.Good) = 0) then
    Exit;
  Args := ['rev-list', AState.Bad, '--not'];
  for Id in AState.Good do
  begin
    SetLength(Args, Length(Args) + 1);
    Args[High(Args)] := Id;
  end;
  if not RunGit(FRoot, Args, Output) then
    Exit(False);
  Commits := TStringList.Create;
  try
    Commits.Text := Output;
    { The bad commit and the skipped ones are not to test; what is left
      when none is, are the commits the first bad one could be. }
    AState.Left := 0;
    for i := 0 to Commits.Count - 1 do
      if Commits[i] = AState.Bad then
        Continue
      else if AnsiIndexStr(Commits[i], AState.Skipped) >= 0 then
      begin
        SetLength(AState.Suspects, Length(AState.Suspects) + 1);
        AState.Suspects[High(AState.Suspects)] := Commits[i];
      end
      else
        Inc(AState.Left);
  finally
    Commits.Free;
  end;
  if AState.Left > 0 then
    AState.Suspects := nil
  else if Length(AState.Suspects) > 0 then
  begin
    SetLength(AState.Suspects, Length(AState.Suspects) + 1);
    AState.Suspects[High(AState.Suspects)] := AState.Bad;
  end
  else
  begin
    AState.Found := AState.Bad;
    if RunGit(FRoot, ['log', '-1', '--format=%s', AState.Found], Output) then
      AState.Subject := Trim(Output);
  end;
end;

function TGittanRepo.BisectStart(const ABad, AGood: string): boolean;
var
  Output: string;
begin
  if FRoot = '' then
    Exit(False);
  if ABad = '' then
    Result := RunGit(FRoot, ['bisect', 'start'], Output)
  else if AGood = '' then
    Result := RunGit(FRoot, ['bisect', 'start', ABad], Output)
  else
    Result := RunGit(FRoot, ['bisect', 'start', ABad, AGood], Output);
end;

{ The commit by its id: git takes HEAD~1 and the like from the commit
  being tested, not from where the bisect started. }
function TGittanRepo.BisectMark(const ACommit: string; AMark: TGittanBisectMark): boolean;
const
  Words: array[TGittanBisectMark] of string = ('good', 'bad', 'skip');
var
  Hash, Output: string;
begin
  if FRoot = '' then
    Exit(False);
  Hash := CommitId(ACommit);
  if Hash = '' then
  begin
    FError := 'No commit ' + ACommit + '.';
    Exit(False);
  end;
  Result := RunGit(FRoot, ['bisect', Words[AMark], Hash], Output);
  if not Result and (Pos('only ''skip''ped commits left', FError) > 0) then
    Result := True;
end;

function TGittanRepo.BisectEnd: boolean;
var
  Output: string;
begin
  Result := (FRoot <> '') and RunGit(FRoot, ['bisect', 'reset'], Output);
end;

function TGittanRepo.DeleteTag(const AName: string): boolean;
var
  Output: string;
begin
  Result := (FRoot <> '') and (AName <> '') and RunGit(FRoot, ['tag', '-d', AName], Output);
end;

function TGittanRepo.PushTag(const ARemote, AName: string): boolean;
begin
  if (FRoot = '') or (ARemote = '') then
    Exit(False);
  if AName = '' then
    Result := RunRemote(['push', '--progress', ARemote, '--tags'])
  else
    Result := RunRemote(['push', '--progress', ARemote, 'refs/tags/' + AName]);
end;

function TGittanRepo.DeleteRemoteTag(const ARemote, AName: string): boolean;
begin
  if (FRoot = '') or (ARemote = '') or (AName = '') then
    Exit(False);
  Result := RunRemote(['push', ARemote, '--delete', 'refs/tags/' + AName]);
end;

{ ---------------------------------------------------------------------------
  Submodules
  ---------------------------------------------------------------------------
  An update and an add clone and fetch, so they run as a fetch does,
  with RemoteEnvironment; a sync only writes the config. }
function TGittanRepo.UpdateSubmodules(const APath: string): boolean;
begin
  if APath = '' then
    Result := RunRemote(['submodule', 'update', '--init', '--recursive', '--progress'])
  else
    Result := RunRemote(['submodule', 'update', '--init', '--recursive', '--progress', '--',
      APath]);
end;

function TGittanRepo.SyncSubmodules(const APath: string): boolean;
var
  Output: string;
begin
  if FRoot = '' then
    Exit(False);
  if APath = '' then
    Result := RunGit(FRoot, ['submodule', 'sync', '--recursive'], Output)
  else
    Result := RunGit(FRoot, ['submodule', 'sync', '--recursive', '--', APath], Output);
end;

{ No --progress: git 2.30 takes it for an update only. }
function TGittanRepo.AddSubmodule(const AUrl, APath, ABranch: string): boolean;
begin
  if (AUrl = '') or (APath = '') then
    Exit(False);
  if ABranch = '' then
    Result := RunRemote(['submodule', 'add', '--', AUrl, APath])
  else
    Result := RunRemote(['submodule', 'add', '-b', ABranch, '--', AUrl, APath]);
end;

function TGittanRepo.IsAncestor(const AAncestor, ADescendant: string): boolean;
var
  Output: string;
begin
  Result := (FRoot <> '') and
    RunGit(FRoot, ['merge-base', '--is-ancestor', AAncestor, ADescendant], Output);
end;

{ Runs a command that makes a commit, as the comment above says. AError
  keeps git's reason; AConflicts is set when it stopped with conflicts. }
function RunCommitting(ARepo: TGittanRepo; const ARoot: string;
  const AArgs: array of string; out AConflicts: boolean; out AError: string): boolean;
var
  Output, Ignored: string;
begin
  AConflicts := False;
  Result := RunGitEnv(ARoot, AArgs, ['GIT_EDITOR=:'], Output, AError);
  if Result then
    Exit;
  AConflicts := (ARepo.Operation <> '') and
    RunGitIn(ARoot, ['ls-files', '-u'], Output, Ignored) and (Trim(Output) <> '');
end;

function TGittanRepo.MergeRef(const ARef: string; out AConflicts: boolean): boolean;
var
  Err: string;
begin
  AConflicts := False;
  if FRoot = '' then
    Exit(False);
  Result := RunCommitting(Self, FRoot, ['merge', '--no-edit', ARef], AConflicts, Err);
  if not Result then
    FError := Err;
end;

function TGittanRepo.RebaseOnto(const AOnto: string; out AConflicts: boolean): boolean;
var
  Err: string;
begin
  AConflicts := False;
  if FRoot = '' then
    Exit(False);
  Result := RunCommitting(Self, FRoot, ['rebase', '--autostash', AOnto], AConflicts, Err);
  if not Result then
    FError := Err;
end;

{ ---------------------------------------------------------------------------
  Interactive rebase
  ---------------------------------------------------------------------------
  The todo list and the message files go in gittan-rebase in the git
  directory, where git keeps no files of its own and which stays where
  it is until the rebase is over, since an exec line reads a message
  file when its turn comes, maybe after a stop. The folder goes when a
  rebase ends: here, or in ContinueOperation, SkipOperation and
  AbortOperation. }
function TGittanRepo.RebaseFilesFolder: string;
begin
  Result := GitDir;
  if Result <> '' then
    Result := IncludeTrailingPathDelimiter(Result) + 'gittan-rebase';
end;

procedure TGittanRepo.CleanRebaseFiles;
var
  Folder: string;
  Info: TSearchRec;
begin
  Folder := RebaseFilesFolder;
  if (Folder = '') or not DirectoryExists(Folder) then
    Exit;
  Folder := IncludeTrailingPathDelimiter(Folder);
  if FindFirst(Folder + '*', faAnyFile, Info) = 0 then
  try
    repeat
      if (Info.Attr and faDirectory) = 0 then
        DeleteFile(Folder + Info.Name);
    until FindNext(Info) <> 0;
  finally
    FindClose(Info);
  end;
  RemoveDir(ExcludeTrailingPathDelimiter(Folder));
end;

{ The log is read as GraphCommits reads it, the body last since it may
  hold line breaks; the commits not on the upstream are the ones not
  pushed, so without an upstream none is. }
function TGittanRepo.RebaseSteps(const AOnto: string; out ASteps: TGittanRebaseSteps;
  out AMerges: boolean): boolean;
var
  Output, NotPushed: string;
  Records, Fields: TStringArray;
  i: integer;
  Seconds: int64;
  HasUpstream: boolean;
begin
  ASteps := nil;
  AMerges := False;
  Result := (FRoot <> '') and RunGit(FRoot, ['log', '--no-color', '--reverse', '-z',
    '--format=%H%x1f%P%x1f%h%x1f%an%x1f%ct%x1f%s%x1f%b', AOnto + '..HEAD'], Output);
  if not Result then
    Exit;
  HasUpstream := RunGit(FRoot, ['rev-list', AOnto + '..HEAD', '^@{upstream}'], NotPushed);
  Records := Output.Split([#0]);
  for i := 0 to High(Records) do
  begin
    Fields := Records[i].Split([#31]);
    if Length(Fields) < 7 then
      Continue;
    SetLength(ASteps, Length(ASteps) + 1);
    with ASteps[High(ASteps)] do
    begin
      Hash := Fields[0];
      if Pos(' ', Trim(Fields[1])) > 0 then
        AMerges := True;
      Short := Fields[2];
      Author := Fields[3];
      if TryStrToInt64(Fields[4], Seconds) then
        Date := UnixToDateTime(Seconds)
      else
        Date := 0;
      Subject := Fields[5];
      Body := TrimRight(Fields[6]);
      Pushed := HasUpstream and (Pos(Hash, NotPushed) = 0);
      Action := raPick;
      Message := OriginalMessage(ASteps[High(ASteps)]);
    end;
  end;
end;

{ Writes AText as it is to AFileName; false, rather than an exception,
  when it cannot. }
function WriteRebaseFile(const AFileName, AText: string): boolean;
begin
  try
    WriteBytes(AFileName, AText);
    Result := True;
  except
    Result := False;
  end;
end;

{ git runs the sequence editor through sh with the todo's path after
  it, so "cp <file>" writes the prepared list over it; cp is there on
  every platform git runs on, Git for Windows' sh included. A stop at
  an edit ends with exit code 0, so what git is in the middle of is
  read afterwards instead. }
function TGittanRepo.RebaseInteractive(const AOnto: string; const ASteps: TGittanRebaseSteps;
  out AConflicts, AStopped: boolean): boolean;
var
  Folder, Todo, Output, Err, Ignored: string;
  MsgFiles: TGittanRebaseFiles;
  i: integer;
begin
  AConflicts := False;
  AStopped := False;
  if FRoot = '' then
    Exit(False);
  if not CheckRebaseSteps(ASteps, FError) then
    Exit(False);
  Folder := RebaseFilesFolder;
  if Folder = '' then
    Exit(False);
  CleanRebaseFiles;
  Folder := IncludeTrailingPathDelimiter(Folder);
  Todo := BuildRebaseTodo(ASteps, Folder, MsgFiles);
  if not ForceDirectories(Folder) or not WriteRebaseFile(Folder + 'todo', Todo) then
  begin
    FError := Format('Could not write the rebase files in %s.', [Folder]);
    Exit(False);
  end;
  for i := 0 to High(MsgFiles) do
    if not WriteRebaseFile(Folder + MsgFiles[i].Name, MsgFiles[i].Text) then
    begin
      FError := Format('Could not write the rebase files in %s.', [Folder]);
      Exit(False);
    end;
  Result := RunGitEnv(FRoot, ['rebase', '-i', '--autostash', '--empty=keep', AOnto],
    ['GIT_SEQUENCE_EDITOR=cp ' + ShellQuote(Folder + 'todo'), 'GIT_EDITOR=:'], Output, Err);
  if Operation = 'rebasing' then
  begin
    AConflicts := RunGitIn(FRoot, ['ls-files', '-u'], Output, Ignored) and (Trim(Output) <> '');
    AStopped := not AConflicts;
    FError := ResolveReturns(Trim(Err));
    Exit(False);
  end;
  CleanRebaseFiles;
  if not Result then
    FError := Err;
end;

{ git appends each todo line it has done to "done" in the rebase's
  state, so the rebase stands at an edit when the last line is one;
  stopped-sha and amend are written for a conflicted fixup too. }
function TGittanRepo.RebaseStoppedAt: string;
var
  FileName, Line: string;
  Lines: TStringList;
  i: integer;
begin
  Result := '';
  if GitDir = '' then
    Exit;
  FileName := IncludeTrailingPathDelimiter(GitDir) + 'rebase-merge' + PathDelim + 'done';
  if not FileExists(FileName) then
    Exit;
  Lines := TStringList.Create;
  try
    Lines.LoadFromFile(FileName);
    for i := Lines.Count - 1 downto 0 do
    begin
      Line := Trim(Lines[i]);
      if Line = '' then
        Continue;
      if (Pos('edit ', Line) = 1) or (Pos('e ', Line) = 1) then
      begin
        Delete(Line, 1, Pos(' ', Line));
        Result := Trim(Copy(Line, 1, Pos(' ', Line + ' ') - 1));
      end;
      Exit;
    end;
  finally
    Lines.Free;
  end;
end;

{ rev-list counts the commits on HEAD but not on AOnto; those also on the
  upstream are the ones pushed. A branch without an upstream has pushed
  none. }
function TGittanRepo.CommitsToRebase(const AOnto: string; out ACount, APushed: integer): boolean;
var
  Output: string;
  NotPushed: integer;
begin
  ACount := 0;
  APushed := 0;
  Result := (FRoot <> '') and
    RunGit(FRoot, ['rev-list', '--count', AOnto + '..HEAD'], Output) and
    TryStrToInt(Trim(Output), ACount);
  if not Result or (ACount = 0) then
    Exit;
  if RunGit(FRoot, ['rev-list', '--count', AOnto + '..HEAD', '^@{upstream}'], Output) and
    TryStrToInt(Trim(Output), NotPushed) then
    APushed := ACount - NotPushed;
end;

function TGittanRepo.CherryPick(const AHash: string; out AConflicts: boolean): boolean;
var
  Err: string;
begin
  AConflicts := False;
  if FRoot = '' then
    Exit(False);
  Result := RunCommitting(Self, FRoot, ['cherry-pick', AHash], AConflicts, Err);
  if not Result then
    FError := Err;
end;

function TGittanRepo.RevertCommit(const AHash: string; out AConflicts: boolean): boolean;
var
  Err: string;
begin
  AConflicts := False;
  if FRoot = '' then
    Exit(False);
  Result := RunCommitting(Self, FRoot, ['revert', '--no-edit', AHash], AConflicts, Err);
  if not Result then
    FError := Err;
end;

function TGittanRepo.Reset(const AHash: string; AMode: TGittanResetMode): boolean;
const
  Flags: array[TGittanResetMode] of string = ('--soft', '--mixed', '--hard');
var
  Output: string;
begin
  Result := (FRoot <> '') and (AHash <> '') and
    RunGit(FRoot, ['reset', '-q', Flags[AMode], AHash], Output);
end;

{ ---------------------------------------------------------------------------
  Clean
  --------------------------------------------------------------------------- }

function UnquoteCPath(const APath: string): string;
var
  i, n: integer;
  C: char;
begin
  n := Length(APath);
  if (n < 2) or (APath[1] <> '"') or (APath[n] <> '"') then
    Exit(APath);
  Result := '';
  i := 2;
  while i < n do
  begin
    C := APath[i];
    if (C = '\') and (i + 1 < n) then
    begin
      Inc(i);
      C := APath[i];
      case C of
        'a': Result := Result + #7;
        'b': Result := Result + #8;
        't': Result := Result + #9;
        'n': Result := Result + #10;
        'v': Result := Result + #11;
        'f': Result := Result + #12;
        'r': Result := Result + #13;
        '0'..'3':
          if (i + 2 < n) and (APath[i + 1] in ['0'..'7']) and (APath[i + 2] in ['0'..'7']) then
          begin
            Result := Result + Chr((Ord(C) - 48) * 64 + (Ord(APath[i + 1]) - 48) * 8 +
              Ord(APath[i + 2]) - 48);
            Inc(i, 2);
          end
          else
            Result := Result + C;
        else
          Result := Result + C;
      end;
    end
    else
      Result := Result + C;
    Inc(i);
  end;
end;

procedure ParseCleanPreview(const AOutput: string; APaths: TStrings);
const
  Prefix = 'Would remove ';
var
  Lines: TStringList;
  i: integer;
begin
  APaths.Clear;
  Lines := TStringList.Create;
  try
    Lines.Text := AOutput;
    for i := 0 to Lines.Count - 1 do
      if (Copy(Lines[i], 1, Length(Prefix)) = Prefix) and (Length(Lines[i]) > Length(Prefix)) then
        APaths.Add(UnquoteCPath(Copy(Lines[i], Length(Prefix) + 1, MaxInt)));
  finally
    Lines.Free;
  end;
end;

function ParseTreeEntries(const AOutput, AFolder: string): TGittanTreeEntries;
var
  Fields: TStringList;
  Head: TStringArray;
  i, j, n, Tab: integer;
  E: TGittanTreeEntry;

  function Before(const A, B: TGittanTreeEntry): boolean;
  begin
    if (A.Kind = tkFolder) <> (B.Kind = tkFolder) then
      Result := A.Kind = tkFolder
    else
      Result := A.Name < B.Name;
  end;

begin
  Result := nil;
  Fields := TStringList.Create;
  try
    SplitNul(AOutput, Fields);
    SetLength(Result, Fields.Count);
    n := 0;
    for i := 0 to Fields.Count - 1 do
    begin
      Tab := Pos(#9, Fields[i]);
      if Tab = 0 then
        Continue;
      Head := Copy(Fields[i], 1, Tab - 1).Split([' '], TStringSplitOptions.ExcludeEmpty);
      if Length(Head) < 4 then
        Continue;
      E.Name := Copy(Fields[i], Tab + 1, MaxInt);
      if E.Name = '' then
        Continue;
      if AFolder = '' then
        E.Path := E.Name
      else
        E.Path := AFolder + '/' + E.Name;
      if Head[1] = 'tree' then
        E.Kind := tkFolder
      else if Head[1] = 'commit' then
        E.Kind := tkSubmodule
      else if Head[0] = '120000' then
        E.Kind := tkLink
      else if Head[1] = 'blob' then
        E.Kind := tkFile
      else
        Continue;
      E.Id := Head[2];
      E.Size := StrToInt64Def(Head[3], -1);
      E.Executable := Head[0] = '100755';
      { An insertion sort: git gives each folder's entries sorted
        already, so this only moves the folders up. }
      j := n;
      while (j > 0) and Before(E, Result[j - 1]) do
      begin
        Result[j] := Result[j - 1];
        Dec(j);
      end;
      Result[j] := E;
      Inc(n);
    end;
    SetLength(Result, n);
  finally
    Fields.Free;
  end;
end;

{ The tree is named as <commit>:<folder>, which with an empty folder is
  the commit's root tree, so the names come relative to the folder. }
function TGittanRepo.TreeEntries(const ACommit, AFolder: string;
  out AList: TGittanTreeEntries): boolean;
var
  Output: string;
begin
  AList := nil;
  if (FRoot = '') or (ACommit = '') then
    Exit(False);
  Result := RunGit(FRoot, ['ls-tree', '-l', '-z', ACommit + ':' + AFolder], Output);
  if Result then
    AList := ParseTreeEntries(Output, AFolder);
end;

const
  CleanFlags: array[TGittanCleanKind] of string = ('-d', '-dX', '-dx');

function TGittanRepo.CleanPreview(AKind: TGittanCleanKind; APaths: TStrings): boolean;
var
  Output: string;
begin
  APaths.Clear;
  Result := (FRoot <> '') and RunGit(FRoot, ['clean', '-n', CleanFlags[AKind]], Output);
  if Result then
    ParseCleanPreview(Output, APaths);
end;

{ git clean reads no pathspec file, so the paths go on the command line,
  a hundred at a time to stay under the length Windows allows. }
function TGittanRepo.Clean(AKind: TGittanCleanKind; APaths: TStrings): boolean;
const
  Batch = 100;
var
  Output: string;
  Args: array of string;
  i, n: integer;
begin
  if FRoot = '' then
    Exit(False);
  Result := True;
  i := 0;
  while Result and (i < APaths.Count) do
  begin
    n := APaths.Count - i;
    if n > Batch then
      n := Batch;
    SetLength(Args, 5 + n);
    Args[0] := '--literal-pathspecs';
    Args[1] := 'clean';
    Args[2] := '-f';
    Args[3] := CleanFlags[AKind];
    Args[4] := '--';
    n := 5;
    while (n < Length(Args)) and (i < APaths.Count) do
    begin
      Args[n] := APaths[i];
      Inc(n);
      Inc(i);
    end;
    Result := RunGit(FRoot, Args, Output);
  end;
end;

{ ---------------------------------------------------------------------------
  Patches
  ---------------------------------------------------------------------------
  A series from AOlder to ANewer is ANewer without AOlder's parents
  (rev-parse <commit>^@ lists them), so AOlder is in it. A root commit
  has none, and format-patch reads a lone commit as "since it", so
  ARoot asks it for everything from the start instead; log reads the
  lone commit as its whole history, the same commits. }
function TGittanRepo.PatchRange(const AOlder, ANewer: string; out ARevs: TStringArray;
  out ARoot: boolean): boolean;
var
  Output: string;
  Parents: TStringList;
  i: integer;
begin
  ARevs := nil;
  ARoot := False;
  if AOlder = '' then
  begin
    ARevs := ['-1', ANewer];
    Exit(True);
  end;
  Result := RunGit(FRoot, ['rev-parse', AOlder + '^@'], Output);
  if not Result then
    Exit;
  Parents := TStringList.Create;
  try
    Parents.Text := Trim(Output);
    SetLength(ARevs, 1 + Parents.Count);
    ARevs[0] := ANewer;
    for i := 0 to Parents.Count - 1 do
      ARevs[1 + i] := '^' + Trim(Parents[i]);
    ARoot := Parents.Count = 0;
  finally
    Parents.Free;
  end;
end;

function TGittanRepo.PatchCommits(const AOlder, ANewer: string;
  out ACommits: TGittanPatchCommits): boolean;
var
  Output: string;
  Revs, Args: TStringArray;
  FromStart: boolean;
  Lines: TStringList;
  Fields: TStringArray;
  i, n: integer;
begin
  ACommits := nil;
  if (FRoot = '') or (ANewer = '') or not PatchRange(AOlder, ANewer, Revs, FromStart) then
    Exit(False);
  Args := Concat(['log', '--no-merges', '--reverse', '--format=%H%x1f%h%x1f%s'], Revs);
  Result := RunGit(FRoot, Args, Output);
  if not Result then
    Exit;
  Lines := TStringList.Create;
  try
    Lines.Text := Output;
    SetLength(ACommits, Lines.Count);
    n := 0;
    for i := 0 to Lines.Count - 1 do
    begin
      Fields := Lines[i].Split([#31]);
      if Length(Fields) < 3 then
        Continue;
      ACommits[n].Hash := Fields[0];
      ACommits[n].Short := Fields[1];
      ACommits[n].Subject := Fields[2];
      Inc(n);
    end;
    SetLength(ACommits, n);
  finally
    Lines.Free;
  end;
end;

{ format-patch prints the name of every file it writes, a line each,
  relative to where git runs when the folder is: the folder is made
  absolute against the root first, so the names are too, whatever this
  process's current folder is. }
function TGittanRepo.FormatPatches(const AOlder, ANewer, AFolder: string;
  ACoverLetter: boolean; AFiles: TStrings): boolean;
var
  Output, Folder: string;
  Revs, Args: TStringArray;
  FromStart: boolean;
  Lines: TStringList;
  i: integer;
begin
  AFiles.Clear;
  if (FRoot = '') or (ANewer = '') or (AFolder = '') or
    not PatchRange(AOlder, ANewer, Revs, FromStart) then
    Exit(False);
  Folder := AFolder;
  if (ExtractFileDrive(Folder) = '') and not (Folder[1] in AllowDirectorySeparators) then
    Folder := IncludeTrailingPathDelimiter(FRoot) + Folder;
  Args := ['format-patch', '-o', Folder];
  if ACoverLetter then
    Args := Concat(Args, ['--cover-letter']);
  if FromStart then
    Args := Concat(Args, ['--root']);
  Result := RunGit(FRoot, Concat(Args, Revs), Output);
  if not Result then
    Exit;
  Lines := TStringList.Create;
  try
    Lines.Text := Output;
    for i := 0 to Lines.Count - 1 do
      if Trim(Lines[i]) <> '' then
        AFiles.Add(ExpandFileName(Trim(Lines[i])));
  finally
    Lines.Free;
  end;
end;

{ am applies the files one after the other and stops at the first that
  fails, so what went in is counted as the commits HEAD gained. apply is
  tried as it is first, since --3way implies --index and so refuses a
  file whose work tree differs from the index, as one changed but not
  staged does; the three-way merge is for a patch that does not fit. }
function TGittanRepo.ApplyPatches(AFiles: TStrings; ACommit: boolean;
  out AConflicts: boolean; out AApplied: integer): boolean;
var
  Output, Err, Before: string;
  Args: TStringArray;
  i: integer;
begin
  AConflicts := False;
  AApplied := 0;
  if (FRoot = '') or (AFiles.Count = 0) then
    Exit(False);
  if ACommit then
  begin
    if RunGit(FRoot, ['rev-parse', '--verify', '-q', 'HEAD'], Output) then
      Before := Trim(Output)
    else
      Before := '';
    Args := ['am', '--3way'];
    for i := 0 to AFiles.Count - 1 do
      Args := Concat(Args, [AFiles[i]]);
    Result := RunCommitting(Self, FRoot, Args, AConflicts, Err);
    if not Result then
      FError := Err;
    if Before = '' then
      Args := ['rev-list', '--count', 'HEAD']
    else
      Args := ['rev-list', '--count', Before + '..HEAD'];
    if RunGitIn(FRoot, Args, Output, Err) then
      AApplied := StrToIntDef(Trim(Output), 0);
    Exit;
  end;
  Result := True;
  for i := 0 to AFiles.Count - 1 do
  begin
    if not RunGitIn(FRoot, ['apply', AFiles[i]], Output, Err) then
    begin
      FError := Err;
      Result := False;
      { Applied with conflicts leaves them in the index, and fails. }
      if not RunGitIn(FRoot, ['apply', '--3way', AFiles[i]], Output, Err) then
      begin
        AConflicts := RunGitIn(FRoot, ['ls-files', '-u'], Output, Err) and
          (Trim(Output) <> '');
        if AConflicts then
          Inc(AApplied);
        Exit;
      end;
      Result := True;
    end;
    Inc(AApplied);
  end;
end;

function IsMailPatch(const AText: string): boolean;
var
  Lines: TStringList;
  i, Colon: integer;
  From, Subject: boolean;
  Line: string;
begin
  Result := False;
  Lines := TStringList.Create;
  try
    Lines.Text := AText;
    i := 0;
    while (i < Lines.Count) and (Trim(Lines[i]) = '') do
      Inc(i);
    if i >= Lines.Count then
      Exit;
    if Copy(Lines[i], 1, 5) = 'From ' then
      Exit(True);
    From := False;
    Subject := False;
    while (i < Lines.Count) and (Lines[i] <> '') do
    begin
      Line := LowerCase(Lines[i]);
      if Copy(Line, 1, 5) = 'from:' then
        From := True
      else if Copy(Line, 1, 8) = 'subject:' then
        Subject := True
      { A header line is a name, a colon and the value, or the value
        going on after white space; anything else ends the header. }
      else if not (Line[1] in [' ', #9]) then
      begin
        Colon := Pos(':', Line);
        if (Colon < 2) or (Pos(' ', Copy(Line, 1, Colon - 1)) > 0) then
          Break;
      end;
      Inc(i);
    end;
    Result := From and Subject;
  finally
    Lines.Free;
  end;
end;

function IsMailPatchFile(const AFileName: string): boolean;
const
  Probe = 8192;
var
  Stream: TFileStream;
  Text: string;
  n: integer;
begin
  Result := False;
  try
    Stream := TFileStream.Create(AFileName, fmOpenRead or fmShareDenyNone);
    try
      SetLength(Text, Probe);
      n := Stream.Read(Text[1], Probe);
      SetLength(Text, n);
    finally
      Stream.Free;
    end;
  except
    Exit;
  end;
  Result := IsMailPatch(Text);
end;

{ ---------------------------------------------------------------------------
  Conflicts
  --------------------------------------------------------------------------- }

{ The stages the index holds for APath while it is in conflict: 1 the
  base, 2 ours, 3 theirs; a side that deleted the file has none. }
function ConflictStages(const ARoot, APath: string): string;
var
  Output, Err, Entry: string;
  Fields: TStringList;
  Tab: integer;
begin
  Result := '';
  if not RunGitIn(ARoot, ['--literal-pathspecs', 'ls-files', '-u', '-z', '--', APath],
    Output, Err) then
    Exit;
  Fields := TStringList.Create;
  try
    SplitNul(Output, Fields);
    for Entry in Fields do
    begin
      { "<mode> <id> <stage>\t<path>" }
      Tab := Pos(#9, Entry);
      if Tab > 1 then
        Result := Result + Entry[Tab - 1];
    end;
  finally
    Fields.Free;
  end;
end;

function TGittanRepo.ResolveConflict(const APath: string; ASide: TGittanConflictSide): boolean;
var
  Output, Stages: string;
  Ours: boolean;
begin
  if FRoot = '' then
    Exit(False);
  Ours := ASide = csMine;
  if Operation = 'rebasing' then
    Ours := not Ours;
  Stages := ConflictStages(FRoot, APath);
  if (Ours and (Pos('2', Stages) = 0)) or (not Ours and (Pos('3', Stages) = 0)) then
    Exit(RunGit(FRoot, ['--literal-pathspecs', 'rm', '-q', '--', APath], Output));
  if Ours then
    Result := RunGit(FRoot, ['--literal-pathspecs', 'checkout', '--ours', '--', APath], Output)
  else
    Result := RunGit(FRoot, ['--literal-pathspecs', 'checkout', '--theirs', '--', APath], Output);
  Result := Result and RunGit(FRoot, ['--literal-pathspecs', 'add', '--', APath], Output);
end;

function TGittanRepo.MarkResolved(const APath: string): boolean;
var
  Output: string;
begin
  if FRoot = '' then
    Exit(False);
  if FileExists(FullPath(APath)) or DirectoryExists(FullPath(APath)) then
    Result := RunGit(FRoot, ['--literal-pathspecs', 'add', '--', APath], Output)
  else
    Result := RunGit(FRoot, ['--literal-pathspecs', 'rm', '-q', '--', APath], Output);
end;

function TGittanRepo.Unresolve(const APath: string): boolean;
var
  Output: string;
begin
  if FRoot = '' then
    Exit(False);
  if not RunGit(FRoot, ['update-index', '--unresolve', '--', APath], Output) then
    Exit(False);
  { git says nothing when it has no stages kept for the path. }
  Result := ConflictStages(FRoot, APath) <> '';
  if not Result then
    FError := 'git kept no conflict to bring back';
end;

{ The command of the operation in progress, '' for none (or bisect,
  which has no --continue). }
function OperationCommand(const AOperation: string): string;
begin
  if AOperation = 'merging' then
    Result := 'merge'
  else if AOperation = 'rebasing' then
    Result := 'rebase'
  else if AOperation = 'applying patches' then
    Result := 'am'
  else if AOperation = 'cherry-picking' then
    Result := 'cherry-pick'
  else if AOperation = 'reverting' then
    Result := 'revert'
  else
    Result := '';
end;

{ git runs the editor through the shell; ":" does nothing there and
  leaves the message git prepared, on every platform. }
function TGittanRepo.ContinueOperation: boolean;
var
  Command, Output, Err: string;
begin
  Command := OperationCommand(Operation);
  if (FRoot = '') or (Command = '') then
  begin
    FError := 'Git is not in the middle of anything to continue.';
    Exit(False);
  end;
  { git add -u would take a file still in conflict, markers and all, as
    resolved. }
  if not RunGit(FRoot, ['ls-files', '-u'], Output) then
    Exit(False);
  if Trim(Output) <> '' then
  begin
    FError := 'Resolve the conflicts first.';
    Exit(False);
  end;
  if not RunGit(FRoot, ['add', '-u'], Output) then
    Exit(False);
  Result := RunGitEnv(FRoot, [Command, '--continue'], ['GIT_EDITOR=:'], Output, Err);
  if Result then
  begin
    if Operation = '' then
      CleanRebaseFiles;
    Exit;
  end;
  FError := Err;
  { Stopped at a later commit with conflicts of its own: going on worked. }
  Result := (Operation <> '') and RunGit(FRoot, ['ls-files', '-u'], Output) and
    (Trim(Output) <> '');
end;

function TGittanRepo.ContinueExtras: TStringArray;
var
  Output, Err, Entry: string;
  Fields, Resolved: TStringList;
  Tab: integer;
begin
  Result := nil;
  if FRoot = '' then
    Exit;
  Fields := TStringList.Create;
  Resolved := TStringList.Create;
  try
    Resolved.Sorted := True;
    Resolved.Duplicates := dupIgnore;
    Resolved.CaseSensitive := True;
    if not RunGitIn(FRoot, ['ls-files', '--resolve-undo', '-z'], Output, Err) then
      Exit;
    SplitNul(Output, Fields);
    for Entry in Fields do
    begin
      { "<mode> <id> <stage>\t<path>", one line for each stage kept }
      Tab := Pos(#9, Entry);
      if Tab > 0 then
        Resolved.Add(Copy(Entry, Tab + 1, MaxInt));
    end;
    if Resolved.Count = 0 then
      Exit;
    if not RunGitIn(FRoot, ['diff', '--name-only', '-z'], Output, Err) then
      Exit;
    Fields.Clear;
    SplitNul(Output, Fields);
    Fields.Sort;
    for Entry in Fields do
      if Resolved.IndexOf(Entry) < 0 then
      begin
        SetLength(Result, Length(Result) + 1);
        Result[High(Result)] := Entry;
      end;
  finally
    Resolved.Free;
    Fields.Free;
  end;
end;

function TGittanRepo.SkipOperation: boolean;
var
  Command, Output: string;
begin
  Command := OperationCommand(Operation);
  if (FRoot = '') or (Command = '') or (Command = 'merge') then
  begin
    FError := 'There is no commit to skip.';
    Exit(False);
  end;
  Result := RunGit(FRoot, [Command, '--skip'], Output);
  if Result and (Operation = '') then
    CleanRebaseFiles;
end;

function TGittanRepo.AbortOperation: boolean;
var
  Command, Output: string;
begin
  Command := OperationCommand(Operation);
  if (FRoot = '') or (Command = '') then
  begin
    FError := 'Git is not in the middle of anything to abort.';
    Exit(False);
  end;
  Result := RunGit(FRoot, [Command, '--abort'], Output);
  if Result then
    CleanRebaseFiles;
end;

function TGittanRepo.QuitOperation: boolean;
var
  Command, Output: string;
begin
  Command := OperationCommand(Operation);
  if (FRoot = '') or (Command = '') or (Command = 'merge') then
  begin
    FError := 'Git is not in the middle of anything to forget.';
    Exit(False);
  end;
  Result := RunGit(FRoot, [Command, '--quit'], Output);
  if Result then
    CleanRebaseFiles;
end;

{ The comment lines git wrote start with core.commentString or
  core.commentChar, # when neither is set. "auto" has git pick a
  character the message does not start a line with, which cannot be
  told afterwards; # stands in then. }
function TGittanRepo.MergeMessage: string;
var
  Dir, Line, Comment: string;
  Lines: TStringList;
begin
  Result := '';
  Dir := GitDir;
  if (Dir = '') or not FileExists(IncludeTrailingPathDelimiter(Dir) + 'MERGE_MSG') then
    Exit;
  if not RunGit(FRoot, ['config', '--get', 'core.commentString'], Comment) and
    not RunGit(FRoot, ['config', '--get', 'core.commentChar'], Comment) then
    Comment := '';
  Comment := TrimRight(Comment);
  if (Comment = '') or (Comment = 'auto') then
    Comment := '#';
  Lines := TStringList.Create;
  try
    Lines.LoadFromFile(IncludeTrailingPathDelimiter(Dir) + 'MERGE_MSG');
    for Line in Lines do
      if not Line.StartsWith(Comment) then
        Result := Result + Line + #10;
  finally
    Lines.Free;
  end;
  Result := Trim(Result);
end;

function TGittanRepo.HeadMessage(out AMessage: string): boolean;
begin
  AMessage := '';
  Result := (FRoot <> '') and RunGit(FRoot, ['log', '-1', '--format=%B', 'HEAD'], AMessage);
  if Result then
    AMessage := TrimRight(AMessage)
  else
    AMessage := '';
end;

{ Against HEAD the list is git status itself. Against another base it is
  `git diff --name-status` turned into the same "XY path" shape, with the
  letter in the work tree column, plus the untracked files from git
  status, which no diff lists (unless WholeTree is set). Untracked files are asked for one by one
  (--untracked-files=all): by default git folds a directory of them into
  a single "dir/" entry, which no diff or numstat can say anything
  about. Both are read with -z: a path with a space,
  a quote or a control character is quoted C-style in the line form, but
  comes as it is between NULs. A status entry is "XY path"; a rename or
  copy (R or C in either column) is followed by the old path as a field
  of its own, which is dropped. A name-status entry is two fields, the
  letter and the path (renames are off, so there is no third). }
function TGittanRepo.Files(AList: TStrings): boolean;
var
  Output: string;
begin
  AList.Clear;
  if FRoot = '' then
    Exit(False);
  Result := RunGit(FRoot, ['ls-files', '-z', '--cached', '--others',
    '--exclude-standard'], Output);
  if Result then
    SplitNul(Output, AList);
end;

{ git grep exits with 1 and says nothing when no row matched, which
  RunGit reports as a failure without a message. }
function TGittanRepo.Grep(AWords: TStrings; AIgnoreCase: boolean; out AOutput: string): boolean;
var
  Args: array of string;
  i, n: integer;
begin
  AOutput := '';
  if (FRoot = '') or (AWords.Count = 0) then
    Exit(False);
  SetLength(Args, 11 + 2 * AWords.Count);
  Args[0] := 'grep';
  Args[1] := '-z';
  Args[2] := '-n';
  Args[3] := '-w';
  Args[4] := '-F';
  Args[5] := '-I';
  Args[6] := '--untracked';
  { color.ui or color.grep set to always would color the matches. }
  Args[7] := '--no-color';
  n := 8;
  if AIgnoreCase then
  begin
    Args[n] := '-i';
    Inc(n);
  end;
  for i := 0 to AWords.Count - 1 do
  begin
    Args[n] := '-e';
    Args[n + 1] := AWords[i];
    Inc(n, 2);
  end;
  Args[n] := '--';
  Args[n + 1] := '.';
  SetLength(Args, n + 2);
  Result := RunGit(FRoot, Args, AOutput);
  if not Result and (FError = '') then
    Result := True;
end;

function TGittanRepo.ChangedFiles(AList: TStrings): boolean;
var
  Output, Entry: string;
  Fields, Removed: TStringList;
  i: integer;
begin
  AList.Clear;
  if FRoot = '' then
    Exit(False);
  Fields := TStringList.Create;
  Removed := TStringList.Create;
  try
    Removed.CaseSensitive := True;
    Removed.Sorted := True;
    { Between two commits the work tree has no say, so git status is
      not asked; nor for the whole tree, where the diff lists the
      untracked files itself. }
    if not IsRange and not WholeTreeActive then
    begin
      Result := RunGit(FRoot, ['status', '--porcelain', '-z',
        '--untracked-files=all'], Output);
      if not Result then
        Exit;
      SplitNul(Output, Fields);
      i := 0;
      while i < Fields.Count do
      begin
        Entry := Fields[i];
        Inc(i);
        if Length(Entry) < 4 then
          Continue;
        if (Entry[1] in ['R', 'C']) or (Entry[2] in ['R', 'C']) then
          Inc(i);
        { A file git rm --cached took out of the index is listed once,
          as the deletion to commit, not also as untracked (those come
          last). }
        if Entry[1] = 'D' then
          Removed.Add(Copy(Entry, 4, MaxInt))
        else if (Copy(Entry, 1, 2) = '??') and (Removed.IndexOf(Copy(Entry, 4, MaxInt)) >= 0) then
          Continue;
        if (FBase = '') or (Copy(Entry, 1, 2) = '??') then
          AList.Add(Entry);
      end;
      if FBase = '' then
        Exit;
    end;
    Result := RunDiff(['--name-status', '--no-renames', '-z'], Output);
    if not Result then
      Exit;
    SplitNul(Output, Fields);
    i := 0;
    while i + 1 < Fields.Count do
    begin
      if Fields[i] <> '' then
        AList.Add(' ' + Fields[i][1] + ' ' + Fields[i + 1]);
      Inc(i, 2);
    end;
  finally
    Fields.Free;
    Removed.Free;
  end;
end;

class function TGittanRepo.StageFlags(const AStatus: string): integer;
begin
  Result := 0;
  if ((Length(AStatus) >= 1) and (AStatus[1] in ['?', '!'])) or
    (ChangeKind(AStatus) = ckConflict) then
    Exit;
  if (Length(AStatus) >= 1) and (AStatus[1] <> ' ') then
    Result := Result or flagStaged;
  if (Length(AStatus) >= 2) and (AStatus[2] <> ' ') then
    Result := Result or flagUnstaged;
end;

function TGittanRepo.ChangedPaths(AList: TStrings): boolean;
var
  i: integer;
begin
  Result := ChangedFiles(AList);
  if not Result then
    Exit;
  for i := 0 to AList.Count - 1 do
  begin
    AList.Objects[i] := TObject(PtrUInt(Ord(ChangeKind(Copy(AList[i], 1, 2))) +
      StageFlags(Copy(AList[i], 1, 2))));
    AList[i] := Copy(AList[i], 4, MaxInt);
  end;
end;

{ Git's own heuristic: a NUL byte in the first 8000 bytes makes a file
  binary. A text file has one line per line feed, plus an unterminated last
  line. A file gone or unreadable since git listed it counts nothing. }
procedure CountNewFile(const AFileName: string; var AStat: TGittanFileStat);
const
  Probe = 8000;
var
  Stream: TFileStream;
  Buffer: array[0..4095] of byte;
  Got, i, Seen: integer;
  LastByte: byte;
begin
  AStat.Added := 0;
  AStat.Deleted := 0;
  AStat.Binary := False;
  try
    Stream := TFileStream.Create(AFileName, fmOpenRead or fmShareDenyNone);
    try
      Seen := 0;
      LastByte := 10;
      repeat
        Got := Stream.Read(Buffer, SizeOf(Buffer));
        for i := 0 to Got - 1 do
        begin
          if (Buffer[i] = 0) and (Seen + i < Probe) then
          begin
            AStat.Binary := True;
            AStat.Added := 0;
            Exit;
          end;
          if Buffer[i] = 10 then
            Inc(AStat.Added);
        end;
        if Got > 0 then
          LastByte := Buffer[Got - 1];
        Inc(Seen, Got);
      until Got = 0;
      if (Seen > 0) and (LastByte <> 10) then
        Inc(AStat.Added);
    finally
      Stream.Free;
    end;
  except
    AStat.Added := 0;
    AStat.Binary := False;
  end;
end;

function IsBinaryFile(const AFileName: string): boolean;
const
  Probe = 8000;
var
  Stream: TFileStream;
  Buffer: array[0..Probe - 1] of byte;
  Got, i: integer;
begin
  Result := False;
  try
    Stream := TFileStream.Create(AFileName, fmOpenRead or fmShareDenyNone);
    try
      Got := Stream.Read(Buffer, SizeOf(Buffer));
      for i := 0 to Got - 1 do
        if Buffer[i] = 0 then
          Exit(True);
    finally
      Stream.Free;
    end;
  except
    Result := False;
  end;
end;

{ A numstat entry is "added<tab>deleted<tab>path", with "-" for both counts
  of a binary file. Renames are turned off so the new path of a rename gets
  its counts; the old path is not in the list and is skipped. The counts
  are against HEAD, so staged and unstaged changes are both in. }
function TGittanRepo.ChangeStats(out AStats: TGittanFileStats): boolean;
var
  Paths, Num, ByPath: TStringList;
  Output, Entry, Path, Counts, FileName: string;
  i, Tab1, Tab2, Idx: integer;
begin
  AStats := nil;
  Paths := TStringList.Create;
  Num := TStringList.Create;
  { The paths sorted, each with its index in AStats, so the counts of
    thousands of changed files are not each looked for from the top. }
  ByPath := TStringList.Create;
  Inc(FIndexPass);
  try
    Paths.CaseSensitive := True;
    Result := ChangedPaths(Paths);
    if not Result then
      Exit;
    ByPath.CaseSensitive := True;
    ByPath.Duplicates := dupIgnore;
    ByPath.Sorted := True;
    SetLength(AStats, Paths.Count);
    for i := 0 to Paths.Count - 1 do
    begin
      ByPath.AddObject(Paths[i], TObject(PtrInt(i)));
      AStats[i] := Default(TGittanFileStat);
      AStats[i].Path := Paths[i];
      AStats[i].Kind := TGittanChangeKind(PtrUInt(Paths.Objects[i]) and 15);
      AStats[i].Staged := PtrUInt(Paths.Objects[i]) and flagStaged <> 0;
      AStats[i].Unstaged := PtrUInt(Paths.Objects[i]) and flagUnstaged <> 0;
    end;
    RunDiff(['--numstat', '--no-renames', '-z'], Output);
    SplitNul(Output, Num);
    for Entry in Num do
    begin
      Tab1 := Pos(#9, Entry);
      if Tab1 = 0 then
        Continue;
      Tab2 := Pos(#9, Entry, Tab1 + 1);
      if Tab2 = 0 then
        Continue;
      Path := Copy(Entry, Tab2 + 1, MaxInt);
      if not ByPath.Find(Path, Idx) then
        Continue;
      Idx := PtrInt(ByPath.Objects[Idx]);
      Counts := Copy(Entry, 1, Tab1 - 1);
      if Counts = '-' then
        AStats[Idx].Binary := True
      else
      begin
        AStats[Idx].Added := StrToIntDef(Counts, 0);
        AStats[Idx].Deleted := StrToIntDef(Copy(Entry, Tab1 + 1, Tab2 - Tab1 - 1), 0);
      end;
    end;
    for i := 0 to High(AStats) do
      if AStats[i].Kind = ckUntracked then
      begin
        FileName := FullPath(AStats[i].Path);
        if FileExists(FileName) and not DirectoryExists(FileName) then
          CountNewFile(FileName, AStats[i]);
      end;
  finally
    Dec(FIndexPass);
    if FIndexPass = 0 then
      FIndexAdded := False;
    ByPath.Free;
    Num.Free;
    Paths.Free;
  end;
end;

{ One pass over git for everything the views read, so a watcher thread can
  gather it and hand the record to the main thread, which then only draws.
  The changed files decide Ok; branch and the rest are read regardless and
  filled in as far as git answered, as LoadRepository used to do call by
  call. }
function TGittanRepo.Snapshot(out ASnap: TGittanRepoSnapshot): boolean;
begin
  ASnap := Default(TGittanRepoSnapshot);
  ASnap.Ok := ChangeStats(ASnap.Stats);
  if not ASnap.Ok then
    ASnap.Error := FError;
  ASnap.Branch := Branch(ASnap.Detached);
  ASnap.DefaultBranch := DefaultBranch;
  if not MergeBase(ASnap.DefaultBranch, ASnap.MergeBase) then
    ASnap.MergeBase := '';
  ASnap.HasUpstream := AheadBehind(ASnap.Ahead, ASnap.Behind);
  if not ASnap.Detached then
    ASnap.BehindDefault := BehindDefault(ASnap.Branch, ASnap.DefaultBranch);
  if ASnap.HasUpstream or ASnap.Detached or (RemoteFor('') = '') then
    ASnap.NotOnRemote := -1
  else
    ASnap.NotOnRemote := NotOnRemotes;
  ASnap.Rewritten := ASnap.HasUpstream and not ASnap.Detached and (ASnap.Ahead > 0) and
    (ASnap.Behind > 0) and UpstreamInReflog(ASnap.Branch);
  ASnap.Operation := Operation;
  if ASnap.Operation = 'rebasing' then
    ASnap.RebaseBranch := RebaseBranch;
  if ASnap.Operation = 'bisecting' then
    BisectState(ASnap.Bisect)
  else
    ASnap.Bisect.Left := -1;
  Stashes(ASnap.Stashes);
  if ASnap.Ok and (Length(ASnap.Stats) = 0) then
    RecentCommits(ASnap.Recent);
  Result := ASnap.Ok;
end;

{ symbolic-ref names the branch even before its first commit; it fails
  when HEAD is detached, and the commit id stands in then. }
function TGittanRepo.DefaultBranch: string;
var
  Remote, Name: string;
begin
  Result := '';
  if FRoot = '' then
    Exit;
  Remote := RemoteFor('');
  if Remote = '' then
    Exit;
  if RunGit(FRoot, ['symbolic-ref', '--short', '-q', 'refs/remotes/' + Remote + '/HEAD'],
    Result) then
    Exit(Trim(Result));
  for Name in ['main', 'master'] do
    if HasCommit(Remote + '/' + Name) then
      Exit(Remote + '/' + Name);
  Result := '';
end;

function TGittanRepo.BehindDefault(const ABranch, ADefault: string): integer;
var
  Remote, Name: string;
begin
  Result := 0;
  if (FRoot = '') or (ABranch = '') or (ADefault = '') or (Upstream(ABranch) = ADefault) or
    (SplitRemoteRef(ADefault, Remote, Name) and (Name = ABranch)) then
    Exit;
  Result := CountCommits('HEAD', ADefault);
  if Result < 0 then
    Result := 0;
end;

function TGittanRepo.NotOnRemotes: integer;
var
  Output: string;
begin
  if (FRoot = '') or not RunGit(FRoot, ['rev-list', '--count', 'HEAD', '--not', '--remotes'],
    Output) or not TryStrToInt(Trim(Output), Result) then
    Result := -1;
end;

{ The upstream's commits none of the entries reach are counted: none
  means one of them reaches the tip. The newest entries are enough, and
  keep the command line short. }
function TGittanRepo.UpstreamInReflog(const ABranch: string): boolean;
const
  MaxEntries = 100;
var
  Up, Output: string;
  Args: array of string;
  Hash: string;
begin
  Result := False;
  if (FRoot = '') or (ABranch = '') or
    not RunGit(FRoot, ['rev-parse', '--verify', '-q', ABranch + '@{upstream}'], Up) then
    Exit;
  Up := Trim(Up);
  if (Up = '') or not RunGit(FRoot, ['reflog', 'show', '-n', IntToStr(MaxEntries),
    '--format=%H', 'refs/heads/' + ABranch, '--'], Output) then
    Exit;
  Args := ['rev-list', '--count', Up, '--not'];
  for Hash in Output.Split([#10]) do
    if Trim(Hash) <> '' then
      Insert(Trim(Hash), Args, Length(Args));
  if Length(Args) = 4 then
    Exit;
  Result := RunGit(FRoot, Args, Output) and (Trim(Output) = '0');
end;

function TGittanRepo.MergeBase(const ARef: string; out AHash: string): boolean;
begin
  AHash := '';
  Result := (FRoot <> '') and (ARef <> '') and
    RunGit(FRoot, ['merge-base', ARef, 'HEAD'], AHash);
  AHash := Trim(AHash);
  Result := Result and (AHash <> '');
end;

function TGittanRepo.AheadBehind(out AAhead, ABehind: integer): boolean;
var
  Output: string;
  Tab: integer;
begin
  AAhead := 0;
  ABehind := 0;
  { left-right counts the commits only on the upstream (behind) and only
    on HEAD (ahead), tab-separated. }
  Result := (FRoot <> '') and
    RunGit(FRoot, ['rev-list', '--left-right', '--count', '@{upstream}...HEAD'], Output);
  if not Result then
    Exit;
  Output := Trim(Output);
  Tab := Pos(#9, Output);
  Result := (Tab > 0) and TryStrToInt(Copy(Output, 1, Tab - 1), ABehind) and
    TryStrToInt(Copy(Output, Tab + 1, MaxInt), AAhead);
end;

function TGittanRepo.SyncCommits(AAhead: boolean; out ACommits: TGittanCommitLines;
  AMax: integer): boolean;
var
  Output, Range, Line: string;
  Lines: TStringList;
  i, A, B: integer;
begin
  ACommits := nil;
  if AAhead then
    Range := '@{upstream}..HEAD'
  else
    Range := 'HEAD..@{upstream}';
  Result := (FRoot <> '') and RunGit(FRoot, ['log', '--no-color', '-n', IntToStr(AMax),
    '--format=%H%x1f%h%x1f%s', Range], Output);
  if not Result then
    Exit;
  Lines := TStringList.Create;
  try
    Lines.Text := Output;
    for i := 0 to Lines.Count - 1 do
    begin
      Line := Lines[i];
      A := Pos(#31, Line);
      B := PosEx(#31, Line, A + 1);
      if (A = 0) or (B = 0) then
        Continue;
      SetLength(ACommits, Length(ACommits) + 1);
      ACommits[High(ACommits)].Hash := Copy(Line, 1, A - 1);
      ACommits[High(ACommits)].Short := Copy(Line, A + 1, B - A - 1);
      ACommits[High(ACommits)].Subject := Copy(Line, B + 1, MaxInt);
    end;
  finally
    Lines.Free;
  end;
end;

{ The fields are split at unit separators, the subject last since it
  may hold anything. The commits not pushed are the newest of those on
  HEAD and not on the upstream: at most AMax of them, in the same order
  as the log, so every one of them in the log's first AMax is found.
  Without an upstream they are those on no remote, when there is one. }
function TGittanRepo.RecentCommits(out ACommits: TGittanCommitLines;
  AMax: integer): boolean;
var
  Output, Ahead: string;
  Lines: TStringList;
  Fields: TStringArray;
  i: integer;
  Seconds: int64;
begin
  ACommits := nil;
  Result := (FRoot <> '') and RunGit(FRoot, ['log', '--no-color', '-n', IntToStr(AMax),
    '--format=%H%x1f%h%x1f%an%x1f%ct%x1f%s', 'HEAD'], Output);
  if not Result then
    Exit;
  if not RunGit(FRoot, ['rev-list', '-n', IntToStr(AMax), '@{upstream}..HEAD'], Ahead) then
    if (RemoteFor('') = '') or not RunGit(FRoot, ['rev-list', '-n', IntToStr(AMax), 'HEAD',
      '--not', '--remotes'], Ahead) then
      Ahead := '';
  Lines := TStringList.Create;
  try
    Lines.Text := Output;
    for i := 0 to Lines.Count - 1 do
    begin
      Fields := SplitString(Lines[i], #31);
      if Length(Fields) < 5 then
        Continue;
      SetLength(ACommits, Length(ACommits) + 1);
      with ACommits[High(ACommits)] do
      begin
        Hash := Fields[0];
        Short := Fields[1];
        Author := Fields[2];
        if TryStrToInt64(Fields[3], Seconds) then
          Date := UnixToDateTime(Seconds)
        else
          Date := 0;
        Subject := Fields[4];
        Unpushed := Pos(Hash, Ahead) > 0;
      end;
    end;
  finally
    Lines.Free;
  end;
end;

{ The fields are split at unit separators and the commits at NULs (-z),
  since the body, last, may hold anything, line breaks too. The commits
  not pushed (or not pulled) are read with the same cut, so every one in
  the log is marked. }
function TGittanRepo.GraphCommits(out ACommits: TGittanGraphCommits;
  AMax: integer): boolean;
var
  Output, Ahead, Behind: string;
  Records, Fields: TStringArray;
  i: integer;
  Seconds: int64;
begin
  ACommits := nil;
  { git leaves a bisect's refs out of the decorations unless asked. }
  Result := (FRoot <> '') and RunGit(FRoot, ['log', '--no-color', '--topo-order',
    '--decorate=full', '--decorate-refs=HEAD', '--decorate-refs=refs/heads/',
    '--decorate-refs=refs/remotes/', '--decorate-refs=refs/tags/',
    '--decorate-refs=refs/bisect/', '-z', '-n', IntToStr(AMax),
    '--format=%H%x1f%P%x1f%h%x1f%an%x1f%ct%x1f%D%x1f%s%x1f%b',
    '--branches', '--remotes', '--tags', 'HEAD'], Output);
  if not Result then
    Exit;
  if not RunGit(FRoot, ['rev-list', '-n', IntToStr(AMax), '@{upstream}..HEAD'], Ahead) then
    Ahead := '';
  if not RunGit(FRoot, ['rev-list', '-n', IntToStr(AMax), 'HEAD..@{upstream}'], Behind) then
    Behind := '';
  Records := Output.Split([#0]);
  for i := 0 to High(Records) do
  begin
    Fields := Records[i].Split([#31]);
    if Length(Fields) < 8 then
      Continue;
    SetLength(ACommits, Length(ACommits) + 1);
    with ACommits[High(ACommits)] do
    begin
      Hash := Fields[0];
      if Fields[1] = '' then
        Parents := nil
      else
        Parents := Fields[1].Split([' ']);
      Short := Fields[2];
      Author := Fields[3];
      if TryStrToInt64(Fields[4], Seconds) then
        Date := UnixToDateTime(Seconds)
      else
        Date := 0;
      Refs := ParseGraphRefs(Fields[5]);
      Subject := Fields[6];
      Body := TrimRight(Fields[7]);
      Unpushed := Pos(Hash, Ahead) > 0;
      Unpulled := Pos(Hash, Behind) > 0;
    end;
  end;
  LayoutGraph(ACommits);
end;

{ --literal-pathspecs, so a path with a glob character is the path. A
  folder is not followed: --follow wants one file. }
function TGittanRepo.PathCommits(const APath: string; AHashes: TStrings;
  AMax: integer): boolean;
var
  Output: string;
  Args: array of string;
  n: integer;
begin
  AHashes.Clear;
  if (FRoot = '') or (APath = '') then
    Exit(False);
  SetLength(Args, 12);
  Args[0] := '--literal-pathspecs';
  Args[1] := 'log';
  Args[2] := '--format=%H';
  Args[3] := '-n';
  Args[4] := IntToStr(AMax);
  n := 5;
  if not DirectoryExists(FullPath(APath)) then
  begin
    Args[n] := '--follow';
    Inc(n);
  end;
  Args[n] := '--branches';
  Args[n + 1] := '--remotes';
  Args[n + 2] := '--tags';
  Args[n + 3] := 'HEAD';
  Args[n + 4] := '--';
  Args[n + 5] := APath;
  SetLength(Args, n + 6);
  Result := RunGit(FRoot, Args, Output);
  if Result then
    AHashes.Text := Output;
end;

function TGittanRepo.Branch: string;
var
  Detached: boolean;
begin
  Result := Branch(Detached);
end;

function TGittanRepo.Branch(out ADetached: boolean): string;
begin
  Result := '';
  ADetached := False;
  if FRoot = '' then
    Exit;
  if RunGit(FRoot, ['symbolic-ref', '--short', '-q', 'HEAD'], Result) then
    Result := Trim(Result)
  else
  begin
    ADetached := True;
    if RunGit(FRoot, ['rev-parse', '--short', 'HEAD'], Result) then
      Result := Trim(Result)
    else
      Result := '';
  end;
end;

{ X is the index column, Y the work tree. A "U" in either (or both sides
  added or deleted) is an unmerged file; a deletion on either side wins over
  the rest since the file is gone; a rename or copy keeps its new path. "T"
  (type change) and anything unknown count as modified. }
class function TGittanRepo.ChangeKind(const AStatus: string): TGittanChangeKind;
var
  X, Y: char;
begin
  X := ' ';
  Y := ' ';
  if Length(AStatus) >= 1 then
    X := AStatus[1];
  if Length(AStatus) >= 2 then
    Y := AStatus[2];
  if (X = '?') or (Y = '?') then
    Result := ckUntracked
  else if (X = 'U') or (Y = 'U') or ((X = 'A') and (Y = 'A')) or
    ((X = 'D') and (Y = 'D')) then
    Result := ckConflict
  else if (X = 'D') or (Y = 'D') then
    Result := ckDeleted
  else if X in ['R', 'C'] then
    Result := ckRenamed
  else if (X = 'A') or (Y = 'A') then
    Result := ckAdded
  else
    Result := ckModified;
end;

{ The commit ids of HEAD and the base catch a commit, an amend or a moved
  branch that leaves the status alone; the status catches staging and the
  set of files; the hash of each changed file catches an edit, also one
  that keeps the line count, which the stat alone would miss when it
  falls within the resolution of the modification time. No diff is run:
  hashing the changed files is what one costs in reading, without the
  process and the diff on top. A deleted file is not on disk and adds
  nothing; a directory (a submodule) adds its stat alone. }
{ The neighbours a pattern matches come in the folder's order, so the
  file itself may come after them. A name without a pattern character
  matches itself alone, and its match is taken as it comes: the folder
  may spell it otherwise than git does (in another case, or decomposed
  on macOS), which a comparison would take for a file gone. }
function StatExact(const AFileName: string; out AInfo: TSearchRec): boolean;
var
  Name: string;
begin
  Name := ExtractFileName(AFileName);
  if FindFirst(AFileName, faAnyFile, AInfo) <> 0 then
    Exit(False);
  if LastDelimiter('*?[', Name) = 0 then
    Exit(True);
  repeat
    if AInfo.Name = Name then
      Exit(True);
  until FindNext(AInfo) <> 0;
  FindClose(AInfo);
  Result := False;
end;

function TGittanRepo.Fingerprint: string;
var
  Paths: TStringList;
  Info: TSearchRec;
  FileName, Id, Left, Right: string;

  i: integer;
begin
  Result := '';
  if FRoot = '' then
    Exit;
  Paths := TStringList.Create;
  try
    if not ChangedPaths(Paths) then
      Exit;
    Result := Branch + #10;
    if RunGit(FRoot, ['rev-parse', '--verify', '-q', 'HEAD'], Id) then
      Result := Result + Trim(Id);
    if IsRange then
    begin
      SplitRange(Left, Right);
      if RunGit(FRoot, ['rev-parse', '--verify', '-q', Left + '^{commit}'], Id) then
        Result := Result + ' ' + Trim(Id);
      if RunGit(FRoot, ['rev-parse', '--verify', '-q', Right + '^{commit}'], Id) then
        Result := Result + ' ' + Trim(Id);
    end
    else if (FBase <> '') and RunGit(FRoot, ['rev-parse', '--verify', '-q',
      FBase + '^{commit}'], Id) then
      Result := Result + ' ' + Trim(Id);
    Result := Result + #10;
    { The upstream, which a fetch moves alone and the ahead and behind
      counts follow, and what git is in the middle of, which a bisect
      started on a clean tree changes alone. }
    if RunGit(FRoot, ['rev-parse', '--verify', '-q', '@{upstream}'], Id) then
      Result := Result + 'upstream ' + Trim(Id) + #10;
    Result := Result + 'operation ' + Operation + #10;
    { The stashes, which the status bar counts and lists. }
    if RunGit(FRoot, ['stash', 'list', '--format=%H'], Id) then
      Result := Result + 'stash ' + StringReplace(Trim(Id), #10, ' ', [rfReplaceAll]) + #10;
    for i := 0 to Paths.Count - 1 do
      Result := Result + IntToStr(PtrUInt(Paths.Objects[i])) + ' ' + Paths[i] + #10;
    { Between two commits the files on disk do not matter. }
    if IsRange then
      Exit;
    for i := 0 to Paths.Count - 1 do
    begin
      FileName := FullPath(Paths[i]);
      if not StatExact(FileName, Info) then
        Continue;
      Result := Result + Paths[i] + #9 + FormatDateTime('yyyymmddhhnnsszzz', Info.TimeStamp) + #9 + IntToStr(Info.Size);
      if Info.Attr and faDirectory = 0 then
        try
          Result := Result + #9 + MD5Print(MD5File(FileName));
        except
          { Gone or unreadable between the stat and the read; the stat
            says what it can. }
        end;
      Result := Result + #10;
      FindClose(Info);
    end;
  finally
    Paths.Free;
  end;
end;

{ The hunk header "@@" starts the lines; "\ No newline at end of file"
  notes are dropped. Renames are turned off so a renamed file is a plain new
  file under its new path, which is how the file tree lists it. }
function TGittanRepo.FileChanges(const APath: string; ALines: TStrings): boolean;
var
  Output, Line, FileName, Tracked: string;
  Raw: TStringList;
  InHunk: boolean;
  Marker: char;
begin
  ALines.Clear;
  if FRoot = '' then
    Exit(False);
  Result := RunDiff(['--no-color', '--no-ext-diff', '--no-renames',
    '-U99999999', '--', APath], Output);
  if not Result then
    Exit;
  Raw := TStringList.Create;
  try
    if Output = '' then
    begin
      { Not in HEAD or the index: an untracked file, all of it new. A
        tracked file without a diff (its changes are in whitespace only
        while IgnoreWhitespace is set, or its mode changed) is shown as
        it is, every line unchanged; between two commits as it is in the
        right one. }
      if IsRange then
      begin
        SplitRange(FileName, Tracked);
        if RunGit(FRoot, ['show', Tracked + ':' + APath], Output) then
        begin
          Raw.Text := Output;
          for Line in Raw do
            ALines.Add(' ' + Line);
        end;
        Exit;
      end;
      FileName := FullPath(APath);
      if FileExists(FileName) then
      begin
        if RunGit(FRoot, ['ls-files', '--', APath], Tracked, CompareIndex) and
          (Tracked <> '') then
          Marker := ' '
        else
          Marker := '+';
        Raw.LoadFromFile(FileName);
        for Line in Raw do
          ALines.Add(Marker + Line);
      end;
      Exit;
    end;
    Raw.Text := Output;
    InHunk := False;
    for Line in Raw do
      if not InHunk then
        InHunk := Copy(Line, 1, 2) = '@@'
      else if (Line <> '') and (Line[1] in [' ', '+', '-']) then
        ALines.Add(Line);
  finally
    Raw.Free;
  end;
end;

function TGittanRepo.FileSize(const APath, ARef: string; out ASize: int64): boolean;
var
  Output: string;
  Info: TSearchRec;
begin
  ASize := 0;
  if (FRoot = '') or (APath = '') then
    Exit(False);
  if ARef <> '' then
  begin
    Result := RunGit(FRoot, ['cat-file', '-s', ARef + ':' + APath], Output) and
      TryStrToInt64(Trim(Output), ASize);
    Exit;
  end;
  Result := StatExact(FullPath(APath), Info);
  if Result then
  begin
    ASize := Info.Size;
    FindClose(Info);
  end;
end;

{ ---------------------------------------------------------------------------
  Blame
  --------------------------------------------------------------------------- }
procedure TGittanRepo.DiffSides(out ALeft, ARight: string);
var
  Output: string;
begin
  if IsRange then
  begin
    SplitRange(ALeft, ARight);
    if (Pos('...', FBase) > 0) and RunGit(FRoot, ['merge-base', ALeft, ARight], Output) and
      (Trim(Output) <> '') then
      ALeft := Trim(Output);
  end
  else
  begin
    ALeft := DiffBase;
    ARight := '';
  end;
end;

function TGittanRepo.FileBlob(const APath, ARef: string; out AData: RawByteString): boolean;
var
  Output: string;
begin
  AData := '';
  if (FRoot = '') or (APath = '') then
    Exit(False);
  if ARef <> '' then
  begin
    Result := RunGit(FRoot, ['cat-file', 'blob', ARef + ':' + APath], Output);
    if Result then
      AData := Output;
    Exit;
  end;
  Result := FileExists(FullPath(APath));
  if not Result then
    Exit;
  try
    AData := ReadFileBytes(FullPath(APath));
  except
    AData := '';
    Result := False;
  end;
end;

function TGittanRepo.CommitRange(const AHash: string): string;
begin
  if HasCommit(AHash + '^') then
    Result := AHash + '^..' + AHash
  else
    Result := EmptyTree + '..' + AHash;
end;

{ One call with the fields split at unit separators; the body, last,
  may hold anything, line breaks too. }
function TGittanRepo.CommitDetails(const AHash: string; out ACommit: TGittanCommitLine;
  out ABody: string): boolean;
var
  Output: string;
  Fields: TStringArray;
  Seconds: int64;
begin
  ACommit := Default(TGittanCommitLine);
  ABody := '';
  Result := (FRoot <> '') and (AHash <> '') and RunGit(FRoot, ['log', '-1', '--no-color',
    '--format=%H%x1f%h%x1f%an%x1f%ct%x1f%s%x1f%b', AHash, '--'], Output);
  if not Result then
    Exit;
  Fields := Output.Split([#31], 6);
  if Length(Fields) < 6 then
    Exit(False);
  ACommit.Hash := Fields[0];
  ACommit.Short := Fields[1];
  ACommit.Author := Fields[2];
  if TryStrToInt64(Fields[3], Seconds) then
    ACommit.Date := UnixToDateTime(Seconds);
  ACommit.Subject := Fields[4];
  ABody := Trim(AdjustLineBreaks(Fields[5], tlbsLF));
end;

function TGittanRepo.Blame(const APath, ARef: string; out AOutput: string): boolean;
var
  Args: array of string;
  n: integer;
begin
  AOutput := '';
  if FRoot = '' then
    Exit(False);
  SetLength(Args, 6);
  Args[0] := 'blame';
  Args[1] := '--porcelain';
  n := 2;
  if FIgnoreWhitespace then
  begin
    Args[n] := '-w';
    Inc(n);
  end;
  if ARef <> '' then
  begin
    Args[n] := ARef;
    Inc(n);
  end;
  Args[n] := '--';
  Args[n + 1] := APath;
  SetLength(Args, n + 2);
  Result := RunGit(FRoot, Args, AOutput);
end;

function TGittanRepo.LineHistory(const APath, ARef: string; AFrom, ATo, AMax: integer;
  out AOutput: string): boolean;
var
  Args: TStringArray;

begin
  AOutput := '';
  if FRoot = '' then
    Exit(False);
  Args := nil;
  AddArg(Args, 'log');
  AddArg(Args, '--no-color');
  AddArg(Args, '--no-ext-diff');
  AddArg(Args, '-n');
  AddArg(Args, IntToStr(AMax));
  AddArg(Args, '--format=%x01%H%x1f%an%x1f%at%x1f%s');
  if FIgnoreWhitespace then
    AddArg(Args, '-w');
  if AFrom > 0 then
  begin
    { -L takes no path list: the file is part of the range. }
    AddArg(Args, '-L');
    AddArg(Args, Format('%d,%d:%s', [AFrom, ATo, APath]));
    if ARef <> '' then
      AddArg(Args, ARef);
  end
  else
  begin
    AddArg(Args, '-p');
    AddArg(Args, '--no-renames');
    if ARef <> '' then
      AddArg(Args, ARef);
    AddArg(Args, '--');
    AddArg(Args, APath);
  end;
  Result := RunGit(FRoot, Args, AOutput);
end;

initialization
  GToolPath := MakeToolPath;
  GOldGitExes := TStringList.Create;
  SetGitExe('');

finalization
  GOldGitExes.Free;
end.
