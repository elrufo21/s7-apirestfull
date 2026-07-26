// @ts-nocheck
import fs from "fs";
import {
  DeleteObjectCommand,
  PutObjectCommand,
  S3Client,
} from "@aws-sdk/client-s3";

const REQUIRED_ENV_VARS = [
  "R2_BUCKET",
  "R2_ENDPOINT",
  "R2_ACCESS_KEY",
  "R2_SECRET_KEY",
];

const REQUEST_PREFIX = process.env.R2_REQUEST_PREFIX || "requests/";
const RESPONSE_PREFIX = process.env.R2_RESPONSE_PREFIX || "responses/";
const CERT_PREFIX = process.env.R2_CERT_PREFIX || "certificates/";
const IMAGE_PREFIX = process.env.R2_IMAGE_PREFIX || "images/";

function assertR2Config() {
  const missing = REQUIRED_ENV_VARS.filter((key) => !process.env[key]);

  if (missing.length) {
    throw new Error(
      `Faltan variables de entorno para R2: ${missing.join(", ")}`
    );
  }
}

function getClient() {
  assertR2Config();

  return new S3Client({
    region: "auto",
    endpoint: process.env.R2_ENDPOINT,
    forcePathStyle: true,
    credentials: {
      accessKeyId: process.env.R2_ACCESS_KEY,
      secretAccessKey: process.env.R2_SECRET_KEY,
    },
  });
}

function buildKey(fileName, prefix) {
  const cleanPrefix = (prefix || "")
    .replace(/^[\\/]+/, "")
    .replace(/[\\/]+$/, "");

  if (!cleanPrefix) return fileName;
  return `${cleanPrefix}/${fileName}`;
}

function buildPublicUrl(key) {
  const base =
    process.env.R2_PUBLIC_BASE_URL ||
    process.env.CLOUDFLARE_PUBLIC_URL ||
    `${process.env.R2_ENDPOINT}/${process.env.R2_BUCKET}`;

  return `${base.replace(/\/+$/, "")}/${key.replace(/^\/+/, "")}`;
}

export async function uploadFileFromDisk(
  localPath,
  fileName,
  prefix,
  options = {}
) {
  if (!fs.existsSync(localPath)) {
    throw new Error(`No se encontro el archivo a subir: ${localPath}`);
  }

  const { contentType } = options;
  const client = getClient();
  const key = buildKey(fileName, prefix);
  const putParams = {
    Bucket: process.env.R2_BUCKET,
    Key: key,
    Body: fs.createReadStream(localPath),
  };

  if (contentType) {
    putParams.ContentType = contentType;
  }

  await client.send(
    new PutObjectCommand(putParams)
  );

  return {
    key,
    url: buildPublicUrl(key),
    name: fileName,
    type: "zip",
  };
}

export async function uploadBufferToR2({
  buffer,
  fileName,
  prefix,
  contentType,
}) {
  if (!Buffer.isBuffer(buffer) || buffer.length === 0) {
    throw new Error("Buffer invalido para subida a R2");
  }

  if (!fileName || typeof fileName !== "string") {
    throw new Error("Nombre de archivo invalido para subida a R2");
  }

  const client = getClient();
  const key = buildKey(fileName, prefix);
  const putParams = {
    Bucket: process.env.R2_BUCKET,
    Key: key,
    Body: buffer,
  };

  if (contentType) {
    putParams.ContentType = contentType;
  }

  await client.send(new PutObjectCommand(putParams));

  return {
    key,
    url: buildPublicUrl(key),
    name: fileName,
    type: contentType || "file",
  };
}

export async function uploadTwoZipsFromDisk({
  requestPath,
  requestName,
  responsePath,
  responseName,
}) {
  const request = await uploadFileFromDisk(
    requestPath,
    requestName,
    REQUEST_PREFIX
  );

  const response = await uploadFileFromDisk(
    responsePath,
    responseName,
    RESPONSE_PREFIX
  );

  return { request, response };
}

export async function uploadCertificateFromDisk(localPath, fileName) {
  return uploadFileFromDisk(localPath, fileName, CERT_PREFIX);
}

export async function deleteObjectFromR2(key) {
  if (!key) {
    throw new Error("Debes enviar el key del archivo a eliminar");
  }

  const client = getClient();

  try {
    await client.send(
      new DeleteObjectCommand({
        Bucket: process.env.R2_BUCKET,
        Key: key,
      })
    );

    return {
      success: true,
      message: `Archivo eliminado correctamente: ${key}`,
    };
  } catch (error) {
    console.error("Error eliminando archivo en R2:", error);
    return { success: false, message: "Error eliminando archivo en R2", error };
  }
}

export const r2Prefixes = {
  request: REQUEST_PREFIX,
  response: RESPONSE_PREFIX,
  certificate: CERT_PREFIX,
  image: IMAGE_PREFIX,
};

