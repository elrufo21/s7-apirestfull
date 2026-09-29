// @ts-nocheck
import fs from "fs";
import path from "path";
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

  const basePath = process.env.STORAGE_PATH || path.join(process.cwd(), "storage");
  const cleanPrefix = (prefix || "").replace(/^[\\/]+/, "").replace(/[\\/]+$/, "");
  const targetDir = cleanPrefix ? path.join(basePath, cleanPrefix) : basePath;

  if (!fs.existsSync(targetDir)) {
    fs.mkdirSync(targetDir, { recursive: true });
  }

  const targetPath = path.join(targetDir, fileName);
  fs.copyFileSync(localPath, targetPath);

  const publicPath = `/storage/${cleanPrefix ? cleanPrefix + '/' : ''}${fileName}`;

  return {
    key: publicPath,
    path: publicPath,
    url: publicPath,
    publicUrl: publicPath,
    name: fileName,
    type: "zip",
  };
}

export async function uploadBufferToR2({
  buffer,
  fileName,
  prefix = "facturacion/",
  contentType,
}) {
  if (!Buffer.isBuffer(buffer) || buffer.length === 0) {
    throw new Error("Buffer invalido");
  }

  if (!fileName || typeof fileName !== "string") {
    throw new Error("Nombre de archivo invalido");
  }

  const basePath = process.env.STORAGE_PATH || path.join(process.cwd(), "storage");
  const cleanPrefix = (prefix || "").replace(/^[\\/]+/, "").replace(/[\\/]+$/, "");
  const targetDir = cleanPrefix ? path.join(basePath, cleanPrefix) : basePath;

  if (!fs.existsSync(targetDir)) {
    fs.mkdirSync(targetDir, { recursive: true });
  }

  const targetPath = path.join(targetDir, fileName);
  fs.writeFileSync(targetPath, buffer);

  const publicPath = `/storage/${cleanPrefix ? cleanPrefix + '/' : ''}${fileName}`;

  return {
    key: publicPath,
    path: publicPath,
    url: publicPath,
    publicUrl: publicPath,
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

  const basePath = process.env.STORAGE_PATH || path.join(process.cwd(), "storage");
  const cleanKey = key.replace(/^\/?storage\/?/, "");
  const targetFile = path.join(basePath, cleanKey);

  if (fs.existsSync(targetFile)) {
    try {
      fs.unlinkSync(targetFile);
    } catch (e) {
      console.warn("No se pudo eliminar archivo local:", e);
    }
  }

  return {
    success: true,
    message: `Archivo eliminado correctamente: ${key}`,
  };
}

export const r2Prefixes = {
  request: REQUEST_PREFIX,
  response: RESPONSE_PREFIX,
  certificate: CERT_PREFIX,
  image: IMAGE_PREFIX,
};

