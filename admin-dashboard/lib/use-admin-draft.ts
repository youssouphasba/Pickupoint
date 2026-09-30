"use client";

import * as React from "react";

export function useAdminDraft<T>(serverValue: T | null) {
  const [draft, setValue] = React.useState<T | null>(serverValue);
  const dirty = React.useRef(false);

  React.useEffect(() => {
    if (!dirty.current) setValue(serverValue);
  }, [serverValue]);

  const setDraft = React.useCallback((value: React.SetStateAction<T | null>) => {
    dirty.current = true;
    setValue(value);
  }, []);

  const acceptSaved = React.useCallback((value: T) => {
    dirty.current = false;
    setValue(value);
  }, []);

  return { draft, setDraft, acceptSaved };
}
