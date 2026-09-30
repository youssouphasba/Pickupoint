"use client";

import * as React from "react";
import Link from "next/link";
import {useSearchParams} from "next/navigation";
import {useInfiniteQuery, useQuery, useQueryClient} from "@tanstack/react-query";
import {
  api, fetchWhatsappSupportConversation, fetchWhatsappSupportConversations,
  sendWhatsappSupportReopenTemplate, sendWhatsappSupportTextReply, sendWhatsappSupportVoiceReply,
  startWhatsappSupport, updateWhatsappSupportConversationStatus, fetchWhatsappSupportSettings,
  saveWhatsappSupportSettings, addWhatsappSupportNote, WhatsAppSupportMessage, SupportStatus, SupportQuickReply,
} from "@/lib/api";
import {Badge} from "@/components/ui/badge";
import {Button} from "@/components/ui/button";
import {Card, CardContent, CardHeader, CardTitle} from "@/components/ui/card";
import {Input} from "@/components/ui/input";
import {formatDate} from "@/lib/utils";

const STATUSES: Record<SupportStatus, string> = {open: "À traiter", pending: "Attente du client", pending_internal: "Action interne", resolved: "Résolu"};
const DELIVERY: Record<string, string> = {sending: "Envoi en cours", accepted: "Accepté par WhatsApp", sent: "Envoyé", delivered: "Livré", read: "Lu", failed: "Échec d’envoi", uncertain: "Envoi incertain — vérifier avant de renvoyer"};
const AUDIO_TYPES = ["audio/ogg;codecs=opus", "audio/webm;codecs=opus", "audio/webm", "audio/mp4"];

function errorMessage(error: unknown): string {
  if (error instanceof DOMException && error.name === "NotAllowedError") return "Autorisez le microphone pour ce site dans votre navigateur.";
  if (error && typeof error === "object" && "response" in error) {
    const detail = (error as {response?: {data?: {detail?: unknown}}}).response?.data?.detail;
    if (typeof detail === "string") return detail;
  }
  return error instanceof Error ? error.message : "L’opération a échoué. Actualisez pour vérifier son résultat.";
}

function PrivateMedia({message}: {message: WhatsAppSupportMessage}) {
  const [src, setSrc] = React.useState<string>();
  const [error, setError] = React.useState<string>();
  const [attempt, setAttempt] = React.useState(0);
  const [requested, setRequested] = React.useState(false);
  const media = message.media;
  React.useEffect(() => {
    if (!media?.download_url || !requested) return;
    let objectUrl: string | undefined;
    const controller = new AbortController();
    setSrc(undefined); setError(undefined);
    let path: string;
    try {path = new URL(media.download_url, api.defaults.baseURL).pathname;} catch {setError("Adresse du média invalide"); return;}
    if (!path.startsWith("/api/admin/support/whatsapp/media/")) {setError("Adresse du média invalide"); return;}
    api.get<Blob>(path, {responseType: "blob", signal: controller.signal}).then(({data}) => {
      if (controller.signal.aborted) return;
      objectUrl = URL.createObjectURL(data); setSrc(objectUrl);
    }).catch(() => {if (!controller.signal.aborted) setError("Média indisponible pour le moment");});
    return () => {controller.abort(); if (objectUrl) URL.revokeObjectURL(objectUrl);};
  }, [media?.download_url, attempt, requested]);
  if (!requested) return <Button size="sm" variant="outline" onClick={() => setRequested(true)}>{message.message_type === "audio" ? "Lire le vocal" : message.message_type === "image" ? "Voir la photo" : "Préparer le document"}</Button>;
  if (error) return <Button size="sm" variant="outline" onClick={() => setAttempt(x => x + 1)}>{error} · Réessayer</Button>;
  if (!src) return <p className="text-xs text-muted-foreground">Chargement du média…</p>;
  if (message.message_type === "audio") return <audio controls src={src} className="mt-2 w-full" />;
  if (message.message_type === "image" && ["image/jpeg", "image/png", "image/webp"].includes(media?.mime_type || "")) {
    return <a href={src} download={media?.filename || "photo"}><img src={src} alt="Photo jointe au message" className="mt-2 max-h-72 max-w-full rounded object-contain" /></a>;
  }
  return <a href={src} download={media?.filename || "document"} className="text-primary underline">Télécharger {media?.filename || "le document"}</a>;
}

