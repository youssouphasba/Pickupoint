"use client";

import { useEffect, useState } from "react";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { fetchSettings, updateSendingGuide } from "@/lib/api";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { useToast } from "@/components/ui/toaster";

export function SendingGuideSettingsCard() {
  const queryClient = useQueryClient();
  const { toast } = useToast();
  const settings = useQuery({ queryKey: ["settings"], queryFn: fetchSettings });
  const [videoUrl, setVideoUrl] = useState("");
  const [thumbnailUrl, setThumbnailUrl] = useState("");
  const [dirty, setDirty] = useState(false);
  useEffect(() => {
    if (!settings.data || dirty) return;
    setVideoUrl(settings.data.sending_guide?.video_url ?? "");
    setThumbnailUrl(settings.data.sending_guide?.thumbnail_url ?? "");
  }, [settings.data, dirty]);
  const save = useMutation({
    mutationFn: updateSendingGuide,
    onSuccess: async () => {
      await queryClient.invalidateQueries({ queryKey: ["settings"] });
      setDirty(false);
      toast("Vidéo d’aide à l’envoi sauvegardée.");
    },
  });
  return (
    <Card>
      <CardHeader><CardTitle>Comment envoyer un colis ?</CardTitle></CardHeader>
      <CardContent>
        <form className="space-y-4" onSubmit={(event) => {
          event.preventDefault();
          save.mutate({ video_url: videoUrl.trim(), thumbnail_url: thumbnailUrl.trim() });
        }}>
          <p className="text-sm text-muted-foreground">La vidéo apparaît sur l’accueil client et à la première étape d’envoi. Sans lien vidéo, ces accès sont masqués. La lecture démarre uniquement à la demande du client.</p>
          <label className="block space-y-2"><span>Lien de la vidéo</span><Input type="url" value={videoUrl} disabled={save.isPending || !settings.data} onChange={(event) => { setDirty(true); setVideoUrl(event.target.value); }} placeholder="https://…" /></label>
          <p className="text-sm text-muted-foreground">Lien HTTPS public vers un fichier vidéo compatible (par exemple MP4), pas une page YouTube. Le fichier reste hébergé à distance.</p>
          <label className="block space-y-2"><span>Miniature (facultative)</span><Input type="url" value={thumbnailUrl} disabled={save.isPending || !settings.data} onChange={(event) => { setDirty(true); setThumbnailUrl(event.target.value); }} placeholder="https://…" /></label>
          {videoUrl.trim().startsWith("https://") && <video key={videoUrl} className="max-h-64 w-full rounded-lg bg-black" controls preload="none" poster={thumbnailUrl.trim() || undefined} src={videoUrl.trim()} />}
          {settings.isError && <p role="alert" className="text-sm text-red-600">Impossible de charger la configuration.</p>}
          {save.isError && <p role="alert" className="text-sm text-red-600">Impossible de sauvegarder. Vérifiez les liens HTTPS et réessayez.</p>}
          <Button type="submit" disabled={save.isPending || !settings.data}>{save.isPending ? "Sauvegarde…" : "Sauvegarder la vidéo"}</Button>
          <p className="text-sm text-muted-foreground">Pour retirer la vidéo, videz son lien et sauvegardez.</p>
        </form>
      </CardContent>
    </Card>
  );
}
