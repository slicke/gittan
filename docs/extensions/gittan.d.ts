// The Gittan object an extension sees (docs/extensions/README.md).
// A member whose permission was not granted is undefined.

declare namespace Gittan {
  type Permission = "data" | "ui" | "timers" | "net" | "exec" | "settings" | "forge";

  const api: { version: string; extensionId: string; permissions: Permission[] };
  const permissions: { has(name: Permission): boolean; require(name: Permission): true };

  interface RepoOptions { repo?: string }
  interface FileStat { path: string; kind: "modified" | "added" | "deleted" | "renamed" | "untracked" | "conflict"; added: number; deleted: number; binary: boolean; staged: boolean; unstaged: boolean }
  interface Commit { hash: string; short: string; subject: string; author: string; date: string | null; unpushed: boolean }
  interface Stash { id: string; index: number; branch: string; message: string; time: number; untracked: boolean }
  interface Tag { name: string; commit: string; annotated: boolean; time: number; subject: string }
  interface Snapshot {
    ok: boolean; error: string; branch: string; defaultBranch: string; detached: boolean; head: string;
    hasUpstream: boolean; ahead: number; behind: number; operation: string; rebaseBranch: string; rewritten: boolean;
    files: FileStat[]; stashes: Stash[]; recent: Commit[]; refs: string[];
  }

  /** Needs data. */
  const repo: {
    root(o?: RepoOptions): string;
    snapshot(o?: RepoOptions): Snapshot | undefined;
    files(o?: RepoOptions): FileStat[] | undefined;
    diff(path?: string, o?: RepoOptions): string | undefined;
    fileText(path: string, ref?: string, o?: RepoOptions): string | undefined;
    blame(path: string, ref?: string, o?: RepoOptions): string | undefined;
    /** diff, blame and fileText run by git in a thread of their own, for a long file that would hold the window. */
    diffAsync(path?: string, o?: RepoOptions): Promise<string | undefined>;
    blameAsync(path: string, ref?: string, o?: RepoOptions): Promise<string | undefined>;
    fileTextAsync(path: string, ref?: string, o?: RepoOptions): Promise<string | undefined>;
    commit(hash: string, o?: RepoOptions): (Commit & { body: string }) | undefined;
    branches(o?: RepoOptions): { local: string[]; remote: string[] } | undefined;
    tags(o?: RepoOptions): Tag[] | undefined;
    stashes(o?: RepoOptions): Stash[] | undefined;
    remotes(o?: RepoOptions): string[] | undefined;
    recent(limit?: number, o?: RepoOptions): Commit[] | undefined;
  };

  /** status is the program's exit code, 128 + the signal when one ended it, -1 when it did not start. */
  interface RunResult { ok: boolean; status: number; stdout: string; stderr: string }
  /** Needs exec. input goes to the program's standard input. */
  const git: { run(args: string[], o?: RepoOptions & { input?: string }): Promise<RunResult> };
  const exec: { run(cmd: string, args: string[], o?: RepoOptions & { cwd?: string; input?: string }): Promise<RunResult> };

  /** The forge the call acts on: the repository's (repo), the one named (forge), else the GitHub view's while it is shown, else the shown repository's. */
  interface ForgeOptions extends RepoOptions { forge?: string; input?: string }
  interface ForgeInfo { name: string; cli: string; ready: boolean; reason?: string; accounts: { host: string; login: string; active: boolean }[] }
  /** Needs forge. cli runs the forge's own tool (gh for GitHub) with your account; rejected on no forge or when it cannot run. */
  const forge: { info(o?: ForgeOptions): ForgeInfo | null; cli(args: string[], o?: ForgeOptions): Promise<RunResult> };
  /** Needs forge. Each forge by its tool: run is rejected where the forge is another. */
  const forges: { gh: { name: "GitHub"; run(args: string[], o?: ForgeOptions): Promise<RunResult> }; [cli: string]: { name: string; run(args: string[], o?: ForgeOptions): Promise<RunResult> } };

  interface FetchResponse { status: number; ok: boolean; url: string; redirected: boolean; headers: { get(n: string): string | null; has(n: string): boolean; keys(): string[] }; text(): Promise<string>; json(): Promise<any> }
  /** Needs net. */
  const net: { fetch(url: string, init?: { method?: string; headers?: Record<string, string>; body?: string; timeout?: number }): Promise<FetchResponse> };

