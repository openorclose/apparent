(() => {
  const isValidApiUrl = (value) => {
    if (typeof value !== "string" || !value.endsWith("/")) return false;

    try {
      const url = new URL(value);
      return url.protocol === "https:" && !url.username && !url.password;
    } catch {
      return false;
    }
  };

  const start = async () => {
    let apiBaseUrl = "";
    let configError = "";

    try {
      const response = await fetch("./ords-config.json", { cache: "no-store" });
      if (!response.ok) {
        throw new Error(`Configuration request returned status ${response.status}.`);
      }

      const config = await response.json();
      const configuredUrl = typeof config.apiBaseUrl === "string" ? config.apiBaseUrl.trim() : "";
      if (!isValidApiUrl(configuredUrl)) {
        throw new Error("Set apiBaseUrl in ords-config.json to your HTTPS ORDS collection URL, including its trailing slash.");
      }

      apiBaseUrl = configuredUrl;
    } catch (error) {
      const message = error instanceof Error ? error.message : "The configuration request failed.";
      configError = `Could not configure Oracle REST Data Services. ${message}`;
    }

    const app = Elm.Main.init({
      node: document.getElementById("app"),
      flags: { apiBaseUrl, configError },
    });
    const sendResponse = (message) => app.ports.ordsResponse.send(JSON.stringify(message));

    app.ports.ordsRequest.subscribe(async (request) => {
      if (!request || !isValidApiUrl(request.url)) {
        sendResponse({
          kind: request?.kind === "createListing" ? "listingCreated" : "listings",
          ok: false,
          error: "The Oracle REST collection URL is invalid.",
        });
        return;
      }

      const isCreate = request.kind === "createListing";
      if (!isCreate && request.kind !== "loadListings") {
        sendResponse({
          kind: "listings",
          ok: false,
          error: "The requested Oracle REST operation is not supported.",
        });
        return;
      }

      try {
        const response = await fetch(request.url, {
          method: isCreate ? "POST" : "GET",
          headers: isCreate
            ? { Accept: "application/json", "Content-Type": "application/json" }
            : { Accept: "application/json" },
          ...(isCreate ? { body: JSON.stringify(request.body) } : {}),
        });

        if (!response.ok) {
          throw new Error(`Oracle REST returned status ${response.status}.`);
        }

        const message = isCreate
          ? { kind: "listingCreated", ok: true }
          : { kind: "listings", ok: true, body: await response.json() };
        sendResponse(message);
      } catch (error) {
        sendResponse({
          kind: isCreate ? "listingCreated" : "listings",
          ok: false,
          error: error instanceof Error ? error.message : "The Oracle REST request failed.",
        });
      }
    });
  };

  start();
})();
