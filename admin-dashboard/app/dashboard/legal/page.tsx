"use client";

import * as React from "react";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { fetchLegalDoc, updateLegalDoc } from "@/lib/api";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Textarea } from "@/components/ui/textarea";
import { useToast } from "@/components/ui/toaster";
import { Loader2, Pencil, Save, X } from "lucide-react";

const DOC_TYPES = [
  { key: "privacy_policy", label: "Politique de confidentialité" },
  { key: "cgu", label: "Conditions générales" },
] as const;

export default function LegalPage() {
  const [activeTab, setActiveTab] = React.useState<string>("privacy_policy");

  return (
    <div className="space-y-5 p-8">
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
              <Input
                value={title}
                onChange={(e) => setTitle(e.target.value)}
              />
            </div>
            <div>
              <label className="mb-1.5 block text-sm font-medium">
                Contenu (texte brut ou HTML)
              </label>
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
              <div dangerouslySetInnerHTML={{ __html: data.content }} />
            ) : (
              <p className="text-muted-foreground">Aucun contenu.</p>
            )}
          </div>
        )}
      </CardContent>
    </Card>
  );
}
