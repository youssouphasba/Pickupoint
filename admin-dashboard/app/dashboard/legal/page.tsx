"use client";

import * as React from "react";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { fetchLegalDoc, updateLegalDoc, fetchLegalReadingStats } from "@/lib/api";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Textarea } from "@/components/ui/textarea";
import { useToast } from "@/components/ui/toaster";
import { Loader2, Pencil, Save, X, Search, CheckCircle2, Circle } from "lucide-react";

const DOC_TYPES = [
  { key: "privacy_policy", label: "Politique de confidentialité" },
  { key: "cgu", label: "Conditions générales" },
  { key: "mentions_legales", label: "Mentions légales" },
] as const;

function legalDisplayText(value?: string | null) {
  return (value ?? "")
    .replace(/<br\s*\/?>/gi, "\n")
    .replace(/<\/p>/gi, "\n\n")
    .replace(/<[^>]+>/g, "")
    .replace(/&nbsp;/g, " ")
    .replace(/&amp;/g, "&")
    .replace(/&lt;/g, "<")
    .replace(/&gt;/g, ">")
    .trim();
}

export default function LegalPage() {
  const [activeTab, setActiveTab] = React.useState<string>("privacy_policy");

  return (
    <div className="space-y-5 p-4 sm:p-6 lg:p-8">
      <div>
        <h1 className="text-2xl font-bold">Juridique</h1>
        <p className="text-sm text-muted-foreground">
          Gérer la politique de confidentialité et les conditions générales.
        </p>
      </div>

      <div className="flex gap-2">
        {DOC_TYPES.map((d) => (
          <button
            key={d.key}
            onClick={() => setActiveTab(d.key)}
            className={`rounded-full border px-3 py-1.5 text-sm transition-colors ${
              activeTab === d.key
                ? "border-primary bg-primary text-primary-foreground"
                : "border-input bg-background hover:bg-accent"
            }`}
          >
            {d.label}
          </button>
        ))}
      </div>

      <LegalDocEditor docType={activeTab} key={activeTab} />
    </div>
  );
}

function LegalDocEditor({ docType }: { docType: string }) {
  const qc = useQueryClient();
  const { toast } = useToast();
  const [editing, setEditing] = React.useState(false);
  const [title, setTitle] = React.useState("");
  const [content, setContent] = React.useState("");
  const [readerSearch, setReaderSearch] = React.useState("");

  const { data, isLoading, isError } = useQuery({
    queryKey: ["legal", docType],
    queryFn: () => fetchLegalDoc(docType),
  });

  React.useEffect(() => {
    if (data) {
      setTitle(data.title ?? "");
      setContent(data.content ?? "");
    }
  }, [data]);

  const saveMut = useMutation({
    mutationFn: () => updateLegalDoc(docType, { title, content }),
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ["legal", docType] });
      setEditing(false);
      toast("Document juridique sauvegardé.");
    },
  });

  const reading = useQuery({
    queryKey: ["legal-reading", docType, readerSearch],
    queryFn: () => fetchLegalReadingStats(docType, readerSearch),
    refetchInterval: 60_000,
  });

  if (isLoading) {
    return (
      <div className="flex h-40 items-center justify-center">
        <Loader2 className="h-5 w-5 animate-spin text-muted-foreground" />
      </div>
    );
  }

  if (isError) {
    return (
      <div className="rounded-md border border-red-200 bg-red-50 p-4 text-sm text-red-700">
        Erreur de chargement.
      </div>
    );
  }

  return (
    <Card>
      <CardHeader className="flex flex-row items-center justify-between">
        <CardTitle className="text-base">{data?.title ?? docType}</CardTitle>
        {!editing ? (
          <Button size="sm" variant="outline" onClick={() => setEditing(true)}>
            <Pencil className="h-4 w-4" />
            Modifier
          </Button>
        ) : (
          <div className="flex gap-2">
            <Button
              size="sm"
              variant="outline"
              onClick={() => {
                setEditing(false);
                setTitle(data?.title ?? "");
                setContent(data?.content ?? "");
              }}
            >
              <X className="h-4 w-4" />
              Annuler
            </Button>
            <Button
              size="sm"
              onClick={() => saveMut.mutate()}
              disabled={saveMut.isPending}
            >
              {saveMut.isPending ? (
                <Loader2 className="h-4 w-4 animate-spin" />
              ) : (
                <Save className="h-4 w-4" />
              )}
              Sauvegarder
            </Button>
          </div>
        )}
      </CardHeader>
      <CardContent>
        {editing ? (
          <div className="space-y-4">
            <div>
              <label className="mb-1.5 block text-sm font-medium">Titre</label>
              <Input value={title} onChange={(e) => setTitle(e.target.value)} />
            </div>
            <div>
              <label className="mb-1.5 block text-sm font-medium">Contenu</label>
              <Textarea
                value={content}
                onChange={(e) => setContent(e.target.value)}
                rows={20}
                className="font-mono text-xs"
              />
            </div>
            {saveMut.isError && (
              <div className="rounded-md border border-red-200 bg-red-50 px-3 py-2 text-sm text-red-700">
                Erreur de sauvegarde.
              </div>
            )}
          </div>
        ) : (
          <div className="prose prose-sm max-w-none">
            {data?.content ? (
              <div className="whitespace-pre-wrap">{legalDisplayText(data.content)}</div>
            ) : (
              <p className="text-muted-foreground">Aucun contenu.</p>
            )}
          </div>
        )}
      </CardContent>
      <CardContent className="border-t">
        <div className="mb-3 flex flex-wrap items-center justify-between gap-3">
          <div>
            <h2 className="text-base font-semibold">Suivi de lecture</h2>
            <p className="text-sm text-muted-foreground">Les utilisateurs sont informés, mais aucune nouvelle acceptation n’est demandée.</p>
          </div>
          <div className="flex items-center gap-2 text-sm"><span className="text-green-700">{reading.data?.read_count ?? 0} lus</span><span className="text-amber-700">{reading.data?.unread_count ?? 0} non lus</span></div>
        </div>
        <div className="relative mb-3 max-w-md"><Search className="absolute left-3 top-2.5 h-4 w-4 text-muted-foreground" /><Input value={readerSearch} onChange={(event) => setReaderSearch(event.target.value)} placeholder="Rechercher un utilisateur…" className="pl-9" /></div>
        {reading.isLoading ? <Loader2 className="h-4 w-4 animate-spin" /> : <div className="max-h-64 space-y-1 overflow-y-auto">{(reading.data?.users ?? []).map((user) => <div key={user.user_id} className="flex items-center gap-2 rounded-md border px-3 py-2 text-sm"><span className={user.has_read ? "text-green-600" : "text-amber-600"}>{user.has_read ? <CheckCircle2 className="h-4 w-4" /> : <Circle className="h-4 w-4" />}</span><span className="flex-1">{user.name || "Utilisateur"}<span className="ml-2 text-xs text-muted-foreground">{user.phone || ""}</span></span><span className="text-xs text-muted-foreground">{user.has_read ? "Lu" : "Non lu"}</span></div>)}</div>}
      </CardContent>
    </Card>
  );
}
