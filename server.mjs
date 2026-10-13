import { createReadStream } from "node:fs";
import { stat } from "node:fs/promises";
import { createServer } from "node:http";
import { extname, isAbsolute, relative, resolve } from "node:path";
import { pipeline } from "node:stream/promises";
import { handler } from "./functions/server-render/index.mjs";

const port = Number(process.env.PORT ?? "3000");
const staticRoot = resolve("dist");
const maximumBodyBytes = 64 * 1024;
const contentTypes = new Map([
  [".css", "text/css; charset=utf-8"],
  [".html", "text/html; charset=utf-8"],
  [".ico", "image/x-icon"],
  [".js", "text/javascript; charset=utf-8"],
  [".json", "application/json; charset=utf-8"],
  [".svg", "image/svg+xml"],
  [".webp", "image/webp"],
  [".woff", "font/woff"],
  [".woff2", "font/woff2"],
]);

if (!Number.isInteger(port) || port < 1 || port > 65535) {
  throw new Error("PORT must be an integer between 1 and 65535.");
}

async function serveStaticAsset(request, response) {
  if (request.method !== "GET" && request.method !== "HEAD") {
    return false;
  }

  let pathname;

  try {
    pathname = decodeURIComponent(new URL(request.url ?? "/", "http://localhost").pathname);
  } catch {
    response.writeHead(400).end("Invalid URL.");
    return true;
  }

  if (pathname === "/") {
    return false;
  }

  const filePath = resolve(staticRoot, `.${pathname}`);
  const relativePath = relative(staticRoot, filePath);

  if (relativePath.startsWith("..") || isAbsolute(relativePath)) {
    return false;
  }

  let fileInfo;

  try {
    fileInfo = await stat(filePath);
  } catch (error) {
    if (error.code === "ENOENT" || error.code === "ENOTDIR") {
      return false;
    }

    throw error;
  }

  if (!fileInfo.isFile()) {
    return false;
  }

  response.writeHead(200, {
    "Content-Type": contentTypes.get(extname(filePath)) ?? "application/octet-stream",
    "Content-Length": fileInfo.size,
    "Cache-Control": pathname.startsWith("/assets/") ? "public, max-age=31536000, immutable" : "no-cache",
  });

  if (request.method === "HEAD") {
    response.end();
  } else {
    await pipeline(createReadStream(filePath), response);
  }

  return true;
}

async function readRequestBody(request) {
  const chunks = [];
  let totalBytes = 0;
  let tooLarge = false;

  for await (const chunk of request) {
    totalBytes += chunk.length;

    if (totalBytes > maximumBodyBytes) {
      tooLarge = true;
    } else {
      chunks.push(chunk);
    }
  }

  return tooLarge ? null : Buffer.concat(chunks).toString("utf8");
}

async function handleRequest(request, response) {
  try {
    if (await serveStaticAsset(request, response)) {
      return;
    }

    const body = await readRequestBody(request);

    if (body === null) {
      response.writeHead(413, { "Content-Type": "text/plain; charset=utf-8" });
      response.end("Request body is too large.");
      return;
    }

    const headers = Object.fromEntries(
      Object.entries(request.headers).map(([name, value]) => [
        name,
        Array.isArray(value) ? value.join(", ") : value ?? "",
      ]),
    );
    const rendered = await handler(
      {
        httpMethod: request.method,
        headers,
        rawUrl: new URL(request.url ?? "/", `http://${request.headers.host ?? "localhost"}`).href,
        body,
      },
      {},
    );
    const responseHeaders = rendered.multiValueHeaders ?? {};

    for (const [name, values] of Object.entries(responseHeaders)) {
      if (values.length > 0) {
        response.setHeader(name, values.length === 1 ? values[0] : values);
      }
    }

    const responseBody = rendered.isBase64Encoded
      ? Buffer.from(rendered.body ?? "", "base64")
      : rendered.body ?? "";

    response.writeHead(rendered.statusCode ?? 500);
    response.end(responseBody);
  } catch (error) {
    console.error("Request handling failed:", error);

    if (!response.headersSent) {
      response.writeHead(500, { "Content-Type": "text/plain; charset=utf-8" });
      response.end("The server could not complete the request.");
    } else {
      response.destroy(error);
    }
  }
}

createServer(handleRequest).listen(port, "0.0.0.0", () => {
  console.log(`AppaRent server listening on port ${port}`);
});
