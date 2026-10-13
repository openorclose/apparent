import { randomUUID } from "node:crypto";
import oracledb from "oracledb";

oracledb.fetchAsString = [oracledb.CLOB];

const listingIdPattern = /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const listingsTable = "APPARENT_OWNER.APPARENT_LISTINGS";
let poolPromise;

function getPool() {
  const { ORACLE_CONNECT_STRING, ORACLE_PASSWORD, ORACLE_USER } = process.env;

  if (!ORACLE_CONNECT_STRING || !ORACLE_PASSWORD || !ORACLE_USER) {
    throw new Error("Set ORACLE_USER, ORACLE_PASSWORD, and ORACLE_CONNECT_STRING.");
  }

  if (!poolPromise) {
    poolPromise = oracledb.createPool({
      user: ORACLE_USER,
      password: ORACLE_PASSWORD,
      connectString: ORACLE_CONNECT_STRING,
      poolMin: 0,
      poolMax: 4,
      poolIncrement: 1,
      poolTimeout: 60,
      queueTimeout: 10000,
    }).catch((error) => {
      poolPromise = undefined;
      throw error;
    });
  }

  return poolPromise;
}

async function withConnection(operation) {
  const pool = await getPool();
  const connection = await pool.getConnection();

  try {
    return await operation(connection);
  } finally {
    await connection.close();
  }
}

function assertListingId(id) {
  if (typeof id !== "string" || !listingIdPattern.test(id)) {
    throw new Error("Invalid listing ID.");
  }
}

function assertTimestamp(timestamp) {
  if (!Number.isSafeInteger(timestamp) || timestamp < 0) {
    throw new Error("Listing expiry must be a non-negative millisecond timestamp.");
  }
}

export async function newListingId() {
  return randomUUID();
}

export async function readListingRows({ now }) {
  assertTimestamp(now);

  return withConnection(async (connection) => {
    await connection.execute(
      `DELETE FROM ${listingsTable} WHERE EXPIRES_AT_MS <= :now`,
      { now },
    );

    const result = await connection.execute(
      `SELECT LISTING_ID AS "id",
              EXPIRES_AT_MS AS "expiresAt",
              LISTING_JSON AS "contents"
         FROM ${listingsTable}
        WHERE EXPIRES_AT_MS > :now
        ORDER BY EXPIRES_AT_MS DESC`,
      { now },
      { outFormat: oracledb.OUT_FORMAT_OBJECT },
    );

    await connection.commit();
    return result.rows ?? [];
  });
}

export async function insertListing({ id, expiresAt, contents }) {
  assertListingId(id);
  assertTimestamp(expiresAt);

  if (typeof contents !== "string") {
    throw new Error("Listing contents must be JSON text.");
  }

  return withConnection(async (connection) => {
    await connection.execute(
      `INSERT INTO ${listingsTable} (LISTING_ID, EXPIRES_AT_MS, LISTING_JSON)
       VALUES (:id, :expiresAt, :contents)`,
      {
        id,
        expiresAt,
        contents: { val: contents, type: oracledb.CLOB },
      },
      { autoCommit: true },
    );

    return true;
  });
}
