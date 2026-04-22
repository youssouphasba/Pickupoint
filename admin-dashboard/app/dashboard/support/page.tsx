"use client";

import * as React from "react";
import Link from "next/link";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import {
  api,
  fetchWhatsappSupportConversation,
  fetchWhatsappSupportConversations,
  sendWhatsappSupportTextReply,
  sendWhatsappSupportVoiceReply,
  updateWhatsappSupportConversationStatus,
  WhatsAppSupportConversation,
} from "@/lib/api";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { formatDate } from "@/lib/utils";
import {
  Loader2,
  MessageCircle,
  Mic,
  Package,
  Search,
  Send,
  Square,
  UserRound,
} from "lucide-react";

const STATUS_LABELS: Record<string, string> = {
  open: "Ouvert",
  pending: "En attente",
  resolved: "Résolu",
};

const STATUS_TONES: Record<string, "danger" | "warning" | "success" | "default"> = {
  open: "danger",
  pending: "warning",
  resolved: "success",
};

const AUDIO_MIME_PREFERENCES = [
  "audio/ogg;codecs=opus",
  "audio/webm;codecs=opus",
  "audio/webm",
];

function supportErrorMessage(error: unknown) {
  if (error && typeof error === "object" && "response" in error) {
    const response = (error as { response?: { data?: { detail?: string; message?: string; error?: string } } }).response;
    return (
      response?.data?.detail ||
      response?.data?.message ||
      response?.data?.error ||
      "La réponse WhatsApp n'a pas pu être envoyée."
    );
  }
  return error instanceof Error ? error.message : "La réponse WhatsApp n'a pas pu être envoyée.";
}

function conversationLabel(conversation?: WhatsAppSupportConversation | null) {
  return conversation?.matched_user?.name || conversation?.phone || "Conversation";
}

function mediaUrl(downloadUrl?: string | null) {
  if (!downloadUrl) return undefined;
  try {
    return `${api.defaults.baseURL}${new URL(downloadUrl).pathname}`;
  } catch {
    return downloadUrl;
  }
}

function AuthenticatedAudio({ downloadUrl }: { downloadUrl?: string | null }) {
  const [src, setSrc] = React.useState<string | null>(null);
  const [error, setError] = React.useState<string | null>(null);

  React.useEffect(() => {
    const url = mediaUrl(downloadUrl);
    if (!url) return;

    let objectUrl: string | null = null;
    let cancelled = false;
    setError(null);
    setSrc(null);

    api
      .get(url, { responseType: "blob" })
      .then((response) => {
        if (cancelled) return;
        objectUrl = URL.createObjectURL(response.data);
        setSrc(objectUrl);
      })
      .catch(() => {
        if (!cancelled) {
          setError("Lecture audio impossible. Le média est indisponible ou expiré.");
        }
      });

    return () => {
      cancelled = true;
      if (objectUrl) URL.revokeObjectURL(objectUrl);
    };
  }, [downloadUrl]);

  if (error) {
    return <div className="mt-3 text-xs text-red-700">{error}</div>;
  }

  if (!src) {
    return (
      <div className="mt-3 flex items-center gap-2 text-xs text-muted-foreground">
        <Loader2 className="h-3.5 w-3.5 animate-spin" />
        Chargement de l'audio...
      </div>
    );
  }

  return <audio className="mt-3 w-full max-w-md" controls src={src} />;
}

