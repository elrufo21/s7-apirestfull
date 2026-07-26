// @ts-nocheck
import { XmlSignature } from "@supernova-team/xml-sunat";
import path from "node:path";
import os from "node:os";
import fs from "fs";

const DEFAULT_CERT_PATH = path.join(
  "certificate",
  "LLAMA-PE-CERTIFICADO-DEMO-20100100100.pfx"
);
const DEFAULT_PASSWORD_PATH = "./certificate/password.txt";

function resolveRootName(xml = "") {
  const cleaned = String(xml).replace(/^\uFEFF/, "").trimStart();
  const match = cleaned.match(/^<\?xml[\s\S]*?\?>\s*<(?:(?:\w+):)?([\w.-]+)/i);

  if (match?.[1]) {
    return match[1];
  }

  const fallbackMatch = cleaned.match(/^<(?:(?:\w+):)?([\w.-]+)/i);
  return fallbackMatch?.[1] || "Invoice";
}

function resolveCertificatePassword(overrides = {}) {
  const requestPassword = String(overrides.certificatePassword || "").trim();
  if (requestPassword) {
    return requestPassword;
  }

  const envPassword = process.env.SUNAT_CERT_PASSWORD?.trim();
  if (envPassword) {
    return envPassword;
  }

  if (fs.existsSync(DEFAULT_PASSWORD_PATH)) {
    return fs.readFileSync(DEFAULT_PASSWORD_PATH, "utf8").trim();
  }

  throw new Error(
    "No se encontro la clave del certificado. Define SUNAT_CERT_PASSWORD o certificate/password.txt."
  );
}

function decodeBase64Input(value = "") {
  const clean = String(value).trim();
  const data = clean.match(/^data:.*;base64,(.+)$/i)?.[1] || clean;
  const buffer = Buffer.from(data.replace(/\s+/g, ""), "base64");

  if (!buffer.length) {
    throw new Error("SUNAT_CERT_PFX_BASE64 es invalido o esta vacio.");
  }

  return buffer;
}

function resolveCertificateFile(overrides = {}) {
  const requestCertBase64 = String(overrides.certificateBase64 || "").trim();
  const certBase64 = requestCertBase64 || process.env.SUNAT_CERT_PFX_BASE64?.trim();
  if (certBase64) {
    const fileName = `sunat-cert-${Date.now()}-${process.pid}.pfx`;
    const tempPath = path.join(os.tmpdir(), fileName);
    fs.writeFileSync(tempPath, decodeBase64Input(certBase64));
    return { filePath: tempPath, cleanup: true };
  }

  const requestPath = String(overrides.certificatePath || "").trim();
  const configuredPath = requestPath || process.env.SUNAT_CERT_PFX_PATH?.trim();
  const filePath = configuredPath || DEFAULT_CERT_PATH;

  if (!fs.existsSync(filePath)) {
    throw new Error(
      `No se encontro el certificado en: ${filePath}. Define SUNAT_CERT_PFX_BASE64 o SUNAT_CERT_PFX_PATH.`
    );
  }

  return { filePath, cleanup: false };
}

export async function signXML(xml, options = {}) {
  const { filePath: pfxFilePath, cleanup } = resolveCertificateFile(options);
  const password = resolveCertificatePassword(options);

  const sig = new XmlSignature(pfxFilePath, password, xml);
  const rootName = resolveRootName(xml);
  sig.signXpath = `//*[local-name()='${rootName}']`;

  try {
    const signedXML = await sig.getSignedXML();
    return signedXML;
  } catch (err) {
    console.error("Error al firmar XML:", err);
    throw err;
  } finally {
    if (cleanup && fs.existsSync(pfxFilePath)) {
      fs.unlinkSync(pfxFilePath);
    }
  }
}

