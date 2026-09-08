// 锚点插图渲染组件：桌面阅读器与移动阅读器共用（段落后渲染，天然滚动流）。

import { useEffect, useState } from "react";
import type { Anchor } from "@marginal/core";
import { store } from "../store";

export function IllustrationImage({ anchor, workId }: { anchor: Anchor; workId: string }) {
  const [url, setUrl] = useState<string | null>(null);
  useEffect(() => {
    let revoke: string | null = null;
    void (async () => {
      const blobs = await store.repo.listBlobs(workId);
      const illus = (await store.repo.listIllustrations(workId)).find((i) => i.id === anchor.targetId);
      if (!illus) return;
      const meta = blobs.find((b) => b.id === illus.blobId);
      if (!meta) return;
      const data = await store.repo.getBlobData(meta.storageKey);
      if (!data) return;
      const url2 = URL.createObjectURL(new Blob([data as BlobPart], { type: meta.mime }));
      revoke = url2;
      setUrl(url2);
    })();
    return () => {
      if (revoke) URL.revokeObjectURL(revoke);
    };
  }, [anchor.targetId, workId]);
  if (!url) return null;
  return <img className="illus" src={url} alt="段落插图" />;
}
