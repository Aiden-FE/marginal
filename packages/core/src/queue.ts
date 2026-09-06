// 任务队列（spec §4.6）：并发可配、暂停/恢复/取消、单项重试 ≤3 次指数退避、
// 预算上限触顶暂停、每完成一项 checkpoint（断点续跑是一等公民，research/002）。

export type TaskState = "pending" | "running" | "done" | "failed" | "cancelled";

export interface QueueTask<T = void> {
  id: string;
  label: string;
  state: TaskState;
  attempts: number;
  error?: string;
  run: () => Promise<T>;
}

export interface QueueEvents {
  onCheckpoint?: () => void; // 每完成一项（调用方持久化进度）
  onBudgetExceeded?: () => void;
  onTaskDone?: (task: QueueTask<any>) => void;
  onTaskFailed?: (task: QueueTask<any>) => void;
}

export class TaskQueue {
  private tasks: QueueTask<any>[] = [];
  private running = 0;
  private _paused = false;
  private _cancelledIds = new Set<string>();
  private budgetUsed = 0;

  constructor(
    private concurrency = 2,
    private maxAttempts = 3,
    private events: QueueEvents = {},
  ) {}

  add<T>(label: string, run: () => Promise<T>): QueueTask<T> {
    const task: QueueTask<T> = { id: crypto.randomUUID(), label, state: "pending", attempts: 0, run };
    this.tasks.push(task);
    void this.drain();
    return task;
  }

  get tasksSnapshot(): QueueTask[] {
    return this.tasks.map((t) => ({ ...t }));
  }

  get pendingCount(): number {
    return this.tasks.filter((t) => t.state === "pending" || t.state === "running").length;
  }

  get budgetSpent(): number {
    return this.budgetUsed;
  }

  pause(): void {
    this._paused = true;
  }

  resume(): void {
    this._paused = false;
    void this.drain();
  }

  cancelAll(): void {
    for (const t of this.tasks) {
      if (t.state === "pending") {
        t.state = "cancelled";
        this._cancelledIds.add(t.id);
      }
    }
  }

  setBudgetLimit(limit: number | null): void {
    this.budgetLimit = limit;
  }

  private budgetLimit: number | null = null;

  private async drain(): Promise<void> {
    if (this._paused) return;
    if (this.budgetLimit !== null && this.budgetUsed >= this.budgetLimit) {
      this._paused = true;
      this.events.onBudgetExceeded?.();
      return;
    }
    while (this.running < this.concurrency) {
      const next = this.tasks.find((t) => t.state === "pending" && !this._cancelledIds.has(t.id));
      if (!next) return;
      next.state = "running";
      this.running++;
      void this.exec(next).finally(() => {
        this.running--;
        this.budgetUsed++;
        void this.drain();
      });
    }
  }

  private async exec(task: QueueTask<any>): Promise<void> {
    while (task.attempts < this.maxAttempts) {
      try {
        task.attempts++;
        await task.run();
        task.state = "done";
        this.events.onTaskDone?.(task);
        this.events.onCheckpoint?.();
        return;
      } catch (err) {
        task.error = err instanceof Error ? err.message : String(err);
        if (this._cancelledIds.has(task.id)) break;
        if (task.attempts >= this.maxAttempts) break;
        await sleep(Math.min(30_000, 2 ** task.attempts * 1000)); // 指数退避
        if (this._paused) {
          task.state = "pending"; // 暂停后回队
          return;
        }
      }
    }
    if (this._cancelledIds.has(task.id)) {
      task.state = "cancelled";
    } else {
      task.state = "failed";
      this.events.onTaskFailed?.(task);
      this.events.onCheckpoint?.();
    }
  }
}

function sleep(ms: number): Promise<void> {
  return new Promise((r) => setTimeout(r, ms));
}