  /** repo: the repository it is for (a command's ctx.repo), else the shown one. */
  interface Card { repo?: string; path: string; line: number; side?: "new" | "old"; title?: string; text: string; severity?: string }
  interface Message { text?: string; title?: string; kind?: "info" | "warn" | "warning" | "error" | "question"; buttons?: string[]; default?: number; cancel?: number }
  const ui: {
    alert(...text: any[]): void;
    /** The index of the button pressed, -1 when closed without one. Up to six buttons; OK alone without any. */
    message(m: Message | string): number;
    confirm(...text: any[]): boolean;
    prompt(caption: string, text?: string, def?: string): string;
    select(caption: string, text: string, options: string[]): number;
    notify(title: string, detail?: string): void;
    error(title: string, detail?: string): void;
    setStatus(text: string, seconds?: number): void;
    clearStatus(): void;
    openFile(path: string, line?: number): void;
    addCard(card: Card): void;
    clearCards(o?: RepoOptions): void;
  };

  /** A command of a repository gets CommandContext; one of the GitHub view (where "forge") gets ForgeContext, and one in both either. */
  interface CommandContext { repo: string; path: string; line: number; selection: string }
  interface ForgeContext { forge: string; login: string }
  type RepoWhere = "menu" | "file" | "editor";
  const commands: {
    register(cmd: { id: string; title: string; where: "forge" | ["forge"]; run(ctx: ForgeContext): void }): boolean;
    register(cmd: { id: string; title: string; where?: RepoWhere | RepoWhere[]; run(ctx: CommandContext): void }): boolean;
    register(cmd: { id: string; title: string; where?: (RepoWhere | "forge")[] | string; run(ctx: CommandContext | ForgeContext): void }): boolean;
    unregister(id: string): boolean;
  };

  type Severity = "info" | "ok" | "warn" | "error";
  interface TabRow { title: string; detail?: string; tag?: string; severity?: Severity; url?: string; repo?: string; actions?: { id: string; title?: string }[]; [more: string]: any }
  interface TabModel { text?: string; rows?: (TabRow | string)[]; empty?: string }
  /** A tab of the GitHub view, after Batch: render as it is shown and on Refresh; an action returns a model, or nothing to render again. */
  const forgeTabs: {
    register(tab: { id: string; title: string; description?: string; render(ctx: ForgeContext): TabModel | TabRow[] | string | Promise<TabModel | TabRow[] | string>; action?(id: string, row: TabRow, ctx: ForgeContext): any }): boolean;
    unregister(id: string): boolean;
  };
  interface BatchContext extends ForgeContext { repo: string; name: string; forge: string }
  /** null, undefined, false, true, 0 and "" say nothing; url is an http(s) address. Not answered within 300 s is an error. */
  type BatchResult = string | number | boolean | { text: string; severity?: Severity; url?: string } | null | undefined;
  /** An operation of the Batch tab, run once for each repository picked, in turn. */
  const batch: {
    register(op: { id: string; title: string; description?: string; run(ctx: BatchContext): BatchResult | Promise<BatchResult> }): boolean;
    unregister(id: string): boolean;
  };

  type Event = "repo.opened" | "repo.changed" | "commit.before" | "commit.after" | "push.before" | "push.after" | "pull.before" | "pull.after" | "unload";
  type Cancel = false | string | { cancel: boolean; message?: string } | void;
  function on(event: Event, fn: (payload: any) => Cancel): typeof fn;
  function off(event: Event, fn: Function): boolean;

  /** The extension's own values, kept in settings.json. A key tells case, is not empty and has no control character; get, set and define throw on another. */
  const storage: {
    get(key: string): string | null;
    set(key: string, value: string): void;
    remove(key: string): void;
    getJSON<T>(key: string, dflt?: T): T | null;
    setJSON(key: string, value: any): void;
  };

  interface SettingDef { key: string; type?: "string" | "bool" | "number" | "choice"; label?: string; default?: string; options?: string[]; note?: string }
  const settings: { define(defs: SettingDef[]): void; get(key: string): string | null };

  /** Needs settings. */
  const app: { setting(name: "GitPath" | "EditorCommand" | "TerminalCommand" | "AIEnabled" | "HostingEnabled" | "ExtensionsDir" | "GitHubCli"): string | boolean | null };

  function alert(...text: any[]): void;
  function log(text: string): void;
}

declare function alert(...text: any[]): void;