export default function WhatsAppSupportPage() {
  const qc = useQueryClient();
  const [selectedId, setSelectedId] = React.useState<string | null>(null);
  const [query, setQuery] = React.useState("");
  const [status, setStatus] = React.useState("open");
  const [replyText, setReplyText] = React.useState("");
  const [recording, setRecording] = React.useState(false);
  const [supportError, setSupportError] = React.useState<string | null>(null);
  const recorderRef = React.useRef<MediaRecorder | null>(null);
  const chunksRef = React.useRef<Blob[]>([]);

  const conversationsQuery = useQuery({
    queryKey: ["whatsapp-support-conversations", status, query],
    queryFn: () =>
      fetchWhatsappSupportConversations({
        status: status === "all" ? undefined : status,
        q: query || undefined,
        limit: 100,
      }),
    refetchInterval: 30_000,
  });

  const conversations = conversationsQuery.data?.conversations ?? [];
  const activeId = selectedId ?? conversations[0]?.conversation_id ?? null;

  const detailQuery = useQuery({
    queryKey: ["whatsapp-support-conversation", activeId],
    queryFn: () => fetchWhatsappSupportConversation(activeId as string),
    enabled: Boolean(activeId),
  });

  const refreshActive = () => {
    qc.invalidateQueries({ queryKey: ["whatsapp-support-conversations"] });
    qc.invalidateQueries({ queryKey: ["whatsapp-support-conversation", activeId] });
  };

  const statusMutation = useMutation({
    mutationFn: (nextStatus: "open" | "pending" | "resolved") =>
      updateWhatsappSupportConversationStatus(activeId as string, nextStatus),
    onSuccess: refreshActive,
  });

  const textReplyMutation = useMutation({
    mutationFn: () => sendWhatsappSupportTextReply(activeId as string, replyText),
    onSuccess: () => {
      setReplyText("");
      setSupportError(null);
      refreshActive();
    },
    onError: (error) => setSupportError(supportErrorMessage(error)),
  });

  const voiceReplyMutation = useMutation({
    mutationFn: (blob: Blob) => sendWhatsappSupportVoiceReply(activeId as string, blob),
    onSuccess: () => {
      setSupportError(null);
      refreshActive();
    },
    onError: (error) => setSupportError(supportErrorMessage(error)),
  });

  const activeConversation = detailQuery.data?.conversation;
  const messages = detailQuery.data?.messages ?? [];

  async function startRecording() {
    if (!activeId || recording) return;
    setSupportError(null);

    if (!navigator.mediaDevices?.getUserMedia || typeof MediaRecorder === "undefined") {
      setSupportError("L'enregistrement vocal n'est pas disponible dans ce navigateur.");
      return;
    }

    try {
      const stream = await navigator.mediaDevices.getUserMedia({ audio: true });
      const mimeType = AUDIO_MIME_PREFERENCES.find((type) => MediaRecorder.isTypeSupported(type));
      const recorder = new MediaRecorder(stream, mimeType ? { mimeType } : undefined);
      chunksRef.current = [];
      recorder.ondataavailable = (event) => {
        if (event.data.size > 0) chunksRef.current.push(event.data);
      };
      recorder.onerror = () => {
        stream.getTracks().forEach((track) => track.stop());
        setRecording(false);
        setSupportError("L'enregistrement audio a échoué. Vérifiez l'accès au micro.");
      };
      recorder.onstop = () => {
        stream.getTracks().forEach((track) => track.stop());
        setRecording(false);
        const blob = new Blob(chunksRef.current, {
          type: recorder.mimeType || mimeType || "audio/webm",
        });
        if (blob.size > 0) {
          voiceReplyMutation.mutate(blob);
        } else {
          setSupportError("Aucun audio n'a été enregistré.");
        }
      };
      recorderRef.current = recorder;
      recorder.start();
      setRecording(true);
    } catch (error) {
      setRecording(false);
      setSupportError(supportErrorMessage(error));
    }
  }

  function stopRecording() {
    recorderRef.current?.stop();
    recorderRef.current = null;
  }

  return (
    <div className="space-y-6 p-8">
      <div className="flex flex-col gap-2 md:flex-row md:items-end md:justify-between">
        <div>
          <h1 className="text-2xl font-bold">Support WhatsApp</h1>
          <p className="text-sm text-muted-foreground">
            Messages entrants, client détecté, colis lié, réponses texte et notes vocales.
          </p>
        </div>
        <div className="flex flex-wrap gap-2">
          {["open", "pending", "resolved", "all"].map((value) => (
            <Button
              key={value}
              variant={status === value ? "default" : "outline"}
              size="sm"
              onClick={() => setStatus(value)}
            >
              {value === "all" ? "Tous" : STATUS_LABELS[value]}
            </Button>
          ))}
        </div>
      </div>

      <div className="grid gap-5 xl:grid-cols-[420px_1fr]">
        <Card className="overflow-hidden">
          <CardHeader className="border-b">
            <CardTitle>Conversations</CardTitle>
            <div className="relative mt-3">
              <Search className="absolute left-3 top-2.5 h-4 w-4 text-muted-foreground" />
              <Input
                value={query}
                onChange={(event) => setQuery(event.target.value)}
                placeholder="Téléphone, nom, code colis..."
                className="pl-9"
              />
            </div>
          </CardHeader>
          <CardContent className="max-h-[68vh] space-y-2 overflow-y-auto p-3">
            {conversationsQuery.isLoading && (
              <div className="flex h-32 items-center justify-center">
                <Loader2 className="h-5 w-5 animate-spin text-muted-foreground" />
              </div>
            )}
            {!conversationsQuery.isLoading && conversations.length === 0 && (
              <div className="rounded-lg border border-dashed p-8 text-center text-sm text-muted-foreground">
                Aucune conversation WhatsApp pour ce filtre.
              </div>
            )}
            {conversations.map((conversation) => {
              const active = conversation.conversation_id === activeId;
              return (
                <button
                  key={conversation.conversation_id}
                  onClick={() => setSelectedId(conversation.conversation_id)}
                  className={[
                    "w-full rounded-lg border p-3 text-left transition-colors",
                    active ? "border-primary bg-primary/5" : "hover:bg-muted/50",
                  ].join(" ")}
                >
                  <div className="flex items-start justify-between gap-3">
                    <div className="min-w-0">
                      <div className="truncate font-medium">
                        {conversationLabel(conversation)}
                      </div>
                      <div className="text-xs text-muted-foreground">
                        {conversation.phone}
                      </div>
                    </div>
                    <Badge tone={STATUS_TONES[conversation.status] ?? "default"}>
                      {STATUS_LABELS[conversation.status] ?? conversation.status}
                    </Badge>
                  </div>
                  {conversation.matched_parcel?.tracking_code && (
                    <div className="mt-2 text-xs font-medium text-primary">
                      {conversation.matched_parcel.tracking_code}
                    </div>
                  )}
                  <div className="mt-2 line-clamp-2 text-sm text-muted-foreground">
                    {conversation.last_message_text || "Message sans texte"}
                  </div>
                </button>
              );
            })}
          </CardContent>
        </Card>

        <div className="space-y-5">
          <Card>
            <CardHeader className="border-b">
              <div className="flex flex-col gap-3 md:flex-row md:items-start md:justify-between">
                <div>
                  <CardTitle>{conversationLabel(activeConversation)}</CardTitle>
                  <p className="mt-1 text-sm text-muted-foreground">
                    {activeConversation?.phone ?? "Sélectionnez une conversation"}
                  </p>
                </div>
                {activeConversation && (
                  <div className="flex flex-wrap gap-2">
                    <Button
                      size="sm"
                      variant="outline"
                      onClick={() => statusMutation.mutate("pending")}
                      disabled={statusMutation.isPending}
                    >
                      En attente
                    </Button>
                    <Button
                      size="sm"
                      onClick={() => statusMutation.mutate("resolved")}
                      disabled={statusMutation.isPending}
                    >
                      Résolu
                    </Button>
                  </div>
                )}
              </div>
            </CardHeader>
            <CardContent className="grid gap-4 p-5 md:grid-cols-2">
              <div className="rounded-lg border p-4">
                <div className="mb-2 flex items-center gap-2 text-sm font-semibold">
                  <UserRound className="h-4 w-4 text-primary" />
                  Client détecté
                </div>
                {activeConversation?.matched_user ? (
                  <div className="space-y-1 text-sm">
                    <div>{activeConversation.matched_user.name ?? "Nom non renseigné"}</div>
                    <div className="text-muted-foreground">
                      {activeConversation.matched_user.role}
                    </div>
                    {activeConversation.matched_user.user_id && (
                      <Link
                        className="text-primary hover:underline"
                        href={`/dashboard/users/${activeConversation.matched_user.user_id}`}
                      >
                        Ouvrir la fiche utilisateur
                      </Link>
                    )}
                  </div>
                ) : (
                  <div className="text-sm text-muted-foreground">
                    Aucun utilisateur inscrit détecté pour ce numéro.
                  </div>
                )}
              </div>

              <div className="rounded-lg border p-4">
                <div className="mb-2 flex items-center gap-2 text-sm font-semibold">
                  <Package className="h-4 w-4 text-primary" />
                  Colis détecté
                </div>
                {activeConversation?.matched_parcel ? (
                  <div className="space-y-1 text-sm">
                    <div className="font-mono">
                      {activeConversation.matched_parcel.tracking_code}
                    </div>
                    <div className="text-muted-foreground">
                      Statut : {activeConversation.matched_parcel.status}
                    </div>
                    <Link
                      className="text-primary hover:underline"
                      href={`/dashboard/parcels/${activeConversation.matched_parcel.parcel_id}`}
                    >
                      Ouvrir la fiche colis
                    </Link>
                  </div>
                ) : (
                  <div className="text-sm text-muted-foreground">
                    Aucun colis détecté. Demandez au client son code de suivi.
                  </div>
                )}
              </div>
            </CardContent>
          </Card>

          <Card>
            <CardHeader className="border-b">
              <CardTitle>Messages</CardTitle>
            </CardHeader>
            <CardContent className="p-0">
              <div className="max-h-[46vh] space-y-3 overflow-y-auto p-5">
                {detailQuery.isLoading && (
                  <div className="flex h-32 items-center justify-center">
                    <Loader2 className="h-5 w-5 animate-spin text-muted-foreground" />
                  </div>
                )}
                {!detailQuery.isLoading && messages.length === 0 && (
                  <div className="rounded-lg border border-dashed p-8 text-center text-sm text-muted-foreground">
                    Aucun message à afficher.
                  </div>
                )}
                {messages.map((message) => {
                  const outbound = message.direction === "outbound";
                  return (
                    <div
                      key={message.message_id}
                      className={`flex gap-3 ${outbound ? "justify-end" : ""}`}
                    >
                      {!outbound && (
                        <div className="mt-1 flex h-8 w-8 shrink-0 items-center justify-center rounded-full bg-green-100 text-green-700">
                          <MessageCircle className="h-4 w-4" />
                        </div>
                      )}
                      <div
                        className={`min-w-0 max-w-[75%] rounded-lg border p-3 ${
                          outbound ? "bg-primary/10" : "bg-muted/30"
                        }`}
                      >
                        <div className="whitespace-pre-wrap text-sm">
                          {message.text || `[${message.message_type}]`}
                        </div>
                        {message.media?.download_url && (
                          <AuthenticatedAudio downloadUrl={message.media.download_url} />
                        )}
                        <div className="mt-2 text-xs text-muted-foreground">
                          {outbound ? "Envoyé · " : ""}
                          {formatDate(message.created_at)}
                          {message.matched_tracking_code && ` · ${message.matched_tracking_code}`}
                        </div>
                      </div>
                    </div>
                  );
                })}
              </div>

              <div className="border-t p-4">
                <div className="flex gap-2">
                  <Input
                    value={replyText}
                    onChange={(event) => setReplyText(event.target.value)}
                    placeholder="Répondre au client..."
                    disabled={!activeId || textReplyMutation.isPending}
                    onKeyDown={(event) => {
                      if (event.key === "Enter" && replyText.trim() && activeId) {
                        textReplyMutation.mutate();
                      }
                    }}
                  />
                  <Button
                    size="icon"
                    disabled={!activeId || !replyText.trim() || textReplyMutation.isPending}
                    onClick={() => textReplyMutation.mutate()}
                    title="Envoyer"
                  >
                    <Send className="h-4 w-4" />
                  </Button>
                  <Button
                    size="icon"
                    variant={recording ? "destructive" : "outline"}
                    disabled={!activeId || voiceReplyMutation.isPending}
                    onClick={recording ? stopRecording : startRecording}
                    title={recording ? "Arrêter l'enregistrement" : "Enregistrer une note vocale"}
                  >
                    {recording ? <Square className="h-4 w-4" /> : <Mic className="h-4 w-4" />}
                  </Button>
                </div>
                {supportError && (
                  <div className="mt-3 rounded-md border border-red-200 bg-red-50 px-3 py-2 text-sm text-red-700">
                    {supportError}
                  </div>
                )}
                <div className="mt-2 text-xs text-muted-foreground">
                  Les réponses libres fonctionnent dans la fenêtre WhatsApp de 24h après le dernier message utilisateur.
                  {recording && " Enregistrement en cours..."}
                  {voiceReplyMutation.isPending && " Envoi de la note vocale..."}
                </div>
              </div>
            </CardContent>
          </Card>
        </div>
      </div>
    </div>
  );
}
