import { api } from "./api";

export async function openSecureDocument(url: string) {
  const destination = new URL(url, api.defaults.baseURL);
  const expected = new URL(api.defaults.baseURL!);
  if (
    destination.origin !== expected.origin || destination.username || destination.password ||
    destination.search || destination.hash ||
    !/^\/api\/users\/[^/]+\/kyc\/(id_card|license)$/.test(destination.pathname)
  ) {
    throw new Error("Ce lien ne correspond pas à un document privé Denkma.");
  }
  const popup = window.open("about:blank", "_blank");
  if (!popup) throw new Error("Autorisez l’ouverture du document dans votre navigateur.");
  popup.opener = null;
  let objectUrl: string | undefined;
  const closeDocument = () => {
    popup.close();
    if (objectUrl) URL.revokeObjectURL(objectUrl);
    window.removeEventListener("denkma-admin-logout", closeDocument);
  };
  window.addEventListener("denkma-admin-logout", closeDocument, { once: true });
  try {
    const response = await api.get(destination.href, { responseType: "blob" });
    if (popup.closed) {
      closeDocument();
      return;
    }
    objectUrl = URL.createObjectURL(response.data);
    popup.location.href = objectUrl;
    window.setTimeout(() => {
      if (objectUrl) URL.revokeObjectURL(objectUrl);
    }, 60_000);
  } catch (error) {
    closeDocument();
    throw error;
  }
}
