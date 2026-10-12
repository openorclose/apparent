import { randomUUID } from "node:crypto";
import { mkdir, readFile, readdir, unlink, writeFile } from "node:fs/promises";
import path from "node:path";

const listingIdPattern = /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

function listingsDirectory(context) {
  return path.resolve(context.cwd, process.env.APPARENT_LISTINGS_DIR || "data/listings");
}

function assertListingId(id) {
  if (typeof id !== "string" || !listingIdPattern.test(id)) {
    throw new Error("Invalid listing file ID.");
  }
}

export async function newListingId() {
  return randomUUID();
}

export async function readListingFiles(_input, context) {
  const directory = listingsDirectory(context);
  await mkdir(directory, { recursive: true });

  const entries = await readdir(directory, { withFileTypes: true });
  const files = entries.filter((entry) => entry.isFile() && entry.name.endsWith(".txt"));

  return Promise.all(
    files.map(async (entry) => {
      const id = entry.name.slice(0, -4);
      assertListingId(id);

      return {
        id,
        contents: await readFile(path.join(directory, entry.name), "utf8"),
      };
    }),
  );
}

export async function writeListingFile({ id, contents }, context) {
  assertListingId(id);
  if (typeof contents !== "string") {
    throw new Error("Listing contents must be text.");
  }

  const directory = listingsDirectory(context);
  await mkdir(directory, { recursive: true });
  await writeFile(path.join(directory, `${id}.txt`), contents, {
    encoding: "utf8",
    flag: "wx",
  });

  return true;
}

export async function deleteListingFiles(ids, context) {
  if (!Array.isArray(ids)) {
    throw new Error("Listing IDs must be an array.");
  }

  const directory = listingsDirectory(context);
  for (const id of ids) {
    assertListingId(id);
    try {
      await unlink(path.join(directory, `${id}.txt`));
    } catch (error) {
      if (error.code !== "ENOENT") {
        throw error;
      }
    }
  }

  return true;
}
