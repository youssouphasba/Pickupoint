import { Inbox } from "lucide-react";

export function EmptyState({ message }: { message: string }) {
  return (
    <div className="flex min-h-32 items-center gap-3 rounded-lg border border-dashed border-slate-300 bg-slate-50 px-4 py-5 text-left text-sm font-medium text-slate-600">
      <span className="flex h-10 w-10 shrink-0 items-center justify-center rounded-full bg-white text-slate-400 shadow-sm">
        <Inbox className="h-5 w-5" />
      </span>
      <span>{message}</span>
    </div>
  );
}
