// 移动端共享小组件：底部 sheet / action sheet / blob 图片 / 迷你队列进度条。

import { useEffect, useState, type ReactNode } from "react";
import { store, useStore } from "../store";
import { queueProgress } from "./logic";

export function BottomSheet({
  title,
  onClose,
  children,
}: {
  title: string;
  onClose: () => void;
  children: ReactNode;
}) {
  return (
    <div className="m-sheet-mask" onClick={onClose}>
      <div className="m-sheet" role="dialog" aria-label={title} onClick={(e) => e.stopPropagation()}>
        <div className="m-sheet-grip" />
        <div className="m-sheet-head">
          <span className="m-sheet-title">{title}</span>
          <button className="m-icon-btn" aria-label="关闭" onClick={onClose}>✕</button>
        </div>
        <div className="m-sheet-body">{children}</div>
      </div>
    </div>
  );
}

export interface SheetAction {
  label: string;
  icon: string;
  onClick: () => void;
  danger?: boolean;
  disabled?: boolean;
}

export function ActionSheet({
  title,
  actions,
  onClose,
}: {
  title?: string;
  actions: SheetAction[];
  onClose: () => void;
}) {
  return (
    <div className="m-sheet-mask" onClick={onClose}>
      <div className="m-action-sheet" role="menu" onClick={(e) => e.stopPropagation()}>
        {title && <div className="m-action-title">{title}</div>}
        {actions.map((action) => (
          <button
            key={action.label}
            className={`m-action-item${action.danger ? " danger" : ""}`}
            disabled={action.disabled}
            onClick={() => { onClose(); action.onClick(); }}
          >
            <span className="m-action-icon">{action.icon}</span>
            {action.label}
          </button>
        ))}
        <button className="m-action-item m-action-cancel" onClick={onClose}>取消</button>
      </div>
    </div>
  );
}

export function BlobImage({ workId, blobId, alt, className }: { workId: string; blobId: string; alt: string; className?: string }) {
  const [url, setUrl] = useState<string | null>(null);
  useEffect(() => {
    let revoke: string | null = null;
    void (async () => {
      const meta = (await store.repo.listBlobs(workId)).find((b) => b.id === blobId);
      if (!meta) return;
      const data = await store.repo.getBlobData(meta.storageKey);
      if (!data) return;
      const objectUrl = URL.createObjectURL(new Blob([data as BlobPart], { type: meta.mime }));
      revoke = objectUrl;
      setUrl(objectUrl);
    })();
    return () => {
      if (revoke) URL.revokeObjectURL(revoke);
    };
  }, [workId, blobId]);
  if (!url) return null;
  return <img className={className} src={url} alt={alt} />;
}

export function MiniQueueProgress() {
  useStore();
  const progress = queueProgress(store.queue.tasksSnapshot);
  if (progress.active === 0) return null;
  return (
    <div className="m-mini-progress" aria-label={`任务进行中 ${progress.active}`}>
      <div className="m-mini-progress-fill" style={{ width: `${Math.round(progress.ratio * 100)}%` }} />
    </div>
  );
}
