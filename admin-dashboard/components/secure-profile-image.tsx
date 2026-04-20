"use client";

import * as React from "react";
import { api } from "@/lib/api";
import { cn } from "@/lib/utils";
import { User } from "lucide-react";

type SecureProfileImageProps = {
  src?: string | null;
  alt: string;
  className?: string;
  fallbackClassName?: string;
};

function apiPathFromUrl(src: string): string {
  try {
    const url = new URL(src);
    return `${url.pathname}${url.search}`;
  } catch {
    return src;
  }
}

export function SecureProfileImage({
  src,
  alt,
  className,
  fallbackClassName,
}: SecureProfileImageProps) {
  const [objectUrl, setObjectUrl] = React.useState<string | null>(null);

  React.useEffect(() => {
    let active = true;
    let localUrl: string | null = null;

    async function load() {
      if (!src) {
        setObjectUrl(null);
        return;
      }
      const response = await api.get(apiPathFromUrl(src), {
        responseType: "blob",
      });
      if (!active) return;
      localUrl = URL.createObjectURL(response.data);
      setObjectUrl(localUrl);
    }

    load().catch(() => {
      if (active) setObjectUrl(null);
    });

    return () => {
      active = false;
      if (localUrl) URL.revokeObjectURL(localUrl);
    };
  }, [src]);

  if (!objectUrl) {
    return (
      <div
        className={cn(
          "flex items-center justify-center rounded-full bg-muted text-muted-foreground",
          className,
          fallbackClassName
        )}
        aria-label={alt}
      >
        <User className="h-5 w-5" />
      </div>
    );
  }

  return (
    // eslint-disable-next-line @next/next/no-img-element
    <img
      src={objectUrl}
      alt={alt}
      className={cn("rounded-full object-cover", className)}
    />
  );
}
