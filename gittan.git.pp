unit gittan.git;

{** Git access for Gittan.

  Runs the git command line tool against a repository and returns its output.
  Nothing is parsed here beyond trimming; the caller decides how to show it. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, gittan.graph;

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
  TGittanRepoSnapshot = record
    Ok: boolean;
    Error: string;
    Stats: TGittanFileStats;
    Branch, DefaultBranch, MergeBase, Operation, RebaseBranch: string;
    HasUpstream: boolean;
    Ahead, Behind: integer;
    {** The newest commits of HEAD, from RecentCommits; read only when
      the work tree is clean, since only the summary of a clean tree
      shows them. }
    Recent: TGittanCommitLines;
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

  {** One opened repository. Open finds the work tree root for a folder, and
    the other calls run inside that root. }
  TGittanRepo = class
  private
    FRoot: string;
    FError: string;
    FBase: string;
    FWholeTree: boolean;
    FTempIndex: string;
    FIgnoreWhitespace: boolean;
    FOnOutput: TGittanOutputEvent;
    function RunGit(const ADir: string; const AArgs: array of string;
      out AOutput: string; const AIndexFile: string = ''): boolean;
    function RunRemote(const AArgs: array of string): boolean;
    function IndexPath: string;
    function CopyIndex(const ATarget: string): boolean;
    function WholeTreeActive: boolean;
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
      where they clash the files are left in conflict. }
    function Switch(const ABranch: string; AMerge: boolean = False): boolean;
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
    {** Stashes every local change, untracked files included, with the
      message AMessage (`git stash push -u`), leaving the work tree as
      HEAD has it. }
    function Stash(const AMessage: string): boolean;
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
      no AAmend outside those operations. AId is the new commit. }
    function Commit(const AMessage: string; APaths: TStrings; AAmend: boolean;
      out AId: string): boolean;
    {** The whole message of HEAD, without its trailing line ends; false
      before the first commit. }
    function HeadMessage(out AMessage: string): boolean;
    {** Whether ARef names a commit in the repository. }
    function HasCommit(const ARef: string): boolean;
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
    {** Resolves the conflict in APath by taking one side whole, as
      `git checkout --ours` or `--theirs` and `git add` do; when that
      side deleted the file it goes (`git rm`). }
    function ResolveConflict(const APath: string; ASide: TGittanConflictSide): boolean;
    {** Marks APath resolved as it is in the work tree (`git add`), or
      deleted when it is gone from there (`git rm`). }
    function MarkResolved(const APath: string): boolean;
    {** Goes on with what git is in the middle of (Operation), once the
      conflicts are resolved: the tracked files' changes are staged
      first (`git add -u`), since they are what the stopped commit
      takes, then `git <merge|rebase|cherry-pick|revert|am> --continue`
      runs without an editor, keeping git's message. Refused while a
      file is still in conflict. A rebase may stop
      again at a later commit, which leaves it rebasing with new
      conflicts and is no failure. }
    function ContinueOperation: boolean;
    {** Leaves out the commit a rebase, cherry-pick, revert or am
      stopped at (`--skip`) and goes on with the rest. }
    function SkipOperation: boolean;
    {** Gives up what git is in the middle of (`--abort`): the branch and
      the work tree go back to how they were before it started. }
    function AbortOperation: boolean;
    {** The message git prepared for the merge, cherry-pick or revert in
      progress (MERGE_MSG in the git directory), its comment lines left
      out; empty when there is none. }
    function MergeMessage: string;
    {** The e-mail the repository commits under (`git config
      user.email`), empty when none is set. }
    function UserEmail: string;
    {** Sets the name and e-mail commits are made under: in the user's
      global git config with AGlobal, else in the repository's own. }
    function SetIdentity(const AName, AEmail: string; AGlobal: boolean): boolean;
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
    {** The remote-tracking branch the repository was cloned from, such as
      origin/main: what the remote's HEAD points at, else main or master
      on the remote RemoteFor gives, else empty. }
    function DefaultBranch: string;
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
      work tree. }
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
    {** A text that changes whenever the branch, the set of changed files
      or the content of a changed file changes: the branch, the commit ids
      of HEAD and Base, the status of every changed file, and the size,
      modification time and content hash of every changed file on disk.
      Empty when nothing is open or git failed. Meant for polling: two
      equal fingerprints mean there is nothing new to show. }
    function Fingerprint: string;
    {** Work tree root, empty when nothing is open. }
    property Root: string read FRoot;
    {** Message from the last git call that failed. }
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

