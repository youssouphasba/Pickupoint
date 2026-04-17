"use client";

import * as React from "react";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import {
  fetchCodMonitoring,
  fetchDrivers,
  fetchFinanceReconciliation,
  settleCod,
} from "@/lib/api";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { useToast } from "@/components/ui/toaster";
import { Banknote, Loader2 } from "lucide-react";

const xof = new Intl.NumberFormat("fr-FR");

export default function FinancePage() {
  const qc = useQueryClient();
  const { toast } = useToast();

  const recon = useQuery({
    queryKey: ["finance-recon"],
    queryFn: fetchFinanceReconciliation,
  });

  const cod = useQuery({
    queryKey: ["finance-cod"],
    queryFn: fetchCodMonitoring,
  });

  const drivers = useQuery({
    queryKey: ["drivers-list"],
    queryFn: fetchDrivers,
  });

  const loading = recon.isLoading || cod.isLoading;
  const error = recon.isError || cod.isError;

  // COD settle state
  const [settleOpen, setSettleOpen] = React.useState(false);
  const [settleDriverId, setSettleDriverId] = React.useState("");
  const [settleAmount, setSettleAmount] = React.useState("");

  const settleMut = useMutation({
    mutationFn: () =>
      settleCod(
        settleDriverId,
        settleAmount ? parseFloat(settleAmount) : undefined
      ),
    onSuccess: (res) => {
      qc.invalidateQueries({ queryKey: ["finance-cod"] });
      toast(
        `COD encaissé : ${xof.format(res.amount_settled ?? 0)} XOF`
      );
      setSettleOpen(false);
      setSettleDriverId("");
      setSettleAmount("");
    },
  });

  return (
    <div className="space-y-6 p-8">
      <div className="flex items-start justify-between gap-4">
        <div>
          <h1 className="text-2xl font-bold">Finance</h1>
          <p className="text-sm text-muted-foreground">
            Réconciliation financière et suivi du cash en circulation.
          </p>
        </div>
        <Button
          variant="outline"
          size="sm"
          onClick={() => setSettleOpen(!settleOpen)}
        >
          <Banknote className="h-4 w-4" />
          Encaisser COD
        </Button>
      </div>

      {/* COD Settle form */}
      {settleOpen && (
        <Card>
          <CardHeader>
            <CardTitle className="text-base">
              Confirmer l'encaissement du cash (COD)
            </CardTitle>
          </CardHeader>
          <CardContent>
            <div className="flex flex-wrap items-end gap-3">
              <div className="min-w-[200px] flex-1">
                <label className="mb-1.5 block text-sm font-medium">
                  Livreur
                </label>
                <select
                  value={settleDriverId}
                  onChange={(e) => setSettleDriverId(e.target.value)}
                  className="flex h-10 w-full rounded-md border border-input bg-background px-3 py-2 text-sm"
                >
                  <option value="">Sélectionner un livreur…</option>
                  {(drivers.data?.drivers ?? []).map((d: any) => (
                    <option key={d.user_id} value={d.user_id}>
                      {d.name ?? d.full_name ?? d.phone} — {d.user_id}
                    </option>
                  ))}
                </select>
              </div>
              <div className="w-40">
                <label className="mb-1.5 block text-sm font-medium">
                  Montant (vide = tout)
                </label>
                <Input
                  type="number"
                  placeholder="XOF"
                  value={settleAmount}
                  onChange={(e) => setSettleAmount(e.target.value)}
                />
              </div>
              <Button
                onClick={() => settleMut.mutate()}
                disabled={!settleDriverId || settleMut.isPending}
              >
                {settleMut.isPending && (
                  <Loader2 className="h-4 w-4 animate-spin" />
                )}
                Encaisser
              </Button>
            </div>
            {settleMut.isError && (
              <div className="mt-3 rounded-md border border-red-200 bg-red-50 px-3 py-2 text-sm text-red-700">
                {(settleMut.error as any)?.response?.data?.detail ??
                  "Erreur lors de l'encaissement."}
              </div>
            )}
          </CardContent>
        </Card>
      )}

      {loading && (
        <div className="flex h-40 items-center justify-center">
          <Loader2 className="h-5 w-5 animate-spin text-muted-foreground" />
        </div>
      )}
      {error && (
        <div className="rounded-md border border-red-200 bg-red-50 p-4 text-sm text-red-700">
          Erreur de chargement des données financières.
        </div>
      )}

      {recon.data && (
        <section>
          <h2 className="mb-3 text-sm font-semibold uppercase tracking-wide text-muted-foreground">
            Réconciliation
          </h2>
          <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
            {Object.entries(recon.data).map(([key, val]) => (
              <Card key={key}>
                <CardContent className="p-5">
                  <div className="text-xs font-medium uppercase tracking-wide text-muted-foreground">
                    {key.replace(/_/g, " ")}
                  </div>
                  <div className="mt-1 text-xl font-bold">
                    {typeof val === "number"
                      ? `${xof.format(Math.round(val as number))} XOF`
                      : String(val)}
                  </div>
                </CardContent>
              </Card>
            ))}
          </div>
        </section>
      )}

      {cod.data && (
        <section>
          <h2 className="mb-3 text-sm font-semibold uppercase tracking-wide text-muted-foreground">
            Cash on delivery (COD)
          </h2>
          <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
            {Object.entries(cod.data).map(([key, val]) => (
              <Card key={key}>
                <CardContent className="p-5">
                  <div className="text-xs font-medium uppercase tracking-wide text-muted-foreground">
                    {key.replace(/_/g, " ")}
                  </div>
                  <div className="mt-1 text-xl font-bold">
                    {typeof val === "number"
                      ? `${xof.format(Math.round(val as number))} XOF`
                      : String(val)}
                  </div>
                </CardContent>
              </Card>
            ))}
          </div>
        </section>
      )}
    </div>
  );
}