function QuickReplySettings({replies, saved}: {replies: SupportQuickReply[]; saved: () => void}) {
  const [items, setItems] = React.useState(replies);
  const [busy, setBusy] = React.useState(false);
  const [error, setError] = React.useState<string>();
  return <details className="rounded-lg border p-4"><summary className="cursor-pointer font-medium">Configurer les réponses rapides</summary>
    <p className="my-2 text-sm text-muted-foreground">Textes à insérer dans une réponse, sans envoi automatique.</p>
    {items.map((item, index) => <div key={index} className="my-3 space-y-2">
      <Input aria-label="Nom de la réponse" value={item.label} maxLength={80} onChange={e => setItems(items.map((x, i) => i === index ? {...x, label: e.target.value} : x))} />
      <textarea aria-label="Texte de la réponse" className="w-full rounded border p-2" value={item.text} maxLength={2000} onChange={e => setItems(items.map((x, i) => i === index ? {...x, text: e.target.value} : x))} />
      <Button variant="outline" size="sm" onClick={() => setItems(items.filter((_, i) => i !== index))}>Supprimer</Button>
    </div>)}
    <div className="flex flex-wrap gap-2"><Button variant="outline" disabled={items.length >= 30 || busy} onClick={() => setItems([...items, {label: "", text: ""}])}>Ajouter</Button>
      <Button disabled={busy || items.some(x => !x.label.trim() || !x.text.trim())} onClick={async () => {
        setBusy(true); setError(undefined);
        try {await saveWhatsappSupportSettings(items); saved();} catch (e) {setError(errorMessage(e));} finally {setBusy(false);}
      }}>{busy ? "Enregistrement…" : "Enregistrer"}</Button></div>
    {error && <p role="alert" className="text-red-700">{error}</p>}
  </details>;
}