{** Full path of the command AName (without .exe; Windows adds it) on
  ToolSearchPath, or empty when it is not installed. node is found this
  way too, wherever nvm, fnm, Volta or Homebrew put it. }
function FindTool(const AName: string): string;

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

{** The files a refused switch or checkout names in AError, git's
  message, as those it "would overwrite" (local changes, or untracked
  files the branch has), each on a line of its own after a tab; false
  when the message names none, a refusal for another reason. }
function SwitchBlockedFiles(const AError: string; AFiles: TStrings): boolean;

{** Whether the file AFileName is binary by git's own rule: a NUL byte
  in its first 8000 bytes. False for a file that cannot be read. }
function IsBinaryFile(const AFileName: string): boolean;

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
  Process, Pipes, md5, StrUtils, DateUtils;

var
  GToolPath: string;
  GGitExe: string;

function ToolSearchPath: string;
begin
  Result := GToolPath;
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
  Result := GetEnvironmentVariable('PATH');
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
    NvmDir := GetEnvironmentVariable('NVM_DIR');
    if (NvmDir = '') and (Home <> '') then
      NvmDir := Home + '/.nvm';
    FnmDir := GetEnvironmentVariable('FNM_DIR');
    Pnpm := GetEnvironmentVariable('PNPM_HOME');
    if Home <> '' then
    begin
      if FnmDir = '' then
      begin
        {$ifdef darwin}
        More := [Home + '/Library/Application Support/fnm', Home + '/.fnm'];
        {$else}
        More := [GetEnvironmentVariable('XDG_DATA_HOME') + '/fnm',
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

{ Gives P the environment of Gittan without the variables whose names
  (with the equals sign) are in ASkip, so the caller can set those, and
  with ToolSearchPath as its PATH outside Windows (whose variable is
  "Path", and whose PATH is kept as it is). }
procedure CopyEnvironment(P: TProcess; const ASkip: array of string);
var
  Env, Prefix: string;
  i: integer;
  Keep: boolean;
begin
  for i := 1 to GetEnvironmentVariableCount do
  begin
    Env := GetEnvironmentString(i);
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

function RunGitEnv(const ADir: string; const AArgs, AEnv: array of string;
  out AOutput, AError: string; const AIndexFile: string;
  AOnOutput: TGittanOutputEvent): boolean;
var
  P: TProcess;
  Skip: array of string;
  Status, i: integer;
  Got: boolean;
begin
  AOutput := '';
  AError := '';
  P := TProcess.Create(nil);
  try
    P.Executable := GGitExe;
    P.CurrentDirectory := ADir;
    P.Parameters.Add('-c');
    P.Parameters.Add('core.quotepath=false');
    for i := 0 to High(AArgs) do
      P.Parameters.Add(ProcessArg(AArgs[i]));
    SetLength(Skip, 4 + Length(AEnv));
    Skip[0] := 'LC_ALL=';
    Skip[1] := 'GIT_TERMINAL_PROMPT=';
    Skip[2] := 'GIT_INDEX_FILE=';
    Skip[3] := 'GIT_OPTIONAL_LOCKS=';
    for i := 0 to High(AEnv) do
      Skip[4 + i] := Copy(AEnv[i], 1, Pos('=', AEnv[i]));
    CopyEnvironment(P, Skip);
    for i := 0 to High(AEnv) do
      P.Environment.Add(AEnv[i]);
    P.Environment.Add('LC_ALL=C');
    P.Environment.Add('GIT_TERMINAL_PROMPT=0');
    { git status refreshes the index when it may, under index.lock; the
      watcher's poll would then make a commit started meanwhile fail. }
    P.Environment.Add('GIT_OPTIONAL_LOCKS=0');
    if AIndexFile <> '' then
      P.Environment.Add('GIT_INDEX_FILE=' + AIndexFile);
    P.Options := [poNoConsole, poUsePipes];
    { Both pipes are read as git writes, so a long command's progress
      can be shown and neither pipe fills up and blocks git; what is
      left once git has ended is read after it. }
    try
      P.Execute;
    except
      AError := 'Could not run git. Is it installed?';
      Exit(False);
    end;
    repeat
      Got := ReadPipe(P.Output, AOutput, AOnOutput);
      if ReadPipe(P.Stderr, AError, AOnOutput) then
        Got := True;
      if not Got then
        if P.Running then
          Sleep(10)
        else
          Break;
    until False;
    while ReadPipe(P.Output, AOutput, AOnOutput) do;
    while ReadPipe(P.Stderr, AError, AOnOutput) do;
    Status := P.ExitStatus;
  finally
    P.Free;
  end;
  { A failed git's reason is what it wrote, on both streams in their
    order: a pre-push hook's output (husky's "pre-push script failed",
    the tests it ran) is on stdout, git's own "failed to push some refs"
    on stderr, and either alone says little. Progress is read as the
    terminal last showed it. }
  Result := Status = 0;
  if not Result then
  begin
    AError := Trim(ResolveReturns(AError));
    AOutput := ResolveReturns(AOutput);
    if Trim(AOutput) <> '' then
      if AError = '' then
        AError := Trim(AOutput)
      else
        AError := Trim(AOutput) + LineEnding + AError;
    AOutput := '';
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
  P: TProcess;
  Status, i: integer;
begin
  AOutput := '';
  AError := '';
  P := TProcess.Create(nil);
  try
    P.Executable := AExe;
    P.CurrentDirectory := ADir;
    for i := 0 to High(AArgs) do
      P.Parameters.Add(ProcessArg(AArgs[i]));
    CopyEnvironment(P, ['GH_PROMPT_DISABLED=', 'GH_NO_UPDATE_NOTIFIER=']);
    P.Environment.Add('GH_PROMPT_DISABLED=1');
    P.Environment.Add('GH_NO_UPDATE_NOTIFIER=1');
    P.Options := [poNoConsole];
    if P.RunCommandLoop(AOutput, AError, Status) <> 0 then
    begin
      AError := 'Could not run ' + AExe;
      Exit(False);
    end;
  finally
    P.Free;
  end;
  { A failed git's reason is what it wrote, on both streams in their
    order: a pre-push hook's output (husky's "pre-push script failed",
    the tests it ran) is on stdout, git's own "failed to push some refs"
    on stderr, and either alone says little. }
  Result := Status = 0;
  if not Result then
  begin
    AError := Trim(AError);
    if Trim(AOutput) <> '' then
      if AError = '' then
        AError := Trim(AOutput)
      else
        AError := Trim(AOutput) + LineEnding + AError;
    AOutput := '';
  end;
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
begin
  Close;
  if not DirectoryExists(ADir) then
  begin
    FError := Format('Folder not found: %s', [ADir]);
    Exit(False);
  end;
  Result := RunGit(ADir, ['rev-parse', '--show-toplevel'], Top);
  if Result then
    FRoot := Trim(Top)
  { git's message is in English (RunGit sets LC_ALL=C), so the common
    case gets a shorter one; any other failure keeps git's own. }
  else if Pos('not a git repository', FError) > 0 then
    FError := Format('Not a git repository: %s', [ADir]);
end;

procedure TGittanRepo.Close;
begin
  DropTempIndex;
  FRoot := '';
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
  Result := '';
  if (FRoot <> '') and RunGit(FRoot, ['rev-parse', '--absolute-git-dir'], Result) then
    Result := Trim(Result)
  else
    Result := '';
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

{ Copies the repository's index to ATarget; no index (nothing staged
  since init) leaves ATarget absent, which git takes as empty. }
