// The Gittan object an extension sees (docs/extensions/README.md).
// A member whose permission was not granted is undefined.

declare namespace Gittan {
  type Permission = "data" | "ui" | "timers" | "net" | "exec" | "settings";

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

  const repo: {
    root(o?: RepoOptions): string;
    snapshot(o?: RepoOptions): Snapshot | undefined;
    files(o?: RepoOptions): FileStat[] | undefined;
    diff(path?: string, o?: RepoOptions): string | undefined;
    fileText(path: string, ref?: string, o?: RepoOptions): string | undefined;
    blame(path: string, ref?: string, o?: RepoOptions): string | undefined;
    commit(hash: string, o?: RepoOptions): (Commit & { body: string }) | undefined;
    branches(o?: RepoOptions): { local: string[]; remote: string[] } | undefined;
    tags(o?: RepoOptions): Tag[] | undefined;
    stashes(o?: RepoOptions): Stash[] | undefined;
    remotes(o?: RepoOptions): string[] | undefined;
    recent(limit?: number, o?: RepoOptions): Commit[] | undefined;
  };

  interface RunResult { ok: boolean; status: number; stdout: string; stderr: string }
  /** Needs exec. */
  const git: { run(args: string[], o?: RepoOptions): Promise<RunResult> };
  const exec: { run(cmd: string, args: string[], o?: RepoOptions & { cwd?: string }): Promise<RunResult> };
  const gh: { run(args: string[], o?: RepoOptions): Promise<RunResult> };

  interface FetchResponse { status: number; ok: boolean; url: string; redirected: boolean; headers: { get(n: string): string | null; has(n: string): boolean; keys(): string[] }; text(): Promise<string>; json(): Promise<any> }
  /** Needs net. */
  const net: { fetch(url: string, init?: { method?: string; headers?: Record<string, string>; body?: string; timeout?: number }): Promise<FetchResponse> };

  interface Card { path: string; line: number; side?: "new" | "old"; title?: string; text: string; severity?: string }
  const ui: {
    alert(...text: any[]): void;
    confirm(...text: any[]): boolean;
    prompt(caption: string, text?: string, def?: string): string;
    select(caption: string, text: string, options: string[]): number;
    notify(title: string, detail?: string): void;
    error(title: string, detail?: string): void;
    setStatus(text: string, seconds?: number): void;
    clearStatus(): void;
    openFile(path: string, line?: number): void;
    addCard(card: Card): void;
    clearCards(): void;
  };

  interface CommandContext { repo: string; path: string; line: number; selection: string }
  const commands: {
    register(cmd: { id: string; title: string; where?: ("menu" | "file" | "editor")[] | string; run(ctx: CommandContext): void }): boolean;
    unregister(id: string): boolean;
  };

  type Event = "repo.opened" | "repo.changed" | "commit.before" | "commit.after" | "push.before" | "push.after" | "pull.before" | "pull.after" | "unload";
  type Cancel = false | string | { cancel: boolean; message?: string } | void;
  function on(event: Event, fn: (payload: any) => Cancel): typeof fn;
  function off(event: Event, fn: Function): boolean;

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