export default function WhatsAppSupportPage() {
  const qc = useQueryClient();
  const params = useSearchParams();
  const [selectedId, setSelectedId] = React.useState<string | null>(params.get("c"));
  const [query, setQuery] = React.useState(params.get("q") || "");
  const [status, setStatus] = React.useState(params.get("q") ? "all" : "open");
  const [phone, setPhone] = React.useState(params.get("q") || "");
  const [drafts, setDrafts] = React.useState<Record<string, {text: string; requestId: string}>>({});
  const [note, setNote] = React.useState("");
  const [busy, setBusy] = React.useState(false);
  const [error, setError] = React.useState<string>();
  const [recording, setRecording] = React.useState(false);
  const [recordingBusy, setRecordingBusy] = React.useState(false);
  const [voice, setVoice] = React.useState<{id: string; blob: Blob; requestId: string; url: string}>();
  const recorder = React.useRef<MediaRecorder>();
  const disposed = React.useRef(false);
  const ids = React.useRef<Record<string, string>>({});
  const [clock, setClock] = React.useState(Date.now());
  React.useEffect(() => {setSelectedId(params.get("c")); setQuery(params.get("q") || "");}, [params]);
  React.useEffect(() => {
    disposed.current = false;
    const interval = setInterval(() => setClock(Date.now()), 1000);
    return () => {
      disposed.current = true; clearInterval(interval);
      if (recorder.current) {
        recorder.current.onstop = null;
        if (recorder.current.state !== "inactive") recorder.current.stop();
        recorder.current.stream.getTracks().forEach(track => track.stop());
      }
    };
  }, []);
  React.useEffect(() => () => {if (voice) URL.revokeObjectURL(voice.url);}, [voice]);
  const settings = useQuery({queryKey: ["whatsapp-support-settings"], queryFn: fetchWhatsappSupportSettings});
  const list = useInfiniteQuery({
    queryKey: ["whatsapp-support-conversations", status, query], initialPageParam: 0,
    queryFn: ({pageParam}) => fetchWhatsappSupportConversations({status: status === "all" ? undefined : status, q: query || undefined, skip: pageParam}),
    getNextPageParam: page => page.skip + page.conversations.length < page.total ? page.skip + page.conversations.length : undefined,
    refetchInterval: 15_000,
  });
  const conversations = [...new Map((list.data?.pages.flatMap(page => page.conversations) || []).map(x => [x.conversation_id, x])).values()];
  const activeId = selectedId || conversations[0]?.conversation_id || null;
  React.useEffect(() => {if (activeId && !selectedId) setSelectedId(activeId);}, [activeId, selectedId]);
  const detail = useInfiniteQuery({
    queryKey: ["whatsapp-support-conversation", activeId], initialPageParam: undefined as string | undefined,
    queryFn: ({pageParam}) => fetchWhatsappSupportConversation(activeId!, {before: pageParam}),
    getNextPageParam: page => page.has_more ? page.next_before || undefined : undefined,
    enabled: Boolean(activeId), refetchInterval: 15_000,
  });
  const current = detail.data?.pages[0];
  const conversation = current?.conversation;
  const name = conversation?.matched_user?.name || conversation?.phone || "Sélectionnez une conversation";
  const messages = [...new Map((detail.data?.pages.slice().reverse().flatMap(page => page.messages) || []).map(x => [x.message_id, x])).values()];
  const replyAllowed = Boolean(conversation?.can_reply_freeform && conversation.reply_window_expires_at && new Date(conversation.reply_window_expires_at).getTime() > clock);
  const draft = activeId ? drafts[activeId] : undefined;
  const locked = busy || recording || recordingBusy || Boolean(voice);
  const refresh = () => {qc.invalidateQueries({queryKey: ["whatsapp-support-conversations"]}); qc.invalidateQueries({queryKey: ["whatsapp-support-conversation"]});};
  async function run(operation: () => Promise<unknown>) {
    if (busy) return;
    setBusy(true); setError(undefined);
    try {await operation();} catch (e) {setError(errorMessage(e));} finally {setBusy(false); refresh();}
  }
  const requestId = (key: string) => ids.current[key] ||= crypto.randomUUID();
  function setDraft(text: string) {
    if (activeId) setDrafts(previous => ({...previous, [activeId]: {text, requestId: crypto.randomUUID()}}));
  }
  async function record() {
    if (!activeId || locked || !replyAllowed) return;
    const target = activeId;
    setRecordingBusy(true); setError(undefined);
    let stream: MediaStream | undefined;
    try {
      if (!navigator.mediaDevices?.getUserMedia || typeof MediaRecorder === "undefined") throw new Error("Enregistrement indisponible dans ce navigateur. Utilisez une connexion HTTPS.");
      stream = await navigator.mediaDevices.getUserMedia({audio: true});
      if (disposed.current) {stream.getTracks().forEach(track => track.stop()); return;}
      const mimeType = AUDIO_TYPES.find(type => MediaRecorder.isTypeSupported(type));
      const instance = new MediaRecorder(stream, mimeType ? {mimeType} : undefined);
      const chunks: Blob[] = [];
      instance.ondataavailable = event => {if (event.data.size) chunks.push(event.data);};
      instance.onerror = () => {instance.onstop = null; instance.stream.getTracks().forEach(track => track.stop()); setRecording(false); setError("Enregistrement interrompu. Réessayez.");};
      instance.onstop = () => {
        instance.stream.getTracks().forEach(track => track.stop()); setRecording(false);
        const blob = new Blob(chunks, {type: instance.mimeType || mimeType || "audio/webm"});
        if (!blob.size) {setError("Aucun audio enregistré."); return;}
        setVoice({id: target, blob, requestId: crypto.randomUUID(), url: URL.createObjectURL(blob)});
      };
      recorder.current = instance; instance.start(); setRecording(true);
    } catch (e) {stream?.getTracks().forEach(track => track.stop()); if (!disposed.current) setError(errorMessage(e));}
    finally {if (!disposed.current) setRecordingBusy(false);}
  }
  return <div className="space-y-5 p-4 sm:p-6 lg:p-8">
    <div className="flex flex-wrap items-center justify-between gap-3"><div><h1 className="text-2xl font-bold">Support WhatsApp</h1><p className="text-sm text-muted-foreground">Conversations, pièces jointes et suivi des réponses.</p></div><Button variant="outline" onClick={refresh}>Actualiser</Button></div>
    <div className="flex flex-wrap gap-2">{[...Object.keys(STATUSES), "all"].map(value => <Button key={value} size="sm" variant={status === value ? "default" : "outline"} disabled={locked} onClick={() => {setStatus(value); setSelectedId(null); setNote("");}}>{value === "all" ? "Tous" : STATUSES[value as SupportStatus]}</Button>)}</div>
    {error && <p role="alert" className="rounded border border-red-200 bg-red-50 p-3 text-red-800">{error}</p>}
    <div className="grid gap-5 xl:grid-cols-[360px_minmax(0,1fr)]">
      <Card><CardHeader><CardTitle>Conversations</CardTitle>
        <Input aria-label="Rechercher une conversation" value={query} disabled={locked} placeholder="Téléphone, nom, code colis…" onChange={e => {setQuery(e.target.value); setSelectedId(null); setNote("");}} />
        <div className="flex gap-2"><Input aria-label="Numéro à contacter" value={phone} disabled={locked} onChange={e => setPhone(e.target.value)} placeholder="Numéro WhatsApp" />
          <Button variant="outline" disabled={locked || !phone.trim() || !settings.data?.reopen_template_available} onClick={() => run(async () => {
            const key = "start:" + phone.trim(); const result = await startWhatsappSupport({phone, request_id: requestId(key)});
            delete ids.current[key]; setStatus("all"); setQuery(phone); setSelectedId(result.conversation.conversation_id);
          })}>Contacter</Button></div><p className="text-xs text-muted-foreground">Envoie le modèle de contact configuré, pas une réponse libre.</p>
      </CardHeader><CardContent className="max-h-[70vh] space-y-2 overflow-y-auto">
        {list.isLoading && <p>Chargement…</p>}
        {list.isError && <Button variant="outline" onClick={() => list.refetch()}>Chargement impossible · Réessayer</Button>}
        {!list.isLoading && !list.isError && !conversations.length && <p>Aucune conversation pour ce filtre.</p>}
        {conversations.map(item => <button key={item.conversation_id} disabled={locked} onClick={() => {setSelectedId(item.conversation_id); setNote(""); setError(undefined);}} className={`w-full rounded-lg border p-3 text-left disabled:opacity-60 ${activeId === item.conversation_id ? "border-primary bg-primary/5" : "hover:bg-muted"}`}>
          <div className="font-medium">{item.matched_user?.name || item.phone}</div><div className="text-xs text-muted-foreground">{item.phone} · {formatDate(item.last_message_at)}</div>
          <Badge tone={item.status === "resolved" ? "success" : item.status === "open" ? "danger" : "warning"}>{STATUSES[item.status]}</Badge><p className="mt-2 line-clamp-2 break-words text-sm">{item.last_message_text || "Sans texte"}</p></button>)}
        {list.hasNextPage && <Button variant="outline" disabled={list.isFetchingNextPage || locked} onClick={() => list.fetchNextPage()}>Voir plus de conversations</Button>}
      </CardContent></Card>
      <div className="min-w-0 space-y-4">
        <Card><CardHeader><CardTitle>{name}</CardTitle><p className="text-sm text-muted-foreground">{conversation?.phone}</p>
          {conversation && <div className="flex flex-wrap gap-2">{(Object.keys(STATUSES) as SupportStatus[]).map(value => <Button key={value} size="sm" variant={conversation.status === value ? "default" : "outline"} disabled={locked} onClick={() => run(() => updateWhatsappSupportConversationStatus(activeId!, value))}>{STATUSES[value]}</Button>)}</div>}
        </CardHeader><CardContent className="flex flex-wrap gap-4 text-sm">
          {conversation?.matched_user ? <Link className="text-primary underline" href={`/dashboard/users/${encodeURIComponent(conversation.matched_user.user_id)}`}>Utilisateur : {conversation.matched_user.name || conversation.phone}</Link> : <span>Utilisateur non identifié</span>}
          {conversation?.matched_parcel ? <Link className="text-primary underline" href={`/dashboard/parcels/${encodeURIComponent(conversation.matched_parcel.parcel_id)}`}>Colis détecté : {conversation.matched_parcel.tracking_code}</Link> : <span>Aucun colis identifié. Demandez le code de suivi.</span>}
        </CardContent></Card>
        <Card><CardHeader><CardTitle>Messages</CardTitle></CardHeader><CardContent className="space-y-3">
          {detail.isLoading && <p>Chargement…</p>}
          {detail.isError && <Button variant="outline" onClick={() => detail.refetch()}>Messages indisponibles · Réessayer</Button>}
          {detail.hasNextPage && <Button size="sm" variant="outline" disabled={detail.isFetchingNextPage} onClick={() => detail.fetchNextPage()}>Messages précédents</Button>}
          <div className="max-h-[55vh] space-y-3 overflow-y-auto">{messages.map(message => <div key={message.message_id} className={`max-w-[95%] rounded-lg border p-3 sm:max-w-[85%] ${message.direction === "outbound" ? "ml-auto bg-primary/5" : "mr-auto bg-muted/40"}`}>
            <p className="text-xs text-muted-foreground">{message.direction === "outbound" ? message.admin_name || "Admin" : "Contact"} · {formatDate(message.created_at)}</p><p className="whitespace-pre-wrap break-words">{message.text}</p>
            {message.media?.download_url && <PrivateMedia message={message} />}
            {message.direction === "outbound" && <p className={`mt-2 text-xs ${["failed", "uncertain"].includes(message.delivery_status || "") ? "text-red-700" : "text-muted-foreground"}`}>{DELIVERY[message.delivery_status || ""] || "Envoi enregistré"}</p>}
            {message.send_error && <p className="mt-1 text-xs text-red-700">{message.send_error}</p>}
            {message.delivery_errors?.map((failure, i) => <p key={i} className="text-xs text-red-700">{failure.message}</p>)}
          </div>)}</div>
          {conversation && <div className="space-y-3 border-t pt-4">
            <p className="text-xs text-muted-foreground">{replyAllowed ? `Réponses libres jusqu’au ${formatDate(conversation.reply_window_expires_at)}.` : "Fenêtre de réponse fermée. Le contact doit répondre à un modèle approuvé pour la rouvrir."}</p>
            {!replyAllowed && <Button variant="outline" disabled={locked || !settings.data?.reopen_template_available} onClick={() => run(async () => {const key = "reopen:" + activeId; await sendWhatsappSupportReopenTemplate(activeId!, requestId(key)); delete ids.current[key];})}>Envoyer une relance approuvée</Button>}
            {replyAllowed && <>
              <div className="flex flex-wrap gap-2">{settings.data?.quick_replies.map((reply, i) => <Button key={i} size="sm" variant="outline" disabled={locked} onClick={() => setDraft((draft?.text ? draft.text + "\n" : "") + reply.text)}>{reply.label}</Button>)}</div>
              <textarea aria-label="Réponse au contact" className="min-h-24 w-full rounded-lg border p-3" placeholder="Votre réponse…" maxLength={2000} disabled={locked} value={draft?.text || ""} onChange={e => setDraft(e.target.value)} />
              <div className="flex flex-wrap gap-2"><Button disabled={locked || !draft?.text.trim()} onClick={() => run(async () => {
                const target = activeId!; const sending = draft!; await sendWhatsappSupportTextReply(target, sending.text, sending.requestId);
                setDrafts(previous => {const next = {...previous}; delete next[target]; return next;});
              })}>Envoyer le texte</Button>
                <Button variant="outline" disabled={busy || recordingBusy || Boolean(voice)} onClick={() => recording ? recorder.current?.stop() : record()}>{recording ? "Arrêter pour écouter" : "Enregistrer un vocal"}</Button></div>
            </>}
            {voice && <div className="space-y-2 rounded border p-3"><p>Vocal pour {name} — non envoyé</p><audio controls src={voice.url} className="w-full" /><div className="flex gap-2">
              <Button disabled={busy || !replyAllowed} onClick={() => run(async () => {await sendWhatsappSupportVoiceReply(voice.id, voice.blob, voice.requestId); setVoice(undefined);})}>Envoyer le vocal</Button>
              <Button variant="outline" disabled={busy} onClick={() => setVoice(undefined)}>Annuler</Button></div></div>}
          </div>}
        </CardContent></Card>
        {conversation && <Card><CardHeader><CardTitle>Notes internes</CardTitle><p className="text-xs text-muted-foreground">Réservées à l’administration, jamais envoyées sur WhatsApp. {current?.notes_total || 0} note(s), les 50 dernières affichées.</p></CardHeader><CardContent className="space-y-3">
          {current?.notes?.map(item => <div key={item.note_id} className="rounded border bg-amber-50 p-3"><p className="whitespace-pre-wrap break-words">{item.text}</p><p className="text-xs text-muted-foreground">{item.admin_name || "Admin"} · {formatDate(item.created_at)}</p></div>)}
          <textarea aria-label="Nouvelle note interne" className="w-full rounded border p-2" maxLength={2000} value={note} disabled={locked} onChange={e => setNote(e.target.value)} />
          <Button variant="outline" disabled={locked || !note.trim()} onClick={() => run(async () => {await addWhatsappSupportNote(activeId!, note); setNote("");})}>Ajouter la note interne</Button>
        </CardContent></Card>}
      </div>
    </div>
    {settings.data && <QuickReplySettings key={JSON.stringify(settings.data.quick_replies)} replies={settings.data.quick_replies} saved={() => qc.invalidateQueries({queryKey: ["whatsapp-support-settings"]})} />}
  </div>;
}