function TGittanRepo.CopyIndex(const ATarget: string): boolean;
var
  Source: string;
  Stream: TMemoryStream;
begin
  Result := True;
  Source := IndexPath;
  if (Source = '') or not FileExists(Source) then
    Exit;
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
  RunGit(FRoot, ['add', '-A', '-N'], Output, FTempIndex);
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
    Tree := Trim(Tree);
    { commit-tree refuses to run without a name and an e-mail, which a
      fresh machine (or a CI runner) does not have; the snapshot is never
      shared, so it gets an identity of its own. }
    if RunGit(FRoot, ['rev-parse', '--verify', '-q', 'HEAD'], Head) then
      Result := RunGit(FRoot, ['-c', 'user.name=Gittan', '-c',
        'user.email=gittan@localhost', 'commit-tree', Tree, '-p', Trim(Head),
        '-m', 'Gittan snapshot'], AId)
    else
      Result := RunGit(FRoot, ['-c', 'user.name=Gittan', '-c',
        'user.email=gittan@localhost', 'commit-tree', Tree, '-m',
        'Gittan snapshot'], AId);
    AId := Trim(AId);
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
  most recently committed first, to AList. A symbolic ref such as
  origin/HEAD (short name "origin") is skipped: it only points at
  another one in the list. }
function TGittanRepo.RefGroup(const AGroup: string; AList: TStrings): boolean;
var
  Output, Line, Name: string;
  Raw: TStringList;
  Tab: integer;
begin
  Result := RunGit(FRoot, ['for-each-ref', '--format=%(refname:short)%09%(symref)',
    '--sort=-committerdate', AGroup], Output);
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

function TGittanRepo.Switch(const ABranch: string; AMerge: boolean): boolean;
var
  Output: string;
begin
  if (FRoot = '') or (ABranch = '') then
    Exit(False);
  if AMerge then
    Result := RunGit(FRoot, ['switch', '--merge', ABranch], Output)
  else
    Result := RunGit(FRoot, ['switch', ABranch], Output);
end;

function TGittanRepo.RevertFiles(APaths, ASaved: TStrings): boolean;
var
  Output, Entry, Path, Id, ListFile: string;
  Fields, Chosen, Paths, InHead, Restore, Remove: TStringList;
  i: integer;

  function NulList(AList: TStrings): string;
  var
    j: integer;
  begin
    Result := '';
    for j := 0 to AList.Count - 1 do
      Result := Result + AList[j] + #0;
  end;

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

function TGittanRepo.Stash(const AMessage: string): boolean;
var
  Output: string;
begin
  Result := (FRoot <> '') and RunGit(FRoot, ['stash', 'push', '-u', '-m', AMessage], Output);
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
  AAmend: boolean; out AId: string): boolean;
var
  Output, Entry, Path, XY, Op, Err, SpecFile, AddFile, MsgFile: string;
  Fields, Chosen, Spec, Added: TStringList;
  Args: array of string;
  Whole: boolean;
  i: integer;

  procedure Arg(const S: string);
  begin
    SetLength(Args, Length(Args) + 1);
    Args[High(Args)] := S;
  end;

  function NulList(AList: TStrings): string;
  var
    j: integer;
  begin
    Result := '';
    for j := 0 to AList.Count - 1 do
      Result := Result + AList[j] + #0;
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
  SpecFile := GetTempFileName(GetTempDir, 'gittan-paths-');
  AddFile := GetTempFileName(GetTempDir, 'gittan-add-');
  MsgFile := GetTempFileName(GetTempDir, 'gittan-message-');
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
        Added.Add(Path);
    end;

    if Added.Count > 0 then
    begin
      WriteBytes(AddFile, NulList(Added));
      if not RunGit(FRoot, ['--literal-pathspecs', 'add', '-A',
        '--pathspec-from-file=' + AddFile, '--pathspec-file-nul'], Output) then
        Exit(False);
    end;
    WriteBytes(MsgFile, AMessage);
    Args := nil;
    Arg('--literal-pathspecs');
    Arg('commit');
    Arg('-q');
    Arg('-F');
    Arg(MsgFile);
    if AAmend then
      Arg('--amend');
    if not Whole then
    begin
      Arg('--only');
      if Spec.Count > 0 then
      begin
        WriteBytes(SpecFile, NulList(Spec));
        Arg('--pathspec-from-file=' + SpecFile);
        Arg('--pathspec-file-nul');
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
    DeleteFile(SpecFile);
    DeleteFile(AddFile);
    DeleteFile(MsgFile);
  end;
end;

{ ---------------------------------------------------------------------------
  Remotes
  ---------------------------------------------------------------------------
  Fetch, pull and push go to the network: they run with
  RemoteEnvironment, and their output on stderr (progress, "To ...") is
  no failure. }
function TGittanRepo.RemoteEnvironment: TStringArray;
var
  Output: string;
begin
  Result := nil;
  if (GetEnvironmentVariable('GIT_SSH_COMMAND') <> '') or
    (GetEnvironmentVariable('GIT_SSH') <> '') then
    Exit;
  if (FRoot <> '') and RunGit(FRoot, ['config', 'core.sshCommand'], Output) and
    (Trim(Output) <> '') then
    Exit;
  SetLength(Result, 1);
  Result[0] := 'GIT_SSH_COMMAND=ssh -o BatchMode=yes';
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
  Result := RunRemote(['push', Remote, '--delete', OnRemote]);
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
    Exit;
  FError := Err;
  { Stopped at a later commit with conflicts of its own: going on worked. }
  Result := (Operation <> '') and RunGit(FRoot, ['ls-files', '-u'], Output) and
    (Trim(Output) <> '');
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
end;

function TGittanRepo.MergeMessage: string;
var
  Dir, Line: string;
  Lines: TStringList;
begin
  Result := '';
  Dir := GitDir;
  if (Dir = '') or not FileExists(IncludeTrailingPathDelimiter(Dir) + 'MERGE_MSG') then
    Exit;
  Lines := TStringList.Create;
  try
    Lines.LoadFromFile(IncludeTrailingPathDelimiter(Dir) + 'MERGE_MSG');
    for Line in Lines do
      if (Line = '') or (Line[1] <> '#') then
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
  SetLength(Args, 10 + 2 * AWords.Count);
  Args[0] := 'grep';
  Args[1] := '-z';
  Args[2] := '-n';
  Args[3] := '-w';
  Args[4] := '-F';
  Args[5] := '-I';
  Args[6] := '--untracked';
  n := 7;
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
  Fields: TStringList;
  i: integer;
begin
  AList.Clear;
  if FRoot = '' then
    Exit(False);
  Fields := TStringList.Create;
  try
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
  line. }
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
  Paths, Num: TStringList;
  Output, Entry, Path, Counts, FileName: string;
  i, Tab1, Tab2, Idx: integer;
begin
  AStats := nil;
  Paths := TStringList.Create;
  Num := TStringList.Create;
  try
    Paths.CaseSensitive := True;
    Result := ChangedPaths(Paths);
    if not Result then
      Exit;
    SetLength(AStats, Paths.Count);
    for i := 0 to Paths.Count - 1 do
    begin
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
      Idx := Paths.IndexOf(Path);
      if Idx < 0 then
        Continue;
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
  ASnap.Branch := Branch;
  ASnap.DefaultBranch := DefaultBranch;
  if not MergeBase(ASnap.DefaultBranch, ASnap.MergeBase) then
    ASnap.MergeBase := '';
  ASnap.HasUpstream := AheadBehind(ASnap.Ahead, ASnap.Behind);
  ASnap.Operation := Operation;
  if ASnap.Operation = 'rebasing' then
    ASnap.RebaseBranch := RebaseBranch;
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
  as the log, so every one of them in the log's first AMax is found. }
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

{ The fields are split at unit separators, the subject last since it
  may hold anything. The commits not pushed (or not pulled) are read
  with the same cut, so every one in the log is marked. }
function TGittanRepo.GraphCommits(out ACommits: TGittanGraphCommits;
  AMax: integer): boolean;
var
  Output, Ahead, Behind: string;
  Lines: TStringList;
  Fields: TStringArray;
  i: integer;
  Seconds: int64;
begin
  ACommits := nil;
  Result := (FRoot <> '') and RunGit(FRoot, ['log', '--no-color', '--topo-order',
    '--decorate=full', '-n', IntToStr(AMax),
    '--format=%H%x1f%P%x1f%h%x1f%an%x1f%ct%x1f%D%x1f%s',
    '--branches', '--remotes', '--tags', 'HEAD'], Output);
  if not Result then
    Exit;
  if not RunGit(FRoot, ['rev-list', '-n', IntToStr(AMax), '@{upstream}..HEAD'], Ahead) then
    Ahead := '';
  if not RunGit(FRoot, ['rev-list', '-n', IntToStr(AMax), 'HEAD..@{upstream}'], Behind) then
    Behind := '';
  Lines := TStringList.Create;
  try
    Lines.Text := Output;
    for i := 0 to Lines.Count - 1 do
    begin
      Fields := SplitString(Lines[i], #31);
      if Length(Fields) < 7 then
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
        Unpushed := Pos(Hash, Ahead) > 0;
        Unpulled := Pos(Hash, Behind) > 0;
      end;
    end;
  finally
    Lines.Free;
  end;
  LayoutGraph(ACommits);
end;

function TGittanRepo.Branch: string;
begin
  Result := '';
  if FRoot = '' then
    Exit;
  if RunGit(FRoot, ['symbolic-ref', '--short', '-q', 'HEAD'], Result) then
    Result := Trim(Result)
  else if RunGit(FRoot, ['rev-parse', '--short', 'HEAD'], Result) then
    Result := Trim(Result)
  else
    Result := '';
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
    for i := 0 to Paths.Count - 1 do
      Result := Result + IntToStr(PtrUInt(Paths.Objects[i])) + ' ' + Paths[i] + #10;
    { Between two commits the files on disk do not matter. }
    if IsRange then
      Exit;
    for i := 0 to Paths.Count - 1 do
    begin
      FileName := FullPath(Paths[i]);
      if FindFirst(FileName, faAnyFile, Info) <> 0 then
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
  Result := FindFirst(FullPath(APath), faAnyFile, Info) = 0;
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
begin
  if IsRange then
    SplitRange(ALeft, ARight)
  else
  begin
    ALeft := DiffBase;
    ARight := '';
  end;
end;

function TGittanRepo.FileBlob(const APath, ARef: string; out AData: RawByteString): boolean;
var
  Output: string;
  Stream: TFileStream;
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
    Stream := TFileStream.Create(FullPath(APath), fmOpenRead or fmShareDenyNone);
    try
      SetLength(AData, Stream.Size);
      if Length(AData) > 0 then
        Stream.ReadBuffer(AData[1], Length(AData));
    finally
      Stream.Free;
    end;
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
  Args: array of string;

  procedure Add(const AArg: string);
  begin
    SetLength(Args, Length(Args) + 1);
    Args[High(Args)] := AArg;
  end;

begin
  AOutput := '';
  if FRoot = '' then
    Exit(False);
  Args := nil;
  Add('log');
  Add('--no-color');
  Add('--no-ext-diff');
  Add('-n');
  Add(IntToStr(AMax));
  Add('--format=%x01%H%x1f%an%x1f%at%x1f%s');
  if FIgnoreWhitespace then
    Add('-w');
  if AFrom > 0 then
  begin
    { -L takes no path list: the file is part of the range. }
    Add('-L');
    Add(Format('%d,%d:%s', [AFrom, ATo, APath]));
    if ARef <> '' then
      Add(ARef);
  end
  else
  begin
    Add('-p');
    Add('--no-renames');
    if ARef <> '' then
      Add(ARef);
    Add('--');
    Add(APath);
  end;
  Result := RunGit(FRoot, Args, AOutput);
end;

initialization
  GToolPath := MakeToolPath;
  GGitExe := FindTool('git');
  if GGitExe = '' then
    GGitExe := 'git';
end.
